#include "prx/libSceAgcDriver/Execution/include/Driver.hpp"
#include "prx/libSceAgcDriver/Execution/include/GuestMemory.hpp"
#include "prx/libSceAgcDriver/Graphics/include/GuestTextureResource.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Texture.hpp"
#include "prx/libSceAgcDriver/Graphics/include/TextureTiling.hpp"
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
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <iostream>
#include <mutex>
#include <optional>
#include <span>
#include <stdexcept>
#include <string_view>
#include <thread>
#include <vector>

namespace {

using AgcDriver::Graphics::Require;
using AgcDriver::Graphics::StorageTexture;
constexpr std::uint32_t Side = 256;
constexpr std::uint32_t Format32UInt = 20;
constexpr std::uint32_t TileR64KBX = 0x1b;
constexpr std::uint32_t Type2D = 9;
constexpr std::size_t Page = 0x1000;
constexpr std::size_t Block = 0x10000;
constexpr std::size_t SurfaceBytes = 4 * Block;
constexpr std::uint32_t Untouched = 0xdeadbeefu;
constexpr std::uint32_t Stored = 0x12345678u;
constexpr std::uint32_t Filled = 0x9abcdef0u;

alignas(256) constexpr std::array<std::uint32_t, 7> StoreCode{
    0x7e040300, 0x7e060280, 0x7e0202ff, Stored, 0xf0200108, 0x00020102, 0xbf810000,
};

alignas(256) constexpr std::array<std::uint32_t, 9> FillCode{
    0xd7460004, 0x04010c08, 0x7e000204, 0x7e020205, 0x7e040206, 0x7e060207, 0xe01c2000, 0x80000004, 0xbf810000,
};

std::uint64_t AddressOf(const void* data) {
    return static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(data));
}

std::array<std::uint32_t, 8> TextureDescriptor(const std::uint32_t* texels) {
    const auto address = AddressOf(texels);
    return {
        static_cast<std::uint32_t>(address >> 8u),
        static_cast<std::uint32_t>((address >> 40u) & 0xffu) | (Format32UInt << 20u) | (((Side - 1u) & 3u) << 30u),
        ((Side - 1u) >> 2u) | ((Side - 1u) << 14u),
        0xfacu | (TileR64KBX << 20u) | (Type2D << 28u),
        0u,
        0u,
        0u,
        0u,
    };
}

void Dispatch(std::span<const std::uint32_t> code, std::uint32_t threads, std::uint32_t resource, std::span<const std::uint32_t> userData, std::uint32_t groups) {
    std::vector<std::uint32_t> words;
    const auto registers = [&](const std::uint32_t first, const std::span<const std::uint32_t> values) {
        words.push_back(0xc0007600u | (static_cast<std::uint32_t>(values.size()) << 16u));
        words.push_back(first);
        words.insert(words.end(), values.begin(), values.end());
    };
    const std::array<std::uint32_t, 3> shape{threads, 1, 1};
    registers(0x207, shape);
    const auto address = AddressOf(code.data());
    const std::array<std::uint32_t, 2> program{static_cast<std::uint32_t>(address >> 8u), static_cast<std::uint32_t>(address >> 40u)};
    registers(0x20c, program);
    const std::array<std::uint32_t, 1> layout{resource};
    registers(0x213, layout);
    registers(0x240, userData);
    words.insert(words.end(), {0xc0031500u, groups, 1, 1, 0x41u});
    Packet packet{words.data(), static_cast<std::uint32_t>(words.size()), 0, {}};
    AgcDriver::Submit(&packet, 0);
}

void Store(const std::uint32_t* texels) {
    std::array<std::uint32_t, 16> userData{};
    const auto texture = TextureDescriptor(texels);
    std::copy(texture.begin(), texture.end(), userData.begin() + 8);
    Dispatch(StoreCode, 8, static_cast<std::uint32_t>(userData.size()) << 1u, userData, 1);
}

void Fill(const std::uint32_t* texels) {
    const auto address = AddressOf(texels);
    const std::array<std::uint32_t, 8> userData{
        static_cast<std::uint32_t>(address),
        static_cast<std::uint32_t>((address >> 32u) & 0xffffu) | (16u << 16u),
        static_cast<std::uint32_t>(SurfaceBytes / 16u),
        0x4bfacu,
        Filled,
        Filled,
        Filled,
        Filled,
    };
    Dispatch(FillCode, 64, (static_cast<std::uint32_t>(userData.size()) << 1u) | 0x80u, userData, static_cast<std::uint32_t>(SurfaceBytes / 1024u));
}

