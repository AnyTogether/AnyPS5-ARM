#include "GuestState.hpp"

#include <algorithm>
#include <cinttypes>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/ucontext.h>

// Emitted by the translator: the guest image (its lowest segment at offset 0), its size, the table
// of translated functions sorted by guest offset, the guest entry point and the PT_TLS layout.
struct TranslatedFunction {
    std::uint64_t offset;
    void (*code)(GuestState*);
};

// The System V va_list the guest's variadic calls are read through (SceTypes.hpp VaList).
struct GuestVaList {
    std::uint32_t gpOffset;
    std::uint32_t fpOffset;
    void* overflowArea;
    void* registerSaveArea;
};

// What aps5_enter saves from a host call: the AAPCS argument registers. On return x[0], x[1], q[0]
// and q[1] hold the results.
struct EnterFrame {
    std::uint64_t x[8];
    std::uint8_t q[8][16];
};

extern "C" {
extern std::uint8_t aps5_guest_image[];
extern const std::uint64_t aps5_guest_image_size;
extern const TranslatedFunction aps5_guest_functions[];
extern const std::uint64_t aps5_guest_function_count;
extern const std::uint64_t aps5_guest_entry;
extern const std::uint64_t aps5_guest_tls[4]; // image offset, file size, block size, alignment

void aps5_host_bridge(GuestState* state, std::uint64_t target);
void aps5_enter();
}

