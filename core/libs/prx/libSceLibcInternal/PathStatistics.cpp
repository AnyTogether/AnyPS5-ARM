#include "prx/libc/include/FilesystemError.hpp"
#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <string_view>
#include <system_error>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#else
#include <unistd.h>
#endif
#ifdef __APPLE__
#include "prx/libSceLibcInternal/include/LibcStatvfs.hpp"
#include <cstring>
#include <sys/stat.h>
#include <sys/statvfs.h>
#endif

struct LibcStatvfs;
extern "C" int APS5_VABI fstatvfs_nid_postfix(int, LibcStatvfs*);

namespace {
int Fail(int error) {
    errno = error;
    return -1;
}

int HostError(int error) {
    switch (error) {
        case ENOENT: return 2;
        case EINTR: return 4;
        case EIO: return 5;
        case ENOMEM: return 12;
        case EACCES: return 13;
        case ENOTDIR: return 20;
        case EINVAL: return 22;
        case ENFILE: return 23;
        case EMFILE: return 24;
        case EAGAIN: return 35;
        case ELOOP: return 62;
        case ENAMETOOLONG: return 63;
        default: throw std::system_error(error, std::generic_category(), "statvfs: unsupported host error");
    }
}

#ifndef __APPLE__
struct Descriptor {
    int value;
    ~Descriptor() {
        const int saved = errno;
#ifdef _WIN32
        ::_close(value);
#else
        ::close(value);
#endif
        errno = saved;
    }
};

int OpenMetadata(const std::filesystem::path& path, bool directory) {
#ifdef _WIN32
    const HANDLE handle = CreateFileW(path.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        const DWORD error = GetLastError();
        if (error == ERROR_PATH_NOT_FOUND || error == ERROR_INVALID_NAME || error == ERROR_DIRECTORY) {
            for (auto prefix = path.parent_path(); !prefix.empty();) {
                const DWORD attributes = GetFileAttributesW(prefix.c_str());
                if (attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY)) return Fail(20);
                const auto parent = prefix.parent_path();
                if (parent == prefix) break;
                prefix = parent;
            }
        }
        switch (error) {
            case ERROR_FILE_NOT_FOUND:
            case ERROR_PATH_NOT_FOUND:
            case ERROR_INVALID_DRIVE: return Fail(2);
            case ERROR_ACCESS_DENIED:
            case ERROR_SHARING_VIOLATION: return Fail(13);
            case ERROR_DIRECTORY: return Fail(20);
            case ERROR_INVALID_NAME:
            case ERROR_INVALID_PARAMETER: return Fail(22);
            case ERROR_CANT_RESOLVE_FILENAME: return Fail(62);
            case ERROR_FILENAME_EXCED_RANGE: return Fail(63);
            default: throw std::system_error(error, std::system_category(), "statvfs: CreateFileW");
        }
    }
    if (directory) {
        BY_HANDLE_FILE_INFORMATION info{};
        if (!GetFileInformationByHandle(handle, &info)) {
            const DWORD error = GetLastError();
            CloseHandle(handle);
            throw std::system_error(error, std::system_category(), "statvfs: GetFileInformationByHandle");
        }
        if (!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
            CloseHandle(handle);
            return Fail(20);
        }
    }
    const int descriptor = ::_open_osfhandle(reinterpret_cast<std::intptr_t>(handle), _O_RDONLY | _O_BINARY | _O_NOINHERIT);
    if (descriptor < 0) {
        const int error = errno;
        CloseHandle(handle);
        return Fail(HostError(error));
    }
    return descriptor;
#else
    const int descriptor = ::open(path.c_str(), O_PATH | O_CLOEXEC | (directory ? O_DIRECTORY : 0));
    return descriptor < 0 ? Fail(HostError(errno)) : descriptor;
#endif
}
#endif
}

extern "C" int APS5_VABI statvfs_nid_postfix(const char* path, LibcStatvfs* output) {
    if (path == nullptr) return Fail(14);
    if (*path == '\0') return Fail(2);
    const int saved = errno;
    const auto last = std::string_view(path).back();
    const bool directory = last == '/' || last == '\\' || FinalPathComponentIsDot_nid_no_patch(path);
    std::filesystem::path native;
    if (const int error = ResolvePathError_nid_no_patch(path, native)) return Fail(error);
#ifdef __APPLE__
    // macOS has no O_PATH: a file without read permission, a socket, or a FIFO without a writer cannot be
    // opened only to name its volume, so the volume is queried by path. The fields match fstatvfs.
    struct stat file {};
    if (::stat(native.c_str(), &file) != 0) return Fail(HostError(errno));
    if (directory && !S_ISDIR(file.st_mode)) return Fail(20);
    struct statvfs host {};
    if (::statvfs(native.c_str(), &host) != 0) return Fail(HostError(errno));
    if (output == nullptr) return Fail(14);
    const LibcStatvfs result{
        static_cast<std::uint64_t>(host.f_bavail), static_cast<std::uint64_t>(host.f_bfree),
        static_cast<std::uint64_t>(host.f_blocks), static_cast<std::uint64_t>(host.f_favail),
        static_cast<std::uint64_t>(host.f_favail), static_cast<std::uint64_t>(host.f_files),
        static_cast<std::uint64_t>(host.f_bsize),
        std::uint64_t{(host.f_flag & ST_RDONLY) ? 1u : 0u} | std::uint64_t{(host.f_flag & ST_NOSUID) ? 2u : 0u},
        static_cast<std::uint64_t>(host.f_frsize != 0 ? host.f_frsize : host.f_bsize), 0,
        static_cast<std::uint64_t>(host.f_namemax)
    };
    std::memcpy(output, &result, sizeof(result));
    errno = saved;
    return 0;
#else
    const int descriptor = OpenMetadata(native, directory);
    if (descriptor < 0) return -1;
    const Descriptor owner{descriptor};
    errno = saved;
    return fstatvfs_nid_postfix(descriptor, output);
#endif
}
