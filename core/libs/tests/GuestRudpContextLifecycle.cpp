#include "SceTypes.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
using GuestRudpEventHandler = void(APS5_VABI*)(int, int, int, void*);
int APS5_VABI sceRudpInit_nid_postfix(void*, int);
int APS5_VABI sceRudpEnd();
int APS5_VABI sceRudpActivate();
int APS5_VABI sceRudpEnableInternalIOThread(std::uint32_t, std::uint32_t);
int APS5_VABI sceRudpSetEventHandler(GuestRudpEventHandler, void*);
int APS5_VABI sceRudpCreateContext(GuestRudpEventHandler, void*, int*);
int APS5_VABI sceRudpBind(int, std::uint16_t, int, std::uint16_t);
int APS5_VABI sceRudpSetOption(int, int, const void*, std::uint32_t);
int APS5_VABI sceRudpInitiate(int, const void*, std::uint32_t, std::uint16_t);
int APS5_VABI sceRudpGetContextStatus(int, void*, std::uint32_t);
int APS5_VABI sceRudpWrite(int, const void*, std::uint32_t, int);
int APS5_VABI sceRudpRead(int, void*, std::uint32_t, int, void*);
int APS5_VABI sceRudpTerminate(int);
}

static void Require(bool value) { if (!value) std::abort(); }

static void APS5_VABI Handler(int, int, int, void*) {}

int main() {
    constexpr int notInitialized = static_cast<int>(0x80770001u);
    constexpr int invalidContextId = static_cast<int>(0x80770003u);
    constexpr int connRefused = static_cast<int>(0x8077000Au);
    constexpr int connReset = static_cast<int>(0x80770009u);
    alignas(16) static unsigned char pool[0x10000];

    Require(sceRudpActivate() == 0);

    Require(sceRudpEnableInternalIOThread(0, 0) == notInitialized);

    Require(sceRudpSetEventHandler(Handler, nullptr) == 0);

    Require(sceRudpBind(0, 0, 0, 0) == notInitialized);
    Require(sceRudpBind(12345, 0, 0, 0) == notInitialized);

    Require(sceRudpSetOption(0, 0, nullptr, 0) == notInitialized);
    Require(sceRudpSetOption(12345, 0, nullptr, 0) == notInitialized);

    Require(sceRudpInitiate(0, nullptr, 0, 0) == notInitialized);
    Require(sceRudpInitiate(12345, nullptr, 0, 0) == notInitialized);

    {
        unsigned char status[64] = {};
        Require(sceRudpGetContextStatus(0, status, sizeof(status)) == notInitialized);
        Require(sceRudpGetContextStatus(12345, status, sizeof(status)) == notInitialized);
    }

    Require(sceRudpWrite(0, nullptr, 0, 0) == notInitialized);
    Require(sceRudpWrite(12345, nullptr, 0, 0) == notInitialized);

    Require(sceRudpRead(0, nullptr, 0, 0, nullptr) == notInitialized);
    Require(sceRudpRead(12345, nullptr, 0, 0, nullptr) == notInitialized);

    Require(sceRudpInit_nid_postfix(pool, sizeof(pool)) == 0);

    Require(sceRudpActivate() == 0);

    Require(sceRudpEnableInternalIOThread(0, 0) == 0);
    Require(sceRudpEnableInternalIOThread(1024, 1) == 0);

    Require(sceRudpBind(12345, 0, 0, 0) == invalidContextId);

    Require(sceRudpSetOption(12345, 0, nullptr, 0) == invalidContextId);

    Require(sceRudpInitiate(12345, nullptr, 0, 0) == invalidContextId);

    {
        unsigned char status[64] = {};
        Require(sceRudpGetContextStatus(12345, status, sizeof(status)) == invalidContextId);
    }

    Require(sceRudpWrite(12345, nullptr, 0, 0) == invalidContextId);

    Require(sceRudpRead(12345, nullptr, 0, 0, nullptr) == invalidContextId);

    int ctx = -1;
    Require(sceRudpCreateContext(Handler, nullptr, &ctx) == 0);
    Require(ctx >= 0);

    Require(sceRudpBind(ctx, 0, 0, 0) == 0);

    Require(sceRudpSetOption(ctx, 0, nullptr, 0) == 0);

    Require(sceRudpInitiate(ctx, nullptr, 0, 0) == connRefused);

    {
        unsigned char status[64];
        std::memset(status, 0x5a, sizeof(status));
        Require(sceRudpGetContextStatus(ctx, status, sizeof(status)) == 0);
        for (std::size_t i = 0; i < sizeof(status); ++i) Require(status[i] == 0);
    }
    Require(sceRudpGetContextStatus(ctx, nullptr, 64) == 0);

    Require(sceRudpWrite(ctx, nullptr, 0, 0) == connReset);

    Require(sceRudpRead(ctx, nullptr, 0, 0, nullptr) == connReset);

    Require(sceRudpSetEventHandler(Handler, nullptr) == 0);

    Require(sceRudpTerminate(ctx) == 0);
    Require(sceRudpEnd() == 0);
    return 0;
}