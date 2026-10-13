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
int APS5_VABI getpid_nid_postfix();
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
    const int unknown[] = {6, 99};
    try {
        sysctl_nid_postfix(unknown, 2, &value, &length, nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw);
}
static void CheckPhysicalMemorySysctl() {
    const int mib[] = {6, 5};
    const std::uint64_t expected = static_cast<std::uint64_t>(sysconf_nid_postfix(121)) * 0x4000;
    *__error_nid_postfix() = 13;
    std::size_t length = 0;
    Require(sysctl_nid_postfix(mib, 2, nullptr, &length, nullptr, 0) == 0 && length == sizeof(std::uint64_t));
    std::uint64_t value = 0;
    length = sizeof(value);
    Require(sysctl_nid_postfix(mib, 2, &value, &length, nullptr, 0) == 0 && value == expected && length == sizeof(std::uint64_t));
    value = 0;
    length = 16;
    Require(sysctlbyname_nid_postfix("hw.physmem", &value, &length, nullptr, 0) == 0 && value == expected && length == sizeof(std::uint64_t));
    Require(*__error_nid_postfix() == 13);
    unsigned char bytes[8] = {0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa};
    length = 4;
    Require(sysctlbyname_nid_postfix("hw.physmem", bytes, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 12);
    Require(length == 4 && bytes[4] == 0xaa);
    length = sizeof(value);
    Require(sysctl_nid_postfix(mib, 2, &value, &length, &value, sizeof(value)) == -1 && *__error_nid_postfix() == 1);
    Require(sysctlbyname_nid_postfix("hw.physmem", &value, &length, &value, sizeof(value)) == -1 && *__error_nid_postfix() == 1);
}
#if defined(__x86_64__) || defined(__i386__)
static void CheckModelSysctl() {
    const int mib[] = {6, 2};
    *__error_nid_postfix() = 13;
    std::size_t length = 0;
    Require(sysctl_nid_postfix(mib, 2, nullptr, &length, nullptr, 0) == 0 && length > 1);
    const std::size_t size = length;
    char model[128] = {};
    length = sizeof(model);
    Require(sysctlbyname_nid_postfix("hw.model", model, &length, nullptr, 0) == 0 && length == size);
    Require(std::strlen(model) + 1 == size && model[0] != ' ');
    Require(*__error_nid_postfix() == 13);
    char truncated[4] = {};
    length = sizeof(truncated);
    Require(sysctl_nid_postfix(mib, 2, truncated, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 12);
    Require(length == sizeof(truncated) && std::memcmp(truncated, model, sizeof(truncated)) == 0);
    length = sizeof(model);
    Require(sysctlbyname_nid_postfix("hw.model", model, &length, model, size) == -1 && *__error_nid_postfix() == 1);
}
#endif
static void CheckMachdepCachelineSizeSysctl() {
    *__error_nid_postfix() = 13;
    int value = 0x5a5a5a5a;
    std::size_t length = sizeof(value);
    Require(sysctlbyname_nid_postfix("machdep.cacheline_size", &value, &length, nullptr, 0) == -1);
    Require(*__error_nid_postfix() == 2);
    Require(value == 0x5a5a5a5a);
}
static void CheckPathnameSysctl() {
    *__error_nid_postfix() = 13;
    char buffer[32] = {};
    std::size_t length = sizeof(buffer);
    Require(sysctlbyname_nid_postfix("kern.proc.pathname", buffer, &length, nullptr, 0) == -1);
    Require(*__error_nid_postfix() == 22);

    const int mibTooShort[] = {1, 14, 12};
    Require(sysctl_nid_postfix(mibTooShort, 3, buffer, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 22);

    const int mibTooLong[] = {1, 14, 12, -1, 0};
    Require(sysctl_nid_postfix(mibTooLong, 5, buffer, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 22);

    const int mibSelf[] = {1, 14, 12, -1};
    length = 0;
    Require(sysctl_nid_postfix(mibSelf, 4, nullptr, &length, nullptr, 0) == 0 && length == sizeof("/app0/eboot.bin"));

    std::memset(buffer, 0xaa, sizeof(buffer));
    length = sizeof(buffer);
    Require(sysctl_nid_postfix(mibSelf, 4, buffer, &length, nullptr, 0) == 0);
    Require(length == sizeof("/app0/eboot.bin"));
    Require(std::strcmp(buffer, "/app0/eboot.bin") == 0);

    const int callerPid = getpid_nid_postfix();
    const int mibPid[] = {1, 14, 12, callerPid};
    std::memset(buffer, 0xaa, sizeof(buffer));
    length = sizeof(buffer);
    Require(sysctl_nid_postfix(mibPid, 4, buffer, &length, nullptr, 0) == 0);
    Require(length == sizeof("/app0/eboot.bin"));
    Require(std::strcmp(buffer, "/app0/eboot.bin") == 0);

    const int mibForeign[] = {1, 14, 12, callerPid + 1000};
    Require(sysctl_nid_postfix(mibForeign, 4, buffer, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 3);

    length = 5;
    std::memset(buffer, 0xaa, sizeof(buffer));
    Require(sysctl_nid_postfix(mibSelf, 4, buffer, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 12);
    Require(length == 5 && buffer[4] == '0' && buffer[5] == static_cast<char>(0xaa));

    length = sizeof(buffer);
    Require(sysctl_nid_postfix(mibSelf, 4, buffer, &length, buffer, sizeof(buffer)) == -1 && *__error_nid_postfix() == 1);
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
static void CheckSdkVersionSysctl() {
    *__error_nid_postfix() = 13;
    std::size_t length = 0;
    Require(sysctlbyname_nid_postfix("kern.sdk_version", nullptr, &length, nullptr, 0) == 0 && length == sizeof(std::uint32_t));
    std::uint32_t version = 0;
    length = sizeof(version);
    Require(sysctlbyname_nid_postfix("kern.sdk_version", &version, &length, nullptr, 0) == 0 && version == 0x01000000 && length == sizeof(std::uint32_t));
    Require(*__error_nid_postfix() == 13);
    unsigned char bytes[4] = {0xaa, 0xaa, 0xaa, 0xaa};
    length = 2;
    Require(sysctlbyname_nid_postfix("kern.sdk_version", bytes, &length, nullptr, 0) == -1 && *__error_nid_postfix() == 12);
    Require(length == 2 && bytes[2] == 0xaa && bytes[3] == 0xaa);
    length = sizeof(version);
    Require(sysctlbyname_nid_postfix("kern.sdk_version", &version, &length, &version, sizeof(version)) == -1 && *__error_nid_postfix() == 1);
}
static void CheckArandomSysctl() {
    const int mib[] = {1, 37};
    *__error_nid_postfix() = 13;
    std::size_t length = 0;
    Require(sysctl_nid_postfix(mib, 2, nullptr, &length, nullptr, 0) == 0 && length == 0);
    length = 64;
    Require(sysctl_nid_postfix(mib, 2, nullptr, &length, nullptr, 0) == 0 && length == 64);
    length = 300;
    Require(sysctl_nid_postfix(mib, 2, nullptr, &length, nullptr, 0) == 0 && length == 256);
    Require(sysctl_nid_postfix(mib, 2, nullptr, nullptr, nullptr, 0) == 0);
    Require(*__error_nid_postfix() == 13);
    unsigned char first[64] = {};
    unsigned char second[64] = {};
    length = sizeof(first);
    Require(sysctl_nid_postfix(mib, 2, first, &length, nullptr, 0) == 0 && length == sizeof(first));
    length = sizeof(second);
    Require(sysctl_nid_postfix(mib, 2, second, &length, nullptr, 0) == 0 && length == sizeof(second));
    Require(std::memcmp(first, second, sizeof(first)) != 0);
    Require(*__error_nid_postfix() == 13);
    unsigned char named[64] = {};
    length = sizeof(named);
    Require(sysctlbyname_nid_postfix("kern.arandom", named, &length, nullptr, 0) == 0 && length == sizeof(named));
    Require(*__error_nid_postfix() == 13);
    length = sizeof(first);
    Require(sysctl_nid_postfix(mib, 2, first, &length, first, sizeof(first)) == -1 && *__error_nid_postfix() == 1);
    *__error_nid_postfix() = 13;
    unsigned char big[300] = {};
    length = sizeof(big);
    Require(sysctl_nid_postfix(mib, 2, big, &length, nullptr, 0) == 0 && length == 256);
    unsigned char small[16] = {};
    length = sizeof(small);
    Require(sysctl_nid_postfix(mib, 2, small, &length, nullptr, 0) == 0 && length == sizeof(small));
    Require(sysctl_nid_postfix(mib, 2, first, nullptr, nullptr, 0) == 0);
    Require(*__error_nid_postfix() == 13);
}
int main() {
    CheckProcessorCountSysctl();
    CheckPhysicalMemorySysctl();
#if defined(__x86_64__) || defined(__i386__)
    CheckModelSysctl();
#endif
    CheckMachdepCachelineSizeSysctl();
    CheckPathnameSysctl();
    CheckSystemSwVersion();
    CheckPseudoRandomSysctl();
    CheckSdkVersionSysctl();
    CheckArandomSysctl();
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
