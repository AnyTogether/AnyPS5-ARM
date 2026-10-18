#ifndef CORE_LIBS_PRX_LIBC_INCLUDE_GENERAL_ATOMICSHAREDPTR_HPP
#define CORE_LIBS_PRX_LIBC_INCLUDE_GENERAL_ATOMICSHAREDPTR_HPP

#include <atomic>
#include <memory>
#include <utility>

// std::atomic<std::shared_ptr<T>> is C++20, but libc++ does not ship it yet. There the shared_ptr
// atomic free functions (deprecated in C++20, still provided) give the same load/store/exchange/compare-exchange.
#if defined(__cpp_lib_atomic_shared_ptr)
template <class T>
using AtomicSharedPtr = std::atomic<std::shared_ptr<T>>;
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
template <class T>
class AtomicSharedPtr {
public:
    AtomicSharedPtr() noexcept = default;
    AtomicSharedPtr(std::shared_ptr<T> desired) noexcept : value(std::move(desired)) {}
    AtomicSharedPtr(const AtomicSharedPtr&) = delete;
    AtomicSharedPtr& operator=(const AtomicSharedPtr&) = delete;

    std::shared_ptr<T> load(std::memory_order order = std::memory_order_seq_cst) const noexcept {
        return std::atomic_load_explicit(&value, order);
    }
    void store(std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        std::atomic_store_explicit(&value, std::move(desired), order);
    }
    std::shared_ptr<T> exchange(std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        return std::atomic_exchange_explicit(&value, std::move(desired), order);
    }
    bool compare_exchange_strong(std::shared_ptr<T>& expected, std::shared_ptr<T> desired, std::memory_order order = std::memory_order_seq_cst) noexcept {
        return std::atomic_compare_exchange_strong_explicit(&value, &expected, std::move(desired), order, order == std::memory_order_acq_rel ? std::memory_order_acquire : order == std::memory_order_release ? std::memory_order_relaxed : order);
    }
    operator std::shared_ptr<T>() const noexcept { return load(); }
    void operator=(std::shared_ptr<T> desired) noexcept { store(std::move(desired)); }

private:
    std::shared_ptr<T> value;
};
#pragma clang diagnostic pop
#endif

#endif
