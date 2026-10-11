#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libkernel/KernelErrors.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
struct SceKernelSystemSwVersion {
    std::uint64_t size;
    char versionString[0x1C];
    std::uint32_t version;
};
static_assert(offsetof(SceKernelSystemSwVersion, size) == 0x00);
static_assert(offsetof(SceKernelSystemSwVersion, versionString) == 0x08);
static_assert(offsetof(SceKernelSystemSwVersion, version) == 0x24);
static_assert(sizeof(SceKernelSystemSwVersion) == 0x28);
extern "C" {
std::int64_t APS5_VABI sysconf_nid_postfix(int);
int APS5_VABI getpagesize_nid_postfix();
int* APS5_VABI __error_nid_postfix();
int APS5_VABI sysctl_nid_postfix(const int*, std::uint32_t, void*, std::size_t*, const void*, std::size_t);
int APS5_VABI sysctlbyname_nid_postfix(const char*, void*, std::size_t*, const void*, std::size_t);
int APS5_VABI sceKernelGetSystemSwVersion_nid_postfix(SceKernelSystemSwVersion*);
extern char** environ_nid_postfix;
}
static void Require(bool value) { if (!value) std::abort(); }
static void CheckProcessorCountSysctl() {
    const int mib[] = {6, 3};
    const int processors = static_cast<int>(sysconf_nid_postfix(58));
    *__error_nid_postfix() = 13;
    std::size_t length = 0;
    Require(sysctl_nid_postfix(mib, 2, nullptr, &length, nullptr, 0) == 0 && length == sizeof(int));
    int value = 0;
    length = sizeof(value);
    Require(sysctl_nid_postfix(mib, 2, &value, &length, nullptr, 0) == 0 && value == processors && length == sizeof(int));
    value = 0;
    length = 16;
    Require(sysctlbyname_nid_postfix("hw.ncpu", &value, &length, nullptr, 0) == 0 && value == processors && length == sizeof(int));
    Require(*__error_nid_postfix() == 13);
    unsigned char bytes[4] = {0xaa, 0xaa, 0xaa, 0xaa};
    length = 2;
    Require(sysctlbyname_nid_postfix("hw.ncpu", bytes, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 12);
    Require(length == 2 && bytes[2] == 0xaa && bytes[3] == 0xaa);
    Require(sysctl_nid_postfix(mib, 2, bytes, nullptr, nullptr, 0) == -1 && *__error_nid_postfix() == 12);
    length = sizeof(value);
    Require(sysctl_nid_postfix(mib, 2, &value, &length, &value, sizeof(value)) == -1 && *__error_nid_postfix() == 1);
    Require(sysctl_nid_postfix(mib, 1, &value, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 22);
    Require(sysctl_nid_postfix(mib, 25, &value, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 22);
    Require(sysctl_nid_postfix(nullptr, 2, &value, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 14);
    Require(sysctlbyname_nid_postfix(nullptr, &value, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 14);
    bool threw = false;
    try {
        sysctlbyname_nid_postfix("kern.osreldate", &value, &length, nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw);
    threw = false;
    const int unknown[] = {6, 5};
    try {
        sysctl_nid_postfix(unknown, 2, &value, &length, nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw);
}
static void CheckSystemSwVersion() {
    *__error_nid_postfix() = 13;
    Require(sceKernelGetSystemSwVersion_nid_postfix(nullptr) == SCE_KERNEL_ERROR_EFAULT && *__error_nid_postfix() == 13);
    SceKernelSystemSwVersion version{};
    version.size = 0;
    *__error_nid_postfix() = 13;
    Require(sceKernelGetSystemSwVersion_nid_postfix(&version) == SCE_KERNEL_ERROR_EINVAL && *__error_nid_postfix() == 13);
    version.size = sizeof(SceKernelSystemSwVersion) - 1;
    *__error_nid_postfix() = 13;
    Require(sceKernelGetSystemSwVersion_nid_postfix(&version) == SCE_KERNEL_ERROR_EINVAL && *__error_nid_postfix() == 13);
    version.size = sizeof(SceKernelSystemSwVersion) + 1;
    *__error_nid_postfix() = 13;
    Require(sceKernelGetSystemSwVersion_nid_postfix(&version) == SCE_KERNEL_ERROR_EINVAL && *__error_nid_postfix() == 13);
    std::memset(&version, 0xaa, sizeof(version));
    version.size = sizeof(SceKernelSystemSwVersion);
    *__error_nid_postfix() = 13;
    Require(sceKernelGetSystemSwVersion_nid_postfix(&version) == 0 && *__error_nid_postfix() == 13);
    Require(version.size == sizeof(SceKernelSystemSwVersion));
    Require(std::strcmp(version.versionString, "01.000.000") == 0);
    for (std::size_t i = sizeof("01.000.000"); i < sizeof(version.versionString); ++i) {
        Require(version.versionString[i] == 0);
    }
    Require(version.version == 0x01000000);
}
static void CheckPseudoRandomSysctl() {
    *__error_nid_postfix() = 13;
    unsigned char first[64] = {};
    unsigned char second[64] = {};
    std::size_t length = sizeof(first);
    Require(sysctlbyname_nid_postfix("kern.rng_pseudo", first, &length, nullptr, 0) == 0 && length == sizeof(first));
    length = sizeof(second);
    Require(sysctlbyname_nid_postfix("kern.rng_pseudo", second, &length, nullptr, 0) == 0 && length == sizeof(second));
    Require(std::memcmp(first, second, sizeof(first)) != 0);
    Require(*__error_nid_postfix() == 13);
    Require(sysctlbyname_nid_postfix("kern.rng_pseudo", first, &length, first, sizeof(first)) == -1 && *__error_nid_postfix() == 1);
    bool threw = false;
    try {
        sysctlbyname_nid_postfix("kern.rng_pseudo", nullptr, &length, nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw);
}
int main() {
    CheckProcessorCountSysctl();
    CheckSystemSwVersion();
    CheckPseudoRandomSysctl();
    *__error_nid_postfix() = 13;
    Require(sysconf_nid_postfix(47) == 0x4000);
    Require(getpagesize_nid_postfix() == sysconf_nid_postfix(47));
    Require(sysconf_nid_postfix(57) > 0);
    Require(sysconf_nid_postfix(58) > 0);
    Require(sysconf_nid_postfix(121) > 0);
    Require(*__error_nid_postfix() == 13);
    Require(sysconf_nid_postfix(-1) == -1); // verifies full-width signed return
    Require(*__error_nid_postfix() == 22);
    Require(sysconf_nid_postfix(0x7fffffff) == -1);
    Require(environ_nid_postfix && !environ_nid_postfix[0]);
}