namespace {

constexpr std::size_t GuestStackBytes = 8u << 20;
constexpr std::size_t TcbBytes = 0x100;
constexpr std::uint64_t StackGuard = 0x5a17c0de2b6e4d91ull;

thread_local GuestState* threadState = nullptr;
// The state of the guest call into the host that is running on this thread, for variadic exports.
thread_local GuestState* bridgedState = nullptr;

struct sigaction previousBus {}, previousSegv {};
// APS5_NATIVE_TRACE: report each redirected host call into guest code.
bool tracing = false;

std::uint64_t ImageBase() {
    return reinterpret_cast<std::uint64_t>(aps5_guest_image);
}

const TranslatedFunction* Find(std::uint64_t address) {
    const auto base = ImageBase();
    if (address < base || address - base >= aps5_guest_image_size) return nullptr;
    const auto offset = address - base;
    const auto* begin = aps5_guest_functions;
    const auto* end = aps5_guest_functions + aps5_guest_function_count;
    const auto* found = std::lower_bound(begin, end, offset, [](const TranslatedFunction& function, std::uint64_t value) { return function.offset < value; });
    return found != end && found->offset == offset ? found : nullptr;
}

[[noreturn]] void Fail(const char* what, std::uint64_t address) {
    std::fprintf(stderr, "[translator] %s 0x%" PRIx64 " (guest offset 0x%" PRIx64 ")\n", what, address, address - ImageBase());
    std::abort();
}

// FreeBSD TLS variant II, as the PS5 lays it out: the executable's block ends at the thread pointer,
// and the thread control block at the thread pointer starts with a pointer to itself; the stack
// guard is at fs:0x28.
std::uint64_t NewThreadPointer() {
    const auto offset = aps5_guest_tls[0], fileSize = aps5_guest_tls[1], blockSize = aps5_guest_tls[2];
    const auto alignment = std::max<std::uint64_t>(aps5_guest_tls[3], 16);
    const auto staticSize = (blockSize + alignment - 1) / alignment * alignment;
    auto* block = static_cast<std::uint8_t*>(std::aligned_alloc(alignment, staticSize + TcbBytes));
    if (block == nullptr) Fail("cannot allocate guest TLS of", staticSize);
    std::memset(block, 0, staticSize + TcbBytes);
    if (fileSize != 0) std::memcpy(block, aps5_guest_image + offset, fileSize);
    const auto threadPointer = reinterpret_cast<std::uint64_t>(block + staticSize);
    std::memcpy(block + staticSize, &threadPointer, 8);
    std::memcpy(block + staticSize + 0x28, &StackGuard, 8);
    return threadPointer;
}

GuestState* NewState() {
    auto* state = static_cast<GuestState*>(std::aligned_alloc(alignof(GuestState), sizeof(GuestState)));
    std::memset(state, 0, sizeof(*state));
    state->mxcsr = 0x1f80;
    void* stack = mmap(nullptr, GuestStackBytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (stack == MAP_FAILED) Fail("cannot map a guest stack for", 0);
    state->gpr[Rsp] = reinterpret_cast<std::uint64_t>(stack) + GuestStackBytes - 64;
    state->fsBase = NewThreadPointer();
    return state;
}

GuestState* ThreadState() {
    if (threadState == nullptr) threadState = NewState();
    return threadState;
}

// Host code calling a guest function pointer executes the guest image, which is not executable.
// The fault is redirected to aps5_enter with the translated function in x16, so every host callback
// site (thread entries, atexit, module init, library callbacks) runs translated code unchanged.
void Redirect(int signal, siginfo_t* info, void* context) {
    auto* machine = static_cast<ucontext_t*>(context)->uc_mcontext;
    const auto pc = static_cast<std::uint64_t>(machine->__ss.__pc);
    if (const auto* function = Find(pc)) {
        machine->__ss.__x[16] = reinterpret_cast<std::uint64_t>(function->code);
        machine->__ss.__pc = reinterpret_cast<std::uint64_t>(&aps5_enter);
        if (tracing) std::fprintf(stderr, "[translator] host call into guest offset 0x%" PRIx64 "\n", pc - ImageBase());
        return;
    }
    const auto& previous = signal == SIGBUS ? previousBus : previousSegv;
    if ((previous.sa_flags & SA_SIGINFO) != 0 && previous.sa_sigaction != nullptr) {
        previous.sa_sigaction(signal, info, context);
        return;
    }
    if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN) {
        previous.sa_handler(signal);
        return;
    }
    if (pc >= ImageBase() && pc - ImageBase() < aps5_guest_image_size) Fail("host call into untranslated guest code at", pc);
    // The process dies on the re-raised fault; say where it was first.
    Dl_info where {};
    const bool named = dladdr(reinterpret_cast<void*>(pc), &where) != 0;
    std::fprintf(stderr, "[translator] signal %d at pc 0x%" PRIx64 " (%s+0x%" PRIx64 "), address %p, lr 0x%" PRIx64 "\n", signal, pc,
                 named && where.dli_sname ? where.dli_sname : "?", named && where.dli_saddr ? pc - reinterpret_cast<std::uint64_t>(where.dli_saddr) : 0,
                 info->si_addr, static_cast<std::uint64_t>(machine->__ss.__lr));
    // Re-raise with the default action.
    struct sigaction fallback {};
    fallback.sa_handler = SIG_DFL;
    sigaction(signal, &fallback, nullptr);
}

void InstallRedirect() {
    tracing = std::getenv("APS5_NATIVE_TRACE") != nullptr;
    struct sigaction action {};
    action.sa_sigaction = Redirect;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    sigaction(SIGBUS, &action, &previousBus);
    sigaction(SIGSEGV, &action, &previousSegv);
}

}

