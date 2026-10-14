#pragma once
#include <cstdint>

namespace GuestSockets {

struct SocketOptionState {
    int reportedError = 0;
};

int SetSocketLevelOption(std::uintptr_t native, SocketOptionState& state, int option, const void* value, std::uint32_t length);
int GetSocketLevelOption(std::uintptr_t native, SocketOptionState& state, int type, int option, void* value, std::uint32_t* length);

}
