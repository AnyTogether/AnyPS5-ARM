#include "prx/libc/include/general/VabiMacros.hpp"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI sceAudioOut2Initialize();
int APS5_VABI sceAudioOut2Set3DLatency(int, std::uint32_t);
int APS5_VABI sceAudioOut2MasteringInit(std::uint32_t);
int APS5_VABI sceAudioOut2MasteringTerm();
int APS5_VABI sceAudioOut2MasteringGetState(void*, std::uint32_t, std::uintptr_t);
int APS5_VABI sceAudioOut2MasteringSetParam(const void*, std::uint32_t, std::uint32_t);
int APS5_VABI sceAudioOut2UserCreate(std::uint32_t, std::uintptr_t*);
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

namespace {

constexpr int systemUser = 0xFF;
constexpr int user = 0x10000000;
constexpr int invalidArgument = static_cast<int>(0x80260502);

void TestSet3DLatency() {
    Require(sceAudioOut2Set3DLatency(systemUser, 2) == 0, "latency 2 for the system user must be accepted");
    Require(sceAudioOut2Set3DLatency(systemUser, 2) == 0, "latency 2 must be accepted again");
    Require(sceAudioOut2Set3DLatency(systemUser, 1) == 0, "latency 1 for the system user must be accepted");
    Require(sceAudioOut2Set3DLatency(systemUser, 0) == invalidArgument, "latency 0 must be refused");
    Require(sceAudioOut2Set3DLatency(systemUser, 3) == invalidArgument, "latency 3 must be refused");
    Require(sceAudioOut2Set3DLatency(user, 2) == invalidArgument, "a user other than the system user must be refused");
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
    Require(sceAudioOut2MasteringSetParam(nullptr, 0, 0) == invalidArgument, "null mastering parameters must be refused");
}

struct StatesBuffer {
    alignas(16) std::uint8_t bytes[512];

    void Fill(std::uint32_t statesId) {
        std::memset(bytes, 0xff, sizeof(bytes));
        std::memcpy(bytes, &statesId, sizeof(statesId));
    }

    std::uint32_t Word(std::size_t offset) const {
        std::uint32_t value = 0;
        std::memcpy(&value, bytes + offset, sizeof(value));
        return value;
    }

    bool ZeroFloats(std::size_t offset, std::size_t count) const {
        for (std::size_t index = 0; index < count; ++index) {
            float value = 0.0f;
            std::memcpy(&value, bytes + offset + index * sizeof(value), sizeof(value));
            if (!(value == 0.0f)) return false;
        }
        return true;
    }

    bool UntouchedFrom(std::size_t offset) const {
        for (std::size_t index = offset; index < sizeof(bytes); ++index) {
            if (bytes[index] != 0xff) return false;
        }
        return true;
    }
};

void TestMasteringGetState() {
    StatesBuffer states{};
    std::uintptr_t userHandle = 0;
    Require(sceAudioOut2UserCreate(user, &userHandle) == 0 && userHandle != 0, "user creation must succeed");

    states.Fill(1);
    Require(sceAudioOut2MasteringGetState(states.bytes, 0, 0) == 0, "states id 1 for the main output must be accepted");
    Require(states.Word(0) == 1 && states.Word(4) == 0 && states.Word(8) == 0 && states.Word(12) == 0, "states id 1 must keep its id and zero the reserved header words");
    Require(states.Word(16) == 0x01010001 && states.Word(20) == 208 && states.Word(24) == 0 && states.Word(28) == 0, "states id 1 must describe a 208-byte default compressor");
    Require(states.ZeroFloats(32, 48), "idle compressor meters must be zero");
    Require(states.Word(224) == 0x01010003 && states.Word(228) == 112 && states.Word(232) == 0 && states.Word(236) == 0, "states id 1 must describe a 112-byte default limiter");
    Require(states.ZeroFloats(240, 24), "idle limiter meters must be zero");
    Require(states.UntouchedFrom(336), "states id 1 must write 336 bytes only");

    states.Fill(1);
    Require(sceAudioOut2MasteringGetState(states.bytes, 1, userHandle) == 0, "states id 1 for the headphone output of a user must be accepted");
    Require(states.Word(16) == 0x01010001 && states.UntouchedFrom(336), "a user's states must have the same layout");

    states.Fill(2);
    Require(sceAudioOut2MasteringGetState(states.bytes, 2, 0) == 0, "states id 2 for the recording output must be accepted");
    Require(states.Word(0) == 2 && states.Word(4) == 0 && states.Word(8) == 0 && states.Word(12) == 0, "states id 2 must keep its id and zero the reserved header words");
    Require(states.Word(16) == 0x01020001 && states.Word(20) == 272 && states.Word(24) == 0 && states.Word(28) == 0, "states id 2 must describe a 272-byte four-band compressor");
    Require(states.ZeroFloats(32, 64), "idle four-band compressor meters must be zero");
    Require(states.Word(288) == 0x01010003 && states.Word(292) == 112 && states.Word(296) == 0 && states.Word(300) == 0, "states id 2 must describe a 112-byte default limiter");
    Require(states.ZeroFloats(304, 24), "idle limiter meters after the four-band compressor must be zero");
    Require(states.UntouchedFrom(400), "states id 2 must write 400 bytes only");

    Require(sceAudioOut2MasteringInit(0) == 0, "the mastering pass must start again");
    states.Fill(1);
    Require(sceAudioOut2MasteringGetState(states.bytes, 0, 0) == 0 && states.Word(16) == 0x01010001, "states must be reported while the mastering pass runs");
    Require(sceAudioOut2MasteringTerm() == 0, "the mastering pass must stop again");
    states.Fill(1);
    Require(sceAudioOut2MasteringGetState(states.bytes, 0, 0) == 0 && states.Word(16) == 0x01010001, "states must be reported after the mastering pass stopped");

    Require(sceAudioOut2MasteringGetState(nullptr, 0, 0) == invalidArgument, "null states must be refused");
    states.Fill(1);
    Require(sceAudioOut2MasteringGetState(states.bytes, 3, 0) == invalidArgument, "output 3 must be refused");
    Require(states.Word(0) == 1 && states.UntouchedFrom(4), "a refused output must not write the states");
    states.Fill(7);
    Require(sceAudioOut2MasteringGetState(states.bytes, 0, 0) == invalidArgument, "states id 7 must be refused");
    Require(states.Word(0) == 7 && states.UntouchedFrom(4), "a refused states id must not write the states");
}

void TestEnableChat() {
    Require(sceAudioOut2EnableChat() == 0, "enabling chat must be accepted");
    Require(sceAudioOut2EnableChat() == 0, "enabling chat again must be accepted");
    Require(sceAudioOut2DisableChat() == 0, "disabling chat must be accepted");
    Require(sceAudioOut2DisableChat() == 0, "disabling chat again must be accepted");
    Require(sceAudioOut2EnableChat() == 0, "enabling chat after disabling it must be accepted");
}

}

int main() {
    Require(sceAudioOut2Initialize() == 0, "initialization must succeed");
    TestSet3DLatency();
    TestMasteringInit();
    TestMasteringTerm();
    TestMasteringSetParam();
    TestMasteringGetState();
    TestEnableChat();
    return 0;
}
