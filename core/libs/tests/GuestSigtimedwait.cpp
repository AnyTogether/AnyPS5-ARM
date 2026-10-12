#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
struct GuestSignalSet {
    std::uint32_t bits[4];
};
struct GuestTimespec {
    std::int64_t seconds;
    std::int64_t nanoseconds;
};
using Handler = void (APS5_VABI *)(int);
extern "C" {
int APS5_VABI sigtimedwait_nid_postfix(const GuestSignalSet*, void*, const GuestTimespec*);
int APS5_VABI sigwaitinfo_nid_postfix(const GuestSignalSet*, void*);
int APS5_VABI sigwait_nid_postfix(const GuestSignalSet*, int*);
int APS5_VABI pause_nid_postfix(void);
Handler APS5_VABI signal_nid_postfix(int, Handler);
int APS5_VABI raise_nid_postfix(int);
int APS5_VABI _sigprocmask_nid_postfix(int, const GuestSignalSet*, GuestSignalSet*);
}
volatile int received = 0;
void APS5_VABI Callback(int value) { received = value; }
static void Require(bool value) { if (!value) std::abort(); }
template <typename TCall>
static bool ReportsNotImplemented(TCall call, const char* message) {
    try {
        call();
    } catch (const std::runtime_error& error) {
        return std::string(error.what()) == message;
    }
    return false;
}
static bool SigtimedwaitReportsNotImplemented(const GuestSignalSet* set, void* info, const GuestTimespec* timeout) {
    return ReportsNotImplemented([&] { sigtimedwait_nid_postfix(set, info, timeout); }, "sigtimedwait: waiting for a pending signal not implemented");
}
static bool SigwaitinfoReportsNotImplemented(const GuestSignalSet* set, void* info) {
    return ReportsNotImplemented([&] { sigwaitinfo_nid_postfix(set, info); }, "sigwaitinfo: waiting for a pending signal not implemented");
}
static bool SigwaitReportsNotImplemented(const GuestSignalSet* set, int* taken) {
    return ReportsNotImplemented([&] { sigwait_nid_postfix(set, taken); }, "sigwait: waiting for a pending signal not implemented");
}
int main() {
    const GuestSignalSet pipe{{1u << 12, 0, 0, 0}};
    const GuestSignalSet empty{{0, 0, 0, 0}};
    const GuestSignalSet interrupt{{1u << 1, 0, 0, 0}};
    unsigned char info[64] = {};
    const unsigned char untouched[64] = {};
    const GuestTimespec poll{0, 0};
    const GuestTimespec second{1, 0};
    Require(SigtimedwaitReportsNotImplemented(&pipe, info, &poll));
    Require(SigtimedwaitReportsNotImplemented(&pipe, nullptr, &second));
    Require(SigtimedwaitReportsNotImplemented(&pipe, info, nullptr));

    Require(SigwaitinfoReportsNotImplemented(&pipe, info));
    Require(SigwaitinfoReportsNotImplemented(&pipe, nullptr));
    Require(SigwaitinfoReportsNotImplemented(&empty, info));
    Require(std::memcmp(info, untouched, sizeof(info)) == 0);

    int taken = -1;
    Require(SigwaitReportsNotImplemented(&pipe, &taken));
    Require(SigwaitReportsNotImplemented(&empty, &taken));
    Require(taken == -1);

    Require(ReportsNotImplemented([] { pause_nid_postfix(); }, "pause: waiting for a delivered signal not implemented"));

    GuestSignalSet previous{};
    Require(signal_nid_postfix(2, Callback) != reinterpret_cast<Handler>(static_cast<std::uintptr_t>(-1)));
    Require(_sigprocmask_nid_postfix(1, &interrupt, &previous) == 0);
    Require(raise_nid_postfix(2) == 0 && received == 0);
    Require(SigwaitReportsNotImplemented(&interrupt, &taken) && taken == -1);
    Require(SigwaitinfoReportsNotImplemented(&interrupt, info));
    Require(std::memcmp(info, untouched, sizeof(info)) == 0);
    GuestSignalSet current{};
    Require(_sigprocmask_nid_postfix(1, nullptr, &current) == 0 && current.bits[0] == (previous.bits[0] | interrupt.bits[0]));
    Require(_sigprocmask_nid_postfix(3, &previous, nullptr) == 0);
    Require(raise_nid_postfix(2) == 0 && received == 2);
    Require(ReportsNotImplemented([] { pause_nid_postfix(); }, "pause: waiting for a delivered signal not implemented"));
}
