#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libkernel/KernelErrors.hpp"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <source_location>

extern "C" {
int APS5_VABI sceKernelGetPageTableStats(int*, int*, int*, int*);
int APS5_VABI sceKernelMapFlexibleMemory(void**, std::size_t, int, int);
int APS5_VABI sceKernelMapDirectMemory(void**, std::size_t, int, int, std::int64_t, std::size_t);
int APS5_VABI sceKernelAllocateDirectMemory(std::int64_t, std::int64_t, std::size_t, std::size_t, int, std::int64_t*);
int APS5_VABI sceKernelReleaseDirectMemory(std::int64_t, std::size_t);
int APS5_VABI sceKernelReserveVirtualRange(void**, std::size_t, int, std::size_t);
int APS5_VABI sceKernelMprotect(const void*, std::size_t, int);
int APS5_VABI sceKernelMunmap(void*, std::size_t);
}

static void Require(bool condition, std::source_location location = std::source_location::current()) {
    if (!condition) {
        std::fprintf(stderr, "Page table stats check failed at %s:%u\n", location.file_name(), static_cast<unsigned>(location.line()));
        std::abort();
    }
}

constexpr std::size_t PageTableGranule = 0x200000;
constexpr int PageTableTotal = 2048;

struct Stats {
    int cpuTotal;
    int cpuAvailable;
    int gpuTotal;
    int gpuAvailable;
};

static Stats Query() {
    Stats stats{};
    Require(sceKernelGetPageTableStats(&stats.cpuTotal, &stats.cpuAvailable, &stats.gpuTotal, &stats.gpuAvailable) == 0);
    return stats;
}

static int Granules(const void* addr, std::size_t len) {
    const auto start = reinterpret_cast<std::uintptr_t>(addr);
    return static_cast<int>((start + len - 1) / PageTableGranule - start / PageTableGranule + 1);
}

static void CheckRejectedArguments() {
    int value = 0;
    Require(sceKernelGetPageTableStats(nullptr, &value, &value, &value) == SCE_KERNEL_ERROR_EFAULT);
    Require(sceKernelGetPageTableStats(&value, nullptr, &value, &value) == SCE_KERNEL_ERROR_EFAULT);
    Require(sceKernelGetPageTableStats(&value, &value, nullptr, &value) == SCE_KERNEL_ERROR_EFAULT);
    Require(sceKernelGetPageTableStats(&value, &value, &value, nullptr) == SCE_KERNEL_ERROR_EFAULT);
}

static void CheckFlexibleMapping() {
    const auto before = Query();
    Require(before.cpuTotal == PageTableTotal && before.gpuTotal == PageTableTotal);
    Require(before.cpuAvailable <= before.cpuTotal && before.gpuAvailable <= before.gpuTotal);

    constexpr std::size_t len = 3 * PageTableGranule;
    void* mapped = nullptr;
    Require(sceKernelMapFlexibleMemory(&mapped, len, 3, 0) == 0 && mapped != nullptr);
    const auto entries = Granules(mapped, len);
    auto during = Query();
    Require(during.cpuAvailable == before.cpuAvailable - entries);
    Require(during.gpuAvailable == before.gpuAvailable);

    Require(sceKernelMprotect(mapped, len, 0x30) == 0);
    during = Query();
    Require(during.cpuAvailable == before.cpuAvailable);
    Require(during.gpuAvailable == before.gpuAvailable - entries);

    Require(sceKernelMunmap(mapped, len) == 0);
    const auto after = Query();
    Require(after.cpuAvailable == before.cpuAvailable && after.gpuAvailable == before.gpuAvailable);
}

static void CheckDualAccessMapping() {
    const auto before = Query();
    constexpr std::size_t len = PageTableGranule;
    void* mapped = nullptr;
    Require(sceKernelMapFlexibleMemory(&mapped, len, 0x33, 0) == 0 && mapped != nullptr);
    const auto entries = Granules(mapped, len);
    const auto during = Query();
    Require(during.cpuAvailable == before.cpuAvailable - entries);
    Require(during.gpuAvailable == before.gpuAvailable - entries);
    Require(sceKernelMunmap(mapped, len) == 0);
    const auto after = Query();
    Require(after.cpuAvailable == before.cpuAvailable && after.gpuAvailable == before.gpuAvailable);
}

static void CheckSharedGranule() {
    const auto before = Query();
    constexpr std::size_t page = 0x4000;
    void* span = nullptr;
    Require(sceKernelReserveVirtualRange(&span, 2 * PageTableGranule, 0, PageTableGranule) == 0 && span != nullptr);
    const auto base = reinterpret_cast<std::uintptr_t>(span);
    const auto aligned = base % PageTableGranule == 0 ? base : (base / PageTableGranule + 1) * PageTableGranule;
    void* first = reinterpret_cast<void*>(aligned);
    void* second = reinterpret_cast<void*>(aligned + page);
    Require(sceKernelMapFlexibleMemory(&first, page, 3, 0) == 0 && first == reinterpret_cast<void*>(aligned));
    Require(sceKernelMapFlexibleMemory(&second, page, 3, 0) == 0 && second == reinterpret_cast<void*>(aligned + page));
    const auto during = Query();
    Require(during.cpuAvailable == before.cpuAvailable - 2);
    Require(during.gpuAvailable == before.gpuAvailable);
    Require(sceKernelMunmap(first, page) == 0);
    Require(sceKernelMunmap(second, page) == 0);
    const auto after = Query();
    Require(after.cpuAvailable == before.cpuAvailable && after.gpuAvailable == before.gpuAvailable);
}

static void CheckGpuDirectMapping() {
    const auto before = Query();
    constexpr std::size_t len = 2 * PageTableGranule;
    std::int64_t phys = 0;
    Require(sceKernelAllocateDirectMemory(0, 0x7fffffffffll, len, 0, 0, &phys) == 0);
    void* mapped = nullptr;
    Require(sceKernelMapDirectMemory(&mapped, len, 0x33, 0, phys, 0) == 0 && mapped != nullptr);
    const auto entries = Granules(mapped, len);
    const auto during = Query();
    Require(during.gpuAvailable == before.gpuAvailable - entries);
    Require(during.cpuAvailable == before.cpuAvailable - entries);
    Require(sceKernelMunmap(mapped, len) == 0);
    Require(sceKernelReleaseDirectMemory(phys, len) == 0);
    const auto after = Query();
    Require(after.cpuAvailable == before.cpuAvailable && after.gpuAvailable == before.gpuAvailable);
}

int main() {
    CheckRejectedArguments();
    CheckFlexibleMapping();
    CheckDualAccessMapping();
    CheckSharedGranule();
    CheckGpuDirectMapping();
    return 0;
}
