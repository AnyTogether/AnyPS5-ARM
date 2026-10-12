#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libkernel/File/include/KernelStatfs.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>

struct LibcStatvfs {
    std::uint64_t f_bavail;
    std::uint64_t f_bfree;
    std::uint64_t f_blocks;
    std::uint64_t f_favail;
    std::uint64_t f_ffree;
    std::uint64_t f_files;
    std::uint64_t f_bsize;
    std::uint64_t f_flag;
    std::uint64_t f_frsize;
    std::uint64_t f_fsid;
    std::uint64_t f_namemax;
};
static_assert(sizeof(LibcStatvfs) == 88);
static_assert(offsetof(LibcStatvfs, f_bsize) == 48);
static_assert(offsetof(LibcStatvfs, f_namemax) == 80);

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
