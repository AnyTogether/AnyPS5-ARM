#include "SceTypes.hpp"
#include <atomic>
#include <cstdint>
#include <cstdlib>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__APPLE__)
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <sys/mman.h>
#else
#include <cstdio>
#include <sys/mman.h>
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
static constexpr std::size_t HostBytes = 0x40000;

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
#elif defined(__APPLE__)
    mach_vm_address_t region = address;
    mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info{};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    if (mach_vm_region(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64, reinterpret_cast<vm_region_info_t>(&info), &count, &object) != KERN_SUCCESS || region > address)
        return {false, false, 0};
    const bool readable = (info.protection & VM_PROT_READ) != 0;
    const bool writable = (info.protection & VM_PROT_WRITE) != 0;
    return {true, readable && writable, 1ull | (readable ? 2ull : 0) | (writable ? 4ull : 0) | ((info.protection & VM_PROT_EXECUTE) != 0 ? 8ull : 0)};
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

static void* MapHostPages() {
#ifdef _WIN32
    return VirtualAlloc(nullptr, HostBytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
#else
    void* mapped = mmap(nullptr, HostBytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return mapped == MAP_FAILED ? nullptr : mapped;
#endif
}

static void UnmapHostPages(void* pages) {
#ifdef _WIN32
    Require(VirtualFree(pages, 0, MEM_RELEASE) != 0);
#else
    Require(munmap(pages, HostBytes) == 0);
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
    if (outside >= 2 * Page) Require(mprotect_nid_postfix(reinterpret_cast<void*>(outside - 2 * Page), Page, 3) == -1);
    const auto stackBytes = reinterpret_cast<std::uintptr_t>(end) - reinterpret_cast<std::uintptr_t>(start);
    Require(mprotect_nid_postfix(start, stackBytes, 0xc2) == 0);
    Require(QueryPage(low).writable);
    static_cast<volatile unsigned char*>(start)[0] = 4;
    Require(mprotect_nid_postfix(start, stackBytes, 3) == 0);
    void* host = MapHostPages();
    Require(host != nullptr);
    Require(mprotect_nid_postfix(host, HostBytes, 1) == -1);
    Require(QueryPage(reinterpret_cast<std::uintptr_t>(host)).writable);
    static_cast<volatile unsigned char*>(host)[HostBytes - 1] = 5;
    UnmapHostPages(host);
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
