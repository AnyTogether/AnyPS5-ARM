#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libkernel/File/include/FileFlags.hpp"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <source_location>
#include <string>
#ifdef _WIN32
#include <windows.h>
#endif
#ifdef __linux__
#include <cerrno>
#include <unistd.h>
#endif

extern "C" {
int APS5_VABI fstatfs_nid_postfix(int, void*);
int APS5_VABI _fstatfs_nid_postfix(int, void*);
int APS5_VABI open_nid_postfix(const char*, int, int);
int APS5_VABI close_nid_postfix(int);
std::int64_t APS5_VABI readlink_nid_postfix(const char*, char*, std::size_t);
int APS5_VABI fchdir_nid_postfix(int);
int APS5_VABI chdir_nid_postfix(const char*);
char* APS5_VABI getcwd_nid_postfix(char*, std::size_t);
int APS5_VABI sceKernelOpen(const char*, int, std::uint16_t);
int APS5_VABI sceKernelClose(int);
int APS5_VABI setsid_nid_postfix(void);
int APS5_VABI link_nid_postfix(const char*, const char*);
int APS5_VABI symlink_nid_postfix(const char*, const char*);
int APS5_VABI openat_nid_postfix(int, const char*, int, ...);
std::int64_t APS5_VABI sceKernelRead(int, void*, std::size_t);
std::uint16_t APS5_VABI umask_nid_postfix(std::uint16_t);
int* APS5_VABI __error_nid_postfix();
}

void Require(bool condition, std::source_location location = std::source_location::current()) {
    if (!condition) {
        std::fprintf(stderr, "Kernel sys check failed at line %u (guest errno %d)\n", location.line(), *__error_nid_postfix());
        std::abort();
    }
}

int Error() {
    return *__error_nid_postfix();
}

