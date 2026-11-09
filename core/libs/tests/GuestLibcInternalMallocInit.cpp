#include "prx/libSceLibcInternal/include/InventoryExports.hpp"
#include "prx/libc/include/GuestHeap.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

void Require(bool condition, const char* message) {
    if (condition) return;
    std::fprintf(stderr, "_malloc_init: %s\n", message);
    std::abort();
}

void CheckHeapAllocates() {
    void* block = GuestHeap::GuestHeapAllocate_nid_postfix(64);
    Require(block != nullptr, "the guest heap did not allocate after initialization");
    Require(GuestHeap::GuestHeapUsableSize_nid_postfix(block) == 64, "the guest heap reports a wrong usable size");
    std::memset(block, 0x5a, 64);
    GuestHeap::GuestHeapFree_nid_postfix(block);
}

}

int main() {
    Require(_malloc_init_nid_no_patch() == 0, "first call did not report a usable heap");
    CheckHeapAllocates();
    Require(_malloc_init_nid_no_patch() == 0, "repeated call did not report a usable heap");
    CheckHeapAllocates();
    return 0;
}
