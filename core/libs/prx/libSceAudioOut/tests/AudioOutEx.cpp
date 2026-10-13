#include "prx/libc/include/general/VabiMacros.hpp"

#include <cstdio>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI sceAudioOutExClose();
int APS5_VABI sceAudioOutExConfigureOutput();
int APS5_VABI sceAudioOutExOpen();
}

using ExFunction = int (APS5_VABI *)();

static bool ReportsNotImplemented(ExFunction function, const char* name) {
    try {
        function();
    } catch (const std::runtime_error& error) {
        if (std::string(error.what()) == std::string(name) + " not implemented") return true;
        std::fprintf(stderr, "%s threw: %s\n", name, error.what());
        return false;
    }
    std::fprintf(stderr, "%s returned instead of reporting that it is not implemented\n", name);
    return false;
}

int main() {
    bool passed = ReportsNotImplemented(sceAudioOutExClose, "sceAudioOutExClose");
    passed = ReportsNotImplemented(sceAudioOutExConfigureOutput, "sceAudioOutExConfigureOutput") && passed;
    passed = ReportsNotImplemented(sceAudioOutExOpen, "sceAudioOutExOpen") && passed;
    return passed ? 0 : 1;
}
