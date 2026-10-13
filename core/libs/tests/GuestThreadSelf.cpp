#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#ifndef _WIN32
#include <signal.h>
#include <time.h>
#endif

extern "C" {
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
int APS5_VABI scePthreadDetach(Pthread thread);
int APS5_VABI pthread_join_nid_postfix(Pthread thread, void** value);
int APS5_VABI pthread_detach_nid_postfix(Pthread thread);
void APS5_VABI scePthreadExit(void* retval);
Pthread APS5_VABI scePthreadSelf();
int APS5_VABI scePthreadGetthreadid(void);
int APS5_VABI pthread_getthreadid_np_nid_postfix(void);
void APS5_VABI scePthreadTestcancel();
void APS5_VABI pthread_testcancel_nid_postfix(void);
int APS5_VABI scePthreadSetcancelstate(int state, int* old_state);
int APS5_VABI scePthreadSetcanceltype(int type, int* old_type);
void APS5_VABI pthread_set_name_np_nid_postfix(Pthread thread, const char* name);
int APS5_VABI scePthreadGetname(Pthread thread, char* name);
int APS5_VABI scePthreadMutexattrInit(PthreadMutexattr* attr);
int APS5_VABI scePthreadMutexattrDestroy(PthreadMutexattr* attr);
int APS5_VABI scePthreadMutexattrSettype(PthreadMutexattr* attr, int type);
int APS5_VABI scePthreadMutexInit(PthreadMutex* mutex, const PthreadMutexattr* attr, const char* name);
int APS5_VABI scePthreadMutexDestroy(PthreadMutex* mutex);
int APS5_VABI scePthreadMutexLock(PthreadMutex* mutex);
int APS5_VABI scePthreadMutexUnlock(PthreadMutex* mutex);
int APS5_VABI scePthreadAttrInit(PthreadAttr* attr);
int APS5_VABI scePthreadAttrDestroy(PthreadAttr* attr);
int APS5_VABI scePthreadAttrGet(Pthread thread, PthreadAttr* attr);
int APS5_VABI scePthreadAttrGetstackaddr(const PthreadAttr* attr, void** stack_addr);
int APS5_VABI scePthreadAttrGetstacksize(const PthreadAttr* attr, size_t* stack_size);
}

static bool StackContains(Pthread thread, const void* address) {
    PthreadAttr attr = nullptr;
    if (scePthreadAttrInit(&attr) != 0 || scePthreadAttrGet(thread, &attr) != 0) return false;
    void* stack = nullptr;
    size_t size = 0;
    const bool queried = scePthreadAttrGetstackaddr(&attr, &stack) == 0 && scePthreadAttrGetstacksize(&attr, &size) == 0;
    scePthreadAttrDestroy(&attr);
    const auto begin = reinterpret_cast<std::uintptr_t>(stack);
    const auto value = reinterpret_cast<std::uintptr_t>(address);
    return queried && stack != nullptr && size != 0 && value >= begin && value - begin < size;
}

static constexpr int SCE_OK = 0;
static constexpr int SCE_KERNEL_ERROR_EINVAL = 0x80020016;
static constexpr int SCE_KERNEL_ERROR_EPERM = 0x80020001;
static constexpr int SCE_KERNEL_ERROR_EDEADLK = 0x8002000b;
static constexpr int GUEST_EDEADLK = 11;
static constexpr int GUEST_EINVAL = 22;
static constexpr int MUTEX_TYPE_RECURSIVE = 2;
static constexpr int PTHREAD_CANCEL_ENABLE = 0;
static constexpr int PTHREAD_CANCEL_ASYNCHRONOUS = 2;
static constexpr std::intptr_t WorkerRetval = 0x1234;

static void Require(bool value) { if (!value) std::abort(); }

#ifndef _WIN32
// A write-watch fault is only delivered to a thread that has SIGSEGV and SIGBUS open.
static bool FaultSignalsOpen() {
    sigset_t mask;
    if (pthread_sigmask(SIG_SETMASK, nullptr, &mask) != 0) return false;
    return sigismember(&mask, SIGSEGV) == 0 && sigismember(&mask, SIGBUS) == 0;
}

static void* APS5_VABI FaultSignalsWorker(void* arg) {
    *static_cast<bool*>(arg) = FaultSignalsOpen();
    return nullptr;
}

// Creating threads leaves SIGSEGV and SIGBUS open on both sides. Under Rosetta the creator's mask
// fell back, some time after a creation, to the set it blocked around pthread_create.
static void CheckFaultSignalsStayOpen() {
    Require(FaultSignalsOpen());
    for (int round = 0; round < 32; ++round) {
        bool open = false;
        Pthread thread = nullptr;
        Require(scePthreadCreate(&thread, nullptr, FaultSignalsWorker, &open, nullptr) == SCE_OK);
        Require(scePthreadJoin(thread, nullptr) == SCE_OK);
        Require(open);
    }
    const timespec pause{0, 200'000'000};
    nanosleep(&pause, nullptr);
    Require(FaultSignalsOpen());
}
#endif

static std::int64_t ThreadIdField(Pthread thread) {
    std::int64_t tid = 0;
    std::memcpy(&tid, static_cast<const void*>(thread), sizeof(tid));
    return tid;
}