int main() {
    Require(setsid_nid_postfix() == -1 && Error() == 1);
    Require(umask_nid_postfix(0) == 022);
    Require(umask_nid_postfix(07777) == 0);
    Require(umask_nid_postfix(022) == 07777);
    const auto root = std::filesystem::path("anyps5-kernel-sys-test-" +
        std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    Require(std::filesystem::create_directory(root));
    const auto file = (root / "file.txt").string();
    std::ofstream(file).put('x');
    const int descriptor = open_nid_postfix(file.c_str(), 0, 0);
    Require(descriptor >= 0);
    unsigned char viaPublic[472] = {};
    unsigned char viaSyscall[472] = {};
    Require(fstatfs_nid_postfix(descriptor, viaPublic) == 0 && _fstatfs_nid_postfix(descriptor, viaSyscall) == 0);
    Require(std::memcmp(viaPublic, viaSyscall, 4) == 0 && std::memcmp(viaPublic + 16, viaSyscall + 16, 8) == 0);
    Require(std::memcmp(viaPublic + 280, viaSyscall + 280, 16) == 0);
    Require(fstatfs_nid_postfix(descriptor, nullptr) == -1 && Error() == 14);
    Require(close_nid_postfix(descriptor) == 0);
    Require(fstatfs_nid_postfix(-1, viaPublic) == -1 && Error() == 9);
    char buffer[64];
    for (const auto& component : {std::string("missing"), std::string("file.txt")}) {
        const auto prefix = root.generic_string() + "/" + component + "/../";
        const auto invalid = prefix + "file.txt";
        const auto created = prefix + "new.txt";
        const int expected = component == "missing" ? 2 : 20;
        Require(readlink_nid_postfix(invalid.c_str(), buffer, sizeof(buffer)) == -1 && Error() == expected);
        Require(link_nid_postfix(invalid.c_str(), created.c_str()) == -1 && Error() == expected);
        Require(link_nid_postfix(file.c_str(), created.c_str()) == -1 && Error() == expected);
        Require(symlink_nid_postfix("file.txt", created.c_str()) == -1 && Error() == expected);
        Require(std::filesystem::hard_link_count(file) == 1 && !std::filesystem::exists(root / "new.txt"));
    }
    Require(readlink_nid_postfix(file.c_str(), buffer, sizeof(buffer)) == -1 && Error() == 22);
    Require(readlink_nid_postfix(root.string().c_str(), buffer, sizeof(buffer)) == -1 && Error() == 22);
    Require(readlink_nid_postfix((root / "missing").string().c_str(), buffer, sizeof(buffer)) == -1 && Error() == 2);
    Require(readlink_nid_postfix("", buffer, sizeof(buffer)) == -1 && Error() == 2);
    Require(readlink_nid_postfix(nullptr, buffer, sizeof(buffer)) == -1 && Error() == 14);
#ifndef _WIN32
    Require(readlink_nid_postfix((root / std::string(300, 'n')).string().c_str(), buffer, sizeof(buffer)) == -1 && Error() == 63);
#endif
    std::error_code error;
    const auto link = (root / "link").string();
    std::filesystem::create_symlink("sub/target.txt", link, error);
    if (!error) {
        std::memset(buffer, '#', sizeof(buffer));
        Require(readlink_nid_postfix(link.c_str(), buffer, sizeof(buffer)) == 14);
        Require(std::memcmp(buffer, "sub/target.txt", 14) == 0 && buffer[14] == '#');
        std::memset(buffer, '#', sizeof(buffer));
        Require(readlink_nid_postfix(link.c_str(), buffer, 3) == 3);
        Require(std::memcmp(buffer, "sub", 3) == 0 && buffer[3] == '#');
        Require(readlink_nid_postfix(link.c_str(), nullptr, 0) == 0);
        Require(readlink_nid_postfix(link.c_str(), nullptr, sizeof(buffer)) == -1 && Error() == 14);
        Require(readlink_nid_postfix((root / "LINK").string().c_str(), buffer, sizeof(buffer)) == 14);
#ifndef _WIN32
        std::filesystem::create_symlink("loopB", root / "loopA");
        std::filesystem::create_symlink("loopA", root / "loopB");
        Require(readlink_nid_postfix((root / "loopA" / "inner").string().c_str(), buffer, sizeof(buffer)) == -1 && Error() == 62);
#endif
    } else {
        std::fprintf(stderr, "symbolic links unavailable: the link cases not tested\n");
    }
    const auto original = (root / "original.bin").string();
    const auto linked = (root / "linked.bin").string();
    std::ofstream(original) << "abc";
    Require(link_nid_postfix(original.c_str(), linked.c_str()) == 0);
    Require(std::filesystem::hard_link_count(original) == 2 && std::filesystem::file_size(linked) == 3);
    std::ofstream(linked, std::ios::trunc).close();
    Require(std::filesystem::file_size(original) == 0);
    Require(link_nid_postfix(original.c_str(), linked.c_str()) == -1 && Error() == 17);
    Require(link_nid_postfix((root / "missing").string().c_str(), (root / "other").string().c_str()) == -1 && Error() == 2);
    Require(link_nid_postfix(original.c_str(), (root / "missing" / "linked.bin").string().c_str()) == -1 && Error() == 2);
    Require(link_nid_postfix(root.string().c_str(), (root / "directory").string().c_str()) == -1 && Error() == 1);
    Require(link_nid_postfix(nullptr, linked.c_str()) == -1 && Error() == 14);
    Require(link_nid_postfix(original.c_str(), "") == -1 && Error() == 2);
    Require(std::filesystem::remove(linked) && std::filesystem::hard_link_count(original) == 1);
    const int directory = sceKernelOpen(root.string().c_str(), SCE_KERNEL_O_RDONLY | SCE_KERNEL_O_DIRECTORY, 0);
    Require(directory >= 0);
    const int fileDescriptor = sceKernelOpen(file.c_str(), SCE_KERNEL_O_RDONLY, 0);
    Require(fileDescriptor >= 0);
    Require(fchdir_nid_postfix(-1) == -1 && Error() == 9);
    Require(fchdir_nid_postfix(fileDescriptor) == -1 && Error() == 20);
    Require(fchdir_nid_postfix(directory) == 0);
    char directoryPath[1024];
    Require(getcwd_nid_postfix(directoryPath, sizeof(directoryPath)) == directoryPath);
    Require(std::strcmp(directoryPath, ("/" + root.filename().string()).c_str()) == 0);
#ifdef __linux__
    Require(chdir_nid_postfix("/") == 0);
    const auto originalPermissions = std::filesystem::status(root).permissions();
    std::filesystem::permissions(root, std::filesystem::perms::owner_read | std::filesystem::perms::owner_write);
    const bool searchDenied = ::access(root.c_str(), X_OK) == -1 && errno == EACCES;
    const int deniedResult = searchDenied ? fchdir_nid_postfix(directory) : 0;
    const int deniedError = Error();
    const bool cwdUnchanged = getcwd_nid_postfix(directoryPath, sizeof(directoryPath)) == directoryPath && std::strcmp(directoryPath, "/") == 0;
    std::filesystem::permissions(root, std::filesystem::perms::owner_exec);
    const int searchOnlyResult = fchdir_nid_postfix(directory);
    std::filesystem::permissions(root, originalPermissions);
    if (searchDenied) Require(deniedResult == -1 && deniedError == EACCES && cwdUnchanged);
    Require(searchOnlyResult == 0);
#endif
    Require(sceKernelClose(fileDescriptor) == 0);
    Require(sceKernelClose(directory) == 0);
    Require(fchdir_nid_postfix(directory) == -1 && Error() == 9);
    Require(chdir_nid_postfix("/") == 0);
    const auto symbolic = (root / "symbolic").string();
    const int created = symlink_nid_postfix("original.bin", symbolic.c_str());
    if (created == 0) {
        const auto dangling = (root / "dangling").string();
#ifdef _WIN32
        Require((GetFileAttributesW(std::filesystem::path(symbolic).wstring().c_str()) & FILE_ATTRIBUTE_REPARSE_POINT) != 0);
        Require(symlink_nid_postfix("original.bin", symbolic.c_str()) == -1 && Error() == 17);
        Require(symlink_nid_postfix("missing.bin", dangling.c_str()) == 0);
        Require((GetFileAttributesW(std::filesystem::path(dangling).wstring().c_str()) & FILE_ATTRIBUTE_REPARSE_POINT) != 0);
        Require(symlink_nid_postfix("missing.bin", dangling.c_str()) == -1 && Error() == 17);
#else
        Require(std::filesystem::is_symlink(std::filesystem::symlink_status(symbolic)));
        Require(readlink_nid_postfix(symbolic.c_str(), buffer, sizeof(buffer)) == 12 && std::memcmp(buffer, "original.bin", 12) == 0);
        Require(std::filesystem::file_size(symbolic) == std::filesystem::file_size(original));
        Require(symlink_nid_postfix("original.bin", symbolic.c_str()) == -1 && Error() == 17);
        Require(symlink_nid_postfix("missing.bin", dangling.c_str()) == 0);
        Require(readlink_nid_postfix(dangling.c_str(), buffer, sizeof(buffer)) == 11 && !std::filesystem::exists(dangling));
        Require(symlink_nid_postfix("missing.bin", dangling.c_str()) == -1 && Error() == 17);
#endif
    } else {
        Require(created == -1 && Error() == 1);
        std::fprintf(stderr, "symbolic links unavailable: the symlink success cases not tested\n");
    }
    Require(symlink_nid_postfix("original.bin", (root / "missing" / "symbolic").string().c_str()) == -1 && Error() == 2);
    Require(symlink_nid_postfix(nullptr, symbolic.c_str()) == -1 && Error() == 14);
    Require(symlink_nid_postfix("original.bin", "") == -1 && Error() == 2);
    const int base = sceKernelOpen(root.string().c_str(), SCE_KERNEL_O_RDONLY | SCE_KERNEL_O_DIRECTORY, 0);
    Require(base >= 0);
    const int relative = openat_nid_postfix(base, "file.txt", SCE_KERNEL_O_RDONLY);
    char byte = 0;
    Require(relative >= 0 && sceKernelRead(relative, &byte, 1) == 1 && byte == 'x');
    Require(sceKernelClose(relative) == 0);
    const int made = openat_nid_postfix(base, "made.bin", SCE_KERNEL_O_WRONLY | SCE_KERNEL_O_CREAT | SCE_KERNEL_O_EXCL, 0644);
    Require(made >= 0 && std::filesystem::is_regular_file(root / "made.bin"));
    Require(sceKernelClose(made) == 0);
    Require(openat_nid_postfix(base, "made.bin", SCE_KERNEL_O_WRONLY | SCE_KERNEL_O_CREAT | SCE_KERNEL_O_EXCL, 0644) == -1 && Error() == 17);
    Require(openat_nid_postfix(base, "missing.bin", SCE_KERNEL_O_RDONLY) == -1 && Error() == 2);
    const auto guestFile = "/" + root.filename().string() + "/file.txt";
    const int absolute = openat_nid_postfix(-1, guestFile.c_str(), SCE_KERNEL_O_RDONLY);
    Require(absolute >= 0 && sceKernelClose(absolute) == 0);
    const int current = openat_nid_postfix(-100, file.c_str(), SCE_KERNEL_O_RDONLY);
    Require(current >= 0 && sceKernelClose(current) == 0);
    const int plain = sceKernelOpen(file.c_str(), SCE_KERNEL_O_RDONLY, 0);
    Require(plain >= 0);
    Require(openat_nid_postfix(plain, "file.txt", SCE_KERNEL_O_RDONLY) == -1 && Error() == 20);
    Require(sceKernelClose(plain) == 0);
    Require(openat_nid_postfix(-1, "file.txt", SCE_KERNEL_O_RDONLY) == -1 && Error() == 9);
    Require(openat_nid_postfix(base, nullptr, SCE_KERNEL_O_RDONLY) == -1 && Error() == 14);
    Require(openat_nid_postfix(base, "", SCE_KERNEL_O_RDONLY) == -1 && Error() == 2);
    Require(sceKernelClose(base) == 0);
    std::filesystem::remove_all(root);
    return 0;
}
