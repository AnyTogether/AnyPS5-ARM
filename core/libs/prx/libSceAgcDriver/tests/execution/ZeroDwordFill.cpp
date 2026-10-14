#include "prx/libSceAgcDriver/Execution/include/Driver.hpp"
#include "prx/libSceAgcDriver/Execution/include/Driver/Memory/DwordPatternFill.hpp"
#include "prx/libSceAgcDriver/Execution/include/GuestMemory.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Draw.hpp"
#include "VulkanTestDevice.hpp"
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using AgcDriver::Graphics::Require;
using AgcDriver::DriverDetail::MatchZeroDwordFill;

alignas(256) constexpr std::array<std::uint32_t, 6> Code{0xd7460000u, 0x04010c04u, 0x7e020280u, 0xe0102000u, 0x80000100u, 0xbf810000u};
constexpr std::uint32_t Untouched = 0xcafebabeu;
alignas(256) std::array<std::uint32_t, 1028> Output{};

std::vector<std::uint32_t> UserData(void* output, std::uint32_t records, std::uint32_t stride = 4, std::uint32_t format = 0x00014204u) {
    const auto address = reinterpret_cast<std::uintptr_t>(output);
    return {static_cast<std::uint32_t>(address), static_cast<std::uint32_t>((address >> 32u) & 0xffffu) | (stride << 16u), records, format};
}

void MatchTests() {
    const ShaderRecompiler::ShaderComputeStageInfo compute{{64, 1, 1}, 0, {true, false, false}, false, 1};
    const std::array<std::uint32_t, 5> packet{0xc0031500u, 4, 1, 1, 0x41u};
    const auto data = UserData(Output.data(), 1024);
    const auto fill = MatchZeroDwordFill(packet, Code, data, compute);
    Require(fill && fill->base == reinterpret_cast<std::uintptr_t>(Output.data()) && fill->bytes == 1024 && fill->pattern == std::array<std::uint32_t, 4>{}, "the zero dword fill kernel was not recognized as a zero fill");
    for (std::size_t word = 0; word < Code.size(); ++word) {
        auto altered = Code;
        altered[word] ^= 1u;
        Require(!MatchZeroDwordFill(packet, altered, data, compute), "a different shader matched the zero dword fill kernel");
    }
    Require(!MatchZeroDwordFill(packet, std::span(Code).first(5), data, compute), "a truncated shader matched");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 8), compute), "a strided descriptor matched a contiguous fill");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 4, 0x00814204u), compute), "an add-tid descriptor matched");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 4, 0x30014204u), compute), "a raw out-of-bounds mode matched");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data() + 1, 1024), compute), "an unaligned destination matched");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 4, 0x00011204u), compute), "an 8-bit output format matched");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 4, 0x00017204u), compute), "an output format above 32_FLOAT matched");
    Require(MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 4, 0x00015204u), compute).has_value(), "32_SINT output did not match");
    Require(MatchZeroDwordFill(packet, Code, UserData(Output.data(), 1024, 4, 0x00016204u), compute).has_value(), "32_FLOAT output did not match");
    Require(!MatchZeroDwordFill(packet, Code, UserData(Output.data(), 102), compute), "a record count not filling 16-byte units matched");
    auto extra = data;
    extra.push_back(0);
    Require(!MatchZeroDwordFill(packet, Code, extra, compute), "a different user SGPR count matched (the group id moves)");
    auto partial = packet;
    partial[4] |= 0x20u;
    Require(!MatchZeroDwordFill(partial, Code, data, compute), "a partial dispatch matched");
    auto noGroup = compute;
    noGroup.groupIdEnable[0] = false;
    Require(!MatchZeroDwordFill(packet, Code, data, noGroup), "a dispatch without the group id matched");
    const auto clamped = MatchZeroDwordFill(packet, Code, UserData(Output.data(), 64), compute);
    Require(clamped && clamped->bytes == 256, "the fill exceeded the descriptor's records");
}

std::vector<std::uint32_t> Commands(const std::vector<std::uint32_t>& data, std::uint32_t groups, bool partial, std::uint32_t threads) {
    std::vector<std::uint32_t> words;
    const auto registers = [&](std::uint32_t first, std::span<const std::uint32_t> values) {
        words.push_back(0xc0007600u | (static_cast<std::uint32_t>(values.size()) << 16u));
        words.push_back(first);
        words.insert(words.end(), values.begin(), values.end());
    };
    const std::array<std::uint32_t, 3> shape{64, 1, 1};
    registers(0x207, shape);
    const auto address = reinterpret_cast<std::uintptr_t>(Code.data());
    const std::array<std::uint32_t, 2> program{static_cast<std::uint32_t>(address >> 8u), static_cast<std::uint32_t>(address >> 40u)};
    registers(0x20c, program);
    const std::array<std::uint32_t, 1> resource{(static_cast<std::uint32_t>(data.size()) << 1u) | (1u << 7u)};
    registers(0x213, resource);
    registers(0x240, data);
    words.insert(words.end(), {0xc0031500u, partial ? threads : groups, 1, 1, 0x41u | (partial ? 0x20u : 0u)});
    return words;
}

void ExecuteTests() {
    struct Case {
        std::uint32_t groups, records, stride;
        bool partial;
        std::uint32_t threads;
    };
    constexpr std::array<Case, 8> cases{{
        {4, 1024, 4, false, 0},
        {16, 1024, 4, false, 0},
        {4, 64, 4, false, 0},
        {4, 100, 4, false, 0},
        {4, 102, 4, false, 0},
        {2, 1024, 8, false, 0},
        {0, 1024, 4, true, 70},
        {0, 1024, 4, false, 0},
    }};
    for (const auto& item : cases) {
        Output.fill(Untouched);
        const auto words = Commands(UserData(Output.data(), item.records, item.stride), item.groups, item.partial, item.threads);
        Packet packet{const_cast<std::uint32_t*>(words.data()), static_cast<std::uint32_t>(words.size()), 0, {}};
        AgcDriver::Submit(&packet, 0);
        AgcDriverWaitIdle_nid_postfix();
        AgcDriver::GuestMemory::FlushGpuWrites(reinterpret_cast<std::uintptr_t>(Output.data()), sizeof(Output));
        const auto launched = item.partial ? item.threads : item.groups * 64u;
        const auto filled = std::min(launched, item.records);
        const auto step = item.stride / 4u;
        for (std::uint32_t i = 0; i < Output.size(); ++i) {
            const bool written = i % step == 0 && i / step < filled;
            const auto expected = written ? 0u : Untouched;
            Require(Output[i] == expected, "zero dword fill mismatch at " + std::to_string(i) + " (groups " + std::to_string(item.groups) + ", records " + std::to_string(item.records) + ", stride " + std::to_string(item.stride) + "): got " + std::to_string(Output[i]) + ", expected " + std::to_string(expected));
        }
    }
}

}

int main() {
    try {
        if (std::getenv("APS5_NO_FILL_HLE") == nullptr) MatchTests();
        {
            const auto device = OpenVulkanTestDevice();
            if (!device) return VulkanTestSkipped;
        }
        ExecuteTests();
        AgcDriverShutdown_nid_postfix();
        std::puts("zero dword fill tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        AgcDriverShutdown_nid_postfix();
        return 1;
    }
}
