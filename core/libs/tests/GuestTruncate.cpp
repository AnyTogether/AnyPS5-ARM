#include "prx/libc/include/general/VabiMacros.hpp"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <unistd.h>
#endif

extern "C" {
int APS5_VABI truncate_nid_postfix(const char*, std::int64_t);
int APS5_VABI sceKernelTruncate_nid_postfix(const char*, std::int64_t);
int* APS5_VABI __error_nid_postfix();
}

static void Require(bool value) { if (!value) std::abort(); }

constexpr int GuestEnoent = 2;
constexpr int GuestEacces = 13;
constexpr int GuestEfault = 14;
constexpr int GuestEisdir = 21;
constexpr int GuestEinval = 22;
constexpr int SceKernelErrorBase = static_cast<int>(0x80020000u);

static void RequireFailure(int result, int error) {
    Require(result == -1);
    Require(*__error_nid_postfix() == error);
}

static std::string Contents(const std::filesystem::path& file) {
    std::ifstream stream(file, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

int main() {
    const auto name = "anyps5-truncate-test-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    const auto directory = std::filesystem::path(name);
    Require(std::filesystem::create_directory(directory));
    const auto file = directory / "sized.txt";
    { std::ofstream output(file, std::ios::binary); output << "0123456789abcdef"; }
    const auto path = file.string();

    Require(truncate_nid_postfix(path.c_str(), 6) == 0);
    Require(std::filesystem::file_size(file) == 6);
    Require(Contents(file) == "012345");

    Require(truncate_nid_postfix(path.c_str(), 9) == 0);
    Require(std::filesystem::file_size(file) == 9);
    Require(Contents(file) == std::string("012345\0\0\0", 9));

    Require(truncate_nid_postfix(path.c_str(), 0) == 0);
    Require(std::filesystem::file_size(file) == 0);

    RequireFailure(truncate_nid_postfix(path.c_str(), -1), GuestEinval);
    Require(std::filesystem::file_size(file) == 0);
    RequireFailure(truncate_nid_postfix((directory / "missing").string().c_str(), 0), GuestEnoent);
    RequireFailure(truncate_nid_postfix("", 0), GuestEnoent);
    RequireFailure(truncate_nid_postfix(nullptr, 0), GuestEfault);
    RequireFailure(truncate_nid_postfix(directory.string().c_str(), 0), GuestEisdir);
    Require(std::filesystem::is_directory(directory));
    Require(sceKernelTruncate_nid_postfix(directory.string().c_str(), 0) == SceKernelErrorBase + GuestEisdir);
    Require(sceKernelTruncate_nid_postfix(path.c_str(), -1) == SceKernelErrorBase + GuestEinval);

    { std::ofstream output(file, std::ios::binary); output << "locked"; }
#ifdef _WIN32
    Require(SetFileAttributesW(file.c_str(), FILE_ATTRIBUTE_READONLY));
    RequireFailure(truncate_nid_postfix(path.c_str(), 1), GuestEacces);
    Require(sceKernelTruncate_nid_postfix(path.c_str(), 1) == SceKernelErrorBase + GuestEacces);
    Require(SetFileAttributesW(file.c_str(), FILE_ATTRIBUTE_NORMAL));
#else
    std::filesystem::permissions(file, std::filesystem::perms::owner_read);
    if (::geteuid() != 0) {
        RequireFailure(truncate_nid_postfix(path.c_str(), 1), GuestEacces);
        Require(sceKernelTruncate_nid_postfix(path.c_str(), 1) == SceKernelErrorBase + GuestEacces);
    } else {
        std::fprintf(stderr, "running as root, which ignores file permissions: the read-only cases not tested\n");
    }
    std::filesystem::permissions(file, std::filesystem::perms::owner_read | std::filesystem::perms::owner_write);
#endif
    Require(Contents(file) == "locked");

    Require(std::filesystem::remove(file));
    Require(std::filesystem::remove(directory));
}
