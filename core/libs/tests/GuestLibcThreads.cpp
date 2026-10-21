#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <thread>

extern "C" {
int APS5_VABI _Mtx_init_nid_postfix(void** handle, int type);
void APS5_VABI _Mtx_destroy_nid_postfix(void** handle);
int APS5_VABI _Mtx_lock_nid_postfix(void** handle);
int APS5_VABI _Mtx_unlock_nid_postfix(void** handle);
int APS5_VABI _Cnd_init_nid_postfix(void** handle);
void APS5_VABI _Cnd_destroy_nid_postfix(void** handle);
int APS5_VABI _Cnd_wait_nid_postfix(void** condition, void** mutex);
int APS5_VABI _Cnd_broadcast_nid_postfix(void** handle);
int APS5_VABI _Cnd_signal_nid_postfix(void** handle);

struct GuestPad {
    unsigned (APS5_VABI* const* vtable)(GuestPad*);
    void* condition;
    void* mutex;
    bool started;
};

void APS5_VABI _ZNSt4_PadC2Ev_nid_postfix(GuestPad* pad);
void APS5_VABI _ZNSt4_PadD2Ev_nid_postfix(GuestPad* pad);
void APS5_VABI _ZNSt4_Pad8_ReleaseEv_nid_postfix(GuestPad* pad);
void APS5_VABI _ZNSt4_Pad7_LaunchEPP7pthread_nid_postfix(GuestPad* pad, void** thread);
int APS5_VABI _Thrd_join_nid_postfix(void* thread, int* code);
int APS5_VABI _Thrd_detach_nid_postfix(void* thread);
void RegisterPthreadCreate_nid_no_patch(int (APS5_VABI* fn)(void**, const void*, void* (APS5_VABI*)(void*), void*));
void RegisterPthreadJoin_nid_no_patch(int (APS5_VABI* fn)(void*, void**));
void RegisterPthreadDetach_nid_no_patch(int (APS5_VABI* fn)(void*));
}

static void Require(bool value) { if (!value) std::abort(); }

template<typename TException, typename TCall>
static void RequireThrows(TCall call) {
    try {
        call();
    } catch (const TException&) {
        return;
    }
    std::abort();
}

constexpr int success = 0;
constexpr int busy = 3;
constexpr int plain = 0x01;
constexpr int tryable = 0x02;
constexpr int timed = 0x04;
constexpr int recursive = 0x100;

static void* CreateMutex(int type) {
    void* mutex = reinterpret_cast<void*>(std::uintptr_t{1});
    Require(_Mtx_init_nid_postfix(&mutex, type) == success && mutex != nullptr);
    return mutex;
}

static void MutexBasics() {
    void* mutex = CreateMutex(tryable);
    Require(_Mtx_lock_nid_postfix(&mutex) == success);
    Require(_Mtx_lock_nid_postfix(&mutex) == busy);
    RequireThrows<std::logic_error>([&] { _Mtx_destroy_nid_postfix(&mutex); });
    std::thread([&] { Require(_Mtx_unlock_nid_postfix(&mutex) == success); }).join();
    Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    void* invalidMutex = nullptr;
    RequireThrows<std::invalid_argument>([&] { _Mtx_lock_nid_postfix(&invalidMutex); });
    void* foreignCondition = nullptr;
    Require(_Cnd_init_nid_postfix(&foreignCondition) == success && foreignCondition != nullptr);
    void* foreignMutex = foreignCondition;
    RequireThrows<std::invalid_argument>([&] { _Mtx_lock_nid_postfix(&foreignMutex); });
    _Cnd_destroy_nid_postfix(&foreignCondition);
    _Mtx_destroy_nid_postfix(&mutex);
    Require(mutex == nullptr);
    RequireThrows<std::invalid_argument>([&] { _Mtx_lock_nid_postfix(&mutex); });
    void* emptyMutex = nullptr;
    _Mtx_destroy_nid_postfix(&emptyMutex);
    RequireThrows<std::invalid_argument>([] { _Mtx_destroy_nid_postfix(nullptr); });

    void* plainMutex = CreateMutex(plain);
    Require(_Mtx_lock_nid_postfix(&plainMutex) == success && _Mtx_lock_nid_postfix(&plainMutex) == busy);
    Require(_Mtx_unlock_nid_postfix(&plainMutex) == success);
    _Mtx_destroy_nid_postfix(&plainMutex);

    void* timedMutex = CreateMutex(timed | tryable);
    Require(_Mtx_lock_nid_postfix(&timedMutex) == success && _Mtx_lock_nid_postfix(&timedMutex) == busy);
    Require(_Mtx_unlock_nid_postfix(&timedMutex) == success);
    _Mtx_destroy_nid_postfix(&timedMutex);

    void* defaultMutex = nullptr;
    Require(_Mtx_init_nid_postfix(&defaultMutex, 0) == success && defaultMutex != nullptr);
    Require(_Mtx_lock_nid_postfix(&defaultMutex) == success && _Mtx_lock_nid_postfix(&defaultMutex) == busy);
    Require(_Mtx_unlock_nid_postfix(&defaultMutex) == success);
    _Mtx_destroy_nid_postfix(&defaultMutex);
    void* unknownBitsMutex = nullptr;
    Require(_Mtx_init_nid_postfix(&unknownBitsMutex, tryable | 0x8) == success && unknownBitsMutex != nullptr);
    Require(_Mtx_lock_nid_postfix(&unknownBitsMutex) == success && _Mtx_lock_nid_postfix(&unknownBitsMutex) == busy);
    Require(_Mtx_unlock_nid_postfix(&unknownBitsMutex) == success);
    _Mtx_destroy_nid_postfix(&unknownBitsMutex);
    RequireThrows<std::invalid_argument>([] { _Mtx_init_nid_postfix(nullptr, tryable); });
    RequireThrows<std::invalid_argument>([] { _Mtx_lock_nid_postfix(nullptr); });
    RequireThrows<std::invalid_argument>([] { _Mtx_unlock_nid_postfix(nullptr); });
}

