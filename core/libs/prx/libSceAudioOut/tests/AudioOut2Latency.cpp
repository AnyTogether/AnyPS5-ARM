#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI sceAudioOut2Initialize();
int APS5_VABI sceAudioOut2LoInit();
int APS5_VABI sceAudioOut2LoTerminate();
int APS5_VABI sceAudioOut2Set3DLatency(int, std::uint32_t);
int APS5_VABI sceAudioOut2MasteringInit(std::uint32_t);
int APS5_VABI sceAudioOut2MasteringTerm();
int APS5_VABI sceAudioOut2MasteringSetParam(const void*, std::uint32_t, std::uint32_t);
int APS5_VABI sceAudioOut2MasteringGetState(void*, std::uint32_t, std::uint64_t);
int APS5_VABI sceAudioOut2SetSystemDebugState(const void*);
int APS5_VABI sceAudioOut2EnableChat();
int APS5_VABI sceAudioOut2DisableChat();
}

static void Require(bool value, const char* message) {
    if (value) return;
    std::fprintf(stderr, "%s\n", message);
    std::abort();
}

template<typename TFunction>
static std::string RuntimeErrorMessage(TFunction function) {
    try {
        function();
    } catch (const std::runtime_error& error) {
        return error.what();
    }
    return {};
}

static bool NamesFunction(const std::string& message, const char* function) {
    return message.rfind(function, 0) == 0 && message.find("not implemented") == std::string::npos;
}

template<typename TFunction>
static bool ThrowsRuntimeError(TFunction function) {
    try {
        function();
    } catch (const std::runtime_error&) {
        return true;
    }
    return false;
}

