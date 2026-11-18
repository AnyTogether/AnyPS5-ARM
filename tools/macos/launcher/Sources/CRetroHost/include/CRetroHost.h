#ifndef CRETROHOST_H
#define CRETROHOST_H

#include <stddef.h>
#include <stdint.h>
#include <sys/socket.h>

uint32_t anyps5_retro_load_u32(void *address);
void anyps5_retro_store_u32(void *address, uint32_t value);
size_t anyps5_retro_cmsg_space(size_t data_bytes);
struct cmsghdr *anyps5_retro_cmsg_first(struct msghdr *message);
struct cmsghdr *anyps5_retro_cmsg_next(struct msghdr *message, struct cmsghdr *header);
size_t anyps5_retro_cmsg_data_bytes(struct cmsghdr *header);
unsigned char *anyps5_retro_cmsg_data(struct cmsghdr *header);

#endif
