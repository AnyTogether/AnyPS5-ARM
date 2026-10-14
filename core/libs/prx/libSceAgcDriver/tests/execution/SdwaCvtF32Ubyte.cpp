#include "prx/libSceAgcDriver/Execution/include/VulkanDevice.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Draw.hpp"
#include "Recompiler.hpp"
#include "VulkanTestDevice.hpp"
#include <array>
#include <bit>
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>

namespace {

using AgcDriver::Graphics::Require;
using ShaderRecompiler::ShaderStage;

constexpr std::uint32_t Threads = 64;
constexpr std::uint32_t Inputs = 4;
constexpr std::uint32_t Results = 4;
alignas(256) std::array<std::uint32_t, Threads * Inputs> Input{};
alignas(256) std::array<std::uint32_t, Threads * Results> Output{};

alignas(256) constexpr std::array<std::uint32_t, 30> SdwaCode{
    0x34020082, 0x34060082, 0xe0302000, 0x80000401,
    0x7e1402ff, 0xabcd1234, 0x7e1602ff, 0xabcd1234, 0x7e1802ff, 0xabcd1234, 0x7e1a02ff, 0xabcd1234,
    0xbf8c3f70, 0x7e1424f9, 0x00040604, 0x7e1624f9, 0x00050604, 0x7e1826f9, 0x000d0604, 0x7e1a28f9, 0x000b0604,
    0xe0702000, 0x80010a03, 0xe0702004, 0x80010b03, 0xe0702008, 0x80010c03, 0xe070200c, 0x80010d03,
    0xbf810000,
};

void FillInput() {
    for (std::uint32_t tid = 0; tid < Threads; ++tid) {
        Input[tid * Inputs] = tid | ((tid + 64u) << 8u) | ((255u - tid) << 16u) | (((tid * 3u + 128u) & 0xffu) << 24u);
    }
}

std::string Hex(std::uint32_t value) {
    char text[16];
    std::snprintf(text, sizeof(text), "0x%08x", value);
    return text;
}

std::uint32_t FloatBits(std::uint32_t value) {
    return std::bit_cast<std::uint32_t>(static_cast<float>(value));
}

std::array<std::uint32_t, 4> BufferDescriptor(const void* data, std::uint32_t count) {
    const auto address = reinterpret_cast<std::uintptr_t>(data);
    return {static_cast<std::uint32_t>(address), static_cast<std::uint32_t>((address >> 32u) & 0xffffu) | (4u << 16u), count, 0x11016facu};
}

void Run(AgcDriver::VulkanDevice& device) {
    Output.fill(0xdeadbeefu);
    std::vector<std::uint32_t> userData(8, 0u);
    const auto input = BufferDescriptor(Input.data(), static_cast<std::uint32_t>(Input.size()));
    const auto output = BufferDescriptor(Output.data(), static_cast<std::uint32_t>(Output.size()));
    std::copy(input.begin(), input.end(), userData.begin());
    std::copy(output.begin(), output.end(), userData.begin() + 4);
    const std::span<const std::uint32_t> code(SdwaCode);
    const std::array<ShaderRecompiler::MemoryRegion, 1> memory{{{reinterpret_cast<std::uintptr_t>(code.data()), std::as_bytes(code)}}};
    const ShaderRecompiler::ShaderComputeStageInfo compute{{Threads, 1, 1}, 0, {false, false, false}, false, 1};
    ShaderRecompiler::RecompileRequest request{
        {ShaderStage::Compute, reinterpret_cast<std::uintptr_t>(code.data()), code, 0, {}},
        {32, 0, userData, compute, std::nullopt, std::nullopt, memory},
        device.Target(),
        {0, 0, 0, 128}
    };
    request.useCache = false;
    const auto result = ShaderRecompiler::Recompile(request);
    device.Dispatch(result, 1, 1, 1, {}, reinterpret_cast<std::uintptr_t>(code.data()));
    device.WaitIdle();
}

void Check() {
    for (std::uint32_t tid = 0; tid < Threads; ++tid) {
        const auto source = Input[tid * Inputs];
        const auto* out = &Output[tid * Results];
        const auto where = [&](std::uint32_t result) { return "sdwa cvt f32 ubyte: thread " + std::to_string(tid) + " result " + std::to_string(result) + " is " + Hex(out[result]); };
        const auto byte1 = FloatBits((source >> 8u) & 0xffu);
        const auto byte3 = FloatBits(source >> 24u);
        const auto signFill = FloatBits((source & 0x80000000u) != 0u ? 0xffu : 0u);
        Require(out[0] == byte1, where(0) + ", expected " + Hex(byte1) + ": v_cvt_f32_ubyte1 src0_sel:WORD_0 must convert bits 15:8");
        Require(out[1] == byte3, where(1) + ", expected " + Hex(byte3) + ": v_cvt_f32_ubyte1 src0_sel:WORD_1 must convert bits 31:24");
        Require(out[2] == signFill, where(2) + ", expected " + Hex(signFill) + ": v_cvt_f32_ubyte2 src0_sel:WORD_1 src0_sext must convert the sign extension of the high word");
        Require(out[3] == signFill, where(3) + ", expected " + Hex(signFill) + ": v_cvt_f32_ubyte3 src0_sel:BYTE_3 src0_sext must convert the sign extension of the top byte");
    }
}

}

int main() {
    try {
        const auto device = OpenVulkanTestDevice();
        if (!device) return VulkanTestSkipped;
        FillInput();
        Run(*device);
        Check();
        std::puts("sdwa cvt f32 ubyte tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
