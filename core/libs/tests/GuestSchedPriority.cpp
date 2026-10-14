#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>
#include <initializer_list>
#include <stdexcept>
extern "C" int* APS5_VABI __error_nid_postfix();
extern "C" {
int APS5_VABI sched_get_priority_max_nid_postfix(int policy);
int APS5_VABI sched_get_priority_min_nid_postfix(int policy);
int APS5_VABI getpriority_nid_postfix(int which, int who);
int APS5_VABI setpriority_nid_postfix(int which, int who, int niceval);
int APS5_VABI getpid_nid_postfix(void);
int* APS5_VABI __error_nid_postfix();
}
static constexpr int PrioProcess = 0;
static constexpr int PrioGroup = 1;
static constexpr int PrioUser = 2;
static void Require(bool value) { if (!value) std::abort(); }
static bool Rejects(int policy) {
    *__error_nid_postfix() = 0;
    const bool max = sched_get_priority_max_nid_postfix(policy) == -1 && *__error_nid_postfix() == 22;
    *__error_nid_postfix() = 0;
    return max && sched_get_priority_min_nid_postfix(policy) == -1 && *__error_nid_postfix() == 22;
}
static void RequireNice(int which, int who) {
    *__error_nid_postfix() = 13;
    Require(getpriority_nid_postfix(which, who) == 0 && *__error_nid_postfix() == 13);
}
static void RequireError(int which, int who, int error) {
    *__error_nid_postfix() = 0;
    Require(getpriority_nid_postfix(which, who) == -1 && *__error_nid_postfix() == error);
}
static void RequireSet(int which, int who, int nice) {
    *__error_nid_postfix() = 13;
    Require(setpriority_nid_postfix(which, who, nice) == 0 && *__error_nid_postfix() == 13);
}
static void RequireSetError(int which, int who, int nice, int error) {
    *__error_nid_postfix() = 0;
    Require(setpriority_nid_postfix(which, who, nice) == -1 && *__error_nid_postfix() == error);
}
int main() {
    Require(Rejects(-1) && Rejects(2) && Rejects(5));
    for (int policy : {1, 3}) {
        Require(sched_get_priority_max_nid_postfix(policy) == 767);
        Require(sched_get_priority_min_nid_postfix(policy) == 256);
    }
    Require(Rejects(0) && Rejects(4));
    const int self = getpid_nid_postfix();
    RequireNice(PrioProcess, 0);
    RequireNice(PrioProcess, self);
    RequireNice(PrioGroup, 0);
    RequireNice(PrioGroup, self);
    RequireNice(PrioUser, 0);
    RequireError(PrioProcess, self + 1, 3);
    RequireError(PrioProcess, -1, 3);
    RequireError(PrioGroup, self + 1, 3);
    RequireError(PrioUser, 1000, 3);
    RequireError(3, 0, 22);
    RequireError(-1, self, 22);
    RequireSet(PrioProcess, 0, 0);
    RequireSet(PrioProcess, self, 5);
    RequireSet(PrioProcess, self, -20);
    RequireSet(PrioGroup, 0, 20);
    RequireSet(PrioUser, 0, -1);
    RequireSetError(PrioProcess, self + 1, 0, 3);
    RequireSetError(PrioProcess, -1, 0, 3);
    RequireSetError(PrioGroup, self + 1, 0, 3);
    RequireSetError(PrioUser, 1000, 0, 3);
    RequireSetError(3, 0, 0, 22);
    RequireSetError(-1, self, 0, 22);
    Require(setpriority_nid_postfix(PrioProcess, 0, 10) == 0 && getpriority_nid_postfix(PrioProcess, 0) == 10);
    Require(setpriority_nid_postfix(PrioProcess, 0, 99) == 0 && getpriority_nid_postfix(PrioProcess, 0) == 20);
    Require(setpriority_nid_postfix(PrioProcess, 0, -99) == 0 && getpriority_nid_postfix(PrioProcess, 0) == -20);
    Require(setpriority_nid_postfix(PrioProcess, 0, 0) == 0 && getpriority_nid_postfix(PrioProcess, 0) == 0);
}
