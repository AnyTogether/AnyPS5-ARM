#include "CRetroHostTesting.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <unistd.h>

int anyps5_retro_test_shm(size_t bytes) {
    char name[32];
    snprintf(name, sizeof name, "/a5t-%08x%04x", arc4random(), arc4random() & 0xFFFF);
    int descriptor = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (descriptor < 0) return -1;
    shm_unlink(name);
    fcntl(descriptor, F_SETFD, FD_CLOEXEC);
    if (ftruncate(descriptor, (off_t)bytes) != 0) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

long anyps5_retro_test_send(int socket, const void *data, size_t length, const int *descriptors, size_t count) {
    struct iovec vector = {(void *)data, length};
    struct msghdr message;
    memset(&message, 0, sizeof message);
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    char *control = NULL;
    if (count > 0) {
        size_t space = CMSG_SPACE(count * sizeof(int));
        control = calloc(1, space);
        if (!control) return -1;
        message.msg_control = control;
        message.msg_controllen = (socklen_t)space;
        struct cmsghdr *header = CMSG_FIRSTHDR(&message);
        header->cmsg_level = SOL_SOCKET;
        header->cmsg_type = SCM_RIGHTS;
        header->cmsg_len = (socklen_t)CMSG_LEN(count * sizeof(int));
        memcpy(CMSG_DATA(header), descriptors, count * sizeof(int));
    }
    long sent = (long)sendmsg(socket, &message, 0);
    free(control);
    return sent;
}
