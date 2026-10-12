#include "prx/libc/include/general/VabiMacros.hpp"
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <limits>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <system_error>
#include <thread>

namespace {

constexpr int threadSuccess = 0;
constexpr int threadNomem = 1;
constexpr int threadBusy = 3;
constexpr int threadError = 4;

constexpr int mutexRecursive = 0x100;

constexpr std::uint64_t mutexTag = 0x5854'4D5F'4D54'5844ull;
constexpr std::uint64_t conditionTag = 0x5854'4E43'5F44'4E43ull;

struct DinkumwareMutex {
    std::uint64_t tag = mutexTag;
    int type = 0;
    int count = 0;
    std::atomic<std::thread::id> owner{};
    std::mutex native;
};

struct DinkumwareCondition {
    std::uint64_t tag = conditionTag;
    std::condition_variable native;
};

DinkumwareMutex* ResolveMutex(void** handle, const char* function) {
    if (!handle)
        throw std::invalid_argument(std::string(function) + ": null mutex handle pointer");
    auto* mutex = static_cast<DinkumwareMutex*>(*handle);
    if (!mutex)
        throw std::invalid_argument(std::string(function) + ": null mutex handle");
    if (mutex->tag != mutexTag)
        throw std::invalid_argument(std::string(function) + ": not a mutex created by _Mtx_init");
    return mutex;
}

DinkumwareCondition* ResolveCondition(void** handle, const char* function) {
    if (!handle)
        throw std::invalid_argument(std::string(function) + ": null condition handle pointer");
    auto* condition = static_cast<DinkumwareCondition*>(*handle);
    if (!condition)
        throw std::invalid_argument(std::string(function) + ": null condition handle");
    if (condition->tag != conditionTag)
        throw std::invalid_argument(std::string(function) + ": not a condition created by _Cnd_init");
    return condition;
}

bool IsOwnedByCaller(const DinkumwareMutex* mutex) {
    return mutex->owner.load(std::memory_order_acquire) == std::this_thread::get_id() && mutex->count > 0;
}

}

extern "C" {

int APS5_VABI _Mtx_init_nid_postfix(void** handle, int type) {
    if (!handle)
        throw std::invalid_argument("_Mtx_init: null handle pointer");
    *handle = nullptr;
    auto* mutex = new (std::nothrow) DinkumwareMutex();
    if (!mutex)
        return threadNomem;
    mutex->type = type;
    *handle = mutex;
    return threadSuccess;
}

void APS5_VABI _Mtx_destroy_nid_postfix(void** handle) {
    if (!handle)
        throw std::invalid_argument("_Mtx_destroy: null mutex handle pointer");
    if (!*handle)
        return;
    auto* mutex = ResolveMutex(handle, "_Mtx_destroy");
    if (mutex->count != 0)
        throw std::logic_error("_Mtx_destroy: mutex destroyed while locked");
    mutex->tag = 0;
    delete mutex;
    *handle = nullptr;
}

int APS5_VABI _Mtx_lock_nid_postfix(void** handle) {
    auto* mutex = ResolveMutex(handle, "_Mtx_lock");
    const auto self = std::this_thread::get_id();
    if (mutex->owner.load(std::memory_order_acquire) == self) {
        if ((mutex->type & mutexRecursive) == 0)
            return threadBusy;
        if (mutex->count == std::numeric_limits<int>::max())
            throw std::overflow_error("_Mtx_lock: recursive lock count overflow");
        ++mutex->count;
        return threadSuccess;
    }
    try {
        mutex->native.lock();
    } catch (const std::system_error& error) {
        return error.code() == std::errc::resource_deadlock_would_occur ? threadBusy : threadError;
    }
    mutex->owner.store(self, std::memory_order_release);
    mutex->count = 1;
    return threadSuccess;
}

int APS5_VABI _Mtx_unlock_nid_postfix(void** handle) {
    auto* mutex = ResolveMutex(handle, "_Mtx_unlock");
    if (!IsOwnedByCaller(mutex))
        return threadSuccess;
    if (--mutex->count == 0) {
        mutex->owner.store(std::thread::id{}, std::memory_order_release);
        mutex->native.unlock();
    }
    return threadSuccess;
}

int APS5_VABI _Cnd_init_nid_postfix(void** handle) {
    if (!handle)
        throw std::invalid_argument("_Cnd_init: null handle pointer");
    *handle = nullptr;
    auto* condition = new (std::nothrow) DinkumwareCondition();
    if (!condition)
        return threadNomem;
    *handle = condition;
    return threadSuccess;
}

void APS5_VABI _Cnd_destroy_nid_postfix(void** handle) {
    if (!handle)
        throw std::invalid_argument("_Cnd_destroy: null condition handle pointer");
    if (!*handle)
        return;
    auto* condition = ResolveCondition(handle, "_Cnd_destroy");
    condition->tag = 0;
    delete condition;
    *handle = nullptr;
}

int APS5_VABI _Cnd_wait_nid_postfix(void** conditionHandle, void** mutexHandle) {
    auto* condition = ResolveCondition(conditionHandle, "_Cnd_wait");
    auto* mutex = ResolveMutex(mutexHandle, "_Cnd_wait");
    if (!IsOwnedByCaller(mutex))
        return threadSuccess;
    if (mutex->count != 1)
        return threadSuccess;
    mutex->count = 0;
    mutex->owner.store(std::thread::id{}, std::memory_order_release);
    std::unique_lock lock(mutex->native, std::adopt_lock);
    try {
        condition->native.wait(lock);
    } catch (const std::system_error&) {
        lock.release();
        mutex->owner.store(std::this_thread::get_id(), std::memory_order_release);
        mutex->count = 1;
        throw;
    }
    lock.release();
    mutex->owner.store(std::this_thread::get_id(), std::memory_order_release);
    mutex->count = 1;
    return threadSuccess;
}

int APS5_VABI _Cnd_broadcast_nid_postfix(void** handle) {
    ResolveCondition(handle, "_Cnd_broadcast")->native.notify_all();
    return threadSuccess;
}

// _Cnd_signal is exported by libSceAmpr, which shares the conditions created here.
int SignalCondition_nid_no_patch(void** handle) {
    ResolveCondition(handle, "_Cnd_signal")->native.notify_one();
    return threadSuccess;
}

}