namespace {

static_assert(sizeof(AudioOut2MasteringCompressorStates) == 208);
static_assert(sizeof(AudioOut2MasteringCompressorStatesV2) == 272);
static_assert(sizeof(AudioOut2MasteringLimiterStates) == 112);
static_assert(sizeof(AudioOut2MasteringStates) == 336);
static_assert(sizeof(AudioOut2MasteringStatesV2) == 400);

constexpr int systemUser = 0xFF;
constexpr int user = 0x10000000;
constexpr int errorInvalidParam = static_cast<int>(0x80268001);
constexpr int errorInvalidArgument = static_cast<int>(0x80260502);
constexpr int errorMasteringInvalidApiParam = static_cast<int>(0x80268201);
constexpr int errorMasteringInvalidStatesId = static_cast<int>(0x80268204);

void TestSet3DLatency() {
    Require(sceAudioOut2Set3DLatency(systemUser, 0) == errorInvalidParam, "output 0 for selector 255 must be refused");
    for (std::uint32_t output = 0; output <= 2; ++output) {
        Require(sceAudioOut2Set3DLatency(0, output) == 0, "selector 0 must accept each supported output");
    }
    Require(sceAudioOut2Set3DLatency(systemUser, 1) == 0, "output 1 for the system user must be accepted");
    Require(sceAudioOut2Set3DLatency(systemUser, 2) == 0, "output 2 for the system user must be accepted");
    Require(sceAudioOut2Set3DLatency(systemUser, 2) == 0, "output 2 must be accepted again");
    Require(sceAudioOut2Set3DLatency(user, 1) == errorInvalidParam, "a user id is not a valid latency selector");
    Require(sceAudioOut2Set3DLatency(systemUser, 3) == errorInvalidParam, "output 3 must be refused");
    Require(sceAudioOut2Set3DLatency(systemUser, 0xFFFFFFFFu) == errorInvalidParam, "a large output must be refused");
}

void TestMasteringInit() {
    Require(sceAudioOut2MasteringInit(0) == 0, "flags 0 must be accepted");
    Require(NamesFunction(RuntimeErrorMessage([] { sceAudioOut2MasteringInit(1); }), "sceAudioOut2MasteringInit"), "flags 1 must throw a runtime error naming the function");
    Require(NamesFunction(RuntimeErrorMessage([] { sceAudioOut2MasteringInit(0x80000000u); }), "sceAudioOut2MasteringInit"), "an unknown flag must throw a runtime error naming the function");
}

void TestMasteringTerm() {
    Require(sceAudioOut2MasteringInit(0) == 0, "a second initialization must be accepted");
    Require(sceAudioOut2MasteringTerm() == 0, "termination must be accepted");
    Require(sceAudioOut2MasteringTerm() == 0, "termination must be accepted for each initialization");
}

void TestMasteringSetParam() {
    const std::uint32_t params[4] = {1u, 0u, 0u, 0u};
    Require(sceAudioOut2MasteringSetParam(params, 0, 0) == 0, "mastering parameters must be accepted");
    Require(sceAudioOut2MasteringSetParam(params, 2, 0) == 0, "mastering parameters for output 2 must be accepted");
    Require(sceAudioOut2MasteringSetParam(nullptr, 0, 0) == errorMasteringInvalidApiParam, "null mastering parameters return the invalid API parameter error");
}

void TestMasteringGetState() {
    alignas(16) std::uint8_t storage[512];
    Require(sceAudioOut2MasteringGetState(nullptr, 0, 0) == errorMasteringInvalidApiParam, "a null state returns the invalid API parameter error");
    auto* header = reinterpret_cast<std::uint32_t*>(storage);
    auto* words = reinterpret_cast<std::uint32_t*>(storage);
    *header = 1u;
    Require(sceAudioOut2MasteringGetState(storage, 0, 0) == 0, "states id 1 must be accepted");
    Require(*header == 1u, "states id 1 is kept");
    Require(words[4] == 0x01010001u && words[5] == 8u + 8u + 3u * 8u * 4u * 2u, "the compressor states descriptor is filled");
    Require(words[56] == 0x01010003u && words[57] == 8u + 8u + 8u * 4u * 3u, "the limiter states descriptor is filled");
    std::fill(storage, storage + sizeof(storage), 0xA5);
    *header = 2u;
    Require(sceAudioOut2MasteringGetState(storage, 2, 1) == 0, "states id 2 must be accepted");
    Require(*header == 2u, "states id 2 is kept");
    Require(words[4] == 0x01020001u && words[5] == 8u + 8u + 4u * 8u * 4u * 2u, "the V2 compressor states descriptor is filled");
    Require(words[72] == 0x01010003u && words[73] == 8u + 8u + 8u * 4u * 3u, "the V2 limiter states descriptor is filled");
    Require(std::all_of(storage + 8, storage + 16, [](std::uint8_t byte) { return byte == 0; }), "the reserved words are zeroed");
    Require(std::all_of(storage + 24, storage + 288, [](std::uint8_t byte) { return byte == 0; }), "the V2 compressor states are zeroed");
    *header = 3u;
    Require(sceAudioOut2MasteringGetState(storage, 0, 0) == errorMasteringInvalidStatesId, "an unknown states id is refused");
    *header = 0u;
    Require(sceAudioOut2MasteringGetState(storage, 0, 0) == errorMasteringInvalidStatesId, "states id 0 is refused");
}

void TestSetSystemDebugState() {
    const std::uint64_t param[4] = {1, 0, 0, 0};
    Require(sceAudioOut2SetSystemDebugState(reinterpret_cast<const void*>(param)) == 0, "a debug state must be accepted");
    Require(sceAudioOut2SetSystemDebugState(reinterpret_cast<const void*>(param)) == 0, "a debug state must be accepted again");
    Require(sceAudioOut2SetSystemDebugState(nullptr) == errorInvalidArgument, "a null debug state is refused");
}

void TestEnableChat() {
    Require(sceAudioOut2EnableChat() == 0, "enabling chat must be accepted");
    Require(sceAudioOut2EnableChat() == 0, "enabling chat again must be accepted");
    Require(sceAudioOut2DisableChat() == 0, "disabling chat must be accepted");
    Require(sceAudioOut2DisableChat() == 0, "disabling chat again must be accepted");
    Require(sceAudioOut2EnableChat() == 0, "enabling chat after disabling it must be accepted");
}

void TestLowLatencyService() {
    Require(sceAudioOut2LoInit() == 0, "starting the low-latency service must be accepted");
    Require(sceAudioOut2LoInit() == 0, "starting the low-latency service again must be accepted");
    Require(ThrowsRuntimeError([] { sceAudioOut2LoTerminate(); }), "stopping the low-latency service must throw");
}

}

int main() {
    Require(sceAudioOut2Initialize() == 0, "initialization must succeed");
    TestSet3DLatency();
    TestMasteringInit();
    TestMasteringTerm();
    TestMasteringSetParam();
    TestMasteringGetState();
    TestSetSystemDebugState();
    TestEnableChat();
    TestLowLatencyService();
    return 0;
}
