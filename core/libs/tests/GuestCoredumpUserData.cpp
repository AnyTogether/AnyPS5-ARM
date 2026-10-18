#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <thread>

extern "C" {
int APS5_VABI sceCoredumpRegisterCoredumpHandler(uint64_t handler, size_t stackSize, uint64_t context);
int APS5_VABI sceCoredumpUnregisterCoredumpHandler(void);
int64_t APS5_VABI sceCoredumpWriteUserData(const void* data, size_t size);
void APS5_VABI sceCoredumpDebugTextOut(const char* str, int len);
int APS5_VABI sceCoredumpAttachUserFile(uint32_t userValue, const char* path);
int APS5_VABI sceCoredumpAttachMemoryRegionAsUserFile(uint32_t userValue, const void* mem, size_t size, const char* name);
}

namespace {
constexpr int64_t NotInCoredumpHandler = static_cast<int32_t>(0x81180003u);
bool handlerRan = false;
int handlerContext = 0;

int APS5_VABI Handler(void*) {
    handlerRan = true;
    return 0;
}

void Require(bool value) { if (!value) std::abort(); }

template <typename TCall>
bool Throws(TCall call, const char* function) {
    try { call(); }
    catch (const std::runtime_error& error) { return std::strstr(error.what(), function) != nullptr; }
    return false;
}

void RequireWritesRefused(const std::array<unsigned char, 64>& region) {
    Require(sceCoredumpWriteUserData(region.data(), region.size()) == NotInCoredumpHandler);
    Require(sceCoredumpWriteUserData(region.data(), 1) == NotInCoredumpHandler);
    int64_t fromThread = 0;
    std::thread([&] { fromThread = sceCoredumpWriteUserData(region.data(), region.size()); }).join();
    Require(fromThread == NotInCoredumpHandler);
}

void RequireAttachesRefused(const std::array<unsigned char, 64>& region) {
    Require(sceCoredumpAttachUserFile(1, "/app0/eboot.bin") == NotInCoredumpHandler);
    Require(sceCoredumpAttachUserFile(0xFFFFFFFFu, "") == NotInCoredumpHandler);
    Require(sceCoredumpAttachMemoryRegionAsUserFile(999, region.data(), region.size(), "region.txt") == NotInCoredumpHandler);
    Require(sceCoredumpAttachMemoryRegionAsUserFile(0, region.data(), 1, "") == NotInCoredumpHandler);
    int fromThread = 0;
    std::thread([&] { fromThread = sceCoredumpAttachMemoryRegionAsUserFile(2, region.data(), region.size(), "thread.txt"); }).join();
    Require(fromThread == NotInCoredumpHandler);
}
}

int main() {
    std::array<unsigned char, 64> region{};
    for (size_t index = 0; index < region.size(); ++index) region[index] = static_cast<unsigned char>(index * 5 + 1);
    const auto original = region;
    const char text[] = "coredump text\n";

    Require(NotInCoredumpHandler < 0);
    RequireWritesRefused(region);
    RequireAttachesRefused(region);
    sceCoredumpDebugTextOut(text, static_cast<int>(sizeof(text) - 1));
    sceCoredumpDebugTextOut(text, 8);
    sceCoredumpDebugTextOut(text, 0);
    sceCoredumpDebugTextOut(nullptr, 0);

    Require(sceCoredumpRegisterCoredumpHandler(reinterpret_cast<uint64_t>(&Handler), 16 * 1024, reinterpret_cast<uint64_t>(&handlerContext)) == 0);
    RequireWritesRefused(region);
    RequireAttachesRefused(region);
    sceCoredumpDebugTextOut(text, static_cast<int>(sizeof(text) - 1));
    Require(!handlerRan);

    Require(Throws([&] { sceCoredumpWriteUserData(nullptr, region.size()); }, "sceCoredumpWriteUserData"));
    Require(Throws([&] { sceCoredumpWriteUserData(region.data(), 0); }, "sceCoredumpWriteUserData"));
    Require(Throws([&] { sceCoredumpWriteUserData(region.data(), SIZE_MAX); }, "sceCoredumpWriteUserData"));
    Require(Throws([&] { sceCoredumpDebugTextOut(nullptr, 4); }, "sceCoredumpDebugTextOut"));
    Require(Throws([&] { sceCoredumpDebugTextOut(text, -1); }, "sceCoredumpDebugTextOut"));
    Require(Throws([&] { sceCoredumpAttachUserFile(1, nullptr); }, "sceCoredumpAttachUserFile"));
    Require(Throws([&] { sceCoredumpAttachMemoryRegionAsUserFile(1, nullptr, region.size(), "a.txt"); }, "sceCoredumpAttachMemoryRegionAsUserFile"));
    Require(Throws([&] { sceCoredumpAttachMemoryRegionAsUserFile(1, region.data(), 0, "a.txt"); }, "sceCoredumpAttachMemoryRegionAsUserFile"));
    Require(Throws([&] { sceCoredumpAttachMemoryRegionAsUserFile(1, region.data(), SIZE_MAX, "a.txt"); }, "sceCoredumpAttachMemoryRegionAsUserFile"));
    Require(Throws([&] { sceCoredumpAttachMemoryRegionAsUserFile(1, region.data(), region.size(), nullptr); }, "sceCoredumpAttachMemoryRegionAsUserFile"));

    Require(sceCoredumpUnregisterCoredumpHandler() == 0);
    RequireWritesRefused(region);
    RequireAttachesRefused(region);
    Require(region == original);
    Require(!handlerRan);
    return 0;
}
