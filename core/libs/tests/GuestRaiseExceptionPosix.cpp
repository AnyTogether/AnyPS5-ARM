#include "SceTypes.hpp"
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <thread>

extern "C" {
int APS5_VABI sceKernelInstallExceptionHandler(int signum, void* handler);
int APS5_VABI sceKernelRemoveExceptionHandler(int signum);
int APS5_VABI sceKernelRaiseException(Pthread thread, int signum);
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
Pthread APS5_VABI scePthreadSelf();
int APS5_VABI sceKernelCreateSema(KernelSema* sem, const char* name, uint32_t attr, int init, int max, void* opt);
int APS5_VABI sceKernelDeleteSema(KernelSema sem);
int APS5_VABI sceKernelSignalSema(KernelSema sem, int count);
int APS5_VABI sceKernelWaitSema(KernelSema sem, int need, KernelUseconds* time);
}

static constexpr int SCE_KERNEL_ERROR_EINVAL = static_cast<int>(0x80020016);
static constexpr int SCE_KERNEL_ERROR_ESRCH = static_cast<int>(0x80020003);
static constexpr int GuestSigusr1 = 30;
static constexpr std::size_t RaxOffset = 0x40 + 7 * 8;
static constexpr std::size_t RspOffset = 0xf8;

static void Require(bool value) { if (!value) std::abort(); }

static std::atomic<int> calls{0};
static std::atomic<Pthread> handlerSelf{nullptr};
static std::atomic<std::uint64_t> handlerRsp{0};
static std::atomic<bool> setRax{false};

static void APS5_VABI Handler(int signum, void* context) {
    Require(signum == GuestSigusr1);
    std::uint64_t rsp = 0;
    std::memcpy(&rsp, static_cast<unsigned char*>(context) + RspOffset, sizeof(rsp));
    handlerRsp.store(rsp);
    handlerSelf.store(scePthreadSelf());
    if (setRax.load()) {
        const std::uint64_t one = 1;
        std::memcpy(static_cast<unsigned char*>(context) + RaxOffset, &one, sizeof(one));
    }
    asm volatile("vzeroall" ::: "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15");
    errno = 0;
    calls.fetch_add(1);
}

struct Worker {
    std::atomic<bool> started{false};
    std::atomic<bool> stop{false};
    KernelSema sem = nullptr;
    int waitResult = -1;
};

static void* APS5_VABI Busy(void* arg) {
    auto& worker = *static_cast<Worker*>(arg);
    worker.started.store(true);
    volatile std::uint64_t spins = 0;
    while (!worker.stop.load()) spins = spins + 1;
    return nullptr;
}

static void* APS5_VABI Waiting(void* arg) {
    auto& worker = *static_cast<Worker*>(arg);
    worker.started.store(true);
    worker.waitResult = sceKernelWaitSema(worker.sem, 1, nullptr);
    return nullptr;
}

// Spins until the handler rewrites rax in the interrupted context.
static void* APS5_VABI Spinning(void* arg) {
    auto& worker = *static_cast<Worker*>(arg);
    worker.started.store(true);
    std::uint64_t rax = 0;
    asm volatile("1:\n pause\n testq %0, %0\n je 1b\n" : "+a"(rax) : : "cc");
    worker.waitResult = static_cast<int>(rax);
    return nullptr;
}

alignas(32) static std::uint8_t pattern[16 * 16];
alignas(32) static std::uint8_t result[16 * 16];
static volatile std::uint8_t vectorStop = 0;