extern "C" {

// A guest call or jump whose target the translator could not resolve statically. The caller has
// pushed the guest return address; a translated callee pops it with its ret, a host callee does not.
void aps5_call(GuestState* state, std::uint64_t target) {
    if (const auto* function = Find(target)) {
        function->code(state);
        return;
    }
    if (target >= ImageBase() && target - ImageBase() < aps5_guest_image_size) {
        Dl_info self {};
        dladdr(reinterpret_cast<void*>(&aps5_call), &self);
        std::fprintf(stderr, "[translator] from translated code at %p (executable offset 0x%llx)\n", __builtin_return_address(0),
                     static_cast<unsigned long long>(reinterpret_cast<std::uint64_t>(__builtin_return_address(0)) - reinterpret_cast<std::uint64_t>(self.dli_fbase)));
        Fail("call into untranslated guest code at", target);
    }
    auto* outer = bridgedState;
    bridgedState = state;
    aps5_host_bridge(state, target);
    bridgedState = outer;
    state->gpr[Rsp] += 8;
}

// Called by aps5_enter: runs a translated function for a host caller on this thread's guest state.
// A host function that guest code called keeps the guest's callee-saved registers and rsp, because
// the nested guest function preserves them like any System V callee.
void aps5_enter_guest(EnterFrame* frame, void (*code)(GuestState*)) {
    auto* state = ThreadState();
    static constexpr unsigned arguments[] = {Rdi, Rsi, Rdx, Rcx, R8, R9};
    for (unsigned i = 0; i < 6; ++i) state->gpr[arguments[i]] = frame->x[i];
    for (unsigned i = 0; i < 8; ++i) {
        std::memcpy(state->ymm[i], frame->q[i], 16);
        std::memset(state->ymm[i] + 16, 0, 16);
    }
    const auto saved = state->gpr[Rsp];
    // Below an interrupted guest frame's red zone; arguments 7 and 8 on the stack, then a return address.
    auto rsp = ((saved - 128) & ~std::uint64_t(15)) - 16;
    std::memcpy(reinterpret_cast<void*>(rsp), &frame->x[6], 16);
    rsp -= 8;
    std::memset(reinterpret_cast<void*>(rsp), 0, 8);
    state->gpr[Rsp] = rsp;
    code(state);
    state->gpr[Rsp] = saved;
    frame->x[0] = state->gpr[Rax];
    frame->x[1] = state->gpr[Rdx];
    std::memcpy(frame->q[0], state->ymm[0], 16);
    std::memcpy(frame->q[1], state->ymm[1], 16);
}

// For the host libraries' variadic exports: a System V va_list over the arguments of the guest call
// running on this thread, after fixedGp integer and fixedFp vector named arguments. saveArea is 176
// bytes the caller keeps alive while it reads the list.
int aps5_guest_va_start(GuestVaList* list, void* saveArea, unsigned fixedGp, unsigned fixedFp) {
    const auto* state = bridgedState;
    if (state == nullptr) return -1;
    static constexpr unsigned arguments[] = {Rdi, Rsi, Rdx, Rcx, R8, R9};
    auto* area = static_cast<std::uint8_t*>(saveArea);
    for (unsigned i = 0; i < 6; ++i) std::memcpy(area + i * 8, &state->gpr[arguments[i]], 8);
    for (unsigned i = 0; i < 8; ++i) std::memcpy(area + 48 + i * 16, state->ymm[i], 16);
    list->gpOffset = fixedGp * 8;
    list->fpOffset = 48 + fixedFp * 16;
    list->overflowArea = reinterpret_cast<void*>(state->gpr[Rsp] + 8);
    list->registerSaveArea = area;
    return 0;
}

[[noreturn]] void aps5_trap(GuestState* state, std::uint64_t address) {
    static_cast<void>(state);
    Fail("guest trap (ud2/int3) at", address);
}

[[noreturn]] void aps5_unsupported(GuestState* state, std::uint64_t address) {
    static_cast<void>(state);
    Fail("untranslated instruction at", address);
}

}

int main(int argc, char** argv, char** envp) {
    InstallRedirect();
    // The FreeBSD start block the guest entry receives: argc, argv[], NULL, envp[], NULL.
    int envc = 0;
    while (envp != nullptr && envp[envc] != nullptr) ++envc;
    auto* block = static_cast<std::uint64_t*>(std::calloc(static_cast<std::size_t>(argc + envc) + 3, sizeof(std::uint64_t)));
    block[0] = static_cast<std::uint64_t>(argc);
    for (int i = 0; i < argc; ++i) block[1 + i] = reinterpret_cast<std::uint64_t>(argv[i]);
    for (int i = 0; i < envc; ++i) block[2 + argc + i] = reinterpret_cast<std::uint64_t>(envp[i]);
    const auto entryAddress = ImageBase() + aps5_guest_entry;
    if (Find(entryAddress) == nullptr) Fail("no translated guest entry at", entryAddress);
    auto* entry = reinterpret_cast<int (*)(void*, void*)>(entryAddress);
    // With libkernel, the guest runs on its own thread while the main thread serves AppKit.
    using StartGuest = void (*)(void (*)(void*, void*), void*);
    if (auto* start = reinterpret_cast<StartGuest>(dlsym(RTLD_DEFAULT, "Aps5StartGuest_nid_no_patch"))) {
        start(reinterpret_cast<void (*)(void*, void*)>(entryAddress), block);
    }
    return entry(block, nullptr);
}