static void RecursiveMutex() {
    void* mutex = CreateMutex(tryable | recursive);
    for (int i = 0; i < 3; ++i) Require(_Mtx_lock_nid_postfix(&mutex) == success);
    std::atomic<bool> acquired{false};
    std::thread other([&] {
        Require(_Mtx_lock_nid_postfix(&mutex) == success);
        acquired = true;
        Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    });
    for (int i = 0; i < 2; ++i) Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    Require(!acquired);
    Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    other.join();
    Require(acquired);
    _Mtx_destroy_nid_postfix(&mutex);
}

static void MutualExclusion() {
    void* mutex = CreateMutex(tryable);
    long counter = 0;
    std::array<std::thread, 4> workers;
    for (auto& worker : workers) worker = std::thread([&] {
        for (int i = 0; i < 20000; ++i) {
            Require(_Mtx_lock_nid_postfix(&mutex) == success);
            ++counter;
            Require(_Mtx_unlock_nid_postfix(&mutex) == success);
        }
    });
    for (auto& worker : workers) worker.join();
    Require(counter == 80000);
    _Mtx_destroy_nid_postfix(&mutex);
}

static void ConditionBroadcast() {
    void* condition = reinterpret_cast<void*>(std::uintptr_t{1});
    Require(_Cnd_init_nid_postfix(&condition) == success && condition != nullptr);
    void* mutex = CreateMutex(tryable);
    bool ready = false;
    int waiting = 0, woken = 0;
    std::array<std::thread, 2> waiters;
    for (auto& waiter : waiters) waiter = std::thread([&] {
        Require(_Mtx_lock_nid_postfix(&mutex) == success);
        ++waiting;
        while (!ready) Require(_Cnd_wait_nid_postfix(&condition, &mutex) == success);
        ++woken;
        Require(_Mtx_lock_nid_postfix(&mutex) == busy);
        Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    });
    for (;;) {
        Require(_Mtx_lock_nid_postfix(&mutex) == success);
        const bool all = waiting == 2;
        Require(_Mtx_unlock_nid_postfix(&mutex) == success);
        if (all) break;
        std::this_thread::yield();
    }
    Require(_Mtx_lock_nid_postfix(&mutex) == success);
    ready = true;
    Require(_Cnd_broadcast_nid_postfix(&condition) == success);
    Require(_Mtx_unlock_nid_postfix(&mutex) == success);
    for (auto& waiter : waiters) waiter.join();
    Require(woken == 2);
    Require(_Cnd_broadcast_nid_postfix(&condition) == success);

    Require(_Cnd_wait_nid_postfix(&condition, &mutex) == success);
    void* recursiveMutex = CreateMutex(tryable | recursive);
    Require(_Mtx_lock_nid_postfix(&recursiveMutex) == success && _Mtx_lock_nid_postfix(&recursiveMutex) == success);
    Require(_Cnd_wait_nid_postfix(&condition, &recursiveMutex) == success);
    Require(_Mtx_unlock_nid_postfix(&recursiveMutex) == success && _Mtx_unlock_nid_postfix(&recursiveMutex) == success);
    _Mtx_destroy_nid_postfix(&recursiveMutex);

    RequireThrows<std::invalid_argument>([&] { _Cnd_wait_nid_postfix(&mutex, &mutex); });
    void* invalidCondition = nullptr;
    RequireThrows<std::invalid_argument>([&] { _Cnd_broadcast_nid_postfix(&invalidCondition); });
    RequireThrows<std::invalid_argument>([] { _Cnd_broadcast_nid_postfix(nullptr); });
    RequireThrows<std::invalid_argument>([] { _Cnd_init_nid_postfix(nullptr); });
    _Cnd_destroy_nid_postfix(&condition);
    Require(condition == nullptr);
    RequireThrows<std::invalid_argument>([&] { _Cnd_broadcast_nid_postfix(&condition); });
    void* emptyCondition = nullptr;
    _Cnd_destroy_nid_postfix(&emptyCondition);
    RequireThrows<std::invalid_argument>([] { _Cnd_destroy_nid_postfix(nullptr); });
    _Mtx_destroy_nid_postfix(&mutex);
}