static void* APS5_VABI Vectors(void* arg) {
    auto& worker = *static_cast<Worker*>(arg);
    worker.started.store(true);
    asm volatile(
        "movdqu 0(%[p]), %%xmm0\n movdqu 16(%[p]), %%xmm1\n movdqu 32(%[p]), %%xmm2\n movdqu 48(%[p]), %%xmm3\n"
        "movdqu 64(%[p]), %%xmm4\n movdqu 80(%[p]), %%xmm5\n movdqu 96(%[p]), %%xmm6\n movdqu 112(%[p]), %%xmm7\n"
        "movdqu 128(%[p]), %%xmm8\n movdqu 144(%[p]), %%xmm9\n movdqu 160(%[p]), %%xmm10\n movdqu 176(%[p]), %%xmm11\n"
        "movdqu 192(%[p]), %%xmm12\n movdqu 208(%[p]), %%xmm13\n movdqu 224(%[p]), %%xmm14\n movdqu 240(%[p]), %%xmm15\n"
        "1:\n pause\n cmpb $0, (%[stop])\n je 1b\n"
        "movdqu %%xmm0, 0(%[r])\n movdqu %%xmm1, 16(%[r])\n movdqu %%xmm2, 32(%[r])\n movdqu %%xmm3, 48(%[r])\n"
        "movdqu %%xmm4, 64(%[r])\n movdqu %%xmm5, 80(%[r])\n movdqu %%xmm6, 96(%[r])\n movdqu %%xmm7, 112(%[r])\n"
        "movdqu %%xmm8, 128(%[r])\n movdqu %%xmm9, 144(%[r])\n movdqu %%xmm10, 160(%[r])\n movdqu %%xmm11, 176(%[r])\n"
        "movdqu %%xmm12, 192(%[r])\n movdqu %%xmm13, 208(%[r])\n movdqu %%xmm14, 224(%[r])\n movdqu %%xmm15, 240(%[r])\n"
        :
        : [p] "r"(pattern), [r] "r"(result), [stop] "r"(&vectorStop)
        : "memory", "cc", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15");
    return nullptr;
}

static void* APS5_VABI Finished(void*) { return nullptr; }

static void WaitForCalls(int expected) {
    for (int i = 0; i < 5000 && calls.load() < expected; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    Require(calls.load() == expected);
}

int main() {
    const Pthread self = scePthreadSelf();
    Require(sceKernelRaiseException(self, 11) == SCE_KERNEL_ERROR_EINVAL);
    bool threw = false;
    try {
        sceKernelRaiseException(self, GuestSigusr1);
    } catch (const std::exception&) {
        threw = true;
    }
    Require(threw && calls.load() == 0);
    Require(sceKernelInstallExceptionHandler(GuestSigusr1, reinterpret_cast<void*>(&Handler)) == 0);

    Require(sceKernelRaiseException(self, GuestSigusr1) == 0);
    WaitForCalls(1);
    Require(handlerSelf.load() == self && handlerRsp.load() != 0);

    Worker busy;
    Pthread thread = nullptr;
    Require(scePthreadCreate(&thread, nullptr, Busy, &busy, "busy") == 0);
    while (!busy.started.load()) std::this_thread::yield();
    for (int round = 0; round < 100; ++round) {
        Require(sceKernelRaiseException(thread, GuestSigusr1) == 0);
        WaitForCalls(2 + round);
        Require(handlerSelf.load() == thread);
    }
    busy.stop.store(true);
    Require(scePthreadJoin(thread, nullptr) == 0);

    Worker waiting;
    Require(sceKernelCreateSema(&waiting.sem, "raise", 0, 0, 1, nullptr) == 0);
    Require(scePthreadCreate(&thread, nullptr, Waiting, &waiting, "waiting") == 0);
    while (!waiting.started.load()) std::this_thread::yield();
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const int beforeWait = calls.load();
    Require(sceKernelRaiseException(thread, GuestSigusr1) == 0);
    WaitForCalls(beforeWait + 1);
    Require(handlerSelf.load() == thread);
    Require(sceKernelSignalSema(waiting.sem, 1) == 0);
    Require(scePthreadJoin(thread, nullptr) == 0);
    Require(waiting.waitResult == 0);
    Require(sceKernelDeleteSema(waiting.sem) == 0);

    Worker spinning;
    setRax.store(true);
    Require(scePthreadCreate(&thread, nullptr, Spinning, &spinning, "spinning") == 0);
    while (!spinning.started.load()) std::this_thread::yield();
    Require(sceKernelRaiseException(thread, GuestSigusr1) == 0);
    Require(scePthreadJoin(thread, nullptr) == 0);
    Require(spinning.waitResult == 1);
    setRax.store(false);

    for (std::size_t i = 0; i < sizeof(pattern); ++i) pattern[i] = static_cast<std::uint8_t>(i * 7 + 1);
    Worker vectors;
    Require(scePthreadCreate(&thread, nullptr, Vectors, &vectors, "vectors") == 0);
    while (!vectors.started.load()) std::this_thread::yield();
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const int beforeVectors = calls.load();
    for (int round = 0; round < 20; ++round) Require(sceKernelRaiseException(thread, GuestSigusr1) == 0);
    for (int i = 0; i < 5000 && calls.load() == beforeVectors; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    Require(calls.load() > beforeVectors);
    vectorStop = 1;
    Require(scePthreadJoin(thread, nullptr) == 0);
    Require(std::memcmp(pattern, result, sizeof(pattern)) == 0);

    Require(scePthreadCreate(&thread, nullptr, Finished, nullptr, "finished") == 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    Require(sceKernelRaiseException(thread, GuestSigusr1) == SCE_KERNEL_ERROR_ESRCH);
    Require(scePthreadJoin(thread, nullptr) == 0);
    Require(sceKernelRemoveExceptionHandler(GuestSigusr1) == 0);
}
