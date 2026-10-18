#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <thread>

struct GuestTlsDescriptor {
    std::uint64_t version;
    std::uint64_t templateAddress;
    std::uint64_t templateSize;
    std::uint64_t blockSize;
    std::uint64_t alignment;
    std::uint64_t key;
};

struct TlsIndex {
    const GuestTlsDescriptor* module;
    std::uint64_t offset;
};

extern "C" {
void Aps5GuestTlsRegister_nid_no_patch(GuestTlsDescriptor* descriptor);
void* APS5_VABI __tls_get_addr_nid_postfix(void* index);
}

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    static const char initial[8] = {'g', 'u', 'e', 's', 't', 't', 'l', 's'};
    GuestTlsDescriptor descriptor{1, reinterpret_cast<std::uint64_t>(initial), sizeof(initial), 32, 16, 0};
    Aps5GuestTlsRegister_nid_no_patch(&descriptor);
    TlsIndex first{&descriptor, 0};
    TlsIndex fifth{&descriptor, 4};
    TlsIndex zeroed{&descriptor, 16};
    auto* block = static_cast<char*>(__tls_get_addr_nid_postfix(&first));
    Require(std::memcmp(block, initial, sizeof(initial)) == 0);
    Require(static_cast<char*>(__tls_get_addr_nid_postfix(&fifth)) == block + 4);
    Require(*static_cast<std::uint64_t*>(__tls_get_addr_nid_postfix(&zeroed)) == 0);
    block[0] = 'G';
    Require(static_cast<char*>(__tls_get_addr_nid_postfix(&first))[0] == 'G');
    char* other = nullptr;
    std::thread([&] { other = static_cast<char*>(__tls_get_addr_nid_postfix(&first)); Require(other[0] == 'g'); }).join();
    Require(other != block);
}