class Surface {
public:
    explicit Surface(bool watched = false) : watched(watched) {
        if (watched) {
#ifdef _WIN32
            texels = static_cast<std::uint32_t*>(GuestArena::GuestArenaAllocate_nid_postfix(SurfaceBytes, Block));
            if (texels != nullptr) GuestArena::GuestArenaCommit_nid_postfix(texels, SurfaceBytes, PAGE_READWRITE, SurfaceBytes);
#else
            void* mapped = mmap(nullptr, SurfaceBytes + Block, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (mapped != MAP_FAILED) {
                const auto begin = reinterpret_cast<std::uintptr_t>(mapped);
                const auto aligned = (begin + Block - 1) & ~std::uintptr_t{Block - 1};
                if (aligned != begin) munmap(mapped, aligned - begin);
                if (aligned != begin + Block) munmap(reinterpret_cast<void*>(aligned + SurfaceBytes), begin + Block - aligned);
                texels = reinterpret_cast<std::uint32_t*>(aligned);
                GuestWriteWatch::GuestWriteWatchRegister_nid_postfix(texels, SurfaceBytes);
            }
#endif
        } else {
            storage.resize((SurfaceBytes + Block) / 4u);
            texels = reinterpret_cast<std::uint32_t*>((reinterpret_cast<std::uintptr_t>(storage.data()) + Block - 1) & ~std::uintptr_t{Block - 1});
        }
        Require(texels != nullptr, "store over untracked: cannot allocate the guest surface");
        std::fill(texels, texels + SurfaceBytes / 4u, Untouched);
        GuestAllocations::Mutation().Add(texels, SurfaceBytes, true, true, true);
    }

    ~Surface() {
        GuestAllocations::Mutation().Remove(texels);
        if (!watched) return;
#ifdef _WIN32
        GuestArena::GuestArenaReset_nid_postfix(texels, SurfaceBytes);
        GuestArena::GuestArenaRelease_nid_postfix(texels, SurfaceBytes);
#else
        munmap(texels, SurfaceBytes);
        GuestWriteWatch::GuestWriteWatchUnregister_nid_postfix(texels, SurfaceBytes);
#endif
    }

    Surface(const Surface&) = delete;
    Surface& operator=(const Surface&) = delete;

    std::uint32_t* Texels() const { return texels; }
    std::uint8_t* Bytes() const { return reinterpret_cast<std::uint8_t*>(texels); }
    std::uint64_t Address() const { return AddressOf(texels); }

private:
    bool watched;
    std::vector<std::uint32_t> storage;
    std::uint32_t* texels = nullptr;
};

std::uint8_t Pattern(std::size_t offset) {
    return static_cast<std::uint8_t>(0x40u + offset % 0x3bu);
}

std::size_t LostBytes(const std::uint8_t* bytes) {
    std::size_t lost = 0;
    for (std::size_t offset = 0; offset < Page; ++offset) {
        if (static_cast<const volatile std::uint8_t*>(bytes)[offset] != Pattern(offset)) ++lost;
    }
    return lost;
}

bool Holds(const std::uint32_t* texels, std::uint32_t value) {
    const auto* words = static_cast<const volatile std::uint32_t*>(texels);
    for (std::size_t index = 0; index < SurfaceBytes / 4u; ++index) {
        if (words[index] == value) return true;
    }
    return false;
}

template <typename THold>
bool HoldPending(THold& hold, const Surface& surface, std::uint32_t result) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (true) {
        hold.lock();
        if (StorageTexture::AnyPending()) return true;
        hold.unlock();
        if (Holds(surface.Texels(), result)) return false;
        Require(std::chrono::steady_clock::now() < deadline, "store over untracked: the result neither became pending nor reached guest memory");
        std::this_thread::yield();
    }
}

template <typename THold>
void Settle(THold& hold, const Surface& surface, std::uint32_t result) {
    if (!HoldPending(hold, surface, result)) return;
    StorageTexture::FlushAllPending("store over untracked fixture");
    hold.unlock();
}

enum class Kind { ReadAfter, ReadBefore, Filled, Copied, LeftWatch };

struct Case {
    const char* name;
    Kind kind;
    std::size_t access;
};

enum class Outcome { Kept, Lost, Missed };

