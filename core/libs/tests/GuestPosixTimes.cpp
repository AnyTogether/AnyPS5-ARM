#include "prx/libScePosixForWebKit/include/Api.hpp"
#include "prx/libScePosixForWebKit/GuestTimes.hpp"
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <source_location>
#include <stdexcept>
#include <thread>

static void Require(bool condition, std::source_location location = std::source_location::current()) {
    if (condition) return;
    std::fprintf(stderr, "posix times check failed at line %u (errno %d)\n", static_cast<unsigned>(location.line()), errno);
    std::abort();
}

static void Run() {
    errno = E2BIG;
    PosixForWebKitTms first{};
    const auto before = times_nid_postfix(&first);
    Require(first.tms_utime >= 0 && first.tms_stime >= 0);
    Require(first.tms_cutime == 0 && first.tms_cstime == 0);
    Require(errno == E2BIG);

    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    PosixForWebKitTms second{};
    const auto after = times_nid_postfix(&second);
    Require(after > before);
    Require(second.tms_utime >= first.tms_utime && second.tms_stime >= first.tms_stime);
    Require(second.tms_cutime == 0 && second.tms_cstime == 0 && errno == E2BIG);

    try {
        times_nid_postfix(nullptr);
        Require(false);
    } catch (const std::invalid_argument&) { Require(errno == E2BIG); }

    try {
        times_nid_postfix(reinterpret_cast<PosixForWebKitTms*>(0x1000));
        Require(false);
    } catch (const std::invalid_argument&) { Require(errno == E2BIG); }
}

int main() {
    try {
        Run();
    } catch (const std::exception& error) {
        std::fprintf(stderr, "posix times: unexpected exception: %s\n", error.what());
        std::abort();
    }
}
