#include <cstdint>
#include <cstddef>
#include <cstring>
#include "SceTypes.hpp"
#include "../include/ThreadLifecycle.hpp"
#include "../include/Cancel.hpp"
#include "prx/libc/include/General.hpp"
#include "../include/Pthread.hpp"
#include "Common.hpp"
#include "prx/libkernel/KernelErrors.hpp"
#include <chrono>
#include <cstring>
#include <thread>

extern "C" {
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadDetach(Pthread thread);
void APS5_VABI scePthreadExit(void* retval);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
int APS5_VABI scePthreadRename(Pthread thread, const char* name);
int APS5_VABI scePthreadGetname(Pthread thread, char* name);
Pthread APS5_VABI scePthreadSelf();
int APS5_VABI scePthreadCancel(Pthread thread);
int APS5_VABI scePthreadSetcancelstate(int state, int* old_state);
int APS5_VABI scePthreadSetcanceltype(int type, int* old_type);
void APS5_VABI scePthreadTestcancel();
int APS5_VABI scePthreadSetprio(Pthread thread, int prio);
int APS5_VABI scePthreadGetprio(Pthread thread, int* prio);
}

static constexpr int GUEST_SCHED_FIFO = 1;
static constexpr std::size_t GUEST_CPUSET_BYTES = 32;
static constexpr int GUEST_ERANGE = 34;