static void ConditionSignal() {
    void* condition = nullptr;
    Require(_Cnd_init_nid_postfix(&condition) == success);
    Require(_Cnd_signal_nid_postfix(&condition) == success);
    _Cnd_destroy_nid_postfix(&condition);
}

struct TestPad {
    unsigned (APS5_VABI* const* vtable)(GuestPad*);
    void* condition;
    void* mutex;
    bool started;
    std::atomic<bool> ran{false};
};

struct HostPadThread {
    std::thread worker;
    void* result = nullptr;
};

static int APS5_VABI HostPthreadCreate(void** thread, const void*, void* (APS5_VABI* entry)(void*), void* arg) {
    auto* handle = new HostPadThread{};
    handle->worker = std::thread([handle, entry, arg] { handle->result = entry(arg); });
    *thread = handle;
    return 0;
}

static int APS5_VABI HostPthreadJoin(void* thread, void** value) {
    if (!thread) return 22;
    auto* handle = static_cast<HostPadThread*>(thread);
    handle->worker.join();
    if (value) *value = handle->result;
    delete handle;
    return 0;
}

static int APS5_VABI HostPthreadDetach(void* thread) {
    if (!thread) return 22;
    static_cast<HostPadThread*>(thread)->worker.detach();
    return 0;
}

static unsigned APS5_VABI TestPadGo(GuestPad* base) {
    auto* pad = reinterpret_cast<TestPad*>(base);
    pad->ran.store(true);
    _ZNSt4_Pad8_ReleaseEv_nid_postfix(base);
    return 42;
}

static void PadLaunchAndJoin() {
    unsigned (APS5_VABI* vtable[1])(GuestPad*) = {TestPadGo};
    TestPad unregPad{};
    unregPad.vtable = vtable;
    _ZNSt4_PadC2Ev_nid_postfix(reinterpret_cast<GuestPad*>(&unregPad));
    RegisterPthreadCreate_nid_no_patch(nullptr);
    RegisterPthreadJoin_nid_no_patch(nullptr);
    void* unregThread = nullptr;
    RequireThrows<std::runtime_error>([&] {
        _ZNSt4_Pad7_LaunchEPP7pthread_nid_postfix(reinterpret_cast<GuestPad*>(&unregPad), &unregThread);
    });
    RequireThrows<std::runtime_error>([&] {
        int code = 0;
        _Thrd_join_nid_postfix(&unregPad, &code);
    });
    _ZNSt4_PadD2Ev_nid_postfix(reinterpret_cast<GuestPad*>(&unregPad));

    RegisterPthreadCreate_nid_no_patch(HostPthreadCreate);
    RegisterPthreadJoin_nid_no_patch(HostPthreadJoin);

    TestPad pad{};
    pad.vtable = vtable;
    _ZNSt4_PadC2Ev_nid_postfix(reinterpret_cast<GuestPad*>(&pad));
    void* thread = nullptr;
    _ZNSt4_Pad7_LaunchEPP7pthread_nid_postfix(reinterpret_cast<GuestPad*>(&pad), &thread);
    Require(thread != nullptr && pad.started && pad.ran.load());
    _ZNSt4_PadD2Ev_nid_postfix(reinterpret_cast<GuestPad*>(&pad));
    int code = 0;
    Require(_Thrd_join_nid_postfix(thread, &code) == success && code == 42);
    Require(_Thrd_join_nid_postfix(nullptr, &code) == 4);

    RegisterPthreadCreate_nid_no_patch(nullptr);
    RegisterPthreadJoin_nid_no_patch(nullptr);
}

static void PadDetach() {
    unsigned (APS5_VABI* vtable[1])(GuestPad*) = {TestPadGo};
    RegisterPthreadDetach_nid_no_patch(nullptr);
    RequireThrows<std::runtime_error>([] { _Thrd_detach_nid_postfix(nullptr); });

    RegisterPthreadCreate_nid_no_patch(HostPthreadCreate);
    RegisterPthreadDetach_nid_no_patch(HostPthreadDetach);

    TestPad pad{};
    pad.vtable = vtable;
    _ZNSt4_PadC2Ev_nid_postfix(reinterpret_cast<GuestPad*>(&pad));
    void* thread = nullptr;
    _ZNSt4_Pad7_LaunchEPP7pthread_nid_postfix(reinterpret_cast<GuestPad*>(&pad), &thread);
    Require(thread != nullptr && pad.ran.load());
    _ZNSt4_PadD2Ev_nid_postfix(reinterpret_cast<GuestPad*>(&pad));
    Require(_Thrd_detach_nid_postfix(thread) == success);
    Require(_Thrd_detach_nid_postfix(nullptr) == 4);

    RegisterPthreadCreate_nid_no_patch(nullptr);
    RegisterPthreadDetach_nid_no_patch(nullptr);
}

int main() {
    MutexBasics();
    RecursiveMutex();
    MutualExclusion();
    ConditionBroadcast();
    ConditionSignal();
    PadLaunchAndJoin();
    PadDetach();
}