Outcome Run(const Case& test) {
    std::optional<Surface> source;
    if (test.kind == Kind::Copied) source.emplace();
    Surface surface(test.kind == Kind::LeftWatch);
    auto* bytes = surface.Bytes();
    const auto address = surface.Address();
    std::unique_lock hold(AgcDriver::GuestMemory::GpuMutex(), std::defer_lock);
    bool unsaved = false;
    if (test.kind == Kind::Copied) {
        Store(source->Texels());
        Settle(hold, *source, Stored);
        Fill(source->Texels());
        Settle(hold, *source, Filled);
    }
    Store(surface.Texels());
    if (test.kind == Kind::Filled) {
        Settle(hold, surface, Stored);
        Fill(surface.Texels());
        if (!HoldPending(hold, surface, Filled)) return Outcome::Missed;
    } else if (test.kind == Kind::Copied) {
        Settle(hold, surface, Stored);
        hold.lock();
        const auto from = StorageTexture::FindLive(source->Address(), SurfaceBytes);
        const auto to = StorageTexture::FindLive(address, SurfaceBytes);
        Require(from != nullptr && to != nullptr, "store over untracked: the surfaces have no storage images to copy between");
        const char* refusal = nullptr;
        if (!to->CopyFrom(*from, refusal)) {
            Require(refusal != nullptr && std::string_view(refusal) == "not imported", "store over untracked: the image copy was refused");
            std::fprintf(stderr, "[store over untracked] %s: not run, the surface has no host import\n", test.name);
            return Outcome::Kept;
        }
    } else if (!HoldPending(hold, surface, Stored)) {
        return Outcome::Missed;
    }
    if (test.kind == Kind::LeftWatch) {
        if (!AgcDriver::GuestMemory::Watched(address, SurfaceBytes)) {
            StorageTexture::FlushAllPending("store over untracked fixture");
            std::fprintf(stderr, "[store over untracked] %s: not run, the surface is not write-watched\n", test.name);
            return Outcome::Kept;
        }
        const auto image = StorageTexture::FindLive(address, SurfaceBytes);
        Require(image != nullptr, "store over untracked: the surface has no storage image");
        unsaved = !image->GuestSnapshotValid();
        AgcDriver::GuestMemory::Unwatch(address, SurfaceBytes);
    }
    std::array<std::byte, Page> read{};
    if (test.kind == Kind::ReadBefore) AgcDriver::GuestMemory::Read(address + Block + Page, read);
    for (std::size_t offset = 0; offset < Page; ++offset) static_cast<volatile std::uint8_t*>(bytes)[offset] = Pattern(offset);
    if (unsaved) {
        bool refused = false;
        try {
            AgcDriver::GuestMemory::Read(address + test.access, read);
        } catch (const std::runtime_error& error) {
            if (std::string_view(error.what()).find("outside the write watch") == std::string_view::npos) throw;
            refused = true;
        }
        static_cast<void>(StorageTexture::DiscardPendingInside(address, SurfaceBytes));
        if (refused && LostBytes(bytes) == 0) return Outcome::Kept;
        std::fprintf(stderr, "[store over untracked] %s: the result was stored with neither write stamps nor saved bytes to tell what the CPU wrote\n", test.name);
        return Outcome::Lost;
    }
    AgcDriver::GuestMemory::Read(address + test.access, read);
    const auto lostAtAccess = LostBytes(bytes);
    StorageTexture::FlushAllPending("store over untracked fixture");
    std::vector<std::byte> whole(SurfaceBytes);
    AgcDriver::GuestMemory::Read(address, whole);
    const auto lostAtEnd = LostBytes(bytes);
    if (test.kind == Kind::Filled || test.kind == Kind::Copied) Require(static_cast<const volatile std::uint32_t*>(surface.Texels())[2 * Block / 4u] == Filled, "store over untracked: the result did not reach a block the CPU left alone");
    if (lostAtAccess == 0 && lostAtEnd == 0) return Outcome::Kept;
    std::fprintf(stderr, "[store over untracked] %s: of 0x%zx bytes the CPU wrote while the result was pending, %zu were lost after the access at +0x%zx and %zu after every result was stored\n", test.name, Page, lostAtAccess, test.access, lostAtEnd);
    return Outcome::Lost;
}

}

int main() {
    try {
        {
            const auto device = OpenVulkanTestDevice();
            if (!device) return VulkanTestSkipped;
        }
        struct ShutdownGuard {
            ~ShutdownGuard() { try { AgcDriverShutdown_nid_postfix(); } catch (...) {} }
        } shutdown;
        {
            Surface probe;
            Require(AgcDriver::Graphics::DescribeSurface(AgcDriver::Graphics::DecodeTextureResource(TextureDescriptor(probe.Texels()))).guestBytes == SurfaceBytes, "store over untracked: unexpected surface size");
        }
        constexpr std::array<Case, 5> cases{{
            {"another block read after the CPU write", Kind::ReadAfter, Block + Page},
            {"another block read before the CPU write", Kind::ReadBefore, 0xe000},
            {"a fill of the surface", Kind::Filled, 0xe000},
            {"an image copy into the surface", Kind::Copied, 0xe000},
            {"a surface that left the write watch", Kind::LeftWatch, 0xe000},
        }};
        bool kept = true;
        for (const auto& test : cases) {
            auto outcome = Outcome::Missed;
            for (std::uint32_t attempt = 0; attempt < 256u && outcome == Outcome::Missed; ++attempt) outcome = Run(test);
            Require(outcome != Outcome::Missed, "store over untracked: the result was never held pending");
            kept = outcome == Outcome::Kept && kept;
        }
        Require(kept, "a pending storage result was stored over bytes the CPU wrote to untracked memory");
        AgcDriverShutdown_nid_postfix();
        std::puts("store over untracked tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