extern "C" {
int* APS5_VABI __error_nid_postfix();
int APS5_VABI scePthreadGetaffinity(Pthread thread, KernelCpumask* mask);
int APS5_VABI scePthreadGetthreadid(void);
int APS5_VABI scePthreadSetaffinity(Pthread thread, KernelCpumask mask);
KernelCpumask APS5_VABI sceKernelGetAvailableCpumask(void);
int APS5_VABI getpid_nid_postfix(void);

// The root set and the cpuset hold every CPU the title may use, and the process's own set is the
// union of its live threads' masks; only the calling thread can be named by thread id, since guest
// threads are not indexed by id.
int APS5_VABI cpuset_getaffinity_nid_postfix(int level, int which, std::int64_t id, std::size_t size, void* mask) {
    constexpr int LevelRoot = 1, LevelCpuset = 2, LevelWhich = 3;
    constexpr int WhichThread = 1, WhichProcess = 2;
    constexpr int GuestEsrch = 3, GuestEfault = 14, GuestEinval = 22, GuestErange = 34;
    constexpr std::size_t MaximumSize = 256 / 8;
    const auto fail = [](int error) {
        *__error_nid_postfix() = error;
        return -1;
    };
    if (size < sizeof(KernelCpumask) || size > MaximumSize) return fail(GuestErange);
    if (level != LevelRoot && level != LevelCpuset && level != LevelWhich) return fail(GuestEinval);
    if (which != WhichThread && which != WhichProcess) return fail(GuestEinval);
    const bool self = id == -1 || (which == WhichThread ? id == scePthreadGetthreadid() : id == getpid_nid_postfix());
    if (!self) return fail(GuestEsrch);
    if (!mask) return fail(GuestEfault);
    KernelCpumask affinity = sceKernelGetAvailableCpumask();
    if (level == LevelWhich && which == WhichThread) scePthreadGetaffinity(scePthreadSelf(), &affinity);
    else if (level == LevelWhich && which == WhichProcess) {
        scePthreadSelf();
        affinity = LiveGuestThreadsAffinity();
    }
    std::memset(mask, 0, size);
    std::memcpy(mask, &affinity, sizeof(affinity));
    return 0;
}

int APS5_VABI cpuset_setaffinity_nid_postfix(int level, int which, std::int64_t id, std::size_t size, const void* mask) {
    constexpr int LevelWhich = 3, WhichThread = 1, WhichProcess = 2;
    constexpr int GuestEdeadlk = 11, GuestEfault = 14, GuestEinval = 22, GuestErange = 34;
    constexpr std::size_t MaximumSize = 256 / 8;
    const auto fail = [](int error) {
        *__error_nid_postfix() = error;
        return -1;
    };
    if (size < sizeof(KernelCpumask) || size > MaximumSize) return fail(GuestErange);
    if (!mask) return fail(GuestEfault);
    const auto* bytes = static_cast<const std::uint8_t*>(mask);
    for (std::size_t index = sizeof(KernelCpumask); index < size; ++index) {
        if (bytes[index] != 0) return fail(GuestEinval);
    }
    const bool thread = level == LevelWhich && which == WhichThread && id == -1;
    const bool process = level == LevelWhich && which == WhichProcess && (id == -1 || id == getpid_nid_postfix());
    if (!thread && !process) NotImplemented_nid_no_patch("cpuset_setaffinity other than the calling thread or process");
    KernelCpumask requested = 0;
    std::memcpy(&requested, bytes, sizeof(requested));
    const KernelCpumask affinity = requested & sceKernelGetAvailableCpumask();
    if (affinity == 0) return fail(GuestEdeadlk);
    if (thread) scePthreadSetaffinity(scePthreadSelf(), affinity);
    else SetLiveGuestThreadsAffinity(affinity);
    return 0;
}

int APS5_VABI pthread_create_nid_postfix(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg) {
    return PosixThread::ToErrno(scePthreadCreate(thread, attr, entry, arg, nullptr));
}

int APS5_VABI pthread_create_name_np_nid_postfix(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name) {
    return PosixThread::ToErrno(scePthreadCreate(thread, attr, entry, arg, name));
}

int APS5_VABI pthread_detach_nid_postfix(Pthread thread) {
    return PosixThread::ToErrno(scePthreadDetach(thread));
}

void APS5_VABI pthread_exit_nid_postfix(void* value) {
    scePthreadExit(value);
}

int APS5_VABI scePthreadGetschedparam(Pthread thread, int* policy, KernelSchedParam* param) {
    if (!policy || !param) return SCE_KERNEL_ERROR_EINVAL;
    *policy = GUEST_SCHED_FIFO;
    return scePthreadGetprio(thread, &param->sched_priority);
}

int APS5_VABI scePthreadSetschedparam(Pthread thread, int policy, const KernelSchedParam* param) {
    (void)policy;
    if (!param) return SCE_KERNEL_ERROR_EINVAL;
    return scePthreadSetprio(thread, param->sched_priority);
}

int APS5_VABI pthread_getschedparam_nid_postfix(Pthread thread, int* policy, KernelSchedParam* param) {
    if (!policy || !param) return PosixThread::GUEST_EINVAL;
    *policy = GUEST_SCHED_FIFO;
    return PosixThread::ToErrno(scePthreadGetprio(thread, &param->sched_priority));
}

int APS5_VABI pthread_getaffinity_np_nid_postfix(Pthread thread, std::size_t cpusetSize, void* cpuset) {
    if (!thread) return PosixThread::GUEST_EINVAL;
    if (cpusetSize != GUEST_CPUSET_BYTES) return GUEST_ERANGE;
    if (!cpuset) return PosixThread::GUEST_EFAULT;
    KernelCpumask mask = 0;
    const int result = scePthreadGetaffinity(thread, &mask);
    if (result != 0) return PosixThread::ToErrno(result);
    std::memset(cpuset, 0, GUEST_CPUSET_BYTES);
    std::memcpy(cpuset, &mask, sizeof(mask));
    return 0;
}

int APS5_VABI pthread_join_nid_postfix(Pthread thread, void** value) {
    return PosixThread::ToErrno(scePthreadJoin(thread, value));
}

int APS5_VABI pthread_rename_np_nid_postfix(Pthread thread, const char* name) {
    if (thread && name && std::strlen(name) >= 32) return PosixThread::ToErrno(SCE_KERNEL_ERROR_ENAMETOOLONG);
    return PosixThread::ToErrno(scePthreadRename(thread, name));
}

int APS5_VABI pthread_getname_np_nid_postfix(Pthread thread, char* name) {
    if (!thread) return PosixThread::GUEST_ESRCH;
    if (!name) return PosixThread::GUEST_EFAULT;
    return PosixThread::ToErrno(scePthreadGetname(thread, name));
}

void APS5_VABI pthread_set_name_np_nid_postfix(Pthread thread, const char* name) {
    scePthreadRename(thread, name != nullptr ? name : "");
}

Pthread APS5_VABI pthread_self_nid_postfix(void) {
    return scePthreadSelf();
}

int APS5_VABI scePthreadGetthreadid(void);

int APS5_VABI pthread_getthreadid_np_nid_postfix(void) {
    return scePthreadGetthreadid();
}

int APS5_VABI pthread_equal_nid_postfix(Pthread first, Pthread second) {
    return first == second;
}

int APS5_VABI pthread_getcpuclockid_nid_postfix(Pthread thread, int* clockId) {
    constexpr int guestFault = 14;
    if (!thread) return PosixThread::GUEST_EINVAL;
    if (!clockId) return guestFault;
    *clockId = GuestThreadCpuClockId(thread);
    return 0;
}

int APS5_VABI sched_yield_nid_postfix(void) {
    std::this_thread::yield();
    return 0;
}

int APS5_VABI pthread_cancel_nid_postfix(Pthread thread) {
    return PosixThread::ToErrno(scePthreadCancel(thread));
}

int APS5_VABI pthread_setcancelstate_nid_postfix(int state, int* old_state) {
    return PosixThread::ToErrno(scePthreadSetcancelstate(state, old_state));
}

int APS5_VABI pthread_setcanceltype_nid_postfix(int type, int* old_type) {
    return PosixThread::ToErrno(scePthreadSetcanceltype(type, old_type));
}

int APS5_VABI pthread_setprio_nid_postfix(Pthread thread, int prio) {
    return PosixThread::ToErrno(scePthreadSetprio(thread, prio));
}

int APS5_VABI pthread_setschedparam_nid_postfix(Pthread thread, int policy, const KernelSchedParam* param) {
    (void)policy;
    if (!param) return PosixThread::GUEST_EINVAL;
    return PosixThread::ToErrno(scePthreadSetprio(thread, param->sched_priority));
}

void APS5_VABI pthread_testcancel_nid_postfix(void) {
    scePthreadTestcancel();
}

void APS5_VABI pthread_yield_nid_postfix(void) {
    std::this_thread::yield();
}

unsigned int APS5_VABI sleep_nid_postfix(unsigned int seconds) {
    ThreadCancel::Check();
    std::this_thread::sleep_for(std::chrono::seconds(seconds));
    ThreadCancel::Check();
    return 0;
}

}
