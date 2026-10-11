#include "SceTypes.hpp"
#include <atomic>
#include <cstdint>
#include <cstdlib>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <cstdio>
#endif

extern "C" {
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
int APS5_VABI sceKernelIsStack(void* addr, void** start, void** end);
int APS5_VABI mprotect_nid_postfix(void* address, std::size_t length, int protection) noexcept;
}

static constexpr int SCE_OK = 0;
static constexpr std::uintptr_t Page = 0x4000;
static constexpr std::size_t GuardBytes = 0x10000;

static void Require(bool value) { if (!value) std::abort(); }

struct PageState {
    bool mapped;
    bool writable;
    std::uint64_t raw;
};

static PageState QueryPage(std::uintptr_t address) {
#ifdef _WIN32
    MEMORY_BASIC_INFORMATION memory{};
    Require(VirtualQuery(reinterpret_cast<const void*>(address), &memory, sizeof(memory)) == sizeof(memory));
    const bool mapped = memory.State == MEM_COMMIT;
    return {mapped, mapped && (memory.Protect & (PAGE_READWRITE | PAGE_EXECUTE_READWRITE)) != 0, (static_cast<std::uint64_t>(memory.State) << 32) | memory.Protect};
#else
    std::FILE* maps = std::fopen("/proc/self/maps", "r");
    Require(maps != nullptr);
    PageState state{false, false, 0};
    char line[512];
    while (std::fgets(line, sizeof(line), maps) != nullptr) {
        unsigned long long low = 0;
        unsigned long long high = 0;
        char permissions[5] = {};
        if (std::sscanf(line, "%llx-%llx %4s", &low, &high, permissions) != 3 || address < low || address >= high) continue;
        state = {true, permissions[0] == 'r' && permissions[1] == 'w', 1ull | (permissions[0] == 'r' ? 2ull : 0) | (permissions[1] == 'w' ? 4ull : 0) | (permissions[2] == 'x' ? 8ull : 0)};
        break;
    }
    std::fclose(maps);
    return state;
#endif
}

static void* APS5_VABI Worker(void* arg) {
    auto& passed = *static_cast<std::atomic<bool>*>(arg);
    int local = 0;
    void* start = nullptr;
    void* end = nullptr;
    Require(sceKernelIsStack(&local, &start, &end) == SCE_OK);
    const auto low = (reinterpret_cast<std::uintptr_t>(start) + Page - 1) & ~(Page - 1);
    Require(low + GuardBytes + Page < reinterpret_cast<std::uintptr_t>(&local));
    auto* guard = reinterpret_cast<volatile unsigned char*>(low);
    Require(mprotect_nid_postfix(const_cast<unsigned char*>(guard), GuardBytes, 0) == 0);
#ifdef _WIN32
    MEMORY_BASIC_INFORMATION memory{};
    Require(VirtualQuery(const_cast<unsigned char*>(guard), &memory, sizeof(memory)) == sizeof(memory));
    Require(memory.Protect == PAGE_NOACCESS && memory.RegionSize >= GuardBytes);
#endif
    Require(mprotect_nid_postfix(const_cast<unsigned char*>(guard), GuardBytes, 3) == 0);
    guard[0] = 1;
    guard[GuardBytes - 1] = 2;
    Require(guard[0] == 1 && guard[GuardBytes - 1] == 2);
    const auto below = reinterpret_cast<std::uintptr_t>(start) - 1;
    const auto belowBefore = QueryPage(below).raw;
    Require(mprotect_nid_postfix(start, GuardBytes, 0) == 0);
    Require(QueryPage(below).raw == belowBefore);
    Require(mprotect_nid_postfix(start, GuardBytes, 3) == 0);
    Require(QueryPage(below).raw == belowBefore);
    static_cast<volatile unsigned char*>(start)[0] = 3;
    const auto outside = reinterpret_cast<std::uintptr_t>(start) & ~(Page - 1);
    if (outside >= Page) Require(mprotect_nid_postfix(reinterpret_cast<void*>(outside - Page), 2 * Page, 3) == -1);
    passed.store(true);
    return nullptr;
}

static std::atomic<std::uintptr_t> leftGuard{0};

static void* APS5_VABI LeaveGuard(void*) {
    int local = 0;
    void* start = nullptr;
    void* end = nullptr;
    Require(sceKernelIsStack(&local, &start, &end) == SCE_OK);
    const auto low = (reinterpret_cast<std::uintptr_t>(start) + Page - 1) & ~(Page - 1);
    Require(mprotect_nid_postfix(reinterpret_cast<void*>(low), GuardBytes, 0) == 0);
    leftGuard.store(low);
    return nullptr;
}

static void* APS5_VABI WriteLeftGuard(void*) {
    int local = 0;
    void* start = nullptr;
    void* end = nullptr;
    Require(sceKernelIsStack(&local, &start, &end) == SCE_OK);
    const auto guard = leftGuard.load();
    if (guard >= reinterpret_cast<std::uintptr_t>(start) && guard + GuardBytes <= reinterpret_cast<std::uintptr_t>(&local)) {
        reinterpret_cast<volatile unsigned char*>(guard)[0] = 4;
    }
    return nullptr;
}

int main() {
    std::atomic<bool> passed{false};
    Pthread thread = nullptr;
    Require(scePthreadCreate(&thread, nullptr, Worker, &passed, nullptr) == SCE_OK);
    Require(scePthreadJoin(thread, nullptr) == SCE_OK);
    Require(passed.load());
    Require(scePthreadCreate(&thread, nullptr, LeaveGuard, nullptr, nullptr) == SCE_OK);
    Require(scePthreadJoin(thread, nullptr) == SCE_OK);
    for (std::uintptr_t offset = 0; offset < GuardBytes; offset += Page) {
        const auto left = QueryPage(leftGuard.load() + offset);
        Require(!left.mapped || left.writable);
    }
    Require(scePthreadCreate(&thread, nullptr, WriteLeftGuard, nullptr, nullptr) == SCE_OK);
    Require(scePthreadJoin(thread, nullptr) == SCE_OK);
}
