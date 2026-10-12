#include <codegen/x86/IAmd64OnlyInstructionMatcher.hpp>
#include <codegen/x86/StubBodyBuilder.hpp>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>
#include <signal.h>
#include <sys/mman.h>

namespace {

void require(const bool condition, const std::string& message) {
    if (!condition)
        throw std::runtime_error(message);
}

struct alignas(32) MachineState {
    std::uint8_t Ymm[16][32];
    std::uint64_t Gpr[16];
    std::uint64_t Flags;
    std::uint64_t Rsp;
    std::uint8_t StackIn[32];
    std::uint8_t StackOut[32];
};

static_assert(offsetof(MachineState, Gpr) == 512 && offsetof(MachineState, Flags) == 640 && offsetof(MachineState, Rsp) == 648);
static_assert(offsetof(MachineState, StackIn) == 656 && offsetof(MachineState, StackOut) == 688);

}

extern "C" void RunMaskedStoreCode(const void* code, MachineState* state);

// Loads every vector and general register and the flags from the state, calls the code, and stores
// them back. The 32 bytes 72 below the caller's stack pointer, where a store at -64(%rsp) of the
// called code lands, are copied in before the call and out after it.
asm(R"(
    .text
    .p2align 4
#ifdef __APPLE__
    .globl _RunMaskedStoreCode
_RunMaskedStoreCode:
#else
    .globl RunMaskedStoreCode
RunMaskedStoreCode:
#endif
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $24, %rsp
    mov %rdi, (%rsp)
    mov %rsi, 8(%rsp)
    mov %rsp, 648(%rsi)
    vmovdqu 656(%rsi), %ymm0
    vmovdqu %ymm0, -72(%rsp)
    vmovdqu 0(%rsi), %ymm0
    vmovdqu 32(%rsi), %ymm1
    vmovdqu 64(%rsi), %ymm2
    vmovdqu 96(%rsi), %ymm3
    vmovdqu 128(%rsi), %ymm4
    vmovdqu 160(%rsi), %ymm5
    vmovdqu 192(%rsi), %ymm6
    vmovdqu 224(%rsi), %ymm7
    vmovdqu 256(%rsi), %ymm8
    vmovdqu 288(%rsi), %ymm9
    vmovdqu 320(%rsi), %ymm10
    vmovdqu 352(%rsi), %ymm11
    vmovdqu 384(%rsi), %ymm12
    vmovdqu 416(%rsi), %ymm13
    vmovdqu 448(%rsi), %ymm14
    vmovdqu 480(%rsi), %ymm15
    mov 512(%rsi), %rax
    mov 520(%rsi), %rcx
    mov 528(%rsi), %rdx
    mov 536(%rsi), %rbx
    mov 552(%rsi), %rbp
    mov 568(%rsi), %rdi
    mov 576(%rsi), %r8
    mov 584(%rsi), %r9
    mov 592(%rsi), %r10
    mov 600(%rsi), %r11
    mov 608(%rsi), %r12
    mov 616(%rsi), %r13
    mov 624(%rsi), %r14
    mov 632(%rsi), %r15
    push 640(%rsi)
    popfq
    mov 560(%rsi), %rsi
    call *(%rsp)
    pushfq
    push %r15
    mov 24(%rsp), %r15
    pop 632(%r15)
    pop 640(%r15)
    mov %rax, 512(%r15)
    mov %rcx, 520(%r15)
    mov %rdx, 528(%r15)
    mov %rbx, 536(%r15)
    mov %rbp, 552(%r15)
    mov %rsi, 560(%r15)
    mov %rdi, 568(%r15)
    mov %r8, 576(%r15)
    mov %r9, 584(%r15)
    mov %r10, 592(%r15)
    mov %r11, 600(%r15)
    mov %r12, 608(%r15)
    mov %r13, 616(%r15)
    mov %r14, 624(%r15)
    vmovdqu %ymm0, 0(%r15)
    vmovdqu %ymm1, 32(%r15)
    vmovdqu %ymm2, 64(%r15)
    vmovdqu %ymm3, 96(%r15)
    vmovdqu %ymm4, 128(%r15)
    vmovdqu %ymm5, 160(%r15)
    vmovdqu %ymm6, 192(%r15)
    vmovdqu %ymm7, 224(%r15)
    vmovdqu %ymm8, 256(%r15)
    vmovdqu %ymm9, 288(%r15)
    vmovdqu %ymm10, 320(%r15)
    vmovdqu %ymm11, 352(%r15)
    vmovdqu %ymm12, 384(%r15)
    vmovdqu %ymm13, 416(%r15)
    vmovdqu %ymm14, 448(%r15)
    vmovdqu %ymm15, 480(%r15)
    vmovdqu -72(%rsp), %ymm0
    vmovdqu %ymm0, 688(%r15)
    vzeroupper
    add $24, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
)");

