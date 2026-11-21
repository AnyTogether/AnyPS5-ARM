#pragma once
// Emulation of CLFLUSHOPT and CLWB, which the PS5's Zen 2 has and older Intel hosts do not.
//
// CLFLUSHOPT arrived with Skylake and CLWB later still (CPUID.(EAX=7,ECX=0):EBX bits 23 and 24), so on a
// Haswell or Broadwell host both raise an invalid-opcode fault (#127: DOOM 3 BFG on an i7-4770K). The
// host fault handlers decode the faulting bytes with this header, run CLFLUSH on the same operand and
// resume after the instruction. CLFLUSH has the same effect on the line; it is only ordered more
// strictly (CLFLUSHOPT and CLWB are ordered only by fences and locked instructions), so it is a safe
// substitute. CLWB may keep the line in the cache; CLFLUSH evicts it, which costs only a later miss.
// Kept header-only and free of process state so a host test can drive it with crafted registers.
//
// Encodings (Intel SDM vol. 2A); only memory operands exist, the register forms are other instructions:
//   CLFLUSHOPT m8   66 [REX] 0F AE /7   (mod != 11; 66 0F AE F8+r is PCOMMIT, removed from the SDM)
//   CLWB m8         66 [REX] 0F AE /6   (mod != 11; 66 0F AE F0+r is TPAUSE)
// Legacy prefixes may come in any order before the REX prefix. A REX prefix that does not immediately
// precede 0F is ignored, as the CPU does. CS, DS, ES and SS overrides have no effect in 64-bit mode and
// are accepted; FS and GS overrides, LOCK, REP and REPNE are declined (the fault is reported as before).
// The address-size prefix 67 selects 32-bit addressing: the effective address wraps at 4 GiB.
#if defined(__x86_64__) || defined(_M_X64)
#include <cstddef>
#include <cstdint>
#include <emmintrin.h>
#ifdef _WIN32
#include <windows.h>
#elif defined(__linux__)
#include <csignal>
#include <ucontext.h>
#endif

