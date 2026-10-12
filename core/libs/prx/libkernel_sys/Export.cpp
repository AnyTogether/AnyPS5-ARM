#include <algorithm>
#include <cstdarg>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <filesystem>
#include <limits>
#include <stdexcept>
#include <string>
#include <system_error>
#ifdef __linux__
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#endif
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libc/include/FilesystemError.hpp"
#include "prx/libkernel/File/include/DirectoryDescriptor.hpp"
#include "prx/libc/include/CreationMask.hpp"
#include "prx/libkernel/File/include/FileFlags.hpp"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#ifndef SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
#define SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE 0x2
#endif
#endif

extern "C" int* APS5_VABI __error_nid_postfix();

namespace {
constexpr int GuestEnoent = 2;
constexpr int GuestEperm = 1;
constexpr int GuestEio = 5;
constexpr int GuestEfault = 14;
constexpr int GuestEinval = 22;
constexpr int GuestEexist = 17;
constexpr int GuestExdev = 18;
constexpr int GuestEdeadlk = 11;
constexpr int GuestEagain = 35;
constexpr int GuestEloop = 62;
constexpr int GuestEnametoolong = 63;
constexpr int GuestEnotempty = 66;
constexpr int GuestEoverflow = 84;
constexpr int GuestAtFdcwd = -100;

std::int64_t Fail(int error) {
    *__error_nid_postfix() = error;
    return -1;
}

int GuestError(const std::error_code& error) {
    const auto condition = error.default_error_condition();
    if (condition == std::errc::resource_unavailable_try_again) return GuestEagain;
    if (condition == std::errc::resource_deadlock_would_occur) return GuestEdeadlk;
    if (condition == std::errc::too_many_symbolic_link_levels) return GuestEloop;
    if (condition == std::errc::filename_too_long) return GuestEnametoolong;
    if (condition == std::errc::directory_not_empty) return GuestEnotempty;
    if (condition == std::errc::value_too_large) return GuestEoverflow;
    const int value = condition.value();
    return value > 0 && value <= 34 ? value : GuestEio;
}
}

