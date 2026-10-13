#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <system_error>
#include <thread>
#include <typeinfo>

struct GuestXtime {
    std::int64_t sec;
    std::int64_t nsec;
};

extern "C" {
int APS5_VABI _Thrd_join_nid_postfix(Pthread thread, int* code);
int APS5_VABI _Thrd_sleep_nid_postfix(const GuestXtime* target, GuestXtime* remaining);
void APS5_VABI _Lock_shared_ptr_spin_lock_nid_postfix(void);
void APS5_VABI _Unlock_shared_ptr_spin_lock_nid_postfix(void);
int APS5_VABI wcstombs_s_nid_postfix(std::size_t* result, char* destination, std::size_t capacity, const std::uint16_t* source, std::size_t limit);
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI pthread_detach_nid_postfix(Pthread thread);
int APS5_VABI clock_gettime_nid_postfix(int clockId, KernelTimespec* tp);
int APS5_VABI _Cnd_init_nid_postfix(void** handle);
int APS5_VABI _Cnd_init_with_name_nid_postfix(void** handle, const char* name);
int APS5_VABI _Cnd_signal_nid_postfix(void** handle);
int APS5_VABI _Cnd_broadcast_nid_postfix(void** handle);
int APS5_VABI _Cnd_wait_nid_postfix(void** condition, void** mutex);
void APS5_VABI _Cnd_destroy_nid_postfix(void** handle);
int APS5_VABI _Mtx_init_nid_postfix(void** handle, int type);
int APS5_VABI _Mtx_lock_nid_postfix(void** handle);
int APS5_VABI _Mtx_unlock_nid_postfix(void** handle);
void APS5_VABI _Mtx_destroy_nid_postfix(void** handle);
int APS5_VABI _Thrd_id_nid_postfix(void);
int APS5_VABI scePthreadGetthreadid(void);
void APS5_VABI _ZNSt4_PadC2Ev_nid_postfix(void* pad);
void APS5_VABI _ZNSt4_PadD2Ev_nid_postfix(void* pad);
void APS5_VABI _ZNSt4_Pad7_LaunchEPP7pthread_nid_postfix(void* pad, Pthread* thread);
void APS5_VABI _ZNSt4_Pad8_ReleaseEv_nid_postfix(void* pad);
extern std::uint64_t _ZNSt7num_getIcSt19istreambuf_iteratorIcSt11char_traitsIcEEE2idE_nid_postfix;
extern std::uint64_t _ZNSt8time_getIcSt19istreambuf_iteratorIcSt11char_traitsIcEEE2idE_nid_postfix;
extern void* _ZTVN10__cxxabiv119__pointer_type_infoE_nid_postfix[9];
extern void* _ZTVN10__cxxabiv120__function_type_infoE_nid_postfix[8];
}

static constexpr int ThrdSuccess = 0;
static constexpr int ThrdError = 4;
static constexpr int GuestEinval = 22;
static constexpr int GuestErange = 34;
static constexpr int GuestEilseq = 86;
static constexpr std::int64_t NanosPerSecond = 1000000000;
static constexpr auto Failed = static_cast<std::size_t>(-1);

#define Require(value) RequireAt((value), __LINE__)

static void RequireAt(bool value, int line) {
    if (value) return;
    std::fprintf(stderr, "requirement failed at line %d\n", line);
    std::abort();
}

static std::int64_t RealtimeNanos() {
    KernelTimespec now{};
    Require(clock_gettime_nid_postfix(0, &now) == 0);
    return now.tv_sec * NanosPerSecond + now.tv_nsec;
}

static GuestXtime XtimeAfter(std::int64_t nanos) {
    const auto target = RealtimeNanos() + nanos;
    return {target / NanosPerSecond, target % NanosPerSecond};
}

static void* APS5_VABI ReturnArgument(void* arg) {
    return arg;
}

