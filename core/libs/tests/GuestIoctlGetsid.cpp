#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>
#include <stdexcept>
#include <string>
extern "C" {
int APS5_VABI getsid_nid_postfix(int);
}
static void Require(bool value) { if (!value) std::abort(); }
template <typename Call>
static bool ReportsNotImplemented(Call call, const std::string& message) {
    try {
        call();
    } catch (const std::runtime_error& error) {
        return error.what() == message;
    }
    return false;
}
int main() {
    Require(ReportsNotImplemented([] { getsid_nid_postfix(0); }, "getsid: process sessions not implemented"));
    Require(ReportsNotImplemented([] { getsid_nid_postfix(1); }, "getsid: process sessions not implemented"));
}
