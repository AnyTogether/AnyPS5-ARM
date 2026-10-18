#include "prx/libkernel/Time/include/Time.hpp"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

static void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "%s\n", message);
        std::abort();
    }
}

int main(int argc, char** argv) {
    constexpr std::uint64_t minuteMicros = 60ULL * 1000 * 1000;
    constexpr std::uint64_t sleptMicros = 50ULL * 1000;
    const char* scaleText = std::getenv("APS5_TIME_SCALE");
    const double scale = scaleText ? std::strtod(scaleText, nullptr) : 1.0;
    const auto elapsedMicros = static_cast<std::uint64_t>(static_cast<double>(sleptMicros) * (scale > 0.0 ? scale : 1.0));
    const auto minimumElapsedMicros = elapsedMicros * 19 / 20;
    const auto slept = std::chrono::steady_clock::now() + std::chrono::microseconds(sleptMicros);
    while (std::chrono::steady_clock::now() < slept) std::this_thread::sleep_until(slept);
    if (argc > 1 && std::strcmp(argv[1], "counter") == 0) {
        const std::uint64_t counter = sceKernelGetProcessTimeCounter();
        Require(counter < minuteMicros * 1000, "first process time counter wrapped");
        Require(counter >= minimumElapsedMicros * 1000, "first process time counter does not include the time before the first call");
        return 0;
    }
    const std::uint64_t first = sceKernelGetProcessTime();
    Require(first < minuteMicros, "first process time wrapped");
    Require(first >= minimumElapsedMicros, "first process time does not include the time before the first call");
    Require(sceKernelGetProcessTime() >= first, "process time went backwards");
    return 0;
}
