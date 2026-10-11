#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <exception>

extern "C" {
int APS5_VABI sceSharePlayInitialize(void*, std::size_t);
int APS5_VABI sceSharePlayTerminate(void);
int APS5_VABI sceSharePlayGetCurrentConnectionInfoA(SharePlayConnectionInfoA*);
}

static void Require(bool value) { if (!value) std::abort(); }

template <typename TCall>
static bool Throws(TCall call) {
    try {
        call();
    } catch (const std::exception&) {
        return true;
    }
    return false;
}

int main() {
    alignas(16) static unsigned char heap[0x1800];
    Require(sceSharePlayInitialize(nullptr, sizeof(heap)) == 0);
    Require(sceSharePlayTerminate() == 0);
    Require(sceSharePlayInitialize(heap, sizeof(heap)) == 0);
    Require(sceSharePlayTerminate() == 0);
    Require(Throws([&] { sceSharePlayInitialize(heap, 0); }));
    Require(Throws([&] { sceSharePlayInitialize(nullptr, 0); }));
    SharePlayConnectionInfoA info;
    std::memset(&info, 0x5a, sizeof(info));
    Require(sceSharePlayGetCurrentConnectionInfoA(&info) == 0);
    Require(info.status == 0 && info.mode == 0 && info.hostAccountId == 0 && info.visitorAccountId == 0);
    Require(info.hostOnlineId.data[0] == 0 && info.visitorOnlineId.data[0] == 0 && info.hostOnlineId.pad[2] == 0);
    Require(info.hostUserId == -1 && info.visitorUserId == -1);
    Require(sceSharePlayGetCurrentConnectionInfoA(nullptr) == static_cast<int>(0x810E0001));
}
