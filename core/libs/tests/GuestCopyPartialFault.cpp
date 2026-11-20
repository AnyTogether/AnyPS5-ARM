#include "prx/libc/include/General.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/mman.h>
#include <unistd.h>

// A checked guest copy that crosses from a readable page into one it may not use stops there:
// GuestCopyIn and GuestCopyOut answer false, and no byte past the faulting page boundary changes,
// in the destination of a copy-in or in the protected page of a copy-out. Bytes before the boundary
// may or may not have been copied (the fault-recovering copy stops at the fault, the kernel calls
// copy nothing). Run with and without APS5_GUEST_COPY_SYSCALL.

static void Check(bool value, int line) {
    if (!value) {
        std::fprintf(stderr, "guest copy partial fault check failed at line %d\n", line);
        std::abort();
    }
}
#define Require(value) Check((value), __LINE__)

namespace {

constexpr unsigned char Pattern = 0x5a;
constexpr unsigned char Untouched = 0xcd;
constexpr unsigned char Written = 0x3c;

// The page the protections are set on. Under Rosetta a process sees 4 KiB pages on a 16 KiB-page
// kernel, so a protection change takes effect on whole 16 KiB pages there.
std::size_t ProtectionPage() {
    const auto page = static_cast<std::size_t>(sysconf(_SC_PAGESIZE));
#if defined(__APPLE__)
    return page < 16384 ? 16384 : page;
#else
    return page;
#endif
}

struct Pages {
    explicit Pages(std::size_t page) : page(page) {
        // Four pages' worth, so three aligned ones fit whatever the mapping's alignment.
        mapping = mmap(nullptr, page * 4, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        Require(mapping != MAP_FAILED);
        const auto address = reinterpret_cast<std::uintptr_t>(mapping);
        base = reinterpret_cast<unsigned char*>((address + page - 1) / page * page);
        std::memset(base, Pattern, page * 3);
        // [base, +page) readable and writable, then a page without access, then a read-only one.
        Require(mprotect(base + page, page, PROT_NONE) == 0);
        Require(mprotect(base + page * 2, page, PROT_READ) == 0);
    }
    ~Pages() { munmap(mapping, page * 4); }
    unsigned char* Boundary() const { return base + page; }
    unsigned char* ReadOnly() const { return base + page * 2; }

    std::size_t page;
    void* mapping = nullptr;
    unsigned char* base = nullptr;
};

void CopyInStopsAtTheFault(const Pages& pages) {
    for (const std::size_t before : {std::size_t{1}, std::size_t{8}, std::size_t{4093}}) {
        std::array<unsigned char, 8192> destination{};
        destination.fill(Untouched);
        const std::size_t bytes = before + 512;
        Require(!GuestCopyIn_nid_no_patch(destination.data(), pages.Boundary() - before, bytes));
        // Nothing past the fault: the destination bytes that map to the page without access, and
        // everything after the copy, keep their value.
        for (std::size_t index = before; index < destination.size(); ++index) Require(destination[index] == Untouched);
        // Before it, either the source's bytes (copied up to the fault) or none.
        const bool copied = destination[0] == Pattern;
        for (std::size_t index = 0; index < before; ++index) Require(destination[index] == (copied ? Pattern : Untouched));
    }
}

void CopyOutStopsAtTheFault(const Pages& pages) {
    std::array<unsigned char, 1024> source{};
    source.fill(Written);
    // Into the page without access.
    Require(!GuestCopyOut_nid_no_patch(pages.Boundary() - 8, source.data(), 64));
    // Into the read-only page.
    Require(!GuestCopyOut_nid_no_patch(pages.ReadOnly(), source.data(), source.size()));
    Require(mprotect(pages.Boundary(), pages.page * 2, PROT_READ) == 0);
    for (std::size_t index = 0; index < pages.page * 2; ++index) Require(pages.Boundary()[index] == Pattern);
    // The writable page's bytes before the boundary may have been written up to the fault.
    for (std::size_t index = 0; index < 8; ++index) {
        const auto value = (pages.Boundary() - 8)[index];
        Require(value == Pattern || value == Written);
    }
    Require(mprotect(pages.Boundary(), pages.page, PROT_NONE) == 0);
}

void WholeCopiesStillWork(const Pages& pages) {
    std::array<unsigned char, 256> buffer{};
    Require(GuestCopyIn_nid_no_patch(buffer.data(), pages.ReadOnly(), buffer.size()));
    for (const auto value : buffer) Require(value == Pattern);
    buffer.fill(Written);
    Require(GuestCopyOut_nid_no_patch(pages.base, buffer.data(), buffer.size()));
    for (std::size_t index = 0; index < buffer.size(); ++index) Require(pages.base[index] == Written);
    Require(GuestCopyIn_nid_no_patch(buffer.data(), pages.base, 0));
}

}

int main() {
    const Pages pages(ProtectionPage());
    CopyInStopsAtTheFault(pages);
    CopyOutStopsAtTheFault(pages);
    WholeCopiesStillWork(pages);
    // Many in a row: the resume leaves the copy usable for the next one.
    for (int round = 0; round < 1000; ++round) {
        unsigned char byte = Untouched;
        Require(!GuestCopyIn_nid_no_patch(&byte, pages.Boundary(), 1));
        Require(byte == Untouched);
    }
    std::puts("guest copy partial fault tests passed");
    return 0;
}
