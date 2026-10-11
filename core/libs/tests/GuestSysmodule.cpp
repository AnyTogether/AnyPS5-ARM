#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>
#ifdef __linux__
#include <cstdio>
#include <fstream>
#include <sys/mman.h>
#include <unistd.h>
#endif

extern "C" {
int APS5_VABI sceSysmoduleIsLoaded(std::uint16_t id);
int APS5_VABI sceSysmoduleLoadModule(std::uint16_t id);
int APS5_VABI sceSysmoduleUnloadModule(std::uint16_t id);
int APS5_VABI sceSysmoduleLoadModuleInternal(std::uint32_t id);
int APS5_VABI sceSysmoduleUnloadModuleInternal(std::uint32_t id);
int APS5_VABI sceSysmoduleGetModuleInfoForUnwind(std::uint64_t addr, int flags, ModuleInfoForUnwind* info);
int APS5_VABI sceSysmoduleGetModuleHandleInternal(std::uint32_t id, std::int32_t* handle);
int APS5_VABI sceKernelDlsym(std::int32_t handle, const char* symbol, void** addr);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

template <typename TFunction>
bool ThrowsRuntimeError(TFunction function) {
    try {
        function();
    } catch (const std::runtime_error&) {
        return true;
    }
    return false;
}

constexpr std::uint16_t kFiberModuleId = 0x0006;
constexpr std::uint16_t kUltModuleId = 0x0007;
constexpr int kModuleUnloaded = static_cast<int>(0x805A1001);
constexpr std::uint16_t kTrophy2ModuleId = 0x0110;

#ifdef __linux__
struct Mapping {
    std::uint64_t start = 0;
    std::uint64_t end = 0;
    std::string path;
};

Mapping MapsEntry(std::uint64_t address) {
    std::ifstream maps("/proc/self/maps");
    std::string line;
    while (std::getline(maps, line)) {
        unsigned long long start = 0;
        unsigned long long end = 0;
        char path[4096] = {};
        const int parsed = std::sscanf(line.c_str(), "%llx-%llx %*s %*x %*x:%*x %*u %4095s", &start, &end, path);
        if (parsed >= 2 && address >= start && address < end) return Mapping{start, end, parsed == 3 ? path : ""};
    }
    std::abort();
}

void RequireUnwindMatchesMaps(const void* pointer) {
    const auto address = reinterpret_cast<std::uint64_t>(pointer);
    const auto expected = MapsEntry(address);
    ModuleInfoForUnwind info{};
    Require(sceSysmoduleGetModuleInfoForUnwind(address, 0, &info) == 0);
    Require(info.st_size == sizeof(ModuleInfoForUnwind));
    Require(info.seg0_addr == expected.start && info.seg0_size == expected.end - expected.start);
    Require(std::string(info.name) == expected.path.substr(0, sizeof(info.name) - 1));
    Require(info.eh_frame_hdr_addr == 0 && info.eh_frame_addr == 0 && info.eh_frame_size == 0);
}

void CheckUnwindInfo() {
    RequireUnwindMatchesMaps(reinterpret_cast<const void*>(&RequireUnwindMatchesMaps));
    RequireUnwindMatchesMaps(reinterpret_cast<const void*>(&sceSysmoduleGetModuleInfoForUnwind));
    int local = 0;
    RequireUnwindMatchesMaps(&local);
    const auto page = static_cast<std::size_t>(sysconf(_SC_PAGESIZE));
    void* anonymous = mmap(nullptr, page, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    Require(anonymous != MAP_FAILED);
    RequireUnwindMatchesMaps(anonymous);
    Require(munmap(anonymous, page) == 0);
    void* gap = mmap(nullptr, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    Require(gap != MAP_FAILED && munmap(gap, page) == 0);
    ModuleInfoForUnwind info{};
    bool threw = false;
    try {
        sceSysmoduleGetModuleInfoForUnwind(reinterpret_cast<std::uint64_t>(gap), 0, &info);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw);
}
#endif

}

int main() {
    Require(sceSysmoduleIsLoaded(kFiberModuleId) == kModuleUnloaded);
    Require(sceSysmoduleLoadModuleInternal(kFiberModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kFiberModuleId) == 0);
    Require(sceSysmoduleLoadModuleInternal(kFiberModuleId) == 0);
    Require(sceSysmoduleUnloadModuleInternal(kFiberModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kFiberModuleId) == 0);
    Require(sceSysmoduleUnloadModuleInternal(kFiberModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kFiberModuleId) == kModuleUnloaded);
    Require(sceSysmoduleUnloadModuleInternal(kFiberModuleId) == kModuleUnloaded);

    Require(sceSysmoduleIsLoaded(kUltModuleId) == kModuleUnloaded);
    Require(sceSysmoduleUnloadModule(kUltModuleId) == kModuleUnloaded);
    Require(sceSysmoduleLoadModule(kUltModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kUltModuleId) == 0);
    Require(sceSysmoduleUnloadModule(kUltModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kUltModuleId) == kModuleUnloaded);

    Require(sceSysmoduleIsLoaded(kTrophy2ModuleId) == kModuleUnloaded);
    Require(sceSysmoduleLoadModuleInternal(kTrophy2ModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kTrophy2ModuleId) == 0);
    Require(sceSysmoduleLoadModuleInternal(kTrophy2ModuleId) == 0);
    Require(sceSysmoduleUnloadModuleInternal(kTrophy2ModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kTrophy2ModuleId) == 0);
    Require(sceSysmoduleUnloadModuleInternal(kTrophy2ModuleId) == 0);
    Require(sceSysmoduleIsLoaded(kTrophy2ModuleId) == kModuleUnloaded);
    Require(sceSysmoduleUnloadModuleInternal(kTrophy2ModuleId) == kModuleUnloaded);
#ifdef __linux__
    CheckUnwindInfo();
#endif

    std::int32_t handle = -1;
    Require(sceSysmoduleGetModuleHandleInternal(kFiberModuleId, &handle) == kModuleUnloaded);
    Require(handle == -1);
    Require(ThrowsRuntimeError([] { sceSysmoduleGetModuleHandleInternal(0, nullptr); }));
    Require(ThrowsRuntimeError([&] { sceSysmoduleGetModuleHandleInternal(0, &handle); }));
    Require(ThrowsRuntimeError([] { sceSysmoduleGetModuleHandleInternal(kFiberModuleId, nullptr); }));
    Require(ThrowsRuntimeError([&] { sceSysmoduleGetModuleHandleInternal(0x00ffffffu, &handle); }));

    Require(sceSysmoduleLoadModule(kFiberModuleId) == 0);
    Require(sceSysmoduleGetModuleHandleInternal(kFiberModuleId, &handle) == 0);
    Require(handle >= 0);
    std::int32_t again = -1;
    Require(sceSysmoduleGetModuleHandleInternal(kFiberModuleId, &again) == 0);
    Require(again == handle);
    void* symbol = nullptr;
    Require(sceKernelDlsym(handle, "sceFiberOptParamInitialize", &symbol) == 0);
    Require(symbol != nullptr);
    Require(sceSysmoduleUnloadModule(kFiberModuleId) == 0);
    Require(sceSysmoduleGetModuleHandleInternal(kFiberModuleId, &handle) == kModuleUnloaded);
}
