#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <stdexcept>

extern "C" {
int APS5_VABI pthread_mutexattr_init_nid_postfix(PthreadMutexattr* attr);
int APS5_VABI pthread_mutexattr_destroy_nid_postfix(PthreadMutexattr* attr);
int APS5_VABI pthread_mutexattr_setprotocol_nid_postfix(PthreadMutexattr* attr, int protocol);
int APS5_VABI pthread_mutexattr_setprioceiling_nid_postfix(PthreadMutexattr* attr, int prioceiling);
int APS5_VABI pthread_mutexattr_getprioceiling_nid_postfix(const PthreadMutexattr* attr, int* prioceiling);
int APS5_VABI pthread_mutexattr_settype_nid_postfix(PthreadMutexattr* attr, int type);
int APS5_VABI pthread_mutexattr_gettype_nid_postfix(const PthreadMutexattr* attr, int* type);
int APS5_VABI pthread_mutex_init_nid_postfix(PthreadMutex* mutex, const PthreadMutexattr* attr);
int APS5_VABI pthread_mutex_lock_nid_postfix(PthreadMutex* mutex);
int APS5_VABI pthread_mutex_unlock_nid_postfix(PthreadMutex* mutex);
int APS5_VABI pthread_mutex_destroy_nid_postfix(PthreadMutex* mutex);
int APS5_VABI pthread_mutex_timedlock_nid_postfix(PthreadMutex* mutex, const KernelTimespec* abstime);
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
int APS5_VABI sched_get_priority_max_nid_postfix(int policy);
}

static constexpr int GUEST_EINVAL = 22;
static constexpr int PRIO_NONE = 0;
static constexpr int PRIO_INHERIT = 1;
static constexpr int PRIO_PROTECT = 2;
static constexpr int SCHED_RR = 3;

static void Require(bool value) { if (!value) std::abort(); }

template <typename Call>
static bool Throws(Call call) {
    try {
        call();
    } catch (const std::exception&) {
        return true;
    }
    return false;
}

static constexpr KernelTimespec INVALID_DEADLINE{0, 1000000000};

static void* APS5_VABI TimedlockInvalidDeadline(void* arg) {
    auto* mutex = static_cast<PthreadMutex*>(arg);
    return reinterpret_cast<void*>(static_cast<std::intptr_t>(pthread_mutex_timedlock_nid_postfix(mutex, &INVALID_DEADLINE)));
}

static void CheckTimedlockInvalidDeadline() {
    PthreadMutex mutex = nullptr;
    Require(pthread_mutex_init_nid_postfix(&mutex, nullptr) == 0);
    Require(pthread_mutex_timedlock_nid_postfix(&mutex, &INVALID_DEADLINE) == 0);
    Pthread thread{};
    void* result = nullptr;
    Require(scePthreadCreate(&thread, nullptr, TimedlockInvalidDeadline, &mutex, nullptr) == 0);
    Require(scePthreadJoin(thread, &result) == 0 && reinterpret_cast<std::intptr_t>(result) == GUEST_EINVAL);
    Require(pthread_mutex_unlock_nid_postfix(&mutex) == 0);
    Require(pthread_mutex_destroy_nid_postfix(&mutex) == 0);
}

static void CheckType() {
    PthreadMutexattr attr = nullptr;
    Require(pthread_mutexattr_init_nid_postfix(&attr) == 0);
    int type = -1;
    Require(pthread_mutexattr_gettype_nid_postfix(&attr, &type) == 0 && type == 1);
    for (const int set : {2, 3, 4, 1}) {
        Require(pthread_mutexattr_settype_nid_postfix(&attr, set) == 0);
        Require(pthread_mutexattr_gettype_nid_postfix(&attr, &type) == 0 && type == set);
    }
    Require(pthread_mutexattr_settype_nid_postfix(&attr, 5) == GUEST_EINVAL);
    Require(pthread_mutexattr_gettype_nid_postfix(&attr, &type) == 0 && type == 1);
    Require(Throws([&] { pthread_mutexattr_gettype_nid_postfix(&attr, nullptr); }));
    Require(pthread_mutexattr_destroy_nid_postfix(&attr) == 0);
    type = -1;
    Require(pthread_mutexattr_gettype_nid_postfix(&attr, &type) == GUEST_EINVAL && type == -1);
    Require(pthread_mutexattr_gettype_nid_postfix(nullptr, &type) == GUEST_EINVAL && type == -1);
}

int main() {
    CheckType();
    CheckTimedlockInvalidDeadline();
    PthreadMutexattr attr = nullptr;
    Require(pthread_mutexattr_init_nid_postfix(&attr) == 0);
    int ceiling = -1;
    Require(pthread_mutexattr_getprioceiling_nid_postfix(&attr, &ceiling) == GUEST_EINVAL && ceiling == -1);
    Require(pthread_mutexattr_setprioceiling_nid_postfix(&attr, 300) == GUEST_EINVAL);
    Require(pthread_mutexattr_setprotocol_nid_postfix(&attr, PRIO_INHERIT) == 0);
    Require(pthread_mutexattr_setprioceiling_nid_postfix(&attr, 300) == GUEST_EINVAL);
    Require(pthread_mutexattr_setprotocol_nid_postfix(&attr, PRIO_PROTECT) == 0);
    Require(pthread_mutexattr_getprioceiling_nid_postfix(&attr, &ceiling) == 0 && ceiling == sched_get_priority_max_nid_postfix(SCHED_RR));
    Require(pthread_mutexattr_setprioceiling_nid_postfix(&attr, 300) == 0);
    Require(pthread_mutexattr_getprioceiling_nid_postfix(&attr, &ceiling) == 0 && ceiling == 300);
    PthreadMutex mutex = nullptr;
    Require(pthread_mutex_init_nid_postfix(&mutex, &attr) == 0);
    Require(pthread_mutex_lock_nid_postfix(&mutex) == 0);
    Require(pthread_mutex_unlock_nid_postfix(&mutex) == 0);
    Require(pthread_mutex_destroy_nid_postfix(&mutex) == 0);
    Require(pthread_mutexattr_setprotocol_nid_postfix(&attr, PRIO_PROTECT) == 0);
    Require(pthread_mutexattr_getprioceiling_nid_postfix(&attr, &ceiling) == 0 && ceiling == sched_get_priority_max_nid_postfix(SCHED_RR));
    Require(pthread_mutexattr_setprotocol_nid_postfix(&attr, PRIO_NONE) == 0);
    Require(pthread_mutexattr_getprioceiling_nid_postfix(&attr, &ceiling) == GUEST_EINVAL);
    Require(Throws([&] { pthread_mutexattr_getprioceiling_nid_postfix(&attr, nullptr); }));
    Require(pthread_mutexattr_destroy_nid_postfix(&attr) == 0);
    Require(Throws([&] { pthread_mutexattr_setprioceiling_nid_postfix(&attr, 300); }));
    Require(Throws([&] { pthread_mutexattr_getprioceiling_nid_postfix(&attr, &ceiling); }));
    return 0;
}