static void* APS5_VABI WaitForRelease(void* arg) {
    auto* release = static_cast<std::atomic<bool>*>(arg);
    while (!release->load()) std::this_thread::yield();
    return nullptr;
}

struct SpinContext {
    std::atomic<int> inside{0};
    std::atomic<bool> overlapped{false};
    int counter = 0;
};

static constexpr int SpinThreads = 4;
static constexpr int SpinIterations = 20000;

static void* APS5_VABI SpinWorker(void* arg) {
    auto& context = *static_cast<SpinContext*>(arg);
    for (int iteration = 0; iteration < SpinIterations; ++iteration) {
        _Lock_shared_ptr_spin_lock_nid_postfix();
        if (context.inside.fetch_add(1) != 0) context.overlapped = true;
        ++context.counter;
        context.inside.fetch_sub(1);
        _Unlock_shared_ptr_spin_lock_nid_postfix();
    }
    return nullptr;
}

static Pthread Start(PthreadEntry entry, void* arg) {
    Pthread thread = nullptr;
    Require(scePthreadCreate(&thread, nullptr, entry, arg, nullptr) == 0);
    return thread;
}

static void TestThreadJoin() {
    int code = 0;
    Require(_Thrd_join_nid_postfix(Start(ReturnArgument, reinterpret_cast<void*>(std::intptr_t{42})), &code) == ThrdSuccess);
    Require(code == 42);
    code = 0;
    Require(_Thrd_join_nid_postfix(Start(ReturnArgument, reinterpret_cast<void*>(std::intptr_t{-7})), &code) == ThrdSuccess);
    Require(code == -7);
    code = 5;
    Require(_Thrd_join_nid_postfix(Start(ReturnArgument, reinterpret_cast<void*>(std::intptr_t{0x100000003})), &code) == ThrdSuccess);
    Require(code == 3);
    Require(_Thrd_join_nid_postfix(Start(ReturnArgument, nullptr), nullptr) == ThrdSuccess);

    static std::atomic<bool> release{false};
    const auto detached = Start(WaitForRelease, &release);
    Require(pthread_detach_nid_postfix(detached) == 0);
    code = 9;
    Require(_Thrd_join_nid_postfix(detached, &code) == ThrdError);
    Require(code == 9);
    release = true;
}

static void TestThreadSleep() {
    const auto target = XtimeAfter(50000000);
    Require(_Thrd_sleep_nid_postfix(&target, nullptr) == 0);
    Require(RealtimeNanos() >= target.sec * NanosPerSecond + target.nsec);

    const auto past = XtimeAfter(-NanosPerSecond);
    const auto before = RealtimeNanos();
    Require(_Thrd_sleep_nid_postfix(&past, nullptr) == 0);
    Require(RealtimeNanos() - before < NanosPerSecond / 2);

    const auto carried = XtimeAfter(30000000);
    const GuestXtime unnormalized{carried.sec - 2, carried.nsec + 2 * NanosPerSecond};
    Require(_Thrd_sleep_nid_postfix(&unnormalized, nullptr) == 0);
    Require(RealtimeNanos() >= carried.sec * NanosPerSecond + carried.nsec);

    const auto borrowed = XtimeAfter(20000000);
    const GuestXtime negative{borrowed.sec + 1, borrowed.nsec - NanosPerSecond};
    Require(_Thrd_sleep_nid_postfix(&negative, nullptr) == 0);
    Require(RealtimeNanos() >= borrowed.sec * NanosPerSecond + borrowed.nsec);

    bool rejected = false;
    try {
        _Thrd_sleep_nid_postfix(nullptr, nullptr);
    } catch (const std::invalid_argument&) {
        rejected = true;
    }
    Require(rejected);
}

