#include <linux/miscdevice.h>
#include <linux/platform_device.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/ioctl.h>
#include <linux/dma-buf.h>
#include <linux/slab.h>
#include <linux/scatterlist.h>

#include <asm/cacheflush.h>

#include "portalmem.h"

#ifdef DEBUG // was KERN_DEBUG
#define driver_devel(format, ...)		\
  do {						\
    printk(format, ## __VA_ARGS__);		\
  } while (0)
#else
#define driver_devel(format, ...)
#endif

#define DRIVER_NAME "portalmem"
#define DRIVER_DESCRIPTION "Memory management between HW and SW processes"
#define DRIVER_VERSION "0.1"

/**
 * struct pa_buffer - metadata for a particular buffer
 * @size:              size of the buffer
 * @lock:		protects the buffers cnt fields
 * @kmap_cnt:		number of times the buffer is mapped to the kernel
 * @vaddr:		the kenrel mapping if kmap_cnt is not zero
 * @sg_table:		the sg table for the buffer
 */
struct pa_buffer {
  size_t          size;
  struct mutex    lock;
  int             kmap_cnt;
  void            *vaddr;
  struct sg_table *sg_table;
};

static struct miscdevice miscdev;

static void free_buffer_page(struct page *page, unsigned int order)
{
  // this is causing kernel panic on x86
  // i'll leave it commented out for now
  //__free_pages(page, order);
}

static int pa_buffer_free(struct pa_buffer *buffer)
{
  struct sg_table *table = buffer->sg_table;
  struct scatterlist *sg;
  LIST_HEAD(pages);
  int i;
  printk("PortalAlloc::pa_system_heap_free\n");
  for_each_sg(table->sgl, sg, table->nents, i){
    free_buffer_page(sg_page(sg), get_order(sg->length));
  }
  sg_free_table(table);
  kfree(table);
  kfree(buffer);
  return 0;
}

/*
 * driver dma_buf callback functions
 */

static struct sg_table *pa_dma_buf_map(struct dma_buf_attachment *attachment,
				       enum dma_data_direction direction)
{
  return ((struct pa_buffer *)attachment->dmabuf->priv)->sg_table;
}

static void pa_dma_buf_unmap(struct dma_buf_attachment *attachment,
	     struct sg_table *table, enum dma_data_direction direction)
{
}

static int pa_dma_buf_mmap(struct dma_buf *dmabuf, struct vm_area_struct *vma)
{
  struct pa_buffer *buffer = dmabuf->priv;
  int ret = 0;
  struct scatterlist *sg;
  int i;

  printk("pa_dma_buf_mmap %08lx %zd\n", (unsigned long)(dmabuf->file), dmabuf->file->f_count.counter);
  vma->vm_page_prot = pgprot_writecombine(vma->vm_page_prot);
  mutex_lock(&buffer->lock);
  /* now map it to userspace */
  {
    struct sg_table *table = buffer->sg_table;
    unsigned long addr = vma->vm_start;
    unsigned long offset = vma->vm_pgoff * PAGE_SIZE;

    //printk("(0) pa_system_heap_map_user %08lx %08lx %08lx\n", vma->vm_start, vma->vm_end, offset);
    for_each_sg(table->sgl, sg, table->nents, i) {
      struct page *page = sg_page(sg);
      unsigned long remainder = vma->vm_end - addr;
      unsigned long len = sg->length;
      //printk("pa_system_heap_map_user %08x %08x\n", sg->length, sg_dma_len(sg));
      //printk("(1) pa_system_heap_map_user %08lx %08lx %08lx\n", (unsigned long) page, remainder, len);
      if (offset >= (sg->length)) {
        //printk("feck %08lx %08x\n", offset, (sg->length));
        offset -= (sg->length);
        continue;
      } else if (offset) {
        page += offset / PAGE_SIZE;
        len = (sg->length) - offset;
        offset = 0;
      }
      len = min(len, remainder);
      //printk("(2) pa_system_heap_map_user %08lx %08lx %08lx\n", addr, (unsigned long)page, page_to_pfn(page));
      remap_pfn_range(vma, addr, page_to_pfn(page), len,
		      vma->vm_page_prot);
      addr += len;
      if (addr >= vma->vm_end)
        break;
    }
  }
  mutex_unlock(&buffer->lock);
  if (ret)
    pr_err("%s: failure mapping buffer to userspace\n", __func__);
  return ret;
}

static void pa_dma_buf_release(struct dma_buf *dmabuf)
{
  struct pa_buffer *buffer = dmabuf->priv;
  printk("PortalAlloc::pa_dma_buf_release %08lx %zd\n", (unsigned long)(dmabuf->file), dmabuf->file->f_count.counter);
  pa_buffer_free(buffer);
}

static void *pa_dma_buf_kmap(struct dma_buf *dmabuf, unsigned long offset)
{
  struct pa_buffer *buffer = dmabuf->priv;
  return buffer->vaddr + offset * PAGE_SIZE;
}

static void pa_dma_buf_kunmap(struct dma_buf *dmabuf, unsigned long offset,
			      void *ptr)
{
}

static int pa_dma_buf_begin_cpu_access(struct dma_buf *dmabuf, size_t start,
		      size_t len, enum dma_data_direction direction)
{
  struct pa_buffer *buffer = dmabuf->priv;
  void *vaddr = NULL;

  mutex_lock(&buffer->lock);
  vaddr = buffer->vaddr;
  if (!buffer->kmap_cnt) {
    struct sg_table *table = buffer->sg_table;
    int npages = PAGE_ALIGN(buffer->size) / PAGE_SIZE;
    struct page **pages = vmalloc(sizeof(struct page *) * npages);
    struct page **tmp = pages;
    if (pages) {
      int i, j;
      struct scatterlist *sg;
      pgprot_t pgprot = pgprot_writecombine(PAGE_KERNEL);
      for_each_sg(table->sgl, sg, table->nents, i) {
        int npages_this_entry = PAGE_ALIGN(sg_dma_len(sg)) / PAGE_SIZE;
        struct page *page = sg_page(sg);
        BUG_ON(i >= npages);
        for (j = 0; j < npages_this_entry; j++)
          *(tmp++) = page++;
      }
      vaddr = vmap(pages, npages, VM_MAP, pgprot);
      vfree(pages);
    }
  }
  if (!IS_ERR_OR_NULL(vaddr)) {
    buffer->vaddr = vaddr;
    buffer->kmap_cnt++;
  }
  mutex_unlock(&buffer->lock);
  if (IS_ERR(vaddr))
    return PTR_ERR(vaddr);
  if (!vaddr)
    return -ENOMEM;
  return 0;
}

static void pa_dma_buf_end_cpu_access(struct dma_buf *dmabuf, size_t start,
		     size_t len, enum dma_data_direction direction)
{
  struct pa_buffer *buffer = dmabuf->priv;

  mutex_lock(&buffer->lock);
  if (!--buffer->kmap_cnt) {
    vunmap(buffer->vaddr);
    buffer->vaddr = NULL;
  }
  mutex_unlock(&buffer->lock);
}

static struct dma_buf_ops dma_buf_ops = {
  .map_dma_buf      = pa_dma_buf_map,
  .unmap_dma_buf    = pa_dma_buf_unmap,
  .mmap             = pa_dma_buf_mmap,
  .release          = pa_dma_buf_release,
  .begin_cpu_access = pa_dma_buf_begin_cpu_access,
  .end_cpu_access   = pa_dma_buf_end_cpu_access,
  .kmap_atomic      = pa_dma_buf_kmap,
  .kunmap_atomic    = pa_dma_buf_kunmap,
  .kmap             = pa_dma_buf_kmap,
  .kunmap           = pa_dma_buf_kunmap,
};

static struct dma_buf *dmabuffer_create(unsigned long len,
					  unsigned long align)
{
  static unsigned int high_order_gfp_flags = (GFP_HIGHUSER | __GFP_ZERO |
	    __GFP_NOWARN | __GFP_NORETRY | __GFP_NO_KSWAPD) & ~__GFP_WAIT;
  static unsigned int low_order_gfp_flags  = (GFP_HIGHUSER | __GFP_ZERO |
					    __GFP_NOWARN);
  static const unsigned int orders[] = {8, 4, 0};
  struct pa_buffer *buffer;
  struct sg_table *table;
  struct scatterlist *sg;
  struct list_head pages;
  struct page_info {
    struct page *page;
    unsigned long order;
    struct list_head list;
  } *info = NULL, *tmp_info;
  unsigned int max_order = orders[0];
  long size_remaining = len;
  int infocount = 0;

  buffer = kzalloc(sizeof(struct pa_buffer), GFP_KERNEL);
  if (!buffer)
    return ERR_PTR(-ENOMEM);
  table = kmalloc(sizeof(struct sg_table), GFP_KERNEL);
  if (!table) {
    kfree(buffer);
    return ERR_PTR(-ENOMEM);
  }
  INIT_LIST_HEAD(&pages);
  while (size_remaining > 0) {
    int ordindex = 0;
    info = NULL;
    for (; ordindex < ARRAY_SIZE(orders); ordindex++) {
      gfp_t gfp_flags = low_order_gfp_flags;
      if (orders[ordindex] > 4)
        gfp_flags = high_order_gfp_flags;
      if (size_remaining >= (PAGE_SIZE << orders[ordindex])
       && max_order >= orders[ordindex]) {
        struct page *page = alloc_pages(gfp_flags, orders[ordindex]);
        if (page) {
          info = kmalloc(sizeof(*info), GFP_KERNEL);
          info->page = page;
          info->order = orders[ordindex];
          list_add_tail(&info->list, &pages);
          size_remaining -= (1 << info->order) * PAGE_SIZE;
          max_order = info->order;
          infocount++;
          break;
        }
      }
    }
    if (!info)
      break;
  }
  if (info) {
    int ret = sg_alloc_table(table, infocount, GFP_KERNEL);
    if (!ret) {
      struct dma_buf *dmabuf;
      sg = table->sgl;
      list_for_each_entry_safe(info, tmp_info, &pages, list) {
        struct page *page = info->page;
        sg_set_page(sg, page, (1 << info->order) * PAGE_SIZE, 0);
        sg = sg_next(sg);
        list_del(&info->list);
        kfree(info);
      }
      if (IS_ERR_OR_NULL(table)) {
        pa_buffer_free(buffer);
        return ERR_PTR(PTR_ERR(table));
      }
      buffer->sg_table = table;
      buffer->size = len;
      mutex_init(&buffer->lock);
      /* this will set up dma addresses for the sglist -- it is not
         technically correct as per the dma api -- a specific
         device isn't really taking ownership here.  However, in practice on
         our systems the only dma_address space is physical addresses.
         Additionally, we can't afford the overhead of invalidating every
         allocation via dma_map_sg. The implicit contract here is that
         memory is ready for dma, ie if it has a
         cached mapping that mapping has been invalidated */
      for_each_sg(buffer->sg_table->sgl, sg, buffer->sg_table->nents, infocount)
        sg_dma_address(sg) = sg_phys(sg);
      dmabuf = dma_buf_export(buffer, &dma_buf_ops, len, O_RDWR);
      if (IS_ERR(dmabuf))
        pa_buffer_free(buffer);
      return dmabuf;
    }
    kfree(table);
  }
  list_for_each_entry(info, &pages, list) {
    free_buffer_page(info->page, info->order);
    kfree(info);
  }
  kfree(buffer);
  return ERR_PTR(-ENOMEM);
}

/*
 * driver file operations
 */

static long pa_unlocked_ioctl(struct file *filep, unsigned int cmd, unsigned long arg)
{
  switch (cmd) {
  case PA_DCACHE_FLUSH_INVAL: {
#if defined(__arm__)
    struct PortalAllocHeader header;
    struct PortalAlloc* palloc = (struct PortalAlloc*)arg;
    unsigned long start_addr, end_addr, length;
    int i;
    if (copy_from_user(&header, (void __user *)arg, sizeof(header)))
      return -EFAULT;
    for(i = 0; i < header.numEntries; i++){
      if (copy_from_user(&start_addr, (void __user *)&(palloc->entries[i].dma_address),
          sizeof(palloc->entries[i].dma_address))
       || copy_from_user(&length, (void __user *)&(palloc->entries[i].length),
          sizeof(palloc->entries[i].length)))
	return -EFAULT;
      end_addr = start_addr+length;
      outer_clean_range(start_addr, end_addr);
      outer_inv_range(start_addr, end_addr);
    }
    return 0;
#elif defined(__i386__) || defined(__x86_64__)
    return -EFAULT;
#else
#error("PA_DCACHE_FLUSH_INVAL architecture undefined");
#endif
  }
  case PA_ALLOC: {
    struct PortalAllocHeader header;
    size_t align = 4096;
    struct dma_buf *dmabuf;
    if (copy_from_user(&header, (void __user *)arg, sizeof(header)))
      return -EFAULT;
    printk("%s, header.size=%zd\n", __FUNCTION__, header.size);
    header.size = PAGE_ALIGN(round_up(header.size, align));
    dmabuf = dmabuffer_create(header.size, align);
    if (IS_ERR(dmabuf))
      return PTR_ERR(dmabuf);
    printk("pa_get_dma_buf %p %zd\n", dmabuf->file, dmabuf->file->f_count.counter);
    header.numEntries = ((struct pa_buffer *)dmabuf->priv)->sg_table->nents;
    header.fd = dma_buf_fd(dmabuf, O_CLOEXEC);
    if (header.fd < 0)
      dma_buf_put(dmabuf);
    if (copy_to_user((void __user *)arg, &header, sizeof(header)))
      return -EFAULT;
    return 0;
  }
  case PA_DMA_ADDRESSES: {
    struct PortalAllocHeader header;
    struct file *f;
    struct sg_table *sgtable;
    struct scatterlist *sg;
    int i;
    struct PortalAlloc* palloc = (struct PortalAlloc*)arg;
    if (copy_from_user(&header, (void __user *)arg, sizeof(header)))
      return -EFAULT;
    f = fget(header.fd);
    sgtable = ((struct pa_buffer *)((struct dma_buf *)f->private_data)->priv)->sg_table;
    for_each_sg(sgtable->sgl, sg, sgtable->nents, i) {
      unsigned long p = sg_phys(sg);
      if (copy_to_user((void __user *)&(palloc->entries[i].dma_address), &(p), sizeof(p))
       || copy_to_user((void __user *)&(palloc->entries[i].length), &(sg->length), sizeof(sg->length)))
    	return -EFAULT;
    }
    fput(f);
    return 0;
  }
  default:
    printk("pa_unlocked_ioctl ENOTTY cmd=%x\n", cmd);
    return -ENOTTY;
  }
  return -ENODEV;
}

static struct file_operations pa_fops = {
    .owner = THIS_MODULE,
    .unlocked_ioctl = pa_unlocked_ioctl
  };

/*
 * driver initialization and exit
 */
 
static int __init pa_init(void)
{
  struct miscdevice *md = &miscdev;
  printk("PortalAlloc::pa_init\n");
  md->minor = MISC_DYNAMIC_MINOR;
  md->name = "portalmem";
  md->fops = &pa_fops;
  md->parent = NULL;
  misc_register(md);
  return 0;
}
 
static void __exit pa_exit(void)
{
  struct miscdevice *md = &miscdev;
  printk("PortalAlloc::pa_exit\n");
  misc_deregister(md);
}
 
module_init(pa_init);
module_exit(pa_exit);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION(DRIVER_DESCRIPTION);
MODULE_VERSION(DRIVER_VERSION);