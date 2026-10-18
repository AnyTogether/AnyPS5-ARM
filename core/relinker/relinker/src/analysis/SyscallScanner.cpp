#include <relinker/analysis/SyscallScanner.hpp>
#include <codegen/IInstructionScanner.hpp>
#include <codegen/x86/DecodedInstruction.hpp>
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstring>

#include <memory>
#include <optional>
#include <sstream>

namespace Relinker {

static constexpr std::uint8_t SYSCALL_BYTE0 = 0x0F;
static constexpr std::uint8_t SYSCALL_BYTE1 = 0x05;
static constexpr std::uint8_t INT80_BYTE0 = 0xCD;
static constexpr std::uint8_t INT80_BYTE1 = 0x80;
static constexpr std::uint8_t SYSENTER_BYTE0 = 0x0F;
static constexpr std::uint8_t SYSENTER_BYTE1 = 0x34;
static constexpr std::uint8_t SYSRET_BYTE0 = 0x0F;
static constexpr std::uint8_t SYSRET_BYTE1 = 0x07;
static constexpr std::size_t SYSCALL_NUMBER_LOOKBACK = 8;

static constexpr std::array<std::uint8_t, 23> SDK_GENERIC_SYSCALL_STUB{
    0x48, 0x89, 0xF8, 0x48, 0x89, 0xF7, 0x48, 0x89, 0xD6, 0x48, 0x89, 0xCA,
    0x4D, 0x89, 0xC2, 0x4D, 0x89, 0xC8, 0x4C, 0x8B, 0x4C, 0x24, 0x08,
};

static bool IsSdkSyscallStub(const std::vector<std::uint8_t>& code, const std::size_t syscallOffset) {
    constexpr std::array<std::uint8_t, 3> numberLoad{0x48, 0xC7, 0xC0};
    constexpr std::array<std::uint8_t, 3> argumentShuffle{0x49, 0x89, 0xCA};
    if (syscallOffset <= code.size() && syscallOffset >= SDK_GENERIC_SYSCALL_STUB.size() && code.size() - syscallOffset >= 3u) {
        const auto begin = code.begin() + static_cast<std::ptrdiff_t>(syscallOffset - SDK_GENERIC_SYSCALL_STUB.size());
        if (std::equal(SDK_GENERIC_SYSCALL_STUB.begin(), SDK_GENERIC_SYSCALL_STUB.end(), begin)
            && code[syscallOffset] == 0x0F && code[syscallOffset + 1] == 0x05 && code[syscallOffset + 2] == 0xC3)
            return true;
    }
    if (syscallOffset > code.size() || syscallOffset < 10u || code.size() - syscallOffset < 3u)
        return false;
    const auto begin = code.begin() + static_cast<std::ptrdiff_t>(syscallOffset - 10u);
    return std::equal(numberLoad.begin(), numberLoad.end(), begin)
        && std::equal(argumentShuffle.begin(), argumentShuffle.end(), begin + 7)
        && code[syscallOffset] == 0x0F && code[syscallOffset + 1] == 0x05 && code[syscallOffset + 2] == 0xC3;
}

enum class ForbiddenInstruction {
    None,
    Invocation,
    Return,
};

static constexpr std::array<std::uint8_t, 62> SDK_MPROTECT_INLINE{
    0x55, 0x48, 0x89, 0xE5, 0x53, 0x50, 0x89, 0xD1, 0x49, 0x89, 0xF0, 0x48, 0x89, 0xFE,
    0xF6, 0xC1, 0x04, 0x75, 0x31, 0x48, 0x63, 0xD1, 0xB8, 0x4A, 0x00, 0x00, 0x00,
    0x48, 0x89, 0xF7, 0x4C, 0x89, 0xC6, 0x45, 0x31, 0xD2, 0x45, 0x31, 0xC0, 0x45, 0x31, 0xC9,
    0x0F, 0x05, 0x0F, 0x93, 0xC1, 0x48, 0x89, 0xC3, 0x48, 0xF7, 0xDB, 0x84, 0xC9,
    0x48, 0x0F, 0x45, 0xD8, 0x48, 0x85, 0xDB,
};

static constexpr std::array<std::uint8_t, 37> SDK_MMAP_INLINE{
    0x49, 0x63, 0xD6, 0x4C, 0x63, 0xD1, 0x4D, 0x63, 0xC0, 0xB8, 0xDD, 0x01, 0x00, 0x00,
    0x48, 0x89, 0xDE, 0x0F, 0x05, 0x48, 0x89, 0xC1, 0x0F, 0x93, 0xC2, 0x48, 0xF7, 0xD8,
    0x84, 0xD2, 0x48, 0x0F, 0x45, 0xC1, 0x48, 0x85, 0xC0,
};

static constexpr std::array<std::uint8_t, 43> SDK_MMAP_EXEC_INLINE{
    0x44, 0x89, 0xF0, 0x83, 0xE0, 0xFB, 0x48, 0x63, 0xD0, 0x4C, 0x63, 0xD1, 0x4D, 0x63, 0xC0,
    0xB8, 0xDD, 0x01, 0x00, 0x00, 0x48, 0x89, 0xDE, 0x0F, 0x05, 0x0F, 0x93, 0xC1,
    0x49, 0x89, 0xC7, 0x49, 0xF7, 0xDF, 0x84, 0xC9, 0x4C, 0x0F, 0x45, 0xF8, 0x4D, 0x85, 0xFF,
};

struct RecentInstructions {
    static constexpr std::size_t Capacity = 64;
    std::array<Codegen::InstructionMatch, Capacity> matches{};
    std::size_t count = 0;

    void Push(const Codegen::InstructionMatch& match) {
        matches[count % Capacity] = match;
        ++count;
    }

    [[nodiscard]] const Codegen::InstructionMatch& Before(std::size_t step) const {
        return matches[(count - 1 - step) % Capacity];
    }

    [[nodiscard]] bool Contains(FileByteOffset offset) const {
        for (std::size_t step = 0; step < std::min(count, Capacity); ++step)
            if (Before(step).Offset == offset) return true;
        return false;
    }
};

template<std::size_t TSize>
static bool MatchesSdkInlineStub(const std::vector<std::uint8_t>& code, std::size_t syscallOffset, std::size_t limit, const std::array<std::uint8_t, TSize>& pattern, std::size_t beforeSyscall, const RecentInstructions& recent, FileByteOffset codeOffset) {
    if (syscallOffset < beforeSyscall || syscallOffset > limit) return false;
    const auto start = syscallOffset - beforeSyscall;
    if (pattern.size() > limit - start || !std::equal(pattern.begin(), pattern.end(), code.begin() + static_cast<std::ptrdiff_t>(start))) return false;
    return recent.Contains(codeOffset + start);
}

static bool IsSdkMmanSyscallStub(const std::vector<std::uint8_t>& code, std::size_t syscallOffset, std::size_t limit, const RecentInstructions& recent, FileByteOffset codeOffset) {
    return MatchesSdkInlineStub(code, syscallOffset, limit, SDK_MPROTECT_INLINE, 42, recent, codeOffset) || MatchesSdkInlineStub(code, syscallOffset, limit, SDK_MMAP_INLINE, 17, recent, codeOffset) || MatchesSdkInlineStub(code, syscallOffset, limit, SDK_MMAP_EXEC_INLINE, 23, recent, codeOffset);
}

static ForbiddenInstruction ClassifyForbiddenInstruction(const std::vector<std::uint8_t>& codeSection, const std::size_t opcodeOffset, const std::size_t limit) {
    if (opcodeOffset + 1 >= limit)
        return ForbiddenInstruction::None;

    const std::uint8_t byte0 = codeSection[opcodeOffset];
    const std::uint8_t byte1 = codeSection[opcodeOffset + 1];

    const bool isSyscall = (byte0 == SYSCALL_BYTE0 && byte1 == SYSCALL_BYTE1);
    const bool isInt80 = (byte0 == INT80_BYTE0 && byte1 == INT80_BYTE1);
    const bool isSysenter = (byte0 == SYSENTER_BYTE0 && byte1 == SYSENTER_BYTE1);
    const bool isSysret = (byte0 == SYSRET_BYTE0 && byte1 == SYSRET_BYTE1);

    if (isSyscall || isInt80 || isSysenter)
        return ForbiddenInstruction::Invocation;

    if (isSysret)
        return ForbiddenInstruction::Return;

    return ForbiddenInstruction::None;
}

static std::optional<std::uint32_t> ConstantRaxLoad(const std::uint8_t* bytes, const std::size_t length) {
    const std::size_t opcode = Codegen::DecodedInstruction{bytes, length}.OpcodeOffset();
    const bool hasRex = opcode > 0 && (bytes[opcode - 1] & 0xF0) == 0x40;
    const std::uint8_t rex = hasRex ? bytes[opcode - 1] : 0;

    if (hasRex && rex == 0x48 && length - opcode == 6 && bytes[opcode] == 0xC7 && bytes[opcode + 1] == 0xC0) {
        std::uint32_t value = 0;
        std::memcpy(&value, bytes + opcode + 2, sizeof(value));
        return value;
    }

    if (!hasRex && length - opcode == 5 && bytes[opcode] == 0xB8) {
        std::uint32_t value = 0;
        std::memcpy(&value, bytes + opcode + 1, sizeof(value));
        return value;
    }

    return std::nullopt;
}

static std::optional<std::uint32_t> ConstantSyscallNumber(const std::vector<std::uint8_t>& codeSection, const FileByteOffset codeSectionOffset, const RecentInstructions& recent) {
    for (std::size_t step = 1; step <= SYSCALL_NUMBER_LOOKBACK && step < recent.count; ++step) {
        const auto& match = recent.Before(step);
        const std::size_t start = static_cast<std::size_t>(match.Offset - codeSectionOffset);

        if (start >= codeSection.size() || match.Length > codeSection.size() - start)
            return std::nullopt;

        const std::uint8_t* bytes = codeSection.data() + start;

        if (const auto value = ConstantRaxLoad(bytes, match.Length))
            return value;

        const std::size_t opcode = Codegen::DecodedInstruction{bytes, match.Length}.OpcodeOffset();
        const bool hasRex = opcode > 0 && (bytes[opcode - 1] & 0xF0) == 0x40;
        const bool movesFirstSyscallArgument = hasRex && bytes[opcode - 1] == 0x49
            && match.Length - opcode == 2 && bytes[opcode] == 0x89 && bytes[opcode + 1] == 0xCA;

        if (!movesFirstSyscallArgument)
            return std::nullopt;
    }

    return std::nullopt;
}

class SyscallScanner : public ISyscallScanner {
public:
    SyscallScanner(Domain::IProgress& progress, const bool trapSdkStubs) : progress(progress), trapSdkStubs(trapSdkStubs) {}

    std::vector<std::size_t> ScanCodeSectionForSyscalls(const std::vector<std::uint8_t>& codeSection, FileByteOffset codeSectionOffset, FileByteOffset codeSectionSize, std::string_view input) override;

private:
    Domain::IProgress& progress;
    bool trapSdkStubs;
};

std::vector<std::size_t> SyscallScanner::ScanCodeSectionForSyscalls(const std::vector<std::uint8_t>& codeSection, const FileByteOffset codeSectionOffset, const FileByteOffset codeSectionSize, std::string_view input) {
    if (codeSectionSize > codeSection.size()) throw RelinkerException("Code section exceeds the input buffer", codeSectionOffset);
    const auto limit = static_cast<std::size_t>(codeSectionSize);

    const std::string source(input);
    const auto scanner = Codegen::MakeInstructionScanner([&](auto completed, auto total) { progress.Report({Domain::ProgressStage::Decode, source, completed, total}); });
    RecentInstructions recent;
    std::vector<std::size_t> trapped;
    scanner->VisitCodeSection(codeSection, codeSectionOffset, codeSectionSize, [&](const Codegen::InstructionMatch& match) {
        recent.Push(match);
        const std::size_t start = static_cast<std::size_t>(match.Offset - codeSectionOffset);
        const auto opcodeOffset = Codegen::DecodedInstruction{codeSection.data() + start, match.Length}.OpcodeOffset();
        const std::size_t opcode = start + opcodeOffset;
        const std::size_t spanLimit = std::min(limit, start + static_cast<std::size_t>(match.Length));

        const auto kind = ClassifyForbiddenInstruction(codeSection, opcode, spanLimit);

        if (kind == ForbiddenInstruction::None)
            return;

        if (trapSdkStubs && kind == ForbiddenInstruction::Invocation &&
            (IsSdkSyscallStub(codeSection, opcode) || IsSdkMmanSyscallStub(codeSection, opcode, limit, recent, codeSectionOffset))) {
            trapped.push_back(opcode);
            std::ostringstream message;
            message << "Trapping SDK syscall instruction at code offset 0x" << std::hex << match.Offset << '\n';
            progress.Message(message.str());
            return;
        }

        std::ostringstream msg;
        msg << "Forbidden syscall instruction at code offset 0x" << std::hex << match.Offset;

        if (kind == ForbiddenInstruction::Invocation)
            if (const auto number = ConstantSyscallNumber(codeSection, codeSectionOffset, recent))
                msg << ": syscall number " << std::dec << *number;

        throw RelinkerException(msg.str(), match.Offset);
    });
    progress.Report({Domain::ProgressStage::Syscalls, source, limit, limit});
    return trapped;
}

std::unique_ptr<ISyscallScanner> MakeSyscallScanner(Domain::IProgress& progress, const bool trapSdkStubs) {
    return std::make_unique<SyscallScanner>(progress, trapSdkStubs);
}

class NullSyscallScanner : public ISyscallScanner {
public:
    std::vector<std::size_t> ScanCodeSectionForSyscalls(const std::vector<std::uint8_t>&, FileByteOffset, FileByteOffset, std::string_view) override { return {}; }
};

std::unique_ptr<ISyscallScanner> MakeNullSyscallScanner() {
    return std::make_unique<NullSyscallScanner>();
}

}
