#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>
#include <stdexcept>

extern "C" {
int APS5_VABI sceNpEAAccessInitialize(void);
int APS5_VABI sceNpEAAccessTerminate(void);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

template <typename TAction>
bool Throws(TAction action) {
    try {
        action();
    } catch (const std::logic_error&) {
        return true;
    }
    return false;
}

}

int main() {
    Require(Throws([] { sceNpEAAccessTerminate(); }));
    Require(sceNpEAAccessInitialize() == 0);
    Require(Throws([] { sceNpEAAccessInitialize(); }));
    Require(sceNpEAAccessTerminate() == 0);
    Require(Throws([] { sceNpEAAccessTerminate(); }));
    Require(sceNpEAAccessInitialize() == 0);
    Require(sceNpEAAccessTerminate() == 0);
}