namespace {

using Bytes = std::vector<std::uint8_t>;

struct Case {
    const char* Name;
    Bytes Instruction;
    std::size_t RipTargetOffset;
};

constexpr std::size_t kNoRip = 0;
constexpr std::size_t kPage = 4096;

MachineState initialState(std::uint8_t* data, std::uint32_t seed) {
    MachineState state{};
    for (std::size_t reg = 0; reg < 16; ++reg) {
        for (std::size_t byte = 0; byte < 32; ++byte) {
            seed = seed * 1103515245u + 12345u;
            state.Ymm[reg][byte] = static_cast<std::uint8_t>(seed >> 16);
        }
    }
    for (std::size_t reg = 0; reg < 16; ++reg)
        state.Gpr[reg] = 0x1111111111111111ull * (reg + 1);
    state.Gpr[1] = 0;
    state.Gpr[7] = reinterpret_cast<std::uint64_t>(data + 64);
    state.Gpr[8] = 12;
    state.Gpr[13] = reinterpret_cast<std::uint64_t>(data + 256);
    state.Flags = 0x2 | 0x1 | 0x40 | 0x80 | 0x800;
    for (std::size_t byte = 0; byte < 32; ++byte)
        state.StackIn[byte] = static_cast<std::uint8_t>(0xA0 + byte);
    return state;
}

void runCase(const Case& item, const std::uint32_t seed) {
    const auto matcher = Codegen::MakeAmd64OnlyInstructionMatcher(Codegen::Amd64OnlyTarget::Rosetta);
    const auto match = matcher->Match(item.Instruction.data(), item.Instruction.size());
    require(match && match->Lowering == Codegen::Amd64OnlyLowering::Trampoline && match->InstructionName == "masked store", std::string(item.Name) + ": no masked-store stub");

    auto* pages = static_cast<std::uint8_t*>(mmap(nullptr, 4 * kPage, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0));
    require(pages != MAP_FAILED, "cannot map executable memory");
    auto* site = pages;
    auto* stub = pages + kPage;
    auto* data = pages + 2 * kPage;

    std::memcpy(site, item.Instruction.data(), item.Instruction.size());
    site[item.Instruction.size()] = 0xC3;
    auto body = match->StubBody;
    const auto ret = body.size();
    body.push_back(0xC3);
    const auto back = static_cast<std::int32_t>(ret - (match->ReturnBranchOffset + 5));
    std::memcpy(body.data() + match->ReturnBranchOffset + 1, &back, sizeof(back));
    Codegen::ApplyStubRelocations(body, match->Relocations, reinterpret_cast<std::uint64_t>(site), reinterpret_cast<std::uint64_t>(stub), 0);
    std::memcpy(stub, body.data(), body.size());

    const auto run = [&](const void* code, std::vector<std::uint8_t>& memory) {
        for (std::size_t byte = 0; byte < kPage; ++byte)
            data[byte] = static_cast<std::uint8_t>(byte * 7);
        auto* ripTarget = site + item.RipTargetOffset;
        if (item.RipTargetOffset != kNoRip)
            std::memset(ripTarget, 0x5A, 32);
        auto state = initialState(data, seed);
        RunMaskedStoreCode(code, &state);
        memory.assign(data, data + kPage);
        if (item.RipTargetOffset != kNoRip)
            memory.insert(memory.end(), ripTarget, ripTarget + 32);
        return state;
    };
    std::vector<std::uint8_t> expectedMemory;
    std::vector<std::uint8_t> actualMemory;
    const auto expected = run(site, expectedMemory);
    const auto actual = run(stub, actualMemory);
    require(expectedMemory == actualMemory, std::string(item.Name) + ": the stub stored different bytes");
    require(std::memcmp(expected.StackOut, actual.StackOut, sizeof(expected.StackOut)) == 0, std::string(item.Name) + ": the stub stored different stack bytes");
    require(std::memcmp(expected.Ymm, actual.Ymm, sizeof(expected.Ymm)) == 0, std::string(item.Name) + ": the stub changed a vector register");
    require(std::memcmp(expected.Gpr, actual.Gpr, sizeof(expected.Gpr)) == 0, std::string(item.Name) + ": the stub changed a general register");
    require((expected.Flags & 0xCD5) == (actual.Flags & 0xCD5), std::string(item.Name) + ": the stub changed the flags");
    munmap(pages, 4 * kPage);
}

// Under Rosetta a masked store whose bytes cross into a page that faults ends the process
// ("EmulateForward on a synchronous exception"); the stub's element stores fault and resume.
void reopenFaultingPage(int, siginfo_t* info, void*) {
    const auto page = reinterpret_cast<std::uintptr_t>(info->si_addr) & ~(std::uintptr_t{kPage} - 1);
    mprotect(reinterpret_cast<void*>(page), kPage, PROT_READ | PROT_WRITE);
}

void runStraddle() {
    const Bytes instruction = {0xc4, 0xe2, 0x75, 0x2e, 0x07};
    const auto matcher = Codegen::MakeAmd64OnlyInstructionMatcher(Codegen::Amd64OnlyTarget::Rosetta);
    const auto match = matcher->Match(instruction.data(), instruction.size());
    require(match && match->Lowering == Codegen::Amd64OnlyLowering::Trampoline, "straddle: no masked-store stub");
    auto* pages = static_cast<std::uint8_t*>(mmap(nullptr, 5 * kPage, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0));
    require(pages != MAP_FAILED, "cannot map executable memory");
    auto* site = pages;
    auto* stub = pages + kPage;
    auto* data = pages + 2 * kPage;
    std::memcpy(site, instruction.data(), instruction.size());
    site[instruction.size()] = 0xC3;
    auto body = match->StubBody;
    const auto ret = body.size();
    body.push_back(0xC3);
    const auto back = static_cast<std::int32_t>(ret - (match->ReturnBranchOffset + 5));
    std::memcpy(body.data() + match->ReturnBranchOffset + 1, &back, sizeof(back));
    std::memcpy(stub, body.data(), body.size());

    auto expectedState = initialState(data, 7);
    expectedState.Gpr[7] = reinterpret_cast<std::uint64_t>(data + kPage - 16);
    std::memset(data, 0x33, 2 * kPage);
    RunMaskedStoreCode(site, &expectedState);
    const std::vector<std::uint8_t> expected(data + kPage - 16, data + kPage + 16);

    struct sigaction action {};
    struct sigaction previousSegv {};
    struct sigaction previousBus {};
    action.sa_sigaction = &reopenFaultingPage;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGSEGV, &action, &previousSegv);
    sigaction(SIGBUS, &action, &previousBus);
    auto actualState = initialState(data, 7);
    actualState.Gpr[7] = reinterpret_cast<std::uint64_t>(data + kPage - 16);
    std::memset(data, 0x33, 2 * kPage);
    require(mprotect(data + kPage, kPage, PROT_READ) == 0, "cannot protect the second page");
    RunMaskedStoreCode(stub, &actualState);
    sigaction(SIGSEGV, &previousSegv, nullptr);
    sigaction(SIGBUS, &previousBus, nullptr);
    const std::vector<std::uint8_t> actual(data + kPage - 16, data + kPage + 16);
    require(expected == actual, "straddle: the stub stored different bytes across the protected page");
    require(std::memcmp(expectedState.Gpr, actualState.Gpr, sizeof(expectedState.Gpr)) == 0, "straddle: the stub changed a general register");
    munmap(pages, 5 * kPage);
}

}