static void TestSpinLock() {
    SpinContext context;
    std::array<Pthread, SpinThreads> threads{};
    for (auto& thread : threads) thread = Start(SpinWorker, &context);
    for (auto thread : threads) Require(_Thrd_join_nid_postfix(thread, nullptr) == ThrdSuccess);
    Require(!context.overlapped);
    Require(context.counter == SpinThreads * SpinIterations);
    _Lock_shared_ptr_spin_lock_nid_postfix();
    _Unlock_shared_ptr_spin_lock_nid_postfix();
}

static void TestWcstombs() {
    const std::uint16_t text[] = {u'a', u'b', u'c', 0};
    const std::uint16_t wide[] = {u'a', 0x100, 0};
    std::size_t result = 0;
    char buffer[8];

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(&result, buffer, sizeof(buffer), text, sizeof(buffer)) == 0);
    Require(result == 3 && std::strcmp(buffer, "abc") == 0);

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(&result, buffer, sizeof(buffer), text, 2) == 0);
    Require(result == 2 && std::strcmp(buffer, "ab") == 0);

    result = 0;
    Require(wcstombs_s_nid_postfix(&result, nullptr, 0, text, 0) == 0);
    Require(result == 3);

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(&result, buffer, 3, text, 3) == GuestErange);
    Require(result == Failed && buffer[0] == '\0');

    result = 0;
    Require(wcstombs_s_nid_postfix(&result, nullptr, 4, text, 4) == GuestEinval);
    Require(result == Failed);

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(&result, buffer, sizeof(buffer), nullptr, sizeof(buffer)) == GuestEinval);
    Require(result == Failed && buffer[0] == '\0');

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(nullptr, buffer, sizeof(buffer), text, sizeof(buffer)) == GuestEinval);
    Require(buffer[0] == '\0');

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(&result, buffer, 0, text, 4) == GuestEinval);
    Require(result == Failed && buffer[0] == 'x');

    std::memset(buffer, 'x', sizeof(buffer));
    Require(wcstombs_s_nid_postfix(&result, buffer, sizeof(buffer), wide, sizeof(buffer)) == GuestEilseq);
    Require(result == Failed && buffer[0] == 'a' && buffer[1] == '\0');

    Require(wcstombs_s_nid_postfix(&result, nullptr, 0, wide, 0) == GuestEilseq);
    Require(result == Failed);
}

struct Pad {
    void* const* vtable;
    void* condition;
    void* mutex;
    bool started;
    std::atomic<int> runner{0};
    std::atomic<bool> finish{false};
};

static unsigned APS5_VABI PadGo(Pad* pad) {
    pad->runner.store(_Thrd_id_nid_postfix());
    _ZNSt4_Pad8_ReleaseEv_nid_postfix(pad);
    while (!pad->finish.load()) std::this_thread::yield();
    return 7;
}

static void* const PadVtable[] = {reinterpret_cast<void*>(&PadGo)};

static void TestPad() {
    Pad pad{PadVtable, nullptr, nullptr, true};
    _ZNSt4_PadC2Ev_nid_postfix(&pad);
    Require(pad.condition != nullptr && pad.mutex != nullptr && !pad.started);
    Pthread thread = nullptr;
    _ZNSt4_Pad7_LaunchEPP7pthread_nid_postfix(&pad, &thread);
    Require(thread != nullptr && pad.started && pad.runner.load() != 0 && pad.runner.load() != _Thrd_id_nid_postfix());
    pad.finish.store(true);
    int code = 0;
    Require(_Thrd_join_nid_postfix(thread, &code) == ThrdSuccess && code == 7);
    _ZNSt4_PadD2Ev_nid_postfix(&pad);
    Require(pad.condition == nullptr && pad.mutex == nullptr);
}

// A guest __pbase_type_info, whose vtable pointer is the vtable's address point (past offset and type).
struct GuestPbaseTypeInfo {
    void* const* vtable;
    const char* name;
    unsigned flags;
    const std::type_info* pointee;
};

