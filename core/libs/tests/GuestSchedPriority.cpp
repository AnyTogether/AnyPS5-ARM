#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>
#include <initializer_list>
#include <stdexcept>
extern "C" int* APS5_VABI __error_nid_postfix();
extern "C" {
int APS5_VABI sched_get_priority_max_nid_postfix(int policy);
int APS5_VABI sched_get_priority_min_nid_postfix(int policy);
}
static void Require(bool value) { if (!value) std::abort(); }
static bool Rejects(int policy) {
    *__error_nid_postfix() = 0;
    const bool max = sched_get_priority_max_nid_postfix(policy) == -1 && *__error_nid_postfix() == 22;
    *__error_nid_postfix() = 0;
    return max && sched_get_priority_min_nid_postfix(policy) == -1 && *__error_nid_postfix() == 22;
}
int main() {
    Require(Rejects(-1) && Rejects(2) && Rejects(5));
    for (int policy : {1, 3}) {
        Require(sched_get_priority_max_nid_postfix(policy) == 767);
        Require(sched_get_priority_min_nid_postfix(policy) == 256);
    }
    Require(Rejects(0) && Rejects(4));
}
