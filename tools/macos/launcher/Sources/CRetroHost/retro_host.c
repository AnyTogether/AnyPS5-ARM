#include "CRetroHost.h"

#include <stdatomic.h>

uint32_t anyps5_retro_load_u32(void *address) {
    return atomic_load_explicit((_Atomic uint32_t *)address, memory_order_seq_cst);
}

void anyps5_retro_store_u32(void *address, uint32_t value) {
    atomic_store_explicit((_Atomic uint32_t *)address, value, memory_order_seq_cst);
}

size_t anyps5_retro_cmsg_space(size_t data_bytes) {
    return CMSG_SPACE(data_bytes);
}

struct cmsghdr *anyps5_retro_cmsg_first(struct msghdr *message) {
    return CMSG_FIRSTHDR(message);
}

struct cmsghdr *anyps5_retro_cmsg_next(struct msghdr *message, struct cmsghdr *header) {
    return CMSG_NXTHDR(message, header);
}

size_t anyps5_retro_cmsg_data_bytes(struct cmsghdr *header) {
    size_t empty = CMSG_LEN(0);
    return header->cmsg_len < empty ? 0 : header->cmsg_len - empty;
}

unsigned char *anyps5_retro_cmsg_data(struct cmsghdr *header) {
    return CMSG_DATA(header);
}
