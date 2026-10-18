#define NOMINMAX
#include "prx/libc/include/WindowsMappings.hpp"
#include <array>
#include <atomic>
#include <iostream>
#include <set>
#include <thread>

namespace {
using Mappings = GuestArena::WindowsMappings;
using Collection = Mappings::Collection;
constexpr std::size_t Small = 4096;
constexpr std::size_t Bytes = 65536;
std::atomic<unsigned> faults{0};

void Require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

LONG CALLBACK HandleWrite(EXCEPTION_POINTERS* exception) {
    const auto* record = exception->ExceptionRecord;
    if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || record->NumberParameters < 2 || record->ExceptionInformation[0] != 1) return EXCEPTION_CONTINUE_SEARCH;
    if (!Mappings::Get().HandleWrite(record->ExceptionInformation[1])) return EXCEPTION_CONTINUE_SEARCH;
    ++faults;
    return EXCEPTION_CONTINUE_EXECUTION;
}

struct Region {
    HANDLE section = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_EXECUTE_READWRITE | SEC_RESERVE, 0, Bytes, nullptr);
    unsigned char* first = static_cast<unsigned char*>(Mappings::Get().Reserve(nullptr, Bytes));
    unsigned char* alias = static_cast<unsigned char*>(Mappings::Get().Reserve(nullptr, Bytes));

    Region() {
        Require(section && first && alias, "cannot allocate shared test memory");
        Mappings::Get().Map(first, Bytes, section, 0, PAGE_READWRITE);
        Mappings::Get().Map(alias, Bytes, section, 0, PAGE_READWRITE);
    }
    ~Region() {
        Mappings::Get().Reset(first, Bytes);
        Mappings::Get().Reset(alias, Bytes);
        VirtualFree(first, 0, MEM_RELEASE);
        VirtualFree(alias, 0, MEM_RELEASE);
        CloseHandle(section);
    }
    void Write(std::size_t page, unsigned char value) {
        static_cast<volatile unsigned char*>(first)[page * Small] = value;
    }
    std::set<std::size_t> Collect(Collection mode, std::size_t begin = 0, std::size_t count = 16, bool clear = true, bool useAlias = false, std::size_t capacity = 32) {
        auto* base = useAlias ? alias : first;
        const auto address = reinterpret_cast<std::uintptr_t>(base);
        auto cursor = address + begin * Small;
        const auto end = cursor + count * Small;
        std::set<std::size_t> result;
        while (cursor < end) {
            std::array<void*, 32> pages{};
            auto available = capacity;
            Require(Mappings::Get().Collect(cursor, end - cursor, pages.data(), &available, clear, mode), "shared collection failed");
            for (std::size_t i = 0; i < available; ++i) result.insert((reinterpret_cast<std::uintptr_t>(pages[i]) - address) / Small);
            if (available < capacity) break;
            cursor = reinterpret_cast<std::uintptr_t>(pages[available - 1]) + Small;
        }
        return result;
    }
    DWORD Protection(std::size_t page, bool useAlias = false) {
        MEMORY_BASIC_INFORMATION info{};
        Require(VirtualQuery((useAlias ? alias : first) + page * Small, &info, sizeof(info)) == sizeof(info), "protection query failed");
        return info.Protect;
    }
};

std::set<std::size_t> Pages(std::size_t begin, std::size_t end) {
    std::set<std::size_t> result;
    for (auto page = begin; page < end; ++page) result.insert(page);
    return result;
}

void CheckArmed() {
    Region region;
    Require(region.Collect(Collection::Armed).empty(), "import collected fresh memory");
    const auto before = faults.load();
    region.Write(0, 1);
    region.Write(4, 2);
    Require(faults == before, "import armed fresh memory");
    Require(region.Collect(Collection::All, 0, 1) == Pages(0, 1), "first partial collect failed");
    Require(region.Protection(0) == PAGE_READONLY && region.Protection(3) == PAGE_READWRITE, "partial collect did not protect only its page");
    region.Write(0, 3);
    region.Write(4, 4);
    Require(region.Collect(Collection::Armed) == Pages(0, 1), "armed collect lost a write or consumed fresh pages");
    Require(region.Protection(4) == PAGE_READWRITE, "armed collect protected another fresh view");
    Require(region.Collect(Collection::All) == Pages(1, 16), "ordinary collect lost fresh pages");
    Require(region.Collect(Collection::All).empty(), "cleared memory reports writes");
}

