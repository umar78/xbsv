// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include <termios.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/select.h> // in MacOSX, poll() does not work with devices!!
#include <dirent.h>
#include <unistd.h>

#define MATCHLIMIT 10
#define CHECKIP "ifconfig -a\n"

void memdump(unsigned char *p, int len, char *title)
{
int i;

    i = 0;
    while (len > 0) {
        if (!(i & 0xf)) {
            if (i > 0)
                printf("\n");
            printf("%s: ",title);
        }
        printf("%02x ", *p++);
        i++;
        len--;
    }
    printf("\n");
}

static char buf[1000], linebuf[1000], ipaddr[1000], *linep;
int main(int argc, char **argv)
{
    struct termios terminfo;
    int fd = -1;
    int rc;
    fd_set fdset;
    int number_fds = 1;
    struct timeval timeout;
    int maxfd = 1;
    int matchcount = 0;
    int loopcount = 0;

    printf("checkip: Waiting for USB device\n");
    while (1) {
        if (fd == -1) {
            struct dirent *direntp;
            DIR *dirptr = opendir("/dev/");
            if (dirptr) {
                while ((direntp = readdir(dirptr))) {
                    if (!strncmp(direntp->d_name, "tty.usbmodem", 12)) {
                        sprintf(buf, "/dev/%s", direntp->d_name);
                        printf("consolable: opening %s\n", buf);
                        fd = open(buf, O_RDWR);
                        linep = linebuf;
                        ipaddr[0] = 0;
                        printf("consolable: fd %d\n", fd);
                        break;
                    }
                }
                closedir(dirptr); 
            }
            if (fd >= 0) {
                number_fds = 2;
                printf("consolable: USB device '%s' opened fd=%d\n", buf, fd);
                maxfd = fd+1;
                rc = tcgetattr(fd, &terminfo);
                terminfo.c_ispeed = B115200;
                terminfo.c_ospeed = B115200;
                rc = tcsetattr(fd, TCSANOW, &terminfo);
            }
        }
        FD_ZERO(&fdset); 
        if (fd != -1)
            FD_SET(fd, &fdset);
        timeout.tv_sec = 0;
        timeout.tv_usec = 300000;
        rc = select(maxfd, &fdset, NULL, NULL, &timeout);
        if (rc > 0 && fd != -1 && FD_ISSET(fd, &fdset)) {
            int len = read(fd, buf, sizeof(buf));
            if (len == -1) {
                if (fd != 0 && (errno == ENXIO || errno == EBADF)) {
                    printf("consolable: USB device closed\n");
                    number_fds = 1;
                    close(fd);
                    maxfd = 0;
                    fd = -1;
                    fd = -1;
                    continue;
                }
                printf("consolable: read error\n");
                exit(-1);
            }
            int i = 0;
            while(i < len)
                if (buf[i++] == '\r')
                    buf[i-1] = ' ';
            //write(1, buf, len);
            char *lfind;
            while ((lfind = index(linebuf, '\n'))) {
                *lfind++ = 0;
                char *p = strstr(linebuf, "addr:");
                if (p) {
                    p += 5;
                    char *pend = strstr(p, "Bcast:");
                    if (pend) {
                        *pend = 0;
                        if (!strcmp(ipaddr, p))
                            matchcount++;
                        else {
                            matchcount = 0;
                            strcpy(ipaddr, p);
                        }
                        if (matchcount > MATCHLIMIT) {
                            fprintf(stderr, "%s\n", p);
                            exit(0);
                        }
                    }
                }
                linep = linebuf;
                while (*lfind)
                    *linep++ = *lfind++;
                *linep = 0;
            }
            memcpy(linep, buf, len);
            linep += len;
            *linep = 0;
        }
        if (fd != -1) {
            write(fd, CHECKIP, strlen(CHECKIP));
            if (loopcount++ > 1000000) {
printf("[%s:%d] timeout\n", __FUNCTION__, __LINE__);
                exit(-1);
            }
        }
    }
    return 0;
}