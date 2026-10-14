#include "prx/libSceAgcDriver/Execution/include/Driver.hpp"
#include "prx/libSceAgcDriver/Execution/include/Driver/Driver.hpp"
#include "prx/libSceAgcDriver/Graphics/include/ShaderResources.hpp"
#include "prx/libSceAgcDriver/Submit/include/Dcb.hpp"
#include "prx/libc/include/GuestAllocations.hpp"
#include "prx/libc/include/GuestArena.hpp"
#include "prx/libc/include/GuestWriteWatch.hpp"
#include "VulkanTestDevice.hpp"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <sys/mman.h>
#endif
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <iostream>
#include <string>
#include <vector>

namespace {

using AgcDriver::Graphics::Require;

constexpr std::uint32_t Records = 65536;
constexpr std::uint32_t Stride = 32;
constexpr std::uint32_t Elements = 4096;
constexpr std::uint32_t Spare = 64;
constexpr std::uint32_t TextureBytes = 2048;
constexpr std::uint32_t Aliases = 256;
constexpr std::uint32_t Surfaces = (Elements + Spare + Aliases - 1) / Aliases;
constexpr std::uint32_t Format8888UNorm = 56;
constexpr std::uint32_t Type2D = 9;
constexpr std::size_t SrtBytes = 256;
constexpr std::size_t SrtSlots = 16;
constexpr std::size_t SrtOffset = 4096;
constexpr std::size_t OutputOffset = SrtOffset + SrtSlots * SrtBytes;
constexpr std::size_t HeapOffset = OutputOffset + 4096;
constexpr std::size_t TexturesOffset = HeapOffset + static_cast<std::size_t>(Records) * Stride;
constexpr std::size_t BlockBytes = (TexturesOffset + static_cast<std::size_t>(Surfaces) * TextureBytes + 65535) & ~static_cast<std::size_t>(65535);

constexpr std::array<std::uint32_t, 17> TableCode{0xf4080100u, 0xfa000000u, 0xf4080200u, 0xfa000010u, 0xf4080300u, 0xfa000020u, 0xf4080700u, 0xfa000030u, 0x7e200500u, 0x8f108510u, 0xf42c0502u, 0x20000000u, 0xf09c0f08u, 0x00450000u, 0xe0700000u, 0x80070000u, 0xbf810000u};

class GuestBlock {
public:
    GuestBlock() {
#ifdef _WIN32
        block = static_cast<std::uint8_t*>(GuestArena::GuestArenaAllocate_nid_postfix(BlockBytes, 65536));
        if (block != nullptr) GuestArena::GuestArenaCommit_nid_postfix(block, BlockBytes, PAGE_READWRITE, BlockBytes);
#else
        constexpr std::uintptr_t alignment = 65536;
        void* mapped = mmap(nullptr, BlockBytes + alignment, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (mapped != MAP_FAILED) {
            const auto begin = reinterpret_cast<std::uintptr_t>(mapped);
            const auto aligned = (begin + alignment - 1) & ~(alignment - 1);
            if (aligned != begin) munmap(mapped, aligned - begin);
            if (aligned + BlockBytes != begin + BlockBytes + alignment) munmap(reinterpret_cast<void*>(aligned + BlockBytes), begin + alignment - aligned);
            block = reinterpret_cast<std::uint8_t*>(aligned);
            GuestWriteWatch::GuestWriteWatchRegister_nid_postfix(block, BlockBytes);
        }
#endif
        Require(block != nullptr, "image table cache bounds: cannot allocate the guest block");
        GuestAllocations::Mutation().Add(block, BlockBytes, true, true, true);
    }

    GuestBlock(const GuestBlock&) = delete;
    GuestBlock& operator=(const GuestBlock&) = delete;

    std::uint64_t At(std::size_t offset) const { return static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(block + offset)); }
    std::uint8_t* Bytes(std::size_t offset) const { return block + offset; }

private:
    std::uint8_t* block = nullptr;
};

std::array<std::uint32_t, 4> V(std::uint64_t address, std::uint32_t stride, std::uint32_t records) {
    return {static_cast<std::uint32_t>(address), static_cast<std::uint32_t>((address >> 32u) & 0xffffu) | (stride << 16u), records, stride == 0u ? 0x31016facu : 0x01016facu};
}

void SetRecord(const GuestBlock& block, std::uint32_t record, std::uint32_t element) {
    const auto address = block.At(TexturesOffset + static_cast<std::size_t>(element / Aliases) * TextureBytes);
    const std::array<std::uint32_t, 8> words{static_cast<std::uint32_t>(address >> 8u), static_cast<std::uint32_t>((address >> 40u) & 0xffu) | (Format8888UNorm << 20u) | (3u << 30u), 7u << 14u, 0xfacu | (Type2D << 28u), 0u, 0u, element % Aliases, 0u};
    std::memcpy(block.Bytes(HeapOffset + static_cast<std::size_t>(record) * Stride), words.data(), sizeof(words));
}

std::vector<std::uint32_t> Pm4(std::uint32_t opcode, std::initializer_list<std::uint32_t> body) {
    std::vector<std::uint32_t> words{0xc0000000u | (static_cast<std::uint32_t>(body.size() - 1) << 16u) | (opcode << 8u)};
    words.insert(words.end(), body);
    return words;
}

void Dispatch(const GuestBlock& block, std::size_t slot) {
    const auto kernel = block.At(0);
    const auto srt = block.At(SrtOffset + slot * SrtBytes);
    std::vector<std::uint32_t> words;
    for (const auto& packet : {Pm4(0x76, {0x20c, static_cast<std::uint32_t>(kernel >> 8u)}), Pm4(0x76, {0x20d, static_cast<std::uint32_t>(kernel >> 40u) & 0xffu}), Pm4(0x76, {0x207, 64}), Pm4(0x76, {0x208, 1}), Pm4(0x76, {0x209, 1}), Pm4(0x76, {0x213, 2u << 1u}), Pm4(0x76, {0x240, static_cast<std::uint32_t>(srt)}), Pm4(0x76, {0x241, static_cast<std::uint32_t>(srt >> 32u)}), Pm4(0x15, {1, 1, 1, 0x41})}) {
        words.insert(words.end(), packet.begin(), packet.end());
    }
    Packet dcb{words.data(), static_cast<std::uint32_t>(words.size()), 0, {}};
    Require(sceAgcDriverSubmitDcb(&dcb) == 0, "image table cache bounds: the dispatch submission failed");
    AgcDriverWaitIdle_nid_postfix();
}

void Prepare(const GuestBlock& block) {
    std::memcpy(block.Bytes(0), TableCode.data(), sizeof(TableCode));
    for (std::uint32_t surface = 0; surface < Surfaces; ++surface) std::memset(block.Bytes(TexturesOffset + static_cast<std::size_t>(surface) * TextureBytes), static_cast<int>(surface), TextureBytes);
    for (std::uint32_t record = 0; record < Records; ++record) SetRecord(block, record, record % Elements);
    for (std::size_t slot = 0; slot < SrtSlots; ++slot) {
        auto* srt = reinterpret_cast<std::uint32_t*>(block.Bytes(SrtOffset + slot * SrtBytes));
        std::fill(srt, srt + SrtBytes / 4u, 0u);
        const auto heap = V(block.At(HeapOffset), Stride, Records);
        const auto output = V(block.At(OutputOffset), 0u, 4096u);
        std::copy(heap.begin(), heap.end(), srt);
        std::copy(output.begin(), output.end(), srt + 12);
    }
}

void TablesChangingPerDispatch(const GuestBlock& block) {
    auto& cache = AgcDriver::Graphics::SharedResourceCache();
    std::uint64_t most = 0;
    for (std::uint32_t dispatch = 0; dispatch < 6; ++dispatch) {
        SetRecord(block, dispatch * 977u % Records, Elements + dispatch % Spare);
        Dispatch(block, 0);
        most = std::max(most, cache.TableElements());
    }
    Require(most >= Elements, "image table cache bounds: no dispatch kept its table in the resource cache");
    Require(most <= AgcDriver::Graphics::ResourceCache::TableElementBudget(), "image table cache bounds: tables that changed every dispatch kept " + std::to_string(most) + " table elements in the resource cache, over its budget of " + std::to_string(AgcDriver::Graphics::ResourceCache::TableElementBudget()));
}

void SrtMovingPerDispatch(const GuestBlock& block) {
    using AgcDriver::DriverDetail::Driver;
    for (std::uint32_t record = 0; record < Records; ++record) SetRecord(block, record, record % 4u);
    std::uint64_t most = 0;
    std::size_t entries = 0;
    for (std::size_t slot = 0; slot < SrtSlots; ++slot) {
        Dispatch(block, slot);
        const auto size = Driver::Get().DispatchCacheSize();
        most = std::max(most, size.variantBytes);
        entries = std::max(entries, size.entries);
    }
    Require(entries >= 2, "image table cache bounds: the dispatches were not kept in the dispatch cache");
    Require(most <= Driver::DispatchCacheBytes(), "image table cache bounds: dispatches reading a 2 MiB table through " + std::to_string(SrtSlots) + " SRTs kept " + std::to_string(most >> 20u) + " MiB of captured words in the dispatch cache, over its budget of " + std::to_string(Driver::DispatchCacheBytes() >> 20u) + " MiB");
}

void SetBudgets() {
#ifdef _WIN32
    _putenv_s("APS5_RESOURCE_CACHE_TABLE_ELEMENTS", "8192");
    _putenv_s("APS5_DISPATCH_CACHE_BYTES", "16777216");
#else
    setenv("APS5_RESOURCE_CACHE_TABLE_ELEMENTS", "8192", 1);
    setenv("APS5_DISPATCH_CACHE_BYTES", "16777216", 1);
#endif
}

}

int main() {
    SetBudgets();
    try {
        {
            const auto device = OpenVulkanTestDevice();
            if (!device) return VulkanTestSkipped;
        }
        GuestBlock block;
        Prepare(block);
        TablesChangingPerDispatch(block);
        SrtMovingPerDispatch(block);
        AgcDriverShutdown_nid_postfix();
        std::puts("image table cache bounds tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        AgcDriverShutdown_nid_postfix();
        return 1;
    }
}
