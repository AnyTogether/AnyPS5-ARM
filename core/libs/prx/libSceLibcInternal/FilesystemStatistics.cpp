#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libSceLibcInternal/include/LibcStatvfs.hpp"
#include "prx/libkernel/File/include/KernelStatfs.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>

extern "C" int APS5_VABI _fstatfs_nid_postfix(int, KernelStatfs*);
extern "C" int* APS5_VABI __error_nid_postfix();

extern "C" int APS5_VABI fstatvfs_nid_postfix(int descriptor, LibcStatvfs* output) {
    int* const error = __error_nid_postfix();
    const int saved = *error;
    KernelStatfs volume{};
    const int status = _fstatfs_nid_postfix(descriptor, &volume);
    if (status != 0) return status;
    if (output == nullptr) {
        *error = 14;
        return -1;
    }
    const LibcStatvfs result{
        static_cast<std::uint64_t>(volume.f_bavail), volume.f_bfree, volume.f_blocks,
        static_cast<std::uint64_t>(volume.f_ffree), static_cast<std::uint64_t>(volume.f_ffree), volume.f_files,
        volume.f_iosize, (volume.f_flags & 1) | ((volume.f_flags & 8) >> 2), volume.f_bsize,
        0, volume.f_namemax
    };
    std::memcpy(output, &result, sizeof(result));
    *error = saved;
    return 0;
}
