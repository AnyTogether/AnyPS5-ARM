#include "prx/libc/include/CacheFlushEmulation.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#if defined(__linux__)
#include <csignal>
#include <dlfcn.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#if defined(__x86_64__) || defined(_M_X64)
namespace {

using Bytes = std::vector<std::uint8_t>;

int failures = 0;

void Check(bool condition, const std::string& message) {
    if (condition) return;
    std::fprintf(stderr, "%s\n", message.c_str());
    ++failures;
}

enum Gpr : unsigned { Rax, Rcx, Rdx, Rbx, Rsp, Rbp, Rsi, Rdi, R8, R9, R10, R11, R12, R13, R14, R15 };

alignas(64) std::uint8_t g_lines[16][64];

std::uint64_t Line(unsigned index) {
    return reinterpret_cast<std::uint64_t>(&g_lines[index][0]);
}

struct Form {
    const char* Name;
    Bytes Encoding;
    cache_flush::Op Op;
    std::uint64_t Address;
    bool RipRelative = false;
};

void PutDisplacement(Bytes& bytes, std::size_t offset, std::int64_t value) {
    const auto narrow = static_cast<std::uint32_t>(static_cast<std::int32_t>(value));
    for (unsigned i = 0; i < 4; ++i) bytes[offset + i] = static_cast<std::uint8_t>(narrow >> (8 * i));
}

cache_flush::Registers Registers() {
    cache_flush::Registers registers;
    for (unsigned i = 0; i < 16; ++i) registers.gpr[i] = Line(i) + 0x400;
    registers.gpr[Rdi] = Line(1);
    registers.gpr[R15] = Line(2);
    registers.gpr[Rsp] = Line(3);
    registers.gpr[R12] = Line(4) + 8;
    registers.gpr[Rax] = Line(5) - 0x100;
    registers.gpr[R13] = Line(6);
    registers.gpr[Rbp] = Line(7) - 0x1000;
    registers.gpr[R14] = Line(8) - 0x10;
    registers.gpr[Rbx] = Line(9) - 0x20;
    registers.gpr[Rsi] = 2;
    registers.gpr[R9] = 0x10;
    return registers;
}

// Each form and the line it flushes with the registers above; the RIP-relative ones are aimed at line 10
// once the stream's address is known.
std::vector<Form> Forms(const cache_flush::Registers& r) {
    using cache_flush::Op;
    return {
        {"clflushopt [rdi] (#127)", {0x66, 0x0F, 0xAE, 0x3F}, Op::Clflushopt, r.gpr[Rdi]},
        {"clflushopt [r15]", {0x66, 0x41, 0x0F, 0xAE, 0x3F}, Op::Clflushopt, r.gpr[R15]},
        {"clflushopt [rsp+8]", {0x66, 0x0F, 0xAE, 0x7C, 0x24, 0x08}, Op::Clflushopt, r.gpr[Rsp] + 8},
        {"clflushopt [r12-8]", {0x66, 0x41, 0x0F, 0xAE, 0x7C, 0x24, 0xF8}, Op::Clflushopt, r.gpr[R12] - 8},
        {"clflushopt [rax+r9*4+0x100]", {0x66, 0x42, 0x0F, 0xAE, 0xBC, 0x88, 0x00, 0x01, 0x00, 0x00}, Op::Clflushopt, r.gpr[Rax] + r.gpr[R9] * 4 + 0x100},
        {"clflushopt [rbx+rsi*8+0x20]", {0x66, 0x0F, 0xAE, 0x7C, 0xF3, 0x20}, Op::Clflushopt, r.gpr[Rbx] + r.gpr[Rsi] * 8 + 0x20},
        {"clflushopt [r13+0]", {0x66, 0x41, 0x0F, 0xAE, 0x7D, 0x00}, Op::Clflushopt, r.gpr[R13]},
        {"clflushopt [rbp+0x1000]", {0x66, 0x0F, 0xAE, 0xBD, 0x00, 0x10, 0x00, 0x00}, Op::Clflushopt, r.gpr[Rbp] + 0x1000},
        {"clflushopt [rsp] with no index", {0x66, 0x0F, 0xAE, 0x3C, 0x24}, Op::Clflushopt, r.gpr[Rsp]},
        {"clflushopt [rip+disp32]", {0x66, 0x0F, 0xAE, 0x3D, 0, 0, 0, 0}, Op::Clflushopt, Line(10), true},
        {"clflushopt ds:[rdi]", {0x3E, 0x66, 0x0F, 0xAE, 0x3F}, Op::Clflushopt, r.gpr[Rdi]},
        {"clflushopt cs:[r15] after 66", {0x66, 0x2E, 0x41, 0x0F, 0xAE, 0x3F}, Op::Clflushopt, r.gpr[R15]},
        {"clflushopt [rdi] with an ignored REX.B", {0x41, 0x66, 0x0F, 0xAE, 0x3F}, Op::Clflushopt, r.gpr[Rdi]},
        {"clflushopt [rdi] with a repeated 66", {0x66, 0x66, 0x0F, 0xAE, 0x3F}, Op::Clflushopt, r.gpr[Rdi]},
        {"clwb [rdi]", {0x66, 0x0F, 0xAE, 0x37}, Op::Clwb, r.gpr[Rdi]},
        {"clwb [r14+0x10]", {0x66, 0x41, 0x0F, 0xAE, 0x76, 0x10}, Op::Clwb, r.gpr[R14] + 0x10},
        {"clwb [rip+disp32]", {0x66, 0x0F, 0xAE, 0x35, 0, 0, 0, 0}, Op::Clwb, Line(10), true},
    };
}

struct Stream {
    Bytes Code;
    std::vector<std::size_t> Starts;
    std::vector<Form> Forms;
};

// The forms back to back, as at `base`, with each RIP-relative displacement aimed at line 10.
Stream Build(const cache_flush::Registers& registers, std::uint64_t base) {
    Stream stream;
    stream.Forms = Forms(registers);
    for (const auto& form : stream.Forms) {
        stream.Starts.push_back(stream.Code.size());
        stream.Code.insert(stream.Code.end(), form.Encoding.begin(), form.Encoding.end());
        if (form.RipRelative) PutDisplacement(stream.Code, stream.Code.size() - 4, static_cast<std::int64_t>(Line(10) - (base + stream.Code.size())));
    }
    return stream;
}

void DecodesEveryForm() {
    const auto registers = Registers();
    const std::uint64_t base = Line(0) - 0x10000;
    const auto stream = Build(registers, base);
    auto at = registers;
    at.rip = base;
    std::size_t offset = 0;
    for (std::size_t i = 0; i < stream.Forms.size(); ++i) {
        const auto& form = stream.Forms[i];
        cache_flush::Instruction instruction;
        std::uint64_t flushed = 0;
        const auto size = cache_flush::Emulate(stream.Code.data() + offset, stream.Code.size() - offset, at, &instruction, &flushed);
        Check(size == form.Encoding.size(), std::string(form.Name) + ": advanced by " + std::to_string(size) + " instead of " + std::to_string(form.Encoding.size()));
        Check(flushed == form.Address, std::string(form.Name) + ": flushed the wrong address");
        Check(instruction.op == form.Op, std::string(form.Name) + ": decoded as the other instruction");
        if (size == 0) return;
        offset += size;
        at.rip += size;
    }
    Check(offset == stream.Code.size(), "the stream did not end after its last instruction");
}

void LeavesTheNextInstruction() {
    const Bytes issue = {0x66, 0x0F, 0xAE, 0x3F, 0x48, 0x83, 0xC7, 0x40};
    const auto registers = Registers();
    Check(cache_flush::Emulate(issue.data(), issue.size(), registers) == 4, "the bytes of #127 did not advance past CLFLUSHOPT alone");
    Check(cache_flush::Emulate(issue.data() + 4, issue.size() - 4, registers) == 0, "add rdi, 0x40 was taken for a cache flush");
}

void ComputesWithoutFlushing() {
    cache_flush::Registers registers;
    registers.gpr[Rdi] = 0xffffffff00001234ull;
    registers.gpr[Rax] = 0x10;
    registers.rip = 0x7f0000000000ull;
    struct Address {
        const char* Name;
        Bytes Encoding;
        std::uint64_t Expected;
    };
    const Address cases[] = {
        {"clflushopt [0x40] (SIB without base or index)", {0x66, 0x0F, 0xAE, 0x3C, 0x25, 0x40, 0x00, 0x00, 0x00}, 0x40},
        {"clflushopt [-0x40] (sign-extended disp32)", {0x66, 0x0F, 0xAE, 0x3C, 0x25, 0xC0, 0xFF, 0xFF, 0xFF}, 0xffffffffffffffc0ull},
        {"clflushopt [rax*8+0x100] (no base)", {0x66, 0x0F, 0xAE, 0x3C, 0xC5, 0x00, 0x01, 0x00, 0x00}, 0x180},
        {"clflushopt [edi] (67 wraps at 4 GiB)", {0x67, 0x66, 0x0F, 0xAE, 0x3F}, 0x1234},
        {"clflushopt [eip-0x10]", {0x66, 0x67, 0x0F, 0xAE, 0x3D, 0xF0, 0xFF, 0xFF, 0xFF}, 0xfffffff9ull},
        {"clflushopt [rip-0x10]", {0x66, 0x0F, 0xAE, 0x3D, 0xF0, 0xFF, 0xFF, 0xFF}, 0x7f0000000000ull + 8 - 0x10},
    };
    for (const auto& item : cases) {
        cache_flush::Instruction instruction;
        if (!cache_flush::Decode(item.Encoding.data(), item.Encoding.size(), instruction)) {
            Check(false, std::string(item.Name) + ": not decoded");
            continue;
        }
        Check(instruction.size == item.Encoding.size(), std::string(item.Name) + ": wrong length");
        Check(cache_flush::EffectiveAddress(instruction, registers) == item.Expected, std::string(item.Name) + ": wrong address");
    }
}

void DeclinesOtherInstructions() {
    const auto registers = Registers();
    struct Other {
        const char* Name;
        Bytes Encoding;
    };
    const Other others[] = {
        {"pcommit (66 0F AE F8)", {0x66, 0x0F, 0xAE, 0xF8}},
        {"tpause eax (66 0F AE F0)", {0x66, 0x0F, 0xAE, 0xF0}},
        {"clflush [rdi]", {0x0F, 0xAE, 0x3F}},
        {"xsaveopt [rdi]", {0x0F, 0xAE, 0x37}},
        {"66 0F AE /5", {0x66, 0x0F, 0xAE, 0x2F}},
        {"rep clflushopt", {0xF3, 0x66, 0x0F, 0xAE, 0x3F}},
        {"repne clflushopt", {0xF2, 0x66, 0x0F, 0xAE, 0x3F}},
        {"lock clflushopt", {0xF0, 0x66, 0x0F, 0xAE, 0x3F}},
        {"fs: clflushopt", {0x64, 0x66, 0x0F, 0xAE, 0x3F}},
        {"gs: clflushopt", {0x66, 0x65, 0x0F, 0xAE, 0x3F}},
        {"ud2", {0x0F, 0x0B}},
        {"extrq (SSE4a)", {0x66, 0x0F, 0x78, 0xC0, 0x08, 0x00}},
        {"truncated before ModRM", {0x66, 0x0F, 0xAE}},
        {"truncated disp8", {0x66, 0x0F, 0xAE, 0x7F}},
        {"truncated SIB", {0x66, 0x0F, 0xAE, 0x3C}},
        {"truncated disp32", {0x66, 0x0F, 0xAE, 0x3D, 0x00, 0x00}},
        {"more than 15 bytes", {0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x0F, 0xAE, 0x3F}},
    };
    for (const auto& other : others) {
        cache_flush::Instruction instruction;
        instruction.size = 99;
        Check(cache_flush::Emulate(other.Encoding.data(), other.Encoding.size(), registers, &instruction) == 0, std::string(other.Name) + " was emulated");
        Check(instruction.size == 99, std::string(other.Name) + ": the decoded instruction was written although it was declined");
    }
}

#ifdef _WIN32
void AdvancesTheContext() {
    const auto registers = Registers();
    const auto base = Line(0) - 0x10000;
    const auto stream = Build(registers, base);
    CONTEXT context{};
    DWORD64* const slots[16] = {&context.Rax, &context.Rcx, &context.Rdx, &context.Rbx, &context.Rsp, &context.Rbp, &context.Rsi, &context.Rdi, &context.R8, &context.R9, &context.R10, &context.R11, &context.R12, &context.R13, &context.R14, &context.R15};
    for (unsigned i = 0; i < 16; ++i) *slots[i] = registers.gpr[i];
    context.Rip = base;
    context.EFlags = 0x203;
    for (std::size_t i = 0; i < stream.Forms.size(); ++i) {
        CONTEXT before;
        std::memcpy(&before, &context, sizeof(context));
        const auto offset = static_cast<std::size_t>(context.Rip - base);
        Check(offset == stream.Starts[i], std::string(stream.Forms[i].Name) + ": the context is not at the instruction");
        std::uint64_t flushed = 0;
        if (!cache_flush::EmulateContext(stream.Code.data() + offset, stream.Code.size() - offset, context, nullptr, &flushed)) {
            Check(false, std::string(stream.Forms[i].Name) + ": the context emulation declined it");
            return;
        }
        Check(flushed == stream.Forms[i].Address, std::string(stream.Forms[i].Name) + ": the context emulation flushed the wrong address");
        CONTEXT expected;
        std::memcpy(&expected, &before, sizeof(before));
        expected.Rip += stream.Forms[i].Encoding.size();
        Check(std::memcmp(&expected, &context, sizeof(context)) == 0, std::string(stream.Forms[i].Name) + ": the context changed beyond Rip");
    }
    Check(context.Rip == base + stream.Code.size(), "Rip did not end after the stream");
    const Bytes ud2 = {0x0F, 0x0B};
    CONTEXT before;
    std::memcpy(&before, &context, sizeof(context));
    Check(!cache_flush::EmulateContext(ud2.data(), ud2.size(), context), "ud2 was emulated on the context");
    Check(std::memcmp(&before, &context, sizeof(context)) == 0, "a declined instruction changed the context");
}
#elif defined(__linux__)
// The context's RIP walks the stream in memory, as after a fault at each instruction.
void AdvancesTheContext() {
    const auto registers = Registers();
    static std::uint8_t code[256];
    const auto base = reinterpret_cast<std::uint64_t>(code);
    const auto stream = Build(registers, base);
    std::memcpy(code, stream.Code.data(), stream.Code.size());
    ucontext_t context{};
    auto& m = context.uc_mcontext;
    const int order[16] = {REG_RAX, REG_RCX, REG_RDX, REG_RBX, REG_RSP, REG_RBP, REG_RSI, REG_RDI, REG_R8, REG_R9, REG_R10, REG_R11, REG_R12, REG_R13, REG_R14, REG_R15};
    for (unsigned i = 0; i < 16; ++i) m.gregs[order[i]] = static_cast<greg_t>(registers.gpr[i]);
    m.gregs[REG_RIP] = static_cast<greg_t>(base);
    m.gregs[REG_EFL] = 0x203;
    for (std::size_t i = 0; i < stream.Forms.size(); ++i) {
        const auto before = m;
        Check(static_cast<std::uint64_t>(m.gregs[REG_RIP]) - base == stream.Starts[i], std::string(stream.Forms[i].Name) + ": RIP is not at the instruction");
        std::uint64_t flushed = 0;
        if (!cache_flush::EmulateContext(m, nullptr, &flushed)) {
            Check(false, std::string(stream.Forms[i].Name) + ": the signal context emulation declined it");
            return;
        }
        Check(flushed == stream.Forms[i].Address, std::string(stream.Forms[i].Name) + ": the signal context emulation flushed the wrong address");
        auto expected = before;
        expected.gregs[REG_RIP] = static_cast<greg_t>(static_cast<std::uint64_t>(before.gregs[REG_RIP]) + stream.Forms[i].Encoding.size());
        Check(std::memcmp(expected.gregs, m.gregs, sizeof(m.gregs)) == 0, std::string(stream.Forms[i].Name) + ": the signal context changed beyond RIP");
    }
    Check(static_cast<std::uint64_t>(m.gregs[REG_RIP]) == base + stream.Code.size(), "RIP did not end after the stream");
    code[stream.Code.size()] = 0x0F;
    code[stream.Code.size() + 1] = 0x0B;
    const auto before = m;
    Check(!cache_flush::EmulateContext(m), "ud2 was emulated on the signal context");
    Check(std::memcmp(before.gregs, m.gregs, sizeof(m.gregs)) == 0, "a declined instruction changed the signal context");
}

// libc's SIGILL handler (upstream's fatal signal report), loaded from the given libc, takes a CLFLUSHOPT
// fault and passes any other SIGILL on: a ud2 still ends the process with SIGILL and the report's line.
void HandlesSigill(const char* libc) {
    int pipe[2];
    if (::pipe(pipe) != 0) {
        Check(false, "cannot make a pipe");
        return;
    }
    const pid_t child = ::fork();
    if (child == 0) {
        ::dup2(pipe[1], STDERR_FILENO);
        if (::dlopen(libc, RTLD_NOW | RTLD_GLOBAL) == nullptr) {
            std::fprintf(stderr, "cannot load %s: %s\n", libc, ::dlerror());
            ::_exit(3);
        }
        struct sigaction current {};
        if (::sigaction(SIGILL, nullptr, &current) != 0 || (current.sa_flags & SA_SIGINFO) == 0 || current.sa_sigaction == nullptr) {
            std::fprintf(stderr, "libc installed no SIGILL handler\n");
            ::_exit(4);
        }
        static const std::uint8_t code[] = {0x66, 0x0F, 0xAE, 0x3F, 0x0F, 0x0B};
        ucontext_t context{};
        context.uc_mcontext.gregs[REG_RIP] = static_cast<greg_t>(reinterpret_cast<std::uint64_t>(code));
        context.uc_mcontext.gregs[REG_RDI] = static_cast<greg_t>(Line(1));
        siginfo_t info{};
        info.si_signo = SIGILL;
        info.si_code = ILL_ILLOPN;
        current.sa_sigaction(SIGILL, &info, &context);
        if (static_cast<std::uint64_t>(context.uc_mcontext.gregs[REG_RIP]) != reinterpret_cast<std::uint64_t>(code) + 4) {
            std::fprintf(stderr, "the SIGILL handler did not step over CLFLUSHOPT\n");
            ::_exit(5);
        }
        std::fprintf(stderr, "stepped over clflushopt\n");
        __builtin_trap();
    }
    ::close(pipe[1]);
    std::string output;
    char buffer[512];
    for (ssize_t count; (count = ::read(pipe[0], buffer, sizeof(buffer))) > 0;) output.append(buffer, static_cast<std::size_t>(count));
    ::close(pipe[0]);
    int status = 0;
    Check(child > 0 && ::waitpid(child, &status, 0) == child, "cannot run the SIGILL child");
    Check(output.find("stepped over clflushopt\n") != std::string::npos, "libc's SIGILL handler did not emulate CLFLUSHOPT: " + output);
    Check(WIFSIGNALED(status) && WTERMSIG(status) == SIGILL, "a ud2 after the emulated CLFLUSHOPT did not end the child with SIGILL: " + output);
    Check(output.find("[libc] fatal SIGILL") != std::string::npos, "the ud2 left no fatal line: " + output);
}
#else
void AdvancesTheContext() {}
#endif

}

int main(int argc, char** argv) {
    DecodesEveryForm();
    LeavesTheNextInstruction();
    ComputesWithoutFlushing();
    DeclinesOtherInstructions();
    AdvancesTheContext();
#if defined(__linux__)
    if (argc > 1) HandlesSigill(argv[1]);
#else
    (void)argc;
    (void)argv;
#endif
    if (failures != 0) return 1;
    std::printf("cache flush emulation tests passed\n");
    return 0;
}
#else
int main() {
    std::printf("cache flush emulation is x86-64 only\n");
    return 0;
}
#endif