void CheckFresh() {
    Region region;
    Require(region.Collect(Collection::All, 0, 1) == Pages(0, 1), "cannot collect initial page");
    region.Write(0, 7);
    Require(region.Collect(Collection::Fresh) == Pages(1, 16), "fresh collect consumed an existing dirty page");
    Require(region.Collect(Collection::Fresh).empty(), "fresh collect repeated initial writes");
    Require(region.Collect(Collection::Armed) == Pages(0, 1), "fresh collect cleared an existing write");
    region.Write(9, 9);
    Require(region.Collect(Collection::Armed) == Pages(9, 10), "write after activation was missed");
}

void CheckAliasesAndCapacity() {
    Region region;
    Require(region.Collect(Collection::All, 0, 1) == Pages(0, 1), "initial collect failed");
    Require(region.Protection(0, true) == PAGE_READONLY, "alias was not protected");
    Require(region.Collect(Collection::Armed, 0, 16, true, true).empty(), "alias protection was mistaken for collection history");
    Require(region.Collect(Collection::Fresh, 0, 16, true, true, 1) == Pages(0, 16), "small output buffers lost fresh pages");
    Require(region.Collect(Collection::Fresh, 0, 16, true, true).empty(), "small output buffers did not finish fresh collection");
    static_cast<volatile unsigned char*>(region.alias)[0] = 8;
    Require(region.Collect(Collection::Armed) == Pages(0, 1), "alias write was missed or fresh neighbors were consumed");
    Require(region.Collect(Collection::Fresh) == Pages(1, 16), "alias collection changed another view's history");
    Mappings::Get().Reset(region.first, Bytes);
    Mappings::Get().Map(region.first, Bytes, region.section, 0, PAGE_READWRITE);
    Require(region.Collect(Collection::Armed).empty(), "remapped address kept old collection history");
    Require(region.Collect(Collection::Fresh) == Pages(0, 16), "remapped memory was not fresh");
}

void CheckPinsAndHostWrites() {
    Region region;
    const auto address = reinterpret_cast<std::uintptr_t>(region.first);
    Mappings::Get().Pin(address, 16384);
    Require(region.Collect(Collection::Fresh) == Pages(0, 16), "pinned fresh collection failed");
    Require(region.Protection(0) == PAGE_READWRITE, "pinned page was protected");
    Require(region.Collect(Collection::Armed) == Pages(0, 4), "pinned writes were trusted as clean");
    Mappings::Get().Unpin(address, 16384);
    Require(region.Collect(Collection::Armed) == Pages(0, 4), "unpin was not invalidated");
    Require(region.Collect(Collection::Armed).empty(), "unpin did not restore tracking");
    Require(Mappings::Get().BeginHostWrite(address, 16384), "host write refused");
    region.Write(0, 3);
    region.Collect(Collection::Armed);
    region.Write(0, 4);
    Mappings::Get().EndHostWrite(address, 16384);
    Require(region.Collect(Collection::Armed) == Pages(0, 4), "host write completion was missed");
    Require(region.Collect(Collection::Armed).empty(), "completed host write stayed dirty");
}

void CheckFailureAndHoles() {
    Region region;
    const auto address = reinterpret_cast<std::uintptr_t>(region.first);
    DWORD previous;
    Mappings::Get().SetProtection(address + 16384, 16384, PAGE_NOACCESS);
    Require(VirtualProtect(region.first + 16384, 16384, PAGE_NOACCESS, &previous), "cannot protect test page");
    std::array<void*, 32> pages{};
    auto count = pages.size();
    Require(!Mappings::Get().Collect(address, Bytes, pages.data(), &count, true, Collection::Fresh), "fresh inaccessible page accepted");
    Require(region.Protection(0) == PAGE_READWRITE, "failed collect changed an earlier page");
    Mappings::Get().SetProtection(address + 16384, 16384, PAGE_READWRITE);
    Require(VirtualProtect(region.first + 16384, 16384, PAGE_READWRITE, &previous), "cannot restore test page");
    Mappings::Get().Reset(region.first + 16384, 16384);
    Require(region.Collect(Collection::Fresh) == std::set<std::size_t>({0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15}), "fresh collection did not tolerate an unmapped block neighbor");
    Require(region.Collect(Collection::Fresh).empty(), "holes caused fresh pages to repeat");
}

