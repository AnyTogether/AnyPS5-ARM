#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>
struct GuestSignalSet {
    std::uint32_t bits[4];
};
struct GuestTimespec {
    std::int64_t seconds;
    std::int64_t nanoseconds;
};
extern "C" int APS5_VABI sigtimedwait_nid_postfix(const GuestSignalSet*, void*, const GuestTimespec*);
static void Require(bool value) { if (!value) std::abort(); }
static bool ReportsNotImplemented(const GuestSignalSet* set, void* info, const GuestTimespec* timeout) {
    try {
        sigtimedwait_nid_postfix(set, info, timeout);
    } catch (const std::runtime_error& error) {
        return std::string(error.what()) == "sigtimedwait: waiting for a pending signal not implemented";
    }
    return false;
}
int main() {
    const GuestSignalSet pipe{{1u << 12, 0, 0, 0}};
    unsigned char info[64] = {};
    const GuestTimespec poll{0, 0};
    const GuestTimespec second{1, 0};
    Require(ReportsNotImplemented(&pipe, info, &poll));
    Require(ReportsNotImplemented(&pipe, nullptr, &second));
    Require(ReportsNotImplemented(&pipe, info, nullptr));
}