struct WorkerContext {
    Pthread thread = nullptr;
    Pthread selfFromWorker = nullptr;
    std::int64_t workerTid = 0;
    int workerThreadId = 0;
    int workerPosixThreadId = 0;
    bool workerStackReported = false;
    PthreadMutex* mutex = nullptr;
    int unlockResult = 0;
    bool testcancelReturned = false;
    int sceJoinSelf = 0;
    int posixJoinSelf = 0;
};

static void* APS5_VABI Worker(void* arg) {
    auto& context = *static_cast<WorkerContext*>(arg);
    context.selfFromWorker = scePthreadSelf();
    context.workerTid = ThreadIdField(context.selfFromWorker);
    context.workerThreadId = scePthreadGetthreadid();
    context.workerPosixThreadId = pthread_getthreadid_np_nid_postfix();
    int local = 0;
    context.workerStackReported = StackContains(context.selfFromWorker, &local);
    context.unlockResult = scePthreadMutexUnlock(context.mutex);
    context.sceJoinSelf = scePthreadJoin(context.selfFromWorker, nullptr);
    context.posixJoinSelf = pthread_join_nid_postfix(context.selfFromWorker, nullptr);
    int oldState = -1;
    int oldType = -1;
    context.testcancelReturned = scePthreadSetcancelstate(PTHREAD_CANCEL_ENABLE, &oldState) == SCE_OK &&
        scePthreadSetcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, &oldType) == SCE_OK;
    scePthreadTestcancel();
    pthread_testcancel_nid_postfix();
    context.testcancelReturned = context.testcancelReturned && oldState == PTHREAD_CANCEL_ENABLE;
    scePthreadExit(reinterpret_cast<void*>(WorkerRetval));
    return nullptr;
}

int main() {
    const Pthread mainSelf = scePthreadSelf();
    Require(mainSelf != nullptr);
    Require(scePthreadSelf() == mainSelf);
    const std::int64_t mainTid = ThreadIdField(mainSelf);
    Require(mainTid != 0);
    Require(scePthreadGetthreadid() == static_cast<int>(mainTid));
    Require(pthread_getthreadid_np_nid_postfix() == static_cast<int>(mainTid));
    int local = 0;
    Require(StackContains(mainSelf, &local));
    Require(scePthreadJoin(mainSelf, nullptr) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadDetach(mainSelf) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadJoin(nullptr, nullptr) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadDetach(nullptr) == SCE_KERNEL_ERROR_EINVAL);
    Require(pthread_join_nid_postfix(nullptr, nullptr) == GUEST_EINVAL);
    Require(pthread_detach_nid_postfix(nullptr) == GUEST_EINVAL);

    PthreadMutexattr attr = nullptr;
    Require(scePthreadMutexattrInit(&attr) == SCE_OK);
    Require(scePthreadMutexattrSettype(&attr, MUTEX_TYPE_RECURSIVE) == SCE_OK);
    PthreadMutex mutex = nullptr;
    Require(scePthreadMutexInit(&mutex, &attr, nullptr) == SCE_OK);
    Require(scePthreadMutexattrDestroy(&attr) == SCE_OK);

    Require(scePthreadMutexLock(&mutex) == SCE_OK);

    WorkerContext context;
    context.mutex = &mutex;
    Require(scePthreadCreate(&context.thread, nullptr, Worker, &context, nullptr) == SCE_OK);
    Require(context.thread != nullptr);
    Require(context.thread != mainSelf);

    void* result = nullptr;
    Require(scePthreadJoin(context.thread, &result) == SCE_OK);
    Require(reinterpret_cast<std::intptr_t>(result) == WorkerRetval);
    Require(context.selfFromWorker != nullptr);
    Require(context.selfFromWorker == context.thread);
    Require(context.selfFromWorker != mainSelf);
    Require(context.workerTid != 0 && context.workerTid != mainTid);
    Require(context.workerThreadId == static_cast<int>(context.workerTid));
    Require(context.workerPosixThreadId == context.workerThreadId && context.workerPosixThreadId != static_cast<int>(mainTid));
    Require(context.unlockResult == SCE_KERNEL_ERROR_EPERM);
    Require(context.sceJoinSelf == SCE_KERNEL_ERROR_EDEADLK);
    Require(context.posixJoinSelf == GUEST_EDEADLK);
    Require(context.workerStackReported);
    Require(context.testcancelReturned);

    scePthreadTestcancel();
    pthread_testcancel_nid_postfix();

    Require(scePthreadMutexUnlock(&mutex) == SCE_OK);
    Require(scePthreadMutexDestroy(&mutex) == SCE_OK);

    char name[32] = {'x'};
    pthread_set_name_np_nid_postfix(mainSelf, "q2-main");
    Require(scePthreadGetname(mainSelf, name) == SCE_OK && std::strcmp(name, "q2-main") == 0);
    pthread_set_name_np_nid_postfix(mainSelf, nullptr);
    Require(scePthreadGetname(mainSelf, name) == SCE_OK && name[0] == '\0');
    pthread_set_name_np_nid_postfix(nullptr, "ignored");
#ifndef _WIN32
    CheckFaultSignalsStayOpen();
#endif

}