namespace cache_flush {

enum class Op : std::uint8_t { Clflushopt, Clwb };

constexpr unsigned kNoRegister = 0xff;
constexpr unsigned kRip = 16; // base "register" of a RIP-relative operand
constexpr std::size_t kMaxInstructionSize = 15;

struct Instruction {
    Op op = Op::Clflushopt;
    unsigned base = kNoRegister;  // 0-15 in x86 order (rax, rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8-r15) or kRip
    unsigned index = kNoRegister; // 0-15, never rsp
    unsigned scale = 1;
    std::int32_t displacement = 0;
    bool addressSize32 = false;   // 67 prefix
    std::size_t size = 0;         // encoded length in bytes
};

// The general-purpose registers in x86 encoding order and the address of the faulting instruction.
struct Registers {
    std::uint64_t gpr[16] = {};
    std::uint64_t rip = 0;
};

// Reads only the bytes of the instruction itself, so `available` may run past them into unmapped memory
// as long as the instruction is complete.
inline bool Decode(const std::uint8_t* bytes, std::size_t available, Instruction& out) {
    const std::size_t limit = available < kMaxInstructionSize ? available : kMaxInstructionSize;
    std::size_t cursor = 0;
    bool operandSize = false;
    bool addressSize = false;
    std::uint8_t rex = 0;
    for (;; ++cursor) {
        if (cursor >= limit) return false;
        const std::uint8_t byte = bytes[cursor];
        if ((byte & 0xf0) == 0x40) {
            rex = byte;
            continue;
        }
        if (byte == 0x66) operandSize = true;
        else if (byte == 0x67) addressSize = true;
        else if (byte == 0x64 || byte == 0x65 || byte == 0xf0 || byte == 0xf2 || byte == 0xf3) return false;
        else if (byte != 0x26 && byte != 0x2e && byte != 0x36 && byte != 0x3e) break; // the first opcode byte
        rex = 0; // a REX prefix followed by a legacy prefix is ignored
    }
    if (!operandSize) return false;
    if (cursor + 3 > limit) return false;
    if (bytes[cursor] != 0x0f || bytes[cursor + 1] != 0xae) return false;
    cursor += 2;
    const std::uint8_t modrm = bytes[cursor++];
    const unsigned mod = modrm >> 6;
    const unsigned reg = (modrm >> 3) & 7;
    unsigned rm = modrm & 7;
    if (mod == 3) return false;
    if (reg != 6 && reg != 7) return false;
    Instruction result;
    result.op = reg == 7 ? Op::Clflushopt : Op::Clwb;
    result.addressSize32 = addressSize;
    std::size_t displacementSize = mod == 1 ? 1 : mod == 2 ? 4 : 0;
    if (rm == 4) {
        if (cursor >= limit) return false;
        const std::uint8_t sib = bytes[cursor++];
        const unsigned index = ((sib >> 3) & 7) | ((rex & 0x2) ? 8u : 0u);
        const unsigned base = sib & 7;
        result.scale = 1u << (sib >> 6);
        if (index != 4) result.index = index;
        if (base == 5 && mod == 0) {
            displacementSize = 4;
        } else {
            result.base = base | ((rex & 0x1) ? 8u : 0u);
        }
    } else if (rm == 5 && mod == 0) {
        result.base = kRip;
        displacementSize = 4;
    } else {
        rm |= (rex & 0x1) ? 8u : 0u;
        result.base = rm;
    }
    if (cursor + displacementSize > limit) return false;
    if (displacementSize == 1) {
        result.displacement = static_cast<std::int8_t>(bytes[cursor]);
    } else if (displacementSize == 4) {
        const std::uint32_t value = static_cast<std::uint32_t>(bytes[cursor]) | static_cast<std::uint32_t>(bytes[cursor + 1]) << 8 | static_cast<std::uint32_t>(bytes[cursor + 2]) << 16 | static_cast<std::uint32_t>(bytes[cursor + 3]) << 24;
        result.displacement = static_cast<std::int32_t>(value);
    }
    cursor += displacementSize;
    result.size = cursor;
    out = result;
    return true;
}

inline std::uint64_t EffectiveAddress(const Instruction& instruction, const Registers& registers) {
    std::uint64_t address = static_cast<std::uint64_t>(static_cast<std::int64_t>(instruction.displacement));
    if (instruction.base == kRip) address += registers.rip + instruction.size;
    else if (instruction.base != kNoRegister) address += registers.gpr[instruction.base & 15];
    if (instruction.index != kNoRegister) address += registers.gpr[instruction.index & 15] * instruction.scale;
    if (instruction.addressSize32) address &= 0xffffffffull;
    return address;
}

// Decodes the instruction at `bytes`, flushes its cache line with CLFLUSH and returns the length to
// advance the instruction pointer by, or 0 when the bytes are not CLFLUSHOPT or CLWB.
inline std::size_t Emulate(const std::uint8_t* bytes, std::size_t available, const Registers& registers, Instruction* decoded = nullptr, std::uint64_t* flushed = nullptr) {
    Instruction instruction;
    if (!Decode(bytes, available, instruction)) return 0;
    const std::uint64_t address = EffectiveAddress(instruction, registers);
    _mm_clflush(reinterpret_cast<const void*>(static_cast<std::uintptr_t>(address)));
    if (decoded) *decoded = instruction;
    if (flushed) *flushed = address;
    return instruction.size;
}

#ifdef _WIN32
inline Registers FromContext(const CONTEXT& context) {
    Registers registers;
    const DWORD64 values[16] = {context.Rax, context.Rcx, context.Rdx, context.Rbx, context.Rsp, context.Rbp, context.Rsi, context.Rdi, context.R8, context.R9, context.R10, context.R11, context.R12, context.R13, context.R14, context.R15};
    for (unsigned i = 0; i < 16; ++i) registers.gpr[i] = values[i];
    registers.rip = context.Rip;
    return registers;
}

// Emulates the instruction at `bytes` (a copy of the code at context.Rip) and advances Rip past it.
// Returns false, leaving the context untouched, when the bytes are not CLFLUSHOPT or CLWB.
inline bool EmulateContext(const std::uint8_t* bytes, std::size_t available, CONTEXT& context, Instruction* decoded = nullptr, std::uint64_t* flushed = nullptr) {
    const std::size_t size = Emulate(bytes, available, FromContext(context), decoded, flushed);
    if (size == 0) return false;
    context.Rip += size;
    return true;
}
#elif defined(__linux__)
inline Registers FromContext(const mcontext_t& context) {
    Registers registers;
    const int order[16] = {REG_RAX, REG_RCX, REG_RDX, REG_RBX, REG_RSP, REG_RBP, REG_RSI, REG_RDI, REG_R8, REG_R9, REG_R10, REG_R11, REG_R12, REG_R13, REG_R14, REG_R15};
    for (unsigned i = 0; i < 16; ++i) registers.gpr[i] = static_cast<std::uint64_t>(context.gregs[order[i]]);
    registers.rip = static_cast<std::uint64_t>(context.gregs[REG_RIP]);
    return registers;
}

// Emulates the instruction at the context's RIP and advances it. The faulting instruction was fetched,
// so its bytes are mapped; Decode reads no further than its end. Returns false, leaving the context
// untouched, when the instruction is not CLFLUSHOPT or CLWB. Async-signal-safe.
inline bool EmulateContext(mcontext_t& context, Instruction* decoded = nullptr, std::uint64_t* flushed = nullptr) {
    const auto* bytes = reinterpret_cast<const std::uint8_t*>(static_cast<std::uintptr_t>(context.gregs[REG_RIP]));
    const std::size_t size = Emulate(bytes, kMaxInstructionSize, FromContext(context), decoded, flushed);
    if (size == 0) return false;
    context.gregs[REG_RIP] = static_cast<greg_t>(static_cast<std::uint64_t>(context.gregs[REG_RIP]) + size);
    return true;
}

// libc's SIGILL handler (specifics/linux/CrashReport.cpp) asks this first: true when a kernel-raised
// SIGILL was a CLFLUSHOPT or CLWB, now run as CLFLUSH, with the context past it (unless
// APS5_NO_CACHE_FLUSH_EMULATION is set). Defined in libc (specifics/linux/CacheFlushEmulation.cpp).
bool EmulateSignal(int signal, siginfo_t* info, void* context);
#endif

}
#endif
