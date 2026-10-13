#include "prx/libSceAgcDriver/Execution/include/Driver/Driver.hpp"
#include "prx/libc/include/GuestAllocations.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include "VulkanTestDevice.hpp"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <iostream>
#include <string>

using GuestFiberEntry = void (APS5_VABI*)(std::uint64_t, std::uint64_t);

extern "C" {
std::int32_t APS5_VABI _sceFiberInitializeImpl_nid_postfix(FiberObject*, const char*, GuestFiberEntry, std::uint64_t, void*, std::uint64_t, const void*, std::uint32_t);
std::int32_t APS5_VABI sceFiberFinalize(FiberObject*);
std::int32_t APS5_VABI sceFiberRun_nid_postfix(FiberObject*, std::uint64_t, std::uint64_t*);
std::int32_t APS5_VABI sceFiberReturnToThread(std::uint64_t, std::uint64_t*);
}

namespace {

using AgcDriver::DriverDetail::Driver;
using AgcDriver::Graphics::Require;

constexpr std::size_t ContextBytes = 64 * 1024;
constexpr std::size_t MappingBytes = 4 * 65536;
constexpr std::size_t FiberStackLimit = 8 * 1024;
constexpr std::uint64_t Fill = 0x5aa5c33c5aa5c33cull;

alignas(16) std::array<std::uint64_t, ContextBytes / sizeof(std::uint64_t)> FiberContext;
struct alignas(8) FiberStorage {
    unsigned char bytes[0x100];
};
FiberStorage FiberObjectStorage;

alignas(256) constexpr std::array<std::uint32_t, 8> VertexCode{0x7e000208u, 0x7e020280u, 0x7e040280u, 0x7e0602f2u, 0xf80008cfu, 0x03020100u, 0xbf810000u, 0xbf810000u};

struct Header {
    Shader shader{};
    ShaderUserData userData{};
};
alignas(8) Header VertexHeader{};

std::uint8_t* Mapping = nullptr;

void RegisterVertexShader() {
    VertexHeader.shader.file_header = 0x34333231u;
    VertexHeader.shader.version = 0x18u;
    VertexHeader.shader.header_size = sizeof(Header);
    VertexHeader.shader.shader_size = static_cast<std::uint32_t>(sizeof(VertexCode));
    VertexHeader.shader.code = VertexCode.data();
    VertexHeader.shader.type = 2;
    VertexHeader.shader.user_data = &VertexHeader.userData;
    AgcDriverRegisterShader_nid_postfix(&VertexHeader.shader);
}

void MapForGpu() {
    GuestAllocations::Mutation mutation;
    mutation.Add(Mapping, MappingBytes, true, true, true);
    mutation.NoteGpuMapping(Mapping, MappingBytes);
}

void APS5_VABI MapOnFiber(std::uint64_t, std::uint64_t) {
    MapForGpu();
    sceFiberReturnToThread(0, nullptr);
}

void ReleaseMapping() {
    if (Mapping == nullptr) return;
#ifdef _WIN32
    VirtualFree(Mapping, 0, MEM_RELEASE);
#else
    std::free(Mapping);
#endif
    Mapping = nullptr;
}

std::size_t FiberStackUsed() {
    std::size_t untouched = 0;
    while (untouched < FiberContext.size() && FiberContext[untouched] == Fill) ++untouched;
    return (FiberContext.size() - untouched) * sizeof(std::uint64_t);
}

}

int main() {
    try {
        if (!OpenVulkanTestDevice()) return VulkanTestSkipped;
        RegisterVertexShader();
#ifdef _WIN32
        Mapping = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, MappingBytes, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
#else
        Mapping = static_cast<std::uint8_t*>(std::aligned_alloc(65536, MappingBytes));
#endif
        Require(Mapping != nullptr, "GPU mapping on a fiber: cannot allocate the mapped memory");
        std::memset(Mapping, 0, MappingBytes);
        FiberContext.fill(Fill);
        auto* fiber = reinterpret_cast<FiberObject*>(&FiberObjectStorage);
        Require(_sceFiberInitializeImpl_nid_postfix(fiber, "gpu map", MapOnFiber, 0, FiberContext.data(), ContextBytes, nullptr, 0) == 0, "GPU mapping on a fiber: the fiber was not initialized");
        const auto beforeFiber = Driver::GpuMapImportThreads();
        Require(sceFiberRun_nid_postfix(fiber, 0, nullptr) == 0, "GPU mapping on a fiber: the fiber did not run");
        const auto onFiber = Driver::GpuMapImportThreads() - beforeFiber;
        Require(sceFiberFinalize(fiber) == 0, "GPU mapping on a fiber: the fiber was not finalized");
        const auto used = FiberStackUsed();
        GuestAllocations::Mutation().Remove(Mapping);
        const auto beforeThread = Driver::GpuMapImportThreads();
        MapForGpu();
        const auto onThread = Driver::GpuMapImportThreads() - beforeThread;
        GuestAllocations::Mutation().Remove(Mapping);
        AgcDriverShutdown_nid_postfix();
        ReleaseMapping();
        Require(used <= FiberStackLimit, "GPU mapping on a fiber used " + std::to_string(used) + " bytes of the fiber's stack, more than " + std::to_string(FiberStackLimit) + ": the import of the mapped memory ran on it");
        Require(onFiber == 1, "GPU mapping on a fiber started " + std::to_string(onFiber) + " host threads for its import instead of one");
        Require(onThread == 0, "GPU mapping on an ordinary thread started " + std::to_string(onThread) + " host threads for its import instead of importing on its own stack");
        std::cout << "A GPU mapping made on a fiber used " << used << " bytes of its stack\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        AgcDriverShutdown_nid_postfix();
        ReleaseMapping();
        return 1;
    }
}