using TypeInfoQuery = bool (APS5_VABI*)(const void*);
using TypeInfoCatch = bool (APS5_VABI*)(const void*, const void*, void**, unsigned);
using TypeInfoUpcast = bool (APS5_VABI*)(const void*, const void*, void**);

static void TestTypeInfoVtables() {
    auto* const pointer = _ZTVN10__cxxabiv119__pointer_type_infoE_nid_postfix;
    auto* const function = _ZTVN10__cxxabiv120__function_type_infoE_nid_postfix;
    Require(pointer[0] == nullptr && function[0] == nullptr);
    Require(std::strcmp(static_cast<const std::type_info*>(pointer[1])->name(), "N10__cxxabiv119__pointer_type_infoE") == 0);
    Require(std::strcmp(static_cast<const std::type_info*>(function[1])->name(), "N10__cxxabiv120__function_type_infoE") == 0);
    Require(reinterpret_cast<TypeInfoQuery>(pointer[4])(nullptr) && !reinterpret_cast<TypeInfoQuery>(pointer[5])(nullptr));
    Require(!reinterpret_cast<TypeInfoQuery>(function[4])(nullptr) && reinterpret_cast<TypeInfoQuery>(function[5])(nullptr));
    int value = 7;
    void* object = &value;
    Require(!reinterpret_cast<TypeInfoUpcast>(pointer[7])(nullptr, nullptr, &object) && object == &value);

    const GuestPbaseTypeInfo intPointer{pointer + 2, "Pi", 0, &typeid(int)};
    const GuestPbaseTypeInfo constIntPointer{pointer + 2, "PKi", 1, &typeid(int)};
    const GuestPbaseTypeInfo floatPointer{pointer + 2, "Pf", 0, &typeid(float)};
    const auto doCatch = reinterpret_cast<TypeInfoCatch>(pointer[6]);
    const auto pointerCatch = reinterpret_cast<TypeInfoCatch>(pointer[8]);
    Require(doCatch(&intPointer, &intPointer, &object, 0) && object == &value);
    Require(doCatch(&constIntPointer, &intPointer, &object, 0));
    Require(pointerCatch(&constIntPointer, &intPointer, &object, 0));
    Require(!doCatch(&intPointer, &constIntPointer, &object, 0));
    Require(!pointerCatch(&floatPointer, &intPointer, &object, 0));

    struct GuestTypeInfo {
        void* const* vtable;
        const char* name;
    } functionType{function + 2, "FvvE"}, otherFunctionType{function + 2, "FivE"};
    Require(reinterpret_cast<TypeInfoCatch>(function[6])(&functionType, &functionType, &object, 0));
    Require(!reinterpret_cast<TypeInfoCatch>(function[6])(&functionType, &otherFunctionType, &object, 0));
}

template<typename TException, typename TCall>
static void RequireThrows(TCall call) {
    try {
        call();
    } catch (const TException&) {
        return;
    }
    std::abort();
}

struct SignalContext {
    void* condition = nullptr;
    void* mutex = nullptr;
    int waiting = 0;
    int tokens = 0;
    int consumed = 0;
    int wakeups = 0;
};

static void Lock(SignalContext& context) {
    Require(_Mtx_lock_nid_postfix(&context.mutex) == ThrdSuccess);
}

static void Unlock(SignalContext& context) {
    Require(_Mtx_unlock_nid_postfix(&context.mutex) == ThrdSuccess);
}

static void* APS5_VABI ConsumeToken(void* arg) {
    auto& context = *static_cast<SignalContext*>(arg);
    Lock(context);
    ++context.waiting;
    while (context.tokens == 0) {
        Require(_Cnd_wait_nid_postfix(&context.condition, &context.mutex) == ThrdSuccess);
        ++context.wakeups;
    }
    --context.tokens;
    ++context.consumed;
    Unlock(context);
    return nullptr;
}

