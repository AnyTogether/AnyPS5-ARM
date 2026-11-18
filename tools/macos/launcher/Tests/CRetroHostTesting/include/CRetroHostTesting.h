#ifndef CRETROHOSTTESTING_H
#define CRETROHOSTTESTING_H

#include <stddef.h>

int anyps5_retro_test_shm(size_t bytes);
long anyps5_retro_test_send(int socket, const void *data, size_t length, const int *descriptors, size_t count);

#endif
