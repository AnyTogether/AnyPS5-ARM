#include "prx/libc/include/GuestDirectory.hpp"
#include "prx/libkernel/File/include/DirectoryDescriptor.hpp"
#include <cerrno>

extern "C" int APS5_VABI close_nid_postfix(int d);
extern "C" int* APS5_VABI __error_nid_postfix();

extern "C" void* APS5_VABI fdopendir_nid_postfix(int fd) {
    int error = 0;
    const char* path = GetDirectoryDescriptorPath_nid_no_patch(fd, &error);
    if (path == nullptr) {
        *__error_nid_postfix() = error == EBADF ? 9 : 20;
        return nullptr;
    }
    return OpenDescriptorDirectory_nid_no_patch(path, fd, close_nid_postfix);
}