template<typename TPredicate>
static void WaitUntil(SignalContext& context, TPredicate predicate) {
    for (;;) {
        Lock(context);
        const bool done = predicate();
        Unlock(context);
        if (done) return;
        std::this_thread::yield();
    }
}

static void Signal(SignalContext& context) {
    Lock(context);
    ++context.tokens;
    Require(_Cnd_signal_nid_postfix(&context.condition) == ThrdSuccess);
    Unlock(context);
}

static void TestConditionSignal() {
    SignalContext context;
    context.condition = reinterpret_cast<void*>(std::uintptr_t{1});
    Require(_Cnd_init_with_name_nid_postfix(&context.condition, "AmprSignal") == ThrdSuccess && context.condition != nullptr);
    Require(_Mtx_init_nid_postfix(&context.mutex, 0) == ThrdSuccess);
    Require(_Cnd_signal_nid_postfix(&context.condition) == ThrdSuccess);

    const auto single = Start(ConsumeToken, &context);
    WaitUntil(context, [&] { return context.waiting == 1; });
    Signal(context);
    Require(_Thrd_join_nid_postfix(single, nullptr) == ThrdSuccess);
    Require(context.consumed == 1 && context.tokens == 0);

    context.waiting = 0;
    context.consumed = 0;
    context.wakeups = 0;
    const std::array<Pthread, 2> pair{Start(ConsumeToken, &context), Start(ConsumeToken, &context)};
    WaitUntil(context, [&] { return context.waiting == 2; });
    Signal(context);
    WaitUntil(context, [&] { return context.consumed == 1; });
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    Lock(context);
    Require(context.consumed == 1 && context.wakeups == 1 && context.tokens == 0);
    Unlock(context);
    Signal(context);
    for (auto thread : pair) Require(_Thrd_join_nid_postfix(thread, nullptr) == ThrdSuccess);
    Require(context.consumed == 2 && context.tokens == 0);
    Require(_Cnd_broadcast_nid_postfix(&context.condition) == ThrdSuccess);

    RequireThrows<std::invalid_argument>([] { _Cnd_signal_nid_postfix(nullptr); });
    void* empty = nullptr;
    RequireThrows<std::invalid_argument>([&] { _Cnd_signal_nid_postfix(&empty); });
    RequireThrows<std::invalid_argument>([&] { _Cnd_signal_nid_postfix(&context.mutex); });
    RequireThrows<std::invalid_argument>([] { _Cnd_init_with_name_nid_postfix(nullptr, "AmprSignal"); });
    _Cnd_destroy_nid_postfix(&context.condition);
    Require(context.condition == nullptr);
    RequireThrows<std::invalid_argument>([&] { _Cnd_signal_nid_postfix(&context.condition); });

    void* unnamed = nullptr;
    Require(_Cnd_init_with_name_nid_postfix(&unnamed, nullptr) == ThrdSuccess && unnamed != nullptr);
    Require(_Cnd_signal_nid_postfix(&unnamed) == ThrdSuccess);
    _Cnd_destroy_nid_postfix(&unnamed);
    void* plain = nullptr;
    Require(_Cnd_init_nid_postfix(&plain) == ThrdSuccess);
    Require(_Cnd_signal_nid_postfix(&plain) == ThrdSuccess);
    _Cnd_destroy_nid_postfix(&plain);
    _Mtx_destroy_nid_postfix(&context.mutex);
}

int main() {
    Require(_ZNSt7num_getIcSt19istreambuf_iteratorIcSt11char_traitsIcEEE2idE_nid_postfix == 0);
    Require(_ZNSt8time_getIcSt19istreambuf_iteratorIcSt11char_traitsIcEEE2idE_nid_postfix == 0);
    Require(_Thrd_id_nid_postfix() == scePthreadGetthreadid());
    TestConditionSignal();
    TestTypeInfoVtables();
    TestPad();
    TestThreadJoin();
    TestThreadSleep();
    TestSpinLock();
    TestWcstombs();
    return 0;
}
