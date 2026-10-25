#pragma once

// The last line a dying process writes to the game log: which host signal ended it, the faulting
// address, the instruction and the image it belongs to. A fault nobody handles otherwise leaves the
// log ending mid-run, which reads like a hang or a silent exit. Only write(2) and dladdr are used.
#ifndef _WIN32
#include <atomic>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/ucontext.h>
#else
#include <ucontext.h>
#endif

namespace FatalLine {

// The host standard error, which moves when the title points descriptor 2 elsewhere.
inline std::atomic<int> logDescriptor{STDERR_FILENO};

inline char* Append(char* out, char* end, const char* text) {
    while (*text != '\0' && out < end) *out++ = *text++;
    return out;
}

inline char* AppendHex(char* out, char* end, std::uint64_t value) {
    static constexpr char digits[] = "0123456789abcdef";
    out = Append(out, end, "0x");
    char reversed[16];
    int count = 0;
    do {
        reversed[count++] = digits[value & 0xf];
        value >>= 4;
    } while (value != 0 && count < 16);
    while (count > 0 && out < end) *out++ = reversed[--count];
    return out;
}

inline char* AppendDecimal(char* out, char* end, unsigned value) {
    char reversed[10];
    int count = 0;
    do {
        reversed[count++] = static_cast<char>('0' + value % 10);
        value /= 10;
    } while (value != 0 && count < 10);
    while (count > 0 && out < end) *out++ = reversed[--count];
    return out;
}

inline std::uint64_t InstructionPointer(void* context) {
    if (context == nullptr) return 0;
#if defined(__APPLE__) && defined(__x86_64__)
    return static_cast<ucontext_t*>(context)->uc_mcontext->__ss.__rip;
#elif defined(__APPLE__) && defined(__aarch64__)
    return static_cast<ucontext_t*>(context)->uc_mcontext->__ss.__pc;
#elif defined(__linux__) && defined(__x86_64__)
    return static_cast<std::uint64_t>(static_cast<ucontext_t*>(context)->uc_mcontext.gregs[REG_RIP]);
#else
    return 0;
#endif
}

inline char* AppendImage(char* out, char* end, std::uint64_t address) {
    Dl_info image{};
    if (address == 0 || dladdr(reinterpret_cast<void*>(address), &image) == 0 || image.dli_fname == nullptr) return Append(out, end, " (no image)");
    const char* name = std::strrchr(image.dli_fname, '/');
    out = Append(out, end, " (");
    out = Append(out, end, name != nullptr ? name + 1 : image.dli_fname);
    out = Append(out, end, "+");
    out = AppendHex(out, end, address - reinterpret_cast<std::uint64_t>(image.dli_fbase));
    if (image.dli_sname != nullptr) {
        out = Append(out, end, " ");
        out = Append(out, end, image.dli_sname);
    }
    return Append(out, end, ")");
}

inline void Write(int signal, const siginfo_t* info, void* context) {
    char line[640];
    char* const end = line + sizeof(line) - 1;
    char* out = Append(line, end, "[fatal] host signal ");
    out = AppendDecimal(out, end, static_cast<unsigned>(signal));
    out = Append(out, end, signal == SIGSEGV ? " (SIGSEGV)" : signal == SIGBUS ? " (SIGBUS)" : signal == SIGILL ? " (SIGILL)" : signal == SIGABRT ? " (SIGABRT)" : "");
    out = Append(out, end, " that no handler takes ends the game: address ");
    out = AppendHex(out, end, info != nullptr ? reinterpret_cast<std::uint64_t>(info->si_addr) : 0);
    const std::uint64_t instruction = InstructionPointer(context);
    out = Append(out, end, ", instruction ");
    out = AppendHex(out, end, instruction);
    out = AppendImage(out, end, instruction);
    *out++ = '\n';
    const auto written = ::write(logDescriptor.load(std::memory_order_relaxed), line, static_cast<std::size_t>(out - line));
    (void)written;
}

}
#endif
