#include <cstdio>
#include <cstdlib>
#include "../prx/libc/include/general/VabiMacros.hpp"

extern "C" int* APS5_VABI __error_nid_postfix();

int main() {
    if (__error_nid_postfix() == nullptr) return 1;
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    std::fputs("aborting\n", stderr);
    std::abort();
}
