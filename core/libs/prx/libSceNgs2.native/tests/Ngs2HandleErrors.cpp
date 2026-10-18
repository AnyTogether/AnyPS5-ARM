#include "Ngs2Test.hpp"

#include <iostream>
#include <stdexcept>

static void Status(int actual, int expected, const char* message) {
    if (actual != expected) throw std::runtime_error(message);
}

int main() {
    try {
        constexpr int systemError = static_cast<int>(0x804A8201u);
        constexpr int rackError = static_cast<int>(0x804A8202u);
        constexpr int outputError = static_cast<int>(0x804A8010u);
        constexpr uintptr_t sentinel = 0x5a5a;
        uintptr_t value = sentinel;
        Status(sceNgs2SystemGetUserData(0x1234, &value), systemError, "invalid system handle returned a non-PS5 error");
        Require(value == sentinel);
        Status(sceNgs2SystemDestroy(0x1234, nullptr), systemError, "system destroy returned a non-PS5 handle error");
        Status(sceNgs2RackGetVoiceHandle(0x1234, 0, &value), rackError, "invalid rack handle returned a non-PS5 error");
        Require(value == sentinel);
        Status(sceNgs2RackGetVoiceHandle(0x1234, 0, nullptr), rackError, "voice lookup checked output before the rack handle");
        Status(sceNgs2RackDestroy(0x1234, nullptr), rackError, "rack destroy returned a non-PS5 handle error");
        const auto system = CreateSystem();
        const auto rack = CreateRack(system, SCE_NGS2_RACK_ID_REVERB);
        Status(sceNgs2SystemGetUserData(rack, &value), systemError, "rack handle was accepted as a system");
        Require(value == sentinel);
        Status(sceNgs2RackGetVoiceHandle(system, 0, &value), rackError, "system handle was accepted as a rack");
        Require(value == sentinel);
        Status(sceNgs2RackGetVoiceHandle(system, 0, nullptr), rackError, "wrong-kind rack did not take precedence over null output");
        Status(sceNgs2RackGetVoiceHandle(rack, 0, nullptr), outputError, "valid rack lost null-output validation");
        Status(sceNgs2RackGetVoiceHandle(rack, 0, &value), SCE_NGS2_OK, "valid voice lookup failed");
        Require(value != 0 && value != sentinel);
        Status(sceNgs2RackDestroy(rack, nullptr), SCE_NGS2_OK, "valid rack destroy failed");
        value = sentinel;
        Status(sceNgs2RackGetVoiceHandle(rack, 0, &value), rackError, "retired rack returned the wrong error");
        Require(value == sentinel);
        Status(sceNgs2RackGetVoiceHandle(rack, 0, nullptr), rackError, "retired rack did not take precedence over null output");
        Status(sceNgs2SystemDestroy(system, nullptr), SCE_NGS2_OK, "valid system destroy failed");
        Status(sceNgs2SystemGetUserData(system, &value), systemError, "retired system returned the wrong error");
        Require(value == sentinel);
        std::cout << "NGS2 PS5 handle errors and validation precedence checked\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
