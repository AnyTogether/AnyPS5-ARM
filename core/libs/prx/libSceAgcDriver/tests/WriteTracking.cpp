#include "prx/libSceAgcDriver/Execution/include/GuestMemory.hpp"
#include "prx/libc/include/GuestAllocations.hpp"
#include "prx/libc/include/GuestArena.hpp"
#include "prx/libc/include/GuestWriteWatch.hpp"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <sys/mman.h>
#endif
#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

using namespace AgcDriver::GuestMemory;

constexpr std::size_t Block = 65536;
#ifdef _WIN32
constexpr wchar_t HostHoleMode[] = L"--host-hole";
#endif

void Require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

void* AllocateWatched(std::size_t bytes, bool crossLeaf = false) {
#ifdef _WIN32
    static_cast<void>(crossLeaf);
    void* block = GuestArena::GuestArenaAllocate_nid_postfix(bytes, Block);
    GuestArena::GuestArenaCommit_nid_postfix(block, bytes, PAGE_READWRITE, bytes);
#else
    const std::size_t alignment = crossLeaf ? std::size_t{1} << 32 : Block;
    const auto prefix = crossLeaf ? Block : 0;
    void* raw = mmap(nullptr, bytes + alignment, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (raw == MAP_FAILED) throw std::runtime_error("cannot map the watched block");
    const auto begin = reinterpret_cast<std::uintptr_t>(raw);
    const auto aligned = ((begin + prefix + alignment - 1) & ~static_cast<std::uintptr_t>(alignment - 1)) - prefix;
    if (aligned != begin) munmap(raw, aligned - begin);
    if (aligned + bytes != begin + bytes + alignment) munmap(reinterpret_cast<void*>(aligned + bytes), begin + alignment - aligned);
    void* block = reinterpret_cast<void*>(aligned);
    GuestWriteWatch::GuestWriteWatchRegister_nid_postfix(block, bytes);
#endif
    Require(Watched(reinterpret_cast<std::uint64_t>(block), bytes), "the test block is not watched");
    return block;
}

void CheckSharedBlock() {
    void* memory = AllocateWatched(3 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    const auto boundary = base + 2 * Block - 0xb800;
    const auto firstBegin = base;
    const auto secondEnd = base + 3 * Block;
    const auto sharedFirst = boundary - (base + Block);
    const auto sharedSecond = base + 2 * Block - boundary;
    std::memset(memory, 0x11, 3 * Block);

    const auto synced = CollectWrites(base, 3 * Block);
    Require(synced != 0, "the test block is not collected");

    Require(MarkWritten(firstBegin, static_cast<std::size_t>(boundary - firstBegin)) != 0, "a driver store into watched memory is not stamped");
    std::array<std::uint64_t, 2> generations{synced, synced};
    std::array<std::uint8_t, 2> changed{};
    Require(ChangedBlocks(base + Block, 2 * Block, generations, changed) && changed[0] == BlockWritten && changed[1] == BlockUnchanged, "the shared block does not read as written");
    Require(!StoredOver(boundary, static_cast<std::size_t>(sharedSecond), synced), "a store of the neighbour's bytes counts for the second surface's part of the shared block");
    Require(StoredOver(base + Block, static_cast<std::size_t>(sharedFirst), synced), "the first surface's own store is not seen over its part of the shared block");
    Require(!StoredOver(boundary, static_cast<std::size_t>(secondEnd - boundary), synced), "the second surface reads as stored over");

    const auto touched = MarkWritten(boundary + 0x100, 4);
    Require(StoredOver(boundary, static_cast<std::size_t>(sharedSecond), synced), "a store over the second surface's bytes is not seen");
    Require(!StoredOver(boundary, static_cast<std::size_t>(sharedSecond), touched), "a store older than the generation is seen");

    const auto whole = TrackerGeneration();
    MarkWritten(base + Block, Block);
    Require(StoredOver(boundary, static_cast<std::size_t>(sharedSecond), whole), "a store over the whole block is not seen");
    const auto afterWhole = TrackerGeneration();
    MarkWritten(base + Block, static_cast<std::size_t>(sharedFirst));
    Require(!StoredOver(boundary, static_cast<std::size_t>(sharedSecond), afterWhole), "a partial store after a whole-block store is taken for the whole block");

    const auto many = TrackerGeneration();
    for (int store = 0; store < 6; ++store) MarkWritten(base + Block + static_cast<std::uint64_t>(store) * 64, 4);
    Require(StoredOver(boundary, static_cast<std::size_t>(sharedSecond), many), "forgotten driver stores are taken as missing the range");

    const auto beforeCpu = CollectWrites(base, 3 * Block);
    static_cast<volatile std::uint8_t*>(memory)[Block + 8] = 0x22;
    CollectWritesUncached(base, 3 * Block);
    Require(!StoredOver(boundary, static_cast<std::size_t>(sharedSecond), beforeCpu), "a CPU store outside the shared range counts for it");

    std::array<std::uint8_t, 64> unwatched{};
    const auto outside = reinterpret_cast<std::uint64_t>(unwatched.data());
    if (!Watched(outside, unwatched.size())) Require(StoredOver(outside, unwatched.size(), TrackerGeneration()), "an unwatched range reads as not stored over");
}

void CheckOwnStore() {
    void* memory = AllocateWatched(2 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    const auto second = base + Block;
    std::memset(memory, 0x11, 2 * Block);
    const auto synced = CollectWrites(base, 2 * Block);
    Require(synced != 0, "the own-store block is not collected");

    std::array<std::byte, 8192> bytes{};
    bytes.fill(std::byte{0x44});
    Write(second, bytes);
    const auto stored = TrackerGeneration();
    Require(!UnchangedSince(second, bytes.size(), synced), "the driver store is not stamped");
    CollectWritesUncached(base, 2 * Block);
    Require(UnchangedSince(second, Block, stored), "a walk after a driver store reports the store again as a newer write");
    Require(UnchangedSinceCollected(second, bytes.size(), synced), "the driver store's own page faults are stamped as a CPU write");

    static_cast<volatile std::uint8_t*>(memory)[Block + 3 * 4096 + 8] = 0x22;
    const std::array<std::byte, 64> label{};
    Write(second + 3 * 4096 + 64, label);
    Require(!UnchangedSinceCollected(second + 3 * 4096, 4096, stored), "a CPU write before a driver store in its page is not stamped as one");

    const auto beforeCpu = TrackerGeneration();
    static_cast<volatile std::uint8_t*>(memory)[16] = 0x33;
    CollectWritesUncached(base, 2 * Block);
    Require(!UnchangedSince(base, 64, beforeCpu), "a CPU write after the driver store is not seen");
}

void CheckUnwatch() {
    void* memory = AllocateWatched(3 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    const auto imported = base + Block;
    std::memset(memory, 0x11, 3 * Block);
    BumpCollectEpoch();
    const auto before = CollectWrites(base, 3 * Block);
    Require(before != 0 && UnchangedSince(imported, Block, before), "the import range was not initially watched");
    Unwatch(imported, Block);
    Require(!Watched(imported, Block) && !UnchangedSince(imported, Block, before), "unwatch kept trusting import stamps");
    Require(CollectWrites(base, 3 * Block) == 0 && CollectWritesUncached(imported, Block) == 0, "unwatch did not invalidate a cached collect");
    Require(Watched(base, Block) && Watched(base + 2 * Block, Block), "unwatch disabled unrelated memory");
    const auto beforeDriverWrite = TrackerGeneration();
    Require(MarkWritten(imported, Block) == 0, "an unwatched import still produces trusted stamps");
    Require(TrackerGeneration() > beforeDriverWrite, "an unwatched driver write did not invalidate byte comparisons");
    const auto beforeOwnWrite = TrackerGeneration();
    StoreOwnBytes(imported, 1, [&] { *reinterpret_cast<std::uint8_t*>(imported) = 0x42; });
    Require(TrackerGeneration() > beforeOwnWrite, "an unwatched CPU store did not invalidate byte comparisons");
    std::array<std::uint64_t, 1> generations{before};
    std::array<std::uint8_t, 1> changed{};
    Require(!ChangedBlocks(imported, Block, generations, changed), "an unwatched import still uses block stamps");
    Unwatch(imported, Block);
    const auto adjacent = CollectWrites(base, Block);
    Require(adjacent != 0, "unwatch broke the adjacent block's collect");
    static_cast<volatile std::uint8_t*>(memory)[0] = 0x33;
    CollectWritesUncached(base, Block);
    Require(!UnchangedSince(base, Block, adjacent), "unwatch hid a CPU edit in unrelated memory");
}

void CheckNewestStamp() {
    void* memory = AllocateWatched(4 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    const auto first = base + Block;
    const auto second = base + 2 * Block;
    std::memset(memory, 0x11, 4 * Block);
    BumpCollectEpoch();
    CollectWrites(base, 4 * Block);
    Unwatch(first, 2 * Block);
    const auto firstBefore = NewestStamp(first, Block);
    const auto secondBefore = NewestStamp(second, Block);
    MarkWritten(second + 16, 4);
    Require(NewestStamp(second, Block) > secondBefore, "a driver store into unwatched memory did not advance its stamp");
    Require(NewestStamp(first, Block) == firstBefore, "a driver store advanced the stamp of other unwatched memory");
    const auto generation = TrackerGeneration();
    static_cast<volatile std::uint8_t*>(memory)[0] = 0x22;
    CollectWritesUncached(base, Block);
    Require(TrackerGeneration() > generation && NewestStamp(first, Block) == firstBefore, "a CPU store into watched memory advanced the stamp of unwatched memory");
    StoreOwnBytes(first, 1, [&] { *reinterpret_cast<std::uint8_t*>(first) = 0x42; });
    Require(NewestStamp(first, Block) > firstBefore, "an own store into unwatched memory did not advance its stamp");
    const auto partial = NewestStamp(base + 3 * Block - 8, Block + 8);
    static_cast<volatile std::uint8_t*>(memory)[3 * Block] = 0x33;
    CollectWritesUncached(base + 3 * Block, Block);
    Require(NewestStamp(base + 3 * Block - 8, Block + 8) > partial, "a CPU store into the watched part of a partly watched range did not advance its stamp");
}

#ifdef _WIN32
void CheckDeferredSharedImports() {
    constexpr std::size_t bytes = 4 * Block;
    HANDLE section = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_EXECUTE_READWRITE | SEC_RESERVE, 0, bytes, nullptr);
    Require(section != nullptr, "cannot create shared import backing");
    auto* memory = static_cast<std::uint8_t*>(GuestArena::GuestArenaAllocate_nid_postfix(bytes, Block));
    Require(memory != nullptr, "cannot allocate shared import address");
    GuestArena::GuestArenaMap_nid_postfix(memory, bytes, section, 0, PAGE_READWRITE);
    const auto base = reinterpret_cast<std::uintptr_t>(memory);
    const auto protection = [&](std::size_t offset) {
        MEMORY_BASIC_INFORMATION info{};
        Require(VirtualQuery(memory + offset, &info, sizeof(info)) == sizeof(info), "cannot query shared import protection");
        return info.Protect;
    };
    Require(ImportWatched(base, bytes, [] { return true; }), "fresh shared import failed");
    Require(protection(0) == PAGE_READWRITE && protection(bytes - 1) == PAGE_READWRITE, "fresh import armed shared pages");
    const auto gpu = MarkWritten(base + 4096, 4);
    Require(gpu != 0 && protection(0) == PAGE_READONLY && protection(Block) == PAGE_READWRITE, "GPU write did not activate only its block");
    CollectWritesUncached(base, Block);
    Require(!WrittenSince(base + 4096, 4, gpu) && !StoredOver(base + 4096, 4, gpu), "first collect overwrote a GPU generation");
    static_cast<volatile std::uint8_t*>(memory)[4096] = 0x44;
    CollectWritesUncached(base, Block);
    Require(WrittenSince(base + 4096, 4, gpu) && StoredOver(base + 4096, 4, gpu), "CPU store after GPU write was missed");

    const auto second = base + Block;
    const auto before = CollectWritesUncached(second, 4096);
    Require(MarkWritten(second, 4) != 0, "GPU write next to fresh pages failed");
    Require(UnchangedSinceCollected(second, 4, before), "fresh neighbors were stamped as new CPU writes over a collected page");
    Require(StoredOver(second + 8 * 4096, 4096, before), "fresh neighbor history was lost");
    const std::array<std::uint64_t, 1> generations{before};
    std::array<std::uint8_t, 1> changed{};
    std::array<std::uint8_t, 1> cpu{};
    Require(ChangedBlocks(second, Block, generations, changed, cpu) && changed[0] == BlockWritten && cpu[0] == 0, "fresh collection set the block's CPU stamp");
    const auto generation = TrackerGeneration();
    Require(MarkWritten(second, 4) == generation + 1, "an already collected GPU block advanced twice");

    const auto third = base + 2 * Block;
    const auto cached = CollectWritesUncached(third, Block);
    Require(ImportWatched(third, Block, [&] {
        static_cast<volatile std::uint8_t*>(memory)[2 * Block] = 0x55;
        return true;
    }), "tracked import window failed");
    Require(!UnchangedSince(third, Block, cached) && WrittenSince(third, Block, cached), "a store of new bytes within a tracked import window was missed");
    const auto afterImport = CollectWritesUncached(third, Block);
    static_cast<volatile std::uint8_t*>(memory)[2 * Block] = 0x66;
    Require(ImportWatched(third, Block, [] { return true; }) && WrittenSince(third, Block, afterImport), "pre-import CPU store was not collected");

    GuestArena::GuestArenaReset_nid_postfix(memory + 3 * Block, 16384);
    const auto edge = base + 3 * Block + 16384;
    Require(ImportWatched(edge, Block - 16384, [] { return true; }), "unaligned shared import failed");
    const auto edgeGpu = MarkWritten(edge, 4);
    Require(edgeGpu != 0, "fresh collection rejected an unmapped block neighbor");
    CollectWritesUncached(edge, Block - 16384);
    Require(!WrittenSince(edge, 4, edgeGpu), "edge block collection overwrote GPU results");
    GuestArena::GuestArenaReset_nid_postfix(memory, bytes);
    GuestArena::GuestArenaRelease_nid_postfix(memory, bytes);
    CloseHandle(section);
}


void CheckPrivateMappingReuse() {
    void* memory = AllocateWatched(3 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    std::memset(memory, 0x11, 3 * Block);
    BumpCollectEpoch();
    const auto before = CollectWrites(base, 3 * Block);
    Require(before != 0, "the original backing was not collected");
    Unwatch(base + Block, Block);
    Require(!Watched(base + Block, Block), "the imported block stayed watched");
    GuestArena::GuestArenaCommit_nid_postfix(memory, 3 * Block, PAGE_READWRITE, 3 * Block);
    Require(!Watched(base + Block, Block), "a protection-only commit restored an imported block");
    const auto neighbour = CollectWrites(base, Block);
    Require(neighbour != 0, "the neighbouring block was not collected before remapping");
    GuestArena::GuestArenaReset_nid_postfix(memory, 3 * Block);
    GuestArena::GuestArenaRelease_nid_postfix(memory, 3 * Block);
    auto* replacement = GuestArena::GuestArenaAllocateAtOrAbove_nid_postfix(base, 3 * Block, Block);
    Require(replacement == memory, "the released arena address was not reused");
    GuestArena::GuestArenaCommit_nid_postfix(replacement, 3 * Block, PAGE_READWRITE, 3 * Block);
    Require(Watched(base, 3 * Block), "fresh backing at an excluded address is not watched");
    Require(!UnchangedSince(base + Block, Block, before), "fresh backing reused an old import generation");
    Require(!UnchangedSince(base, Block, neighbour), "fresh backing reused an adjacent block's old generation");
    const auto after = CollectWrites(base, 3 * Block);
    Require(after > before && UnchangedSince(base, 3 * Block, after), "fresh backing was not collected");
    static_cast<volatile std::uint8_t*>(replacement)[Block + 8] = 0x22;
    CollectWritesUncached(base, 3 * Block);
    Require(!UnchangedSince(base + Block, Block, after), "a CPU edit in fresh backing was missed");
    Unwatch(base + Block, Block);
    Require(!Watched(base + Block, Block) && CollectWrites(base + Block, Block) == 0, "a second import of fresh backing stayed watched");
    GuestArena::GuestArenaReset_nid_postfix(replacement, 3 * Block);
    GuestArena::GuestArenaRelease_nid_postfix(replacement, 3 * Block);
}

std::uint64_t ChildHostHole() {
    std::uintptr_t arena = 0;
    std::size_t arenaBytes = 0;
    GuestArena::GuestArenaRange_nid_postfix(&arena, &arenaBytes);
    return (arena + arenaBytes / 2) & ~(std::uint64_t{Block} - 1);
}

void CheckHostHoleInChild() {
    std::array<wchar_t, 32768> executable{};
    const DWORD length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
    Require(length != 0 && length < executable.size(), "cannot name the test executable");
    const std::wstring command = L"\"" + std::wstring(executable.data(), length) + L"\" " + HostHoleMode;
    std::vector<wchar_t> commandLine(command.begin(), command.end());
    commandLine.push_back(L'\0');
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION process{};
    Require(CreateProcessW(executable.data(), commandLine.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &process) != 0, "cannot create the host-hole child");
    const bool reserved = VirtualAllocEx(process.hProcess, reinterpret_cast<void*>(ChildHostHole()), Block, MEM_RESERVE, PAGE_NOACCESS) != nullptr;
    const bool resumed = reserved && ResumeThread(process.hThread) != static_cast<DWORD>(-1);
    const bool exited = resumed && WaitForSingleObject(process.hProcess, 60000) == WAIT_OBJECT_0;
    if (!exited) {
        TerminateProcess(process.hProcess, 1);
        WaitForSingleObject(process.hProcess, INFINITE);
    }
    DWORD exitCode = 1;
    const bool reported = GetExitCodeProcess(process.hProcess, &exitCode) != 0;
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    Require(reserved, "cannot reserve a host range in the child's arena interval");
    Require(resumed, "cannot resume the host-hole child");
    Require(exited, "the host-hole child did not exit");
    Require(reported && exitCode == 0, "the host-hole child failed");
}

void CheckHostHole() {
    constexpr std::size_t bytes = 64;
    const auto hole = ChildHostHole();
    Require(GuestArena::GuestArenaHostRegionOverlaps_nid_postfix(hole, bytes), "the range reserved before the arena is not an arena host region");
    const auto before = TrackerGeneration();
    Require(!Watched(hole, bytes), "an arena host hole reads as watched");
    Require(CollectWrites(hole, bytes) == 0 && CollectWritesUncached(hole, bytes) == 0, "an arena host hole was collected");
    auto* watched = static_cast<std::uint8_t*>(AllocateWatched(Block, true));
    struct Cleanup {
        void* memory;
        ~Cleanup() { GuestArena::GuestArenaRelease_nid_postfix(memory, Block); }
    } cleanup{watched};
    const auto base = reinterpret_cast<std::uint64_t>(watched);
    for (unsigned epoch = 0; epoch < 2; ++epoch) {
        BumpCollectEpoch();
        watched[7] ^= 1;
        Require(CollectWrites(base + 7, 1) != 0, "a warm host-hole check could not collect its watched range");
        for (unsigned repeat = 0; repeat < 3; ++repeat) {
            Require(CollectWrites(base + 7, 1) != 0, "a warm host-hole check lost its watched range");
            Require(CollectWrites(hole, bytes) == 0, "a repeated host-hole query hit a collect memo");
            Require(CollectWrites(hole + 7, 1) == 0, "a page-rounded host-hole query hit a collect memo");
        }
    }
    Require(StoredOver(hole, bytes, before), "an arena host hole reads as not stored over");
    Require(!UnchangedSince(hole, bytes, before), "an arena host hole reads as unchanged");
    const std::array queries{UnchangedQuery{hole, bytes, before}};
    Require(!UnchangedSinceAll(queries), "an arena host hole reads as unchanged in a batch");
    Require(!UnchangedSinceCollected(hole, bytes, before), "an arena host hole reads as unchanged since a collect");
    Require(MarkWritten(hole, bytes) == 0, "a driver store into an arena host hole is stamped");
    Require(StoreOwnBytes(hole, bytes, [] {}) == 0, "an own store into an arena host hole is stamped");
    Require(!WrittenSince(hole, bytes, before), "an arena host hole reads its stamps as written");
    std::array<std::uint64_t, 1> generations{before};
    std::array<std::uint8_t, 1> changed{};
    std::array<std::uint8_t, 1> cpu{};
    Require(!ChangedBlocks(hole, bytes, generations, changed, cpu) && changed[0] == BlockWritten && cpu[0] == 1, "an arena host hole uses block stamps");
    bool imported = false;
    Require(ImportWatched(hole, bytes, [&] {
        imported = true;
        return true;
    }) && imported, "an import into an arena host hole did not run");
    Require(!Watched(hole, bytes), "an import made an arena host hole watched");
}
#endif

void CheckVersionRanges() {
    constexpr std::size_t count = 80;
    constexpr auto bytes = count * Block;
    auto* memory = static_cast<std::uint8_t*>(AllocateWatched(bytes, true));
    struct Cleanup {
        void* memory;
        ~Cleanup() {
#ifdef _WIN32
            GuestArena::GuestArenaRelease_nid_postfix(memory, bytes);
#else
            GuestWriteWatch::GuestWriteWatchUnregister_nid_postfix(memory, bytes);
            munmap(memory, bytes);
#endif
        }
    } cleanup{memory};
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    Require(UnchangedSince(base, bytes, TrackerGeneration()), "a new range has newer version stamps");
    std::memset(memory, 17, bytes);
    const auto initial = CollectWritesUncached(base, bytes);
    Require(initial != 0, "version ranges could not be collected");
    struct Write { std::size_t block; std::uint64_t generation; };
    std::vector<Write> history;
    std::vector<std::uint64_t> checkpoints{initial};
    std::uint32_t random = 0x61387a29;
    const auto next = [&] { random = random * 1664525u + 1013904223u; return random; };
    const auto expected = [&](const UnchangedQuery& query) {
        if (query.generation == 0) return false;
        for (const auto& write : history) {
            const auto begin = base + write.block * Block;
            if (write.generation > query.generation && begin < query.address + query.bytes && query.address < begin + Block) return false;
        }
        return true;
    };
    for (unsigned step = 0; step < 512; ++step) {
        const auto block = step < 3 ? step : next() % count;
        std::uint64_t generation;
        if (step % 3 == 0) {
            memory[block * Block + 9] ^= 1;
            generation = CollectWritesUncached(base + block * Block, Block);
        } else generation = MarkWritten(base + block * Block + 13, 4);
        Require(generation > checkpoints.back(), "version range write did not advance the tracker");
        history.push_back({block, generation});
        checkpoints.push_back(generation);
        for (unsigned check = 0; check < 16; ++check) {
            std::array<UnchangedQuery, 3> queries;
            bool all = true;
            for (auto& query : queries) {
                const auto offset = next() % bytes;
                query = {base + offset, 1 + next() % (bytes - offset), checkpoints[next() % checkpoints.size()]};
                const auto same = expected(query);
                Require(UnchangedSince(query.address, query.bytes, query.generation) == same, "version range disagrees with write history");
                all = all && same;
            }
            Require(UnchangedSinceAll(queries) == all, "batched version ranges disagree with write history");
        }
    }
    Require(!UnchangedSince(base, bytes, 0), "an unknown generation was accepted");
    Require(UnchangedSince(base, bytes, checkpoints.back()), "the latest checkpoint was rejected");
}

void CheckCollectBoundaries() {
    constexpr std::size_t bytes = 3 * Block;
    auto* memory = static_cast<std::uint8_t*>(AllocateWatched(bytes));
    struct Cleanup {
        void* memory;
        ~Cleanup() {
#ifdef _WIN32
            GuestArena::GuestArenaRelease_nid_postfix(memory, bytes);
#else
            Unwatch(reinterpret_cast<std::uint64_t>(memory), bytes);
            munmap(memory, bytes);
#endif
        }
    } cleanup{memory};
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    std::memset(memory, 17, bytes);
    bool unboundedObserved = false;
    std::thread observer([&] {
        const auto before = CollectWrites(base + 7, 1);
        memory[7] = 19;
        const auto after = CollectWrites(base + 7, 1);
        unboundedObserved = before != 0 && after > before && !UnchangedSince(base + 7, 1, before);
    });
    observer.join();
    Require(unboundedObserved, "a thread without collect epochs reused a stale observation");
    for (const auto offset : {7u, 4096u + 3u, static_cast<unsigned>(Block - 8), static_cast<unsigned>(Block + 3)}) {
        BumpCollectEpoch();
        const auto before = CollectWrites(base + offset, 16);
        Require(before != 0, "an epoch lost watched coverage");
        memory[offset] ^= 1;
        BumpCollectEpoch();
        Require(CollectWrites(base + offset, 16) > before && !UnchangedSince(base + offset, 16, before), "a new epoch missed a CPU write");
        const auto observed = TrackerGeneration();
        memory[offset + 1] ^= 1;
        Require(CollectWritesUncached(base + offset, 16) > observed && !UnchangedSince(base + offset, 16, observed), "an uncached observation reused an epoch result");
        const auto stored = MarkWritten(base + offset + 2, 1);
        Require(CollectWrites(base + offset, 16) >= stored && !UnchangedSince(base + offset, 16, observed), "a memoized observation hid a driver write");
    }
#ifndef _WIN32
    BumpCollectEpoch();
    Require(CollectWrites(base, 1) != 0, "initial partial-block observation failed");
    Unwatch(base + 4096, 4096);
    Require(CollectWrites(base + 4096, 1) == 0, "an unwatched neighbor retained an epoch observation");
    BumpCollectEpoch();
    const auto before = CollectWrites(base, 16);
    Require(before != 0, "an unwatched neighbor prevented collecting a watched prefix");
    memory[0] ^= 1;
    BumpCollectEpoch();
    Require(CollectWrites(base, 16) > before && !UnchangedSince(base, 16, before), "partial-block collection missed a CPU write");
    GuestWriteWatch::GuestWriteWatchRegister_nid_postfix(memory + 4096, 4096);
    Require(CollectWrites(base + 4096, 1) != 0, "a re-registered neighbor stayed unwatched");
#endif
}
}

void CheckImportWindow() {
    void* memory = AllocateWatched(3 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    auto* bytes = static_cast<volatile std::uint8_t*>(memory);
    std::memset(memory, 0x11, 3 * Block);
    const auto synced = CollectWritesUncached(base, 3 * Block);
    Require(synced != 0, "the import window block is not collected");
    Require(ImportWatched(base, 3 * Block, [&] {
        bytes[0x100] = 0x11;
        bytes[Block + 0x2000] = 0x22;
        return true;
    }), "the import window import failed");
    Require(Watched(base, 3 * Block), "an import window left its range unwatched");
    const std::array<std::uint64_t, 3> generations{synced, synced, synced};
    std::array<std::uint8_t, 3> changed{};
    std::array<std::uint8_t, 3> cpu{};
    Require(ChangedBlocks(base, 3 * Block, generations, changed, cpu), "the import window block is not tracked");
    Require(changed[0] == BlockUnchanged && UnchangedSince(base, Block, synced), "a page an import window resolved without changing its bytes reads as written");
    Require(changed[1] == BlockWritten && WrittenSince(base + Block, Block, synced) && cpu[1] == 1, "a store of new bytes within an import window was missed");
    Require(changed[2] == BlockUnchanged && cpu[2] == 0, "a block the import window did not touch reads as written");
    Require(cpu[0] == 1, "a page an import window resolved no longer counts as possibly touched by the CPU");
    const auto after = CollectWritesUncached(base, 3 * Block);
    bytes[0x100] = 0x33;
    static_cast<void>(CollectWritesUncached(base, 3 * Block));
    Require(!UnchangedSince(base, Block, after), "a store after the import window was missed");
}

void ProtectPage(std::uint64_t address, bool readable) {
#ifdef _WIN32
    DWORD previous = 0;
    Require(VirtualProtect(reinterpret_cast<void*>(address), 4096, readable ? PAGE_READWRITE : PAGE_NOACCESS, &previous) != 0, "cannot change the protection of a test page");
#else
    Require(mprotect(reinterpret_cast<void*>(address), 4096, readable ? PROT_READ | PROT_WRITE : PROT_NONE) == 0, "cannot change the protection of a test page");
#endif
    GuestAllocations::GuestAllocationsInvalidate_nid_postfix(static_cast<std::uintptr_t>(address), 4096);
}

void CheckUnwatchedImport() {
    void* memory = AllocateWatched(3 * Block);
    const auto base = reinterpret_cast<std::uint64_t>(memory);
    auto* bytes = static_cast<volatile std::uint8_t*>(memory);
    std::memset(memory, 0x11, 3 * Block);
    const auto synced = CollectWritesUncached(base, 3 * Block);
    Require(synced != 0, "the unwatched import block is not collected");
    const auto imported = base + Block / 2;
    const std::size_t importedBytes = Block + Block / 2;
    const auto unreadable = base + Block + 0x3000;
    ProtectPage(unreadable, false);
    bool threw = false;
    bool ran = false;
    try {
        static_cast<void>(ImportWatched(imported, importedBytes, [&] {
            ran = true;
            return true;
        }));
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw && !ran, "an import that stays watched did not read its range before the import");
    threw = false;
    try {
        Require(ImportWatched(imported, importedBytes, [&] {
            bytes[Block / 2 + 0x100] = 0x22;
            ran = true;
            return true;
        }, false), "an import that leaves the watch failed");
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(!threw && ran, "an import that leaves the watch read its range");
    ProtectPage(unreadable, true);
    Require(!Watched(imported, importedBytes) && !Watched(imported, 4096) && !Watched(base + Block, Block), "an import that leaves the watch is still watched");
    Require(Watched(base + 2 * Block, Block), "an import that leaves the watch unwatched a block outside its range");
    Require(UnchangedSince(base + 2 * Block, Block, synced), "an import that leaves the watch stamped a block outside its range");
#ifndef _WIN32
    Require(Watched(base, Block / 2), "an import that leaves the watch unwatched the pages before its range");
    const std::array<std::uint64_t, 1> generations{synced};
    std::array<std::uint8_t, 1> changed{};
    std::array<std::uint8_t, 1> cpu{};
    Require(ChangedBlocks(base, Block / 2, generations, changed, cpu), "the pages before an import that leaves the watch are not tracked");
    Require(changed[0] == BlockUnchanged && UnchangedSince(base, Block / 2, synced) && !WrittenSince(base, Block / 2, synced), "a store to a page that left the watch reads as a store to the watched pages of its block");
    Require(cpu[0] == 1, "a page resolved while an import left the watch no longer counts as possibly touched by the CPU");
    const auto after = CollectWritesUncached(base, Block / 2);
    bytes[0x100] = 0x33;
    static_cast<void>(CollectWritesUncached(base, Block / 2));
    Require(after != 0 && !UnchangedSince(base, Block / 2, after), "a store beside an import that left the watch was missed");
#endif
}

int main() {
    try {
        if (!WriteWatched()) {
            std::cout << "no write watching: skipped\n";
            return 77;
        }
#ifdef _WIN32
        if (std::wstring_view(GetCommandLineW()).ends_with(HostHoleMode)) {
            CheckHostHole();
            return 0;
        }
#endif
        CheckSharedBlock();
        CheckOwnStore();
        CheckUnwatch();
        CheckNewestStamp();
#ifdef _WIN32
        CheckDeferredSharedImports();
        CheckPrivateMappingReuse();
        CheckHostHoleInChild();
#endif
        CheckVersionRanges();
        CheckCollectBoundaries();
        CheckImportWindow();
        CheckUnwatchedImport();
    } catch (const std::exception& error) {
        std::cerr << "write tracking test failed: " << error.what() << "\n";
        return 1;
    }
    std::cout << "write tracking tests passed\n";
    return 0;
}
