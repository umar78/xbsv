/* Copyright (c) 2014 Quanta Research Cambridge, Inc
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include <fstream>
#include <iostream>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/mman.h>
#include <assert.h>
#include <mp.h>

#include "StdDmaIndication.h"
#include "DmaDebugRequestProxy.h"
#include "SGListConfigRequestProxy.h"
#include "GeneratedTypes.h" 
#include "NandSimIndicationWrapper.h"
#include "NandSimRequestProxy.h"
#include "StrstrIndicationWrapper.h"
#include "StrstrRequestProxy.h"

static int trace_memory = 1;
extern "C" {
#include "sys/ioctl.h"
#include "portalmem.h"
#include "sock_utils.h"
#include "dmaManager.h"
#include "userReference.h"
}

size_t numBytes = 1 << 12;
#ifndef BOARD_bluesim
size_t nandBytes = 1 << 24;
#else
size_t nandBytes = 1 << 14;
#endif

class NandSimIndication : public NandSimIndicationWrapper
{
public:
  unsigned int rDataCnt;
  virtual void readDone(uint32_t v){
    fprintf(stderr, "NandSim::readDone v=%x\n", v);
    sem_post(&sem);
  }
  virtual void writeDone(uint32_t v){
    fprintf(stderr, "NandSim::writeDone v=%x\n", v);
    sem_post(&sem);
  }
  virtual void eraseDone(uint32_t v){
    fprintf(stderr, "NandSim::eraseDone v=%x\n", v);
    sem_post(&sem);
  }
  virtual void configureNandDone(){
    fprintf(stderr, "NandSim::configureNandDone\n");
    sem_post(&sem);
  }

  NandSimIndication(int id) : NandSimIndicationWrapper(id) {
    sem_init(&sem, 0, 0);
  }
  void wait() {
    fprintf(stderr, "NandSim::wait for semaphore\n");
    sem_wait(&sem);
  }
private:
  sem_t sem;
};

class StrstrIndication : public StrstrIndicationWrapper
{
public:
  StrstrIndication(unsigned int id) : StrstrIndicationWrapper(id){
    sem_init(&sem, 0, 0);
    match_cnt = 0;
  };
  virtual void setupComplete() {
    fprintf(stderr, "Strstr::setupComplete\n");
    sem_post(&sem);
  }
  virtual void searchResult (int v){
    fprintf(stderr, "searchResult = %d\n", v);
    if (v == -1)
      sem_post(&sem);
    else 
      match_cnt++;
  }
  void wait() {
    fprintf(stderr, "Strstr::wait for semaphore\n");
    sem_wait(&sem);
  }
  int match_cnt;
private:
  sem_t sem;
};



static int sockfd;
#define SOCK_NAME "socket_for_nandsim"
void wait_for_connect_nandsim_exe()
{
  int listening_socket;

  if ((listening_socket = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
    fprintf(stderr, "%s: socket error %s",__FUNCTION__, strerror(errno));
    exit(1);
  }

  struct sockaddr_un local;
  local.sun_family = AF_UNIX;
  strcpy(local.sun_path, SOCK_NAME);
  unlink(local.sun_path);
  int len = strlen(local.sun_path) + sizeof(local.sun_family);
  if (bind(listening_socket, (struct sockaddr *)&local, len) == -1) {
    fprintf(stderr, "%s[%d]: bind error %s\n",__FUNCTION__, listening_socket, strerror(errno));
    exit(1);
  }

  if (listen(listening_socket, 5) == -1) {
    fprintf(stderr, "%s[%d]: listen error %s\n",__FUNCTION__, listening_socket, strerror(errno));
    exit(1);
  }
  
  //fprintf(stderr, "%s[%d]: waiting for a connection...\n",__FUNCTION__, listening_socket);
  if ((sockfd = accept(listening_socket, NULL, NULL)) == -1) {
    fprintf(stderr, "%s[%d]: accept error %s\n",__FUNCTION__, listening_socket, strerror(errno));
    exit(1);
  }
  remove(SOCK_NAME);  // we are connected now, so we can remove named socket
}

unsigned int read_from_nandsim_exe()
{
  unsigned int rv;
  if(recv(sockfd, &rv, sizeof(rv), 0) == -1){
    fprintf(stderr, "%s recv error\n",__FUNCTION__);
    exit(1);	  
  }
  return rv;
}

int main(int argc, const char **argv)
{

  DmaDebugRequestProxy *hostmemDmaDebugRequest = 0;
  DmaDebugIndication *hostmemDmaDebugIndication = 0;

  SGListConfigRequestProxy *hostmemSGListConfigRequest = 0;
  SGListConfigIndication *hostmemSGListConfigIndication = 0;

  SGListConfigRequestProxy *nandsimSGListConfigRequest = 0;
  SGListConfigIndication *nandsimSGListConfigIndication = 0;

  StrstrRequestProxy *strstrRequest = 0;
  StrstrIndication *strstrIndication = 0;

  DmaDebugRequestProxy *nandsimDmaDebugRequest = 0;
  DmaDebugIndication *nandsimDmaDebugIndication = 0;

  fprintf(stderr, "Main::%s %s\n", __DATE__, __TIME__);

  hostmemDmaDebugRequest = new DmaDebugRequestProxy(IfcNames_HostmemDmaDebugRequest);
  hostmemSGListConfigRequest = new SGListConfigRequestProxy(IfcNames_BackingStoreSGListConfigRequest); // change this to AlgoSGListConfigRequest
  DmaManager *hostmemDma = new DmaManager(hostmemDmaDebugRequest, hostmemSGListConfigRequest);
  hostmemDma->priv.handle = 4; // so doesn't overlap with nandsim // remove this once above change is made

  hostmemDmaDebugIndication = new DmaDebugIndication(hostmemDma, IfcNames_HostmemDmaDebugIndication);
  hostmemSGListConfigIndication = new SGListConfigIndication(hostmemDma, IfcNames_BackingStoreSGListConfigIndication);  // change this to AlgoSGListConfigIndication

  strstrRequest = new StrstrRequestProxy(IfcNames_AlgoRequest);
  strstrIndication = new StrstrIndication(IfcNames_AlgoIndication);

  nandsimDmaDebugRequest = new DmaDebugRequestProxy(IfcNames_NandsimDmaDebugRequest);
  nandsimSGListConfigRequest = new SGListConfigRequestProxy(IfcNames_NandsimSGListConfigRequest);
  DmaManager *nandsimDma = new DmaManager(nandsimDmaDebugRequest, nandsimSGListConfigRequest);
  nandsimDmaDebugIndication = new DmaDebugIndication(nandsimDma,IfcNames_NandsimDmaDebugIndication);
  nandsimSGListConfigIndication = new SGListConfigIndication(nandsimDma,IfcNames_NandsimSGListConfigIndication);

  portalExec_start();
  fprintf(stderr, "Main::allocating memory...\n");

  // allocate memory for strstr data
  int needleAlloc = portalAlloc(numBytes);
  int mpNextAlloc = portalAlloc(numBytes);
  int ref_needleAlloc = hostmemDma->reference(needleAlloc);
  int ref_mpNextAlloc = hostmemDma->reference(mpNextAlloc);
  char *needle = (char *)portalMmap(needleAlloc, numBytes);
  int *mpNext = (int *)portalMmap(mpNextAlloc, numBytes);

  const char *needle_text = "ababab";
  int needle_len = strlen(needle_text);
  strncpy(needle, needle_text, needle_len);
  compute_MP_next(needle, mpNext, needle_len);
  fprintf(stderr, "mpNext=[");
  for(int i= 0; i <= needle_len; i++)
    fprintf(stderr, "%d ", mpNext[i]);
  fprintf(stderr, "]\n");
  portalDCacheFlushInval(needleAlloc, numBytes, needle);
  portalDCacheFlushInval(mpNextAlloc, numBytes, mpNext);
  fprintf(stderr, "Main::flush and invalidate complete\n");

  fprintf(stderr, "Main::waiting to connect to nandsim_exe\n");
  wait_for_connect_nandsim_exe();
  fprintf(stderr, "Main::connected to nandsim_exe\n");
  // base of haystack in "flash" memory
  int haystack_base = read_from_nandsim_exe();
  int haystack_len  = read_from_nandsim_exe();


  int id = nandsimDma->priv.handle++;
  // pairs of ('offset','size') poinging to space in nandsim memory
  // this is unsafe.  We should check that the we aren't overflowing 
  // 'nandBytes', the size of the nandSimulator backing store
  RegionRef region[] = {{0, 0x100000}, {0x100000, 0x100000}};
  printf("[%s:%d]\n", __FUNCTION__, __LINE__);
  int ref_haystackInNandMemory = send_reference_to_portal(nandsimDma->priv.sglDevice, sizeof(region)/sizeof(region[0]), region, id);
  sem_wait(&(nandsimDma->priv.confSem));

  fprintf(stderr, "about to setup device %d %d\n", ref_needleAlloc, ref_mpNextAlloc);
  strstrRequest->setup(ref_needleAlloc, ref_mpNextAlloc, needle_len);
  strstrIndication->wait();

  fprintf(stderr, "about to invoke search %d\n", ref_haystackInNandMemory);
  strstrRequest->search(ref_haystackInNandMemory, haystack_len, 1);
  strstrIndication->wait();  

  exit(!(strstrIndication->match_cnt==3));
}
