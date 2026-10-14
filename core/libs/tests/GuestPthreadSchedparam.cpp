#include "SceTypes.hpp"
#include <cstdlib>
#include <initializer_list>

extern "C" {
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
Pthread APS5_VABI scePthreadSelf(void);
int APS5_VABI scePthreadGetschedparam(Pthread thread, int* policy, KernelSchedParam* param);
int APS5_VABI scePthreadSetschedparam(Pthread thread, int policy, const KernelSchedParam* param);
int APS5_VABI pthread_getschedparam_nid_postfix(Pthread thread, int* policy, KernelSchedParam* param);
int APS5_VABI pthread_setschedparam_nid_postfix(Pthread thread, int policy, const KernelSchedParam* param);
int APS5_VABI scePthreadAttrInit(PthreadAttr* attr);
int APS5_VABI scePthreadAttrDestroy(PthreadAttr* attr);
int APS5_VABI scePthreadAttrSetinheritsched(PthreadAttr* attr, int inheritSched);
int APS5_VABI scePthreadAttrSetschedpolicy(PthreadAttr* attr, int policy);
}

static constexpr int SCE_OK = 0;
static constexpr int SCE_KERNEL_ERROR_EINVAL = static_cast<int>(0x80020016);
static constexpr int GUEST_EINVAL = 22;
static constexpr int SCHED_FIFO = 1;
static constexpr int SCHED_OTHER = 2;
static constexpr int SCHED_RR = 3;
static constexpr int EXPLICIT_SCHED = 0;
static constexpr int INHERIT_SCHED = 4;

static void Require(bool value) { if (!value) std::abort(); }

static void RequireSched(int policy, int priority) {
    int current = -1;
    KernelSchedParam param{};
    Require(scePthreadGetschedparam(scePthreadSelf(), &current, &param) == SCE_OK);
    Require(current == policy && param.sched_priority == priority);
    current = -1;
    param.sched_priority = -1;
    Require(pthread_getschedparam_nid_postfix(scePthreadSelf(), &current, &param) == 0);
    Require(current == policy && param.sched_priority == priority);
}

static int SceSet(int policy, int priority) {
    const KernelSchedParam param{priority};
    return scePthreadSetschedparam(scePthreadSelf(), policy, &param);
}

static int PosixSet(int policy, int priority) {
    const KernelSchedParam param{priority};
    return pthread_setschedparam_nid_postfix(scePthreadSelf(), policy, &param);
}

static void* APS5_VABI Run(void*) {
    int policy = -1;
    KernelSchedParam param{};
    Require(scePthreadGetschedparam(scePthreadSelf(), &policy, &param) == SCE_OK);
    Require(policy == SCHED_FIFO);

    for (int priority : {256, 767, 896, 959}) {
        Require(SceSet(SCHED_FIFO, priority) == SCE_OK);
        RequireSched(SCHED_FIFO, priority);
    }
    for (int priority : {-1, 0, 255, 768, 895, 960, 1023, 4096}) {
        Require(SceSet(SCHED_FIFO, priority) == SCE_KERNEL_ERROR_EINVAL);
        Require(PosixSet(SCHED_FIFO, priority) == GUEST_EINVAL);
        RequireSched(SCHED_FIFO, 959);
    }

    Require(SceSet(SCHED_RR, 300) == SCE_OK);
    RequireSched(SCHED_RR, 300);
    for (int other : {-1, 0, SCHED_OTHER, 4}) {
        Require(SceSet(other, 700) == SCE_KERNEL_ERROR_EINVAL);
        Require(PosixSet(other, 700) == GUEST_EINVAL);
        RequireSched(SCHED_RR, 300);
    }
    Require(PosixSet(SCHED_FIFO, 700) == 0);
    RequireSched(SCHED_FIFO, 700);
    Require(scePthreadSetschedparam(scePthreadSelf(), SCHED_FIFO, nullptr) == SCE_KERNEL_ERROR_EINVAL);
    return nullptr;
}

static void* APS5_VABI ReportPolicy(void* arg) {
    int policy = -1;
    KernelSchedParam param{};
    Require(scePthreadGetschedparam(scePthreadSelf(), &policy, &param) == SCE_OK);
    *static_cast<int*>(arg) = policy;
    return nullptr;
}

static int CreatedPolicy(int inheritSched, int policy) {
    PthreadAttr attr = nullptr;
    Require(scePthreadAttrInit(&attr) == SCE_OK);
    Require(scePthreadAttrSetinheritsched(&attr, inheritSched) == SCE_OK);
    Require(scePthreadAttrSetschedpolicy(&attr, policy) == SCE_OK);
    int reported = -1;
    Pthread thread = nullptr;
    Require(scePthreadCreate(&thread, &attr, ReportPolicy, &reported, "policy") == SCE_OK);
    Require(scePthreadJoin(thread, nullptr) == SCE_OK);
    Require(scePthreadAttrDestroy(&attr) == SCE_OK);
    return reported;
}

int main() {
    Pthread thread = nullptr;
    Require(scePthreadCreate(&thread, nullptr, Run, nullptr, "schedparam") == SCE_OK);
    Require(scePthreadJoin(thread, nullptr) == SCE_OK);
    Require(CreatedPolicy(EXPLICIT_SCHED, SCHED_RR) == SCHED_RR);
    Require(CreatedPolicy(EXPLICIT_SCHED, SCHED_FIFO) == SCHED_FIFO);
    Require(CreatedPolicy(INHERIT_SCHED, SCHED_RR) == SCHED_FIFO);
}
