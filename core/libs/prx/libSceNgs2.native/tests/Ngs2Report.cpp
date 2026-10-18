#include "prx/libc/include/general/VabiMacros.hpp"

#include <cstdint>
#include <cstdlib>
#include <stdexcept>

extern "C" {
int APS5_VABI sceNgs2ReportRegisterHandler(std::uint32_t reportType, void* handler, std::uintptr_t userData, std::uintptr_t* outHandle);
int APS5_VABI sceNgs2ReportUnregisterHandler(std::uintptr_t reportHandle);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

template <typename Call>
bool Throws(Call call) {
    try {
        call();
    } catch (const std::runtime_error&) {
        return true;
    }
    return false;
}

}

int main() {
    std::uintptr_t handle = 0x1234;
    Require(Throws([&] { sceNgs2ReportRegisterHandler(5, nullptr, 0, &handle); }));
    Require(handle == 0x1234);
    Require(Throws([] { sceNgs2ReportUnregisterHandler(0x1234); }));
}
