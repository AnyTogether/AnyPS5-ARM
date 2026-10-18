#include "SceTypes.hpp"

#include <array>
#include <cstdlib>

extern "C" {
using GuestRudpEventHandler = void(APS5_VABI*)(int, int, int, void*);
int APS5_VABI sceRudpInit_nid_postfix(void*, int);
int APS5_VABI sceRudpCreateContext(GuestRudpEventHandler, void*, int*);
int APS5_VABI sceRudpTerminate(int);
int APS5_VABI sceRudpEnd();
int APS5_VABI sceRudpGetNumberOfPacketsToRead(int);
int APS5_VABI sceRudpGetSizeWritable(int);
int APS5_VABI sceRudpGetSizeReadable(int);
}

static void Require(bool value) {
    if (!value) std::abort();
}

static void APS5_VABI Handler(int, int, int, void*) {}

int main() {
    constexpr int notInitialized = static_cast<int>(0x80770001u);
    constexpr int invalidContext = static_cast<int>(0x80770003u);
    constexpr int invalidArgument = static_cast<int>(0x80770004u);
    constexpr int notAcceptable = static_cast<int>(0x80770011u);
    alignas(16) static std::array<unsigned char, 0x10000> pool{};

    Require(sceRudpGetNumberOfPacketsToRead(0) == notInitialized);
    Require(sceRudpGetSizeWritable(0) == notInitialized);
    Require(sceRudpGetSizeReadable(0) == notInitialized);
    Require(sceRudpInit_nid_postfix(pool.data(), static_cast<int>(pool.size())) == 0);
    Require(sceRudpGetNumberOfPacketsToRead(0) == invalidContext);
    Require(sceRudpGetSizeWritable(0) == invalidContext);
    Require(sceRudpGetSizeReadable(0) == invalidContext);
    Require(sceRudpGetNumberOfPacketsToRead(12345) == invalidContext);
    Require(sceRudpGetSizeWritable(12345) == invalidContext);
    Require(sceRudpGetSizeReadable(12345) == invalidContext);
    Require(sceRudpGetNumberOfPacketsToRead(-1) == invalidArgument);
    Require(sceRudpGetSizeWritable(-1) == invalidArgument);
    Require(sceRudpGetSizeReadable(-1) == invalidArgument);

    int context = -1;
    Require(sceRudpCreateContext(Handler, nullptr, &context) == 0);
    Require(sceRudpGetNumberOfPacketsToRead(context) == 0);
    Require(sceRudpGetSizeWritable(context) == notAcceptable);
    Require(sceRudpGetSizeReadable(context) == notAcceptable);
    Require(sceRudpTerminate(context) == 0);
    Require(sceRudpGetNumberOfPacketsToRead(context) == invalidContext);
    Require(sceRudpGetSizeWritable(context) == invalidContext);
    Require(sceRudpGetSizeReadable(context) == invalidContext);
    Require(sceRudpEnd() == 0);
    return 0;
}
