#include "SceTypes.hpp"

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <thread>

extern "C" {
using GuestRudpEventHandler = void(APS5_VABI*)(int, int, int, void*);
struct GuestRudpPollEvent {
    int ctxId;
    std::uint16_t reqEvents;
    std::uint16_t rtnEvents;
};
int APS5_VABI sceRudpInit_nid_postfix(void*, int);
int APS5_VABI sceRudpCreateContext(GuestRudpEventHandler, void*, int*);
int APS5_VABI sceRudpTerminate(int);
int APS5_VABI sceRudpEnd();
int APS5_VABI sceRudpPollCreate(std::size_t);
int APS5_VABI sceRudpPollControl(int, int, int, std::uint16_t);
int APS5_VABI sceRudpPollWait(int, GuestRudpPollEvent*, std::size_t, std::uint64_t);
int APS5_VABI sceRudpPollDestroy(int);
}

static void Require(bool value) {
    if (!value) std::abort();
}

static void APS5_VABI Handler(int, int, int, void*) {}

int main() {
    constexpr int notInitialized = static_cast<int>(0x80770001u);
    constexpr int invalidContext = static_cast<int>(0x80770003u);
    constexpr int invalidArgument = static_cast<int>(0x80770004u);
    constexpr int invalidPoll = static_cast<int>(0x8077001Fu);
    constexpr int tooManyContexts = static_cast<int>(0x80770020u);
    constexpr int add = 1;
    constexpr int modify = 2;
    constexpr int remove = 3;
    constexpr std::uint16_t read = 0x0001;
    constexpr std::uint16_t write = 0x0002;
    constexpr std::uint64_t forever = std::numeric_limits<std::uint64_t>::max();
    alignas(16) static std::array<unsigned char, 0x10000> pool{};
    std::array<GuestRudpPollEvent, 4> events{};
    const auto eventCount = static_cast<std::uint32_t>(events.size());

    Require(sceRudpPollCreate(1) == notInitialized);
    Require(sceRudpPollControl(1, add, 0, read) == notInitialized);
    Require(sceRudpPollWait(1, events.data(), eventCount, 0) == notInitialized);
    Require(sceRudpPollDestroy(1) == notInitialized);
    Require(sceRudpInit_nid_postfix(pool.data(), static_cast<int>(pool.size())) == 0);

    Require(sceRudpPollCreate(0) == invalidArgument);
    const int poll = sceRudpPollCreate(1);
    Require(poll > 0);
    const int other = sceRudpPollCreate(2);
    Require(other > 0 && other != poll);

    int first = -1;
    int second = -1;
    Require(sceRudpCreateContext(Handler, nullptr, &first) == 0);
    Require(sceRudpCreateContext(Handler, nullptr, &second) == 0);

    Require(sceRudpPollControl(poll, 0, first, read) == invalidArgument);
    Require(sceRudpPollControl(poll, 4, first, read) == invalidArgument);
    Require(sceRudpPollControl(-1, add, first, read) == invalidArgument);
    Require(sceRudpPollControl(poll, add, -1, read) == invalidArgument);
    Require(sceRudpPollControl(12345, add, first, read) == invalidPoll);
    Require(sceRudpPollControl(poll, add, 12345, read) == invalidContext);
    Require(sceRudpPollControl(poll, modify, first, read) == invalidContext);
    Require(sceRudpPollControl(poll, remove, first, read) == invalidContext);

    Require(sceRudpPollControl(poll, add, first, read) == 0);
    Require(sceRudpPollControl(poll, add, first, read) == tooManyContexts);
    Require(sceRudpPollControl(poll, add, second, read) == tooManyContexts);
    Require(sceRudpPollControl(other, add, first, read) == 0);
    Require(sceRudpPollControl(other, add, first, read) == invalidContext);
    Require(sceRudpPollControl(poll, modify, first, read | write) == 0);
    Require(sceRudpPollControl(poll, remove, first, 0) == 0);
    Require(sceRudpPollControl(poll, remove, first, 0) == invalidContext);
    Require(sceRudpPollControl(poll, add, second, write) == 0);

    Require(sceRudpPollWait(-1, events.data(), eventCount, 0) == invalidArgument);
    Require(sceRudpPollWait(poll, nullptr, eventCount, 0) == invalidArgument);
    Require(sceRudpPollWait(poll, events.data(), 0, 0) == invalidArgument);
    Require(sceRudpPollWait(12345, events.data(), eventCount, 0) == invalidPoll);
    Require(sceRudpPollWait(poll, events.data(), eventCount, 0) == 0);
    const auto start = std::chrono::steady_clock::now();
    Require(sceRudpPollWait(poll, events.data(), eventCount, 20000) == 0);
    Require(std::chrono::steady_clock::now() - start >= std::chrono::milliseconds(20));

    Require(sceRudpTerminate(second) == 0);
    Require(sceRudpPollControl(poll, add, first, read) == 0);
    Require(sceRudpTerminate(first) == 0);
    Require(sceRudpPollControl(poll, add, first, read) == invalidContext);
    int third = -1;
    Require(sceRudpCreateContext(Handler, nullptr, &third) == 0);
    Require(sceRudpPollControl(poll, add, third, read) == 0);
    Require(sceRudpPollControl(other, add, third, read) == 0);

    int destroyedResult = 0;
    std::thread destroyedWaiter([&] { destroyedResult = sceRudpPollWait(poll, events.data(), eventCount, forever); });
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    Require(sceRudpPollDestroy(poll) == 0);
    destroyedWaiter.join();
    Require(destroyedResult == invalidPoll);
    Require(sceRudpPollDestroy(poll) == invalidPoll);
    Require(sceRudpPollDestroy(-1) == invalidArgument);
    Require(sceRudpPollControl(poll, add, third, read) == invalidPoll);

    int endedResult = 0;
    std::thread endedWaiter([&] { endedResult = sceRudpPollWait(other, events.data(), eventCount, forever); });
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    Require(sceRudpEnd() == 0);
    endedWaiter.join();
    Require(endedResult == notInitialized);

    Require(sceRudpInit_nid_postfix(pool.data(), static_cast<int>(pool.size())) == 0);
    Require(sceRudpPollDestroy(other) == invalidPoll);
    Require(sceRudpEnd() == 0);
    return 0;
}