extern "C" {

int APS5_VABI fork_nid_postfix(void) {
    NotImplemented_nid_no_patch("fork: child processes");
    return -1;
}

int APS5_VABI setsid_nid_postfix(void) {
    return static_cast<int>(Fail(GuestEperm));
}

std::uint16_t APS5_VABI umask_nid_postfix(std::uint16_t mask) {
    return File::ExchangeCreationMask_nid_no_patch(mask);
}

int APS5_VABI _fstatfs_nid_postfix(int d, void* buf);

int APS5_VABI fstatfs_nid_postfix(int d, void* buf) {
    return _fstatfs_nid_postfix(d, buf);
}

std::int64_t APS5_VABI readlink_nid_postfix(const char* path, char* buffer, std::size_t size) {
    if (path == nullptr) return Fail(GuestEfault);
    if (*path == '\0') return Fail(GuestEnoent);
    if (size > static_cast<std::size_t>(std::numeric_limits<std::int64_t>::max())) return Fail(GuestEinval);
    std::filesystem::path native;
    if (const int error = ResolvePathError_nid_no_patch(path, native)) return Fail(error);
#ifdef _WIN32
    const DWORD attributes = GetFileAttributesW(native.wstring().c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        NotImplemented_nid_no_patch("readlink of a Windows symbolic link");
        return -1;
    }
#endif
    std::error_code error;
    const auto status = std::filesystem::symlink_status(native, error);
    if (error) return Fail(GuestError(error));
    if (status.type() == std::filesystem::file_type::not_found) return Fail(GuestEnoent);
    if (!std::filesystem::is_symlink(status)) return Fail(GuestEinval);
    const auto target = std::filesystem::read_symlink(native, error).generic_string();
    if (error) return Fail(GuestError(error));
    const auto count = std::min(size, target.size());
    if (count != 0 && buffer == nullptr) return Fail(GuestEfault);
    if (count != 0) std::memcpy(buffer, target.data(), count);
    return static_cast<std::int64_t>(count);
}

int APS5_VABI link_nid_postfix(const char* existing, const char* created) {
    if (existing == nullptr || created == nullptr) return static_cast<int>(Fail(GuestEfault));
    if (*existing == '\0' || *created == '\0') return static_cast<int>(Fail(GuestEnoent));
    std::filesystem::path source, destination;
    if (const int error = ResolvePathError_nid_no_patch(existing, source)) return static_cast<int>(Fail(error));
    if (const int error = ResolvePathError_nid_no_patch(created, destination)) return static_cast<int>(Fail(error));
    std::error_code error;
    const auto status = std::filesystem::symlink_status(source, error);
    if (!std::filesystem::exists(status)) return static_cast<int>(Fail(GuestEnoent));
    if (std::filesystem::is_symlink(status)) throw std::runtime_error("link: a symbolic link as the existing path is not supported");
    if (std::filesystem::is_directory(status)) return static_cast<int>(Fail(GuestEperm));
    if (std::filesystem::exists(std::filesystem::symlink_status(destination, error))) return static_cast<int>(Fail(GuestEexist));
    if (!std::filesystem::is_directory(destination.parent_path(), error)) return static_cast<int>(Fail(GuestEnoent));
    std::filesystem::create_hard_link(source, destination, error);
    if (error == std::errc::cross_device_link) return static_cast<int>(Fail(GuestExdev));
    if (error) throw std::system_error(error, "link");
    RecordWrittenPath_nid_no_patch(destination);
    return 0;
}

int APS5_VABI fchdir_nid_postfix(int fd) {
    int error = 0;
    const char* path = GetDirectoryDescriptorPath_nid_no_patch(fd, &error);
    if (path == nullptr) return static_cast<int>(Fail(error));
#ifdef __linux__
    if (::faccessat(fd, ".", X_OK, AT_EACCESS) != 0) return static_cast<int>(Fail(errno));
#endif
    error = SetWorkingDirectory_nid_no_patch(path);
    if (error != 0) return static_cast<int>(Fail(error));
    return 0;
}

int APS5_VABI symlink_nid_postfix(const char* target, const char* created) {
    if (target == nullptr || created == nullptr) return static_cast<int>(Fail(GuestEfault));
    if (*target == '\0' || *created == '\0') return static_cast<int>(Fail(GuestEnoent));
    if (*target == '/') {
        NotImplemented_nid_no_patch("symlink: absolute targets");
        return -1;
    }
    std::filesystem::path native;
    if (const int error = ResolvePathError_nid_no_patch(created, native)) return static_cast<int>(Fail(error));
    std::error_code error;
#ifdef _WIN32
    if (GetFileAttributesW(native.wstring().c_str()) != INVALID_FILE_ATTRIBUTES) return static_cast<int>(Fail(GuestEexist));
#else
    if (std::filesystem::exists(std::filesystem::symlink_status(native, error))) return static_cast<int>(Fail(GuestEexist));
#endif
    if (!std::filesystem::is_directory(native.parent_path(), error)) return static_cast<int>(Fail(GuestEnoent));
    const std::filesystem::path contents(target);
    const bool directory = std::filesystem::is_directory(native.parent_path() / contents, error);
#ifdef _WIN32
    DWORD flags = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
    if (directory) flags |= SYMBOLIC_LINK_FLAG_DIRECTORY;
    if (!CreateSymbolicLinkW(native.wstring().c_str(), std::filesystem::path(contents).make_preferred().wstring().c_str(), flags)) {
        const DWORD code = GetLastError();
        if (code == ERROR_PRIVILEGE_NOT_HELD) return static_cast<int>(Fail(GuestEperm));
        if (code == ERROR_ALREADY_EXISTS || code == ERROR_FILE_EXISTS) return static_cast<int>(Fail(GuestEexist));
        if (code == ERROR_PATH_NOT_FOUND) return static_cast<int>(Fail(GuestEnoent));
        throw std::system_error(static_cast<int>(code), std::system_category(), "symlink");
    }
#else
    if (directory)
        std::filesystem::create_directory_symlink(contents, native, error);
    else
        std::filesystem::create_symlink(contents, native, error);
    if (error) throw std::system_error(error, "symlink");
#endif
    RecordWrittenPath_nid_no_patch(native);
    return 0;
}

int APS5_VABI open_nid_postfix(const char* path, int flags, int mode);

int APS5_VABI openat_nid_postfix(int fd, const char* path, int flags, ...) {
    int mode = 0;
    if (flags & SCE_KERNEL_O_CREAT) {
#ifdef _WIN32
        __builtin_sysv_va_list arguments;
        __builtin_sysv_va_start(arguments, flags);
        mode = __builtin_va_arg(arguments, int);
        __builtin_sysv_va_end(arguments);
#else
        std::va_list arguments;
        va_start(arguments, flags);
        mode = va_arg(arguments, int);
        va_end(arguments);
#endif
    }
    if (path == nullptr) return static_cast<int>(Fail(GuestEfault));
    if (*path == '\0') return static_cast<int>(Fail(GuestEnoent));
    if (fd == GuestAtFdcwd || *path == '/') return open_nid_postfix(path, flags, mode);
    const int result = OpenInDirectory_nid_no_patch(fd, path, flags, static_cast<std::uint16_t>(mode));
    if (result < 0) return static_cast<int>(Fail(result & 0xffff));
    return result;
}

}
