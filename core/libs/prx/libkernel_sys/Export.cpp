#include <atomic>
#include <algorithm>
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
#include "prx/libkernel/File/include/DirectoryDescriptor.hpp"

extern "C" int* APS5_VABI __error_nid_postfix();

namespace {
constexpr int GuestEnoent = 2;
constexpr int GuestEperm = 1;
constexpr int GuestEio = 5;
constexpr int GuestEfault = 14;
constexpr int GuestEinval = 22;
constexpr int GuestEexist = 17;
constexpr int GuestExdev = 18;
#ifdef _WIN32
constexpr int WindowsPrivilegeNotHeld = 1314;
#endif

std::atomic<std::uint16_t> creationMask{022};

std::int64_t Fail(int error) {
    *__error_nid_postfix() = error;
    return -1;
}

int GuestError(const std::error_code& error) {
    const int value = error.default_error_condition().value();
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
    return creationMask.exchange(static_cast<std::uint16_t>(mask & 07777));
}

int APS5_VABI _fstatfs_nid_postfix(int d, void* buf);

int APS5_VABI fstatfs_nid_postfix(int d, void* buf) {
    return _fstatfs_nid_postfix(d, buf);
}

std::int64_t APS5_VABI readlink_nid_postfix(const char* path, char* buffer, std::size_t size) {
    if (path == nullptr) return Fail(GuestEfault);
    if (*path == '\0') return Fail(GuestEnoent);
    if (size > static_cast<std::size_t>(std::numeric_limits<std::int64_t>::max())) return Fail(GuestEinval);
    const auto native = ResolvePath_nid_no_patch(path);
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
    const auto source = ResolvePath_nid_no_patch(existing);
    const auto destination = ResolvePath_nid_no_patch(created);
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
    const auto native = ResolvePath_nid_no_patch(created);
    std::error_code error;
    if (std::filesystem::exists(std::filesystem::symlink_status(native, error))) return static_cast<int>(Fail(GuestEexist));
    if (!std::filesystem::is_directory(native.parent_path(), error)) return static_cast<int>(Fail(GuestEnoent));
    const std::filesystem::path contents(target);
    if (std::filesystem::is_directory(native.parent_path() / contents, error))
        std::filesystem::create_directory_symlink(contents, native, error);
    else
        std::filesystem::create_symlink(contents, native, error);
#ifdef _WIN32
    if (error.category() == std::system_category() && error.value() == WindowsPrivilegeNotHeld) return static_cast<int>(Fail(GuestEperm));
#endif
    if (error) throw std::system_error(error, "symlink");
    RecordWrittenPath_nid_no_patch(native);
    return 0;
}

}