int main() {
    try {
        const Case cases[] = {
            {"vmaskmovps ymm, (rdi)", {0xc4, 0xe2, 0x75, 0x2e, 0x07}, kNoRip},
            {"vmaskmovps xmm, (rdi)", {0xc4, 0xe2, 0x61, 0x2e, 0x17}, kNoRip},
            {"vmaskmovpd ymm, 8(rdi)", {0xc4, 0xe2, 0x55, 0x2f, 0x67, 0x08}, kNoRip},
            {"vmaskmovpd xmm, (rdi)", {0xc4, 0xe2, 0x41, 0x2f, 0x37}, kNoRip},
            {"vpmaskmovd ymm9, ymm10 mask, (rdi,rcx,4)", {0xc4, 0x62, 0x2d, 0x8e, 0x0c, 0x8f}, kNoRip},
            {"vpmaskmovq ymm11, ymm12 mask, -16(r13)", {0xc4, 0x42, 0x9d, 0x8e, 0x5d, 0xf0}, kNoRip},
            {"vpmaskmovd xmm14, xmm15 mask, 4(r13,r8)", {0xc4, 0x02, 0x01, 0x8e, 0x74, 0x05, 0x04}, kNoRip},
            {"vmaskmovps ymm8, -64(rsp)", {0xc4, 0x62, 0x45, 0x2e, 0x44, 0x24, 0xc0}, kNoRip},
            {"vpmaskmovq xmm1, -64(rsp,rcx,8)", {0xc4, 0xe2, 0xe9, 0x8e, 0x4c, 0xcc, 0xc0}, kNoRip},
            {"vmaskmovps ymm, 256(rip)", {0xc4, 0xe2, 0x75, 0x2e, 0x05, 0x00, 0x01, 0x00, 0x00}, 9 + 256},
        };
        std::size_t runs = 0;
        for (const auto& item : cases) {
            for (std::uint32_t seed = 1; seed <= 16; ++seed) {
                runCase(item, seed);
                ++runs;
            }
        }
        runStraddle();
        const auto matcher = Codegen::MakeAmd64OnlyInstructionMatcher(Codegen::Amd64OnlyTarget::Rosetta);
        const Bytes load = {0xc4, 0xe2, 0x75, 0x2c, 0x07};
        const auto loadMatch = matcher->Match(load.data(), load.size());
        require(!loadMatch || loadMatch->InstructionName != "masked store", "a masked load was lowered as a store");
        const auto intel = Codegen::MakeAmd64OnlyInstructionMatcher(Codegen::Amd64OnlyTarget::Intel);
        const auto intelMatch = intel->Match(cases[0].Instruction.data(), cases[0].Instruction.size());
        require(!intelMatch, "a masked store was lowered for an Intel host");
        std::printf("masked store stubs match the instructions in %zu runs and resume a store across a protected page\n", runs);
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