void CheckPrivate() {
    auto& mappings = Mappings::Get();
    auto* memory = static_cast<unsigned char*>(mappings.Reserve(nullptr, Bytes));
    Require(memory != nullptr, "private reservation failed");
    mappings.Commit(memory, Bytes, PAGE_READWRITE, Bytes, true);
    const auto address = reinterpret_cast<std::uintptr_t>(memory);
    std::array<void*, 32> pages{};
    std::size_t count = pages.size();
    mappings.Collect(address, Bytes, pages.data(), &count, true);
    static_cast<volatile unsigned char*>(memory)[Small] = 3;
    count = pages.size();
    Require(mappings.Collect(address, Bytes, pages.data(), &count, true, Collection::Fresh) && count == 0, "fresh collect touched private memory");
    count = pages.size();
    Require(mappings.Collect(address, Bytes, pages.data(), &count, true, Collection::Armed) && count == 1 && pages[0] == memory + Small, "private write watch changed");
    mappings.Reset(memory, Bytes);
    VirtualFree(memory, 0, MEM_RELEASE);
}

void CheckForgottenSectionKeepsNoPages() {
    auto& mappings = Mappings::Get();
    HANDLE section = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_EXECUTE_READWRITE | SEC_RESERVE, 0, Bytes, nullptr);
    auto* first = static_cast<unsigned char*>(mappings.Reserve(nullptr, Bytes));
    auto* second = static_cast<unsigned char*>(mappings.Reserve(nullptr, Bytes));
    Require(section && first && second, "cannot allocate forgotten section test memory");
    const auto resident = [&](unsigned char* address) {
        MEMORY_BASIC_INFORMATION info{};
        Require(VirtualQuery(address, &info, sizeof(info)) == sizeof(info), "resident query failed");
        return info.State == MEM_COMMIT && info.Type == MEM_PRIVATE;
    };
    mappings.Map(first, Bytes, section, 0, PAGE_READWRITE, true, true);
    mappings.Map(second, Bytes, section, 0, PAGE_READWRITE, true, true);
    Require(!resident(first) && !resident(second), "a second mapping kept the first resident");
    mappings.ForgetSection(section);
    mappings.Reset(first, Bytes);
    mappings.Reset(second, Bytes);
    mappings.Map(first, Bytes, section, 0, PAGE_READWRITE, true, true);
    Require(resident(first), "a forgotten section's handle value kept its pages in the section");
    first[0] = 7;
    mappings.ForgetSection(section);
    mappings.Reset(first, Bytes);
    mappings.Map(first, Bytes, section, 0, PAGE_READWRITE, true, true);
    Require(resident(first) && first[0] == 0, "a forgotten section's handle value kept its unmapped bytes");
    mappings.Reset(first, Bytes);
    VirtualFree(first, 0, MEM_RELEASE);
    VirtualFree(second, 0, MEM_RELEASE);
    CloseHandle(section);
}

void CheckConcurrentWrites() {
    Region region;
    std::atomic<bool> start{false};
    std::thread writer([&] {
        while (!start.load(std::memory_order_acquire)) std::this_thread::yield();
        for (std::size_t page = 0; page < 16; ++page) region.Write(page, static_cast<unsigned char>(page + 1));
    });
    start.store(true, std::memory_order_release);
    region.Collect(Collection::Fresh);
    writer.join();
    for (std::size_t page = 0; page < 16; ++page) Require(region.first[page * Small] == page + 1, "activation lost a concurrent write");
    region.Collect(Collection::Armed);
    Require(region.Collect(Collection::Armed).empty(), "concurrent writes did not settle");
}
}

int main() {
    auto* handler = AddVectoredExceptionHandler(1, HandleWrite);
    try {
        Require(handler != nullptr, "cannot install test handler");
        CheckArmed();
        CheckFresh();
        CheckAliasesAndCapacity();
        CheckPinsAndHostWrites();
        CheckFailureAndHoles();
        CheckPrivate();
        CheckConcurrentWrites();
        CheckForgottenSectionKeepsNoPages();
        std::cout << "Windows deferred write-watch tests passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    RemoveVectoredExceptionHandler(handler);
}
