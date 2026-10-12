#include "prx/libSceAgcDriver/Execution/include/VulkanDevice.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Draw.hpp"
#include "FlatApertures.hpp"
#include "Recompiler.hpp"
#include "VulkanTestDevice.hpp"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <iostream>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using AgcDriver::Graphics::Require;
using ShaderRecompiler::ShaderStage;

constexpr std::uint32_t LdsDwords = 64u;
constexpr std::uint32_t ScratchDwords = 4u;
constexpr std::uint32_t OutputStride = 8u;

alignas(256) constexpr std::array<std::uint32_t, 49> Code{
    0x34020082u,
    0xbe8804ebu,
    0xbe8a04edu,
    0xd70f6a02u, 0x00020208u,
    0x7e060209u,
    0x50060680u,
    0x34080088u,
    0x38080900u,
    0x380808ffu, 0x5a5a0000u,
    0xdc700000u, 0x007d0402u,
    0xd70f6a06u, 0x00001484u,
    0x7e0e020bu,
    0x500e0e80u,
    0x7e106f04u,
    0xdc700000u, 0x007d0806u,
    0xbf8c0070u,
    0xd8d80000u, 0x05000001u,
    0x7e140280u,
    0xdc304004u, 0x097d000au,
    0x7e160208u,
    0x7e180209u,
    0x7e1c020au,
    0x7e1e020bu,
    0x341a0085u,
    0xbf8c0070u,
    0xe0701000u, 0x8000050du,
    0xe0701004u, 0x8000090du,
    0xe0701008u, 0x80000b0du,
    0xe070100cu, 0x80000c0du,
    0xe0701010u, 0x80000e0du,
    0xe0701014u, 0x80000f0du,
    0xe0701018u, 0x8000040du,
    0xe070101cu, 0x8000080du,
    0xbf810000u
};

std::array<std::uint32_t, 4> BufferDescriptor(const void* data, std::uint32_t bytes) {
    const auto address = reinterpret_cast<std::uintptr_t>(data);
    return {static_cast<std::uint32_t>(address), static_cast<std::uint32_t>((address >> 32u) & 0xffffu), bytes, 0x31016facu};
}

std::string Hex(std::uint32_t value) {
    char text[16];
    std::snprintf(text, sizeof(text), "0x%08x", value);
    return text;
}

std::uint32_t LaneData(std::uint32_t lane) {
    return 0x5a5a0000u | (lane << 8u) | lane;
}

void Run(AgcDriver::VulkanDevice& device, std::uint32_t waveSize) {
    std::vector<std::uint32_t> output(waveSize * OutputStride, 0xdeadbeefu);
    std::vector<std::uint32_t> userData(8, 0u);
    const auto outputDescriptor = BufferDescriptor(output.data(), static_cast<std::uint32_t>(output.size() * 4u));
    std::copy(outputDescriptor.begin(), outputDescriptor.end(), userData.begin());
    const std::span<const std::uint32_t> code(Code);
    const std::array<ShaderRecompiler::MemoryRegion, 1> memory{{{reinterpret_cast<std::uintptr_t>(code.data()), std::as_bytes(code)}}};
    ShaderRecompiler::ShaderComputeStageInfo compute{{waveSize, 1, 1}, LdsDwords, {false, false, false}, false, 1};
    compute.scratchDwords = ScratchDwords;
    ShaderRecompiler::RecompileRequest request{
        {ShaderStage::Compute, reinterpret_cast<std::uintptr_t>(code.data()), code, 0, {}},
        {waveSize, 0, userData, compute, std::nullopt, std::nullopt, memory},
        device.Target(),
        {0, 0, 0, 128}
    };
    request.useCache = false;
    const auto result = ShaderRecompiler::Recompile(request);
    device.Dispatch(result, 1, 1, 1, {}, reinterpret_cast<std::uintptr_t>(code.data()));
    device.WaitIdle();
    for (std::uint32_t lane = 0; lane < waveSize; ++lane) {
        const std::uint32_t* row = output.data() + lane * OutputStride;
        const std::string wave = "wave" + std::to_string(waveSize);
        const auto expect = [&](const char* name, std::uint32_t actual, std::uint32_t expected) {
            Require(actual == expected, wave + " lane " + std::to_string(lane) + ": " + name + " is " + Hex(actual) + ", expected " + Hex(expected));
        };
        expect("the low dword of src_shared_base", row[2], 0u);
        expect("the high dword of src_shared_base", row[3], ShaderRecompiler::SharedApertureHigh);
        expect("the low dword of src_private_base", row[4], 0u);
        expect("the high dword of src_private_base", row[5], ShaderRecompiler::PrivateApertureHigh);
        expect("the data stored through the shared aperture", row[6], LaneData(lane));
        expect("the data stored through the private aperture", row[7], ~LaneData(lane));
        expect("ds_read_b32 at the lane's LDS offset after flat_store_dword at src_shared_base plus that offset", row[0], LaneData(lane));
        expect("scratch_load_dword at byte 4 after flat_store_dword at src_private_base plus 4", row[1], ~LaneData(lane));
    }
}

}

int main() {
    try {
        const auto device = OpenVulkanTestDevice();
        if (!device) return VulkanTestSkipped;
        Run(*device, 32u);
        if (device->Target().subgroupSize >= 32u) {
            Run(*device, 64u);
        } else {
            std::printf("skipped the wave64 run, subgroup size %u cannot hold a wave64 in two lanes\n", device->Target().subgroupSize);
        }
        std::puts("flat aperture source tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
