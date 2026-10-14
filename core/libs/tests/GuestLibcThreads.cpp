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

int main() {
    MutexBasics();
    RecursiveMutex();
    MutualExclusion();
    ConditionBroadcast();
    ConditionSignal();
}
