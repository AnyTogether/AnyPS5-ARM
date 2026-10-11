#ifndef CORE_LIBS_PRX_LIBKERNEL_FILE_DESCRIPTORCONTROL_HPP
#define CORE_LIBS_PRX_LIBKERNEL_FILE_DESCRIPTORCONTROL_HPP

#include <cstdint>

namespace File {

int Fcntl(int fd, int command, std::intptr_t argument);
int Ioctl(int fd, std::uint64_t request, void* argument);
int DuplicateFrom(int fd, int start);
void RememberDescriptor(int fd, int openFlags);
void ShareDescriptor(int from, int to);
void ForgetDescriptor(int fd);

}

#endif
