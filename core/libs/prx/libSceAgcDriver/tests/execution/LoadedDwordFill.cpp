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
using AgcDriver::DriverDetail::MatchLoadedDwordFill;

// v_lshl_add_u32 v0, s8, 6, v0; s_buffer_load_dword vcc_lo, s[4:7], 0; s_waitcnt lgkmcnt(0);
// v_mov_b32 v1, vcc_lo; buffer_store_dword v1, v0, s[0:3], 0 idxen; s_endpgm (Stray's DCC key clear).
alignas(256) constexpr std::array<std::uint32_t, 9> Code{0xd7460000u, 0x04010c08u, 0xf4201a82u, 0xfa000000u, 0xbf8cc07fu, 0x7e02026au, 0xe0102000u, 0x80000100u, 0xbf810000u};
constexpr std::uint32_t Untouched = 0xcafebabeu;
alignas(256) std::array<std::uint32_t, 1028> Output{};
alignas(256) std::array<std::uint32_t, 4> Source{0x40404040u, 0xdeadbeefu, 0xdeadbeefu, 0xdeadbeefu};

std::vector<std::uint32_t> UserData(void* output, std::uint32_t records, const void* source = Source.data(), std::uint32_t sourceRecords = 1, std::uint32_t format = 0x00014204u) {
    const auto address = reinterpret_cast<std::uintptr_t>(output);
    const auto from = reinterpret_cast<std::uintptr_t>(source);
    return {static_cast<std::uint32_t>(address), static_cast<std::uint32_t>((address >> 32u) & 0xffffu) | (4u << 16u), records, format,
            static_cast<std::uint32_t>(from), static_cast<std::uint32_t>((from >> 32u) & 0xffffu) | (16u << 16u), sourceRecords, 0x0004dfacu};
}

void MatchTests() {
    const ShaderRecompiler::ShaderComputeStageInfo compute{{64, 1, 1}, 0, {true, false, false}, false, 1};
    const std::array<std::uint32_t, 5> packet{0xc0031500u, 4, 1, 1, 0x41u};
    const auto data = UserData(Output.data(), 1024);
    const auto fill = MatchLoadedDwordFill(packet, Code, data, compute);
    Require(fill && fill->base == reinterpret_cast<std::uintptr_t>(Output.data()) && fill->bytes == 1024 && fill->source == reinterpret_cast<std::uintptr_t>(Source.data()), "the loaded-dword fill kernel was not recognized");
    for (std::size_t word = 0; word < Code.size(); ++word) {
        auto altered = Code;
        altered[word] ^= 1u;
        Require(!MatchLoadedDwordFill(packet, altered, data, compute), "a different shader matched the loaded-dword fill kernel");
    }
    Require(!MatchLoadedDwordFill(packet, std::span(Code).first(8), data, compute), "a truncated shader matched");
    const auto clamped = MatchLoadedDwordFill(packet, Code, UserData(Output.data(), 64), compute);
    Require(clamped && clamped->bytes == 256, "the fill exceeded the descriptor's records");
    Require(!MatchLoadedDwordFill(packet, Code, UserData(Output.data(), 250), compute), "a fill of whole dwords not filling 16-byte units matched");
    Require(!MatchLoadedDwordFill(packet, Code, UserData(Output.data() + 1, 1024), compute), "an unaligned destination matched");
    Require(!MatchLoadedDwordFill(packet, Code, UserData(Output.data(), 1024, Source.data(), 0), compute), "an empty source buffer matched");
    Require(!MatchLoadedDwordFill(packet, Code, UserData(Output.data(), 1024, Source.data(), 1, 0x00814204u), compute), "an add-tid descriptor matched");
    auto extra = data;
    extra.push_back(0);
    Require(!MatchLoadedDwordFill(packet, Code, extra, compute), "a different user SGPR count matched (the group id moves)");
    auto partial = packet;
    partial[4] |= 0x20u;
    Require(!MatchLoadedDwordFill(partial, Code, data, compute), "a dispatch in thread dimensions matched");
    auto indirect = packet;
    indirect[0] = 0xc0021600u;
    Require(!MatchLoadedDwordFill(indirect, Code, data, compute), "an indirect dispatch matched");
    auto noGroup = compute;
    noGroup.groupIdEnable[0] = false;
    Require(!MatchLoadedDwordFill(packet, Code, data, noGroup), "a dispatch without the group id matched");
}

std::vector<std::uint32_t> Commands(const std::vector<std::uint32_t>& data, std::uint32_t groups) {
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
    words.insert(words.end(), {0xc0031500u, groups, 1, 1, 0x41u});
    return words;
}

// Runs through the HLE, or through the recompiled kernel under APS5_NO_FILL_HLE: both must store the
// loaded dword to every element up to the launched threads and the records.
void ExecuteTests() {
    struct Case {
        std::uint32_t groups, records, value;
    };
    constexpr std::array<Case, 5> cases{{
        {4, 1024, 0x40404040u},
        {16, 1024, 0xffffffffu},
        {4, 64, 0x12345678u},
        {2, 1024, 0x00000000u},
        {4, 252, 0x80808080u},
    }};
    for (const auto& item : cases) {
        Output.fill(Untouched);
        Source[0] = item.value;
        const auto words = Commands(UserData(Output.data(), item.records), item.groups);
        Packet packet{const_cast<std::uint32_t*>(words.data()), static_cast<std::uint32_t>(words.size()), 0, {}};
        AgcDriver::Submit(&packet, 0);
        AgcDriverWaitIdle_nid_postfix();
        AgcDriver::GuestMemory::FlushGpuWrites(reinterpret_cast<std::uintptr_t>(Output.data()), sizeof(Output));
        const auto filled = std::min(item.groups * 64u, item.records);
        for (std::uint32_t i = 0; i < Output.size(); ++i) {
            const auto expected = i < filled ? item.value : Untouched;
            Require(Output[i] == expected, "loaded-dword fill mismatch at " + std::to_string(i) + " (groups " + std::to_string(item.groups) + ", records " + std::to_string(item.records) + "): got " + std::to_string(Output[i]) + ", expected " + std::to_string(expected));
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
        std::puts("loaded dword fill tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        AgcDriverShutdown_nid_postfix();
        return 1;
    }
}
