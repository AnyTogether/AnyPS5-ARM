#include "prx/libSceAgcDriver/Graphics/include/Context.hpp"
#include <cstdint>
#include <cstdio>
#include <exception>
#include <string>

using namespace AgcDriver::Graphics;

namespace {

int failures = 0;

void Expect(bool condition, const std::string& what) {
    if (condition) return;
    std::fprintf(stderr, "FAIL: %s\n", what.c_str());
    ++failures;
}

constexpr std::uint32_t HostType = 0;
constexpr std::uint32_t DeviceType = 1;
constexpr std::uint64_t MiB = 1ull << 20u;

std::uint64_t reportedBudget = 0;
std::uint64_t reportedUsage = 0;

VKAPI_ATTR void VKAPI_CALL mockMemoryProperties2(VkPhysicalDevice, VkPhysicalDeviceMemoryProperties2* properties) {
    auto* reported = static_cast<VkPhysicalDeviceMemoryBudgetPropertiesEXT*>(properties->pNext);
    reported->heapBudget[0] = reportedBudget;
    reported->heapUsage[0] = reportedUsage;
}

Context mockContext(bool budgetExtension) {
    Context context{};
    context.physical = reinterpret_cast<VkPhysicalDevice>(static_cast<std::uintptr_t>(1));
    context.memoryProperties2 = budgetExtension ? mockMemoryProperties2 : nullptr;
    context.memory.memoryHeapCount = 2;
    context.memory.memoryHeaps[0] = {4096 * MiB, VK_MEMORY_HEAP_DEVICE_LOCAL_BIT};
    context.memory.memoryHeaps[1] = {16384 * MiB, 0};
    context.memory.memoryTypeCount = 2;
    context.memory.memoryTypes[HostType] = {0, 1};
    context.memory.memoryTypes[DeviceType] = {VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 0};
    return context;
}

void Choose(const char* what, bool budgetExtension, std::uint64_t budget, std::uint64_t usage, std::uint32_t mask, std::uint32_t expected) {
    reportedBudget = budget;
    reportedUsage = usage;
    const auto type = mockContext(budgetExtension).DeviceMemoryType(mask, 64 * MiB, "test");
    Expect(type == expected, std::string(what) + ": chose memory type " + std::to_string(type) + ", expected " + std::to_string(expected));
}

}

int main() {
    try {
        const std::uint32_t both = (1u << HostType) | (1u << DeviceType);
        Choose("no VK_EXT_memory_budget", false, 0, 0, both, DeviceType);
        Choose("budget not reported", true, 0, 4000 * MiB, both, DeviceType);
        Choose("room in the device-local budget", true, 3000 * MiB, 2000 * MiB, both, DeviceType);
        Choose("allocation fills the budget exactly", true, 3000 * MiB, 2936 * MiB, both, DeviceType);
        Choose("allocation exceeds the budget", true, 3000 * MiB, 2937 * MiB, both, HostType);
        Choose("usage already over the budget", true, 2952 * MiB, 3633 * MiB, both, HostType);
        Choose("no host type allowed", true, 3000 * MiB, 3000 * MiB, 1u << DeviceType, DeviceType);
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 1;
    }
    if (failures != 0) return 1;
    std::puts("device memory placement tests passed");
    return 0;
}
