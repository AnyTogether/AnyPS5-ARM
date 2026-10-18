#pragma once
#include <cstddef>
#include <cstdint>

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
