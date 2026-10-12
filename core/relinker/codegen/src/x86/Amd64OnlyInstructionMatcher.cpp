#include <codegen/x86/IAmd64OnlyInstructionMatcher.hpp>
#include <codegen/x86/DecodedInstruction.hpp>
#include <codegen/x86/Amd64OnlySubstitutionTable.hpp>
#include <codegen/x86/Sse4aLowering.hpp>
#include <codegen/x86/Sse4aOperands.hpp>
#include <codegen/x86/ClzeroLowering.hpp>
#include <codegen/x86/ClzeroOperands.hpp>
#include <codegen/x86/ReciprocalLowering.hpp>
#include <codegen/x86/ReciprocalOperands.hpp>
#include <codegen/x86/Sha256Lowering.hpp>
#include <codegen/x86/Sha256Operands.hpp>
#include <codegen/x86/Sha1Lowering.hpp>
#include <codegen/x86/Sha1Operands.hpp>
#include <codegen/x86/WideStoreLowering.hpp>
#include <codegen/x86/WideStoreOperands.hpp>
#include <codegen/x86/StubBodyBuilder.hpp>
#include <codegen/x86/X64InstructionDecoder.hpp>
#include <codegen/x86/X64OpcodeConstants.hpp>
#include <codegen/CodegenException.hpp>
#include <algorithm>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <vector>

namespace Codegen {

namespace {

using namespace Amd64OnlySubstitutionTable;

constexpr std::size_t kMaxInstructionLength = 15;

Amd64OnlyMatch _unsupported(const Entry& entry, const std::size_t length) {
    return Amd64OnlyMatch{entry.Name, length, Amd64OnlyLowering::Unsupported, {}, {}, 0};
}

const Entry& _sse4aEntry(const Sse4aOperands& operands) {
    if (operands.RegisterForm)
        return operands.Insertq ? kInsertqRegisterForm : kExtrqRegisterForm;
    return operands.Insertq ? kInsertq : kExtrq;
}

const Entry& _reciprocalEntry(const ReciprocalOperands& operands) {
    return operands.Operation == ReciprocalOperation::ReciprocalSquareRoot ? kVrsqrtps : kVrcpps;
}

const Entry& _wideStoreEntry(const WideStoreOperands& operands) {
    switch (operands.Kind) {
    case WideStoreKind::Movups:
        return kVmovups;
    case WideStoreKind::Movupd:
        return kVmovupd;
    case WideStoreKind::Movaps:
        return kVmovaps;
    case WideStoreKind::Movapd:
        return kVmovapd;
    case WideStoreKind::Movdqa:
        return kVmovdqa;
    case WideStoreKind::Movdqu:
        return kVmovdqu;
    case WideStoreKind::Movntps:
        return kVmovntps;
    case WideStoreKind::Movntpd:
        return kVmovntpd;
    case WideStoreKind::Movntdq:
        return kVmovntdq;
    case WideStoreKind::Maskmovps:
        return kVmaskmovps;
    case WideStoreKind::Maskmovpd:
        return kVmaskmovpd;
    case WideStoreKind::Pmaskmovd:
        return kVpmaskmovd;
    case WideStoreKind::Pmaskmovq:
        return kVpmaskmovq;
    }
    return kVmovups;
}

const Entry& _sha256Entry(const Sha256Operands& operands) {
    switch (operands.Operation) {
    case Sha256Operation::Rnds2:
        return kSha256rnds2;
    case Sha256Operation::Msg1:
        return kSha256msg1;
    case Sha256Operation::Msg2:
        return kSha256msg2;
    }
    return kSha256rnds2;
}

const Entry& _sha1Entry(const Sha1Operands& operands) {
    switch (operands.Operation) {
    case Sha1Operation::Rnds4:
        return kSha1rnds4;
    case Sha1Operation::Nexte:
        return kSha1nexte;
    case Sha1Operation::Msg1:
        return kSha1msg1;
    case Sha1Operation::Msg2:
        return kSha1msg2;
    }
    return kSha1rnds4;
}

Amd64OnlyMatch _trampoline(std::string name, const std::size_t length, LoweredBody body, const bool optional = false) {
    return Amd64OnlyMatch{std::move(name), length, Amd64OnlyLowering::Trampoline, {}, std::move(body.Bytes), body.ReturnBranchOffset, optional, std::move(body.Relocations)};
}

void _moveTrailing(StubBodyBuilder& body, std::span<const std::uint8_t> trailing) {
    const X64InstructionDecoder decoder;
    while (!trailing.empty()) {
        const auto info = decoder.DecodeInstruction(trailing.data(), trailing.size());
        if (info.Length == 0 || info.Length > trailing.size())
            throw CodegenException("Trailing bytes do not split into whole instructions");
        body.Move(trailing.first(info.Length), info.HasRipRelativeDisp ? std::optional<std::size_t>(info.RipRelativeDispOffset) : std::nullopt);
        trailing = trailing.subspan(info.Length);
    }
}

template<typename TEmit>
LoweredBody _outOfLine(const std::size_t length, const std::span<const std::uint8_t> trailing, const TEmit& emit) {
    StubBodyBuilder body;
    emit(body);
    body.Advance(length);
    _moveTrailing(body, trailing);
    return body.Finish();
}

Amd64OnlyMatch _inPlace(const Entry& entry, const std::size_t length, std::vector<std::uint8_t> replacement) {
    while (replacement.size() < length) {
        const auto& nop = kNops[std::min<std::size_t>(length - replacement.size(), std::size(kNops)) - 1];
        replacement.insert(replacement.end(), nop.Bytes, nop.Bytes + nop.Size);
    }
    return Amd64OnlyMatch{entry.Name, length, Amd64OnlyLowering::InPlace, std::move(replacement), {}, 0};
}

bool _isClzeroOpcode(const DecodedInstruction& instr) {
    const auto pos = instr.OpcodeOffset();
    return pos + 2 < instr.Length && instr.Data[pos] == X64OpcodeConstants::TwoByteOpcodeEscape && instr.Data[pos + 1] == X64OpcodeConstants::TwoByteGrp7 && instr.Data[pos + 2] == 0xFC;
}

// RDPID r64 becomes mov r32, 0 (zero-extended, flags kept): Rosetta's TSC_AUX is a constant that is
// no processor index, so every thread reports processor 0.
std::vector<std::uint8_t> _rdpidReplacement(const DecodedInstruction& instr) {
    using namespace X64OpcodeConstants;
    const auto opcode = instr.OpcodeOffset();
    const auto rex = opcode > 0 && instr.Data[opcode - 1] >= RexMin && instr.Data[opcode - 1] <= RexMax ? instr.Data[opcode - 1] : 0;
    const auto reg = static_cast<std::uint8_t>((instr.Data[opcode + 2] & ModRmRmMask) | ((rex & 1) << 3));
    std::vector<std::uint8_t> bytes;
    if (reg >= 8)
        bytes.push_back(0x41);
    bytes.push_back(static_cast<std::uint8_t>(0xB8 + (reg & 7)));
    bytes.insert(bytes.end(), 4, 0);
    return bytes;
}

bool _validWait(const DecodedInstruction& instr) {
    const auto opcode = instr.Data + instr.OpcodeOffset();
    return instr.Length <= kMaxInstructionLength && std::find(instr.Data, opcode, X64OpcodeConstants::PrefixLock) == opcode;
}

class Amd64OnlyInstructionMatcher : public IAmd64OnlyInstructionMatcher {
public:
    explicit Amd64OnlyInstructionMatcher(const Amd64OnlyTarget target) : _target(target) {}

    [[nodiscard]] std::optional<Amd64OnlyMatch> Match(
        const std::uint8_t* data,
        std::size_t length,
        std::span<const std::uint8_t> trailing = {}
    ) const override;

    [[nodiscard]] std::optional<Amd64OnlyMatch> MatchSequence(
        std::span<const std::span<const std::uint8_t>> instructions
    ) const override;

private:
    Amd64OnlyTarget _target;
    Sse4aLowering _lowering;
    Sha256Lowering _sha256Lowering;
    Sha1Lowering _sha1Lowering;
    ClzeroLowering _clzeroLowering;
    ReciprocalLowering _reciprocalLowering;
    WideStoreLowering _wideStoreLowering;

    [[nodiscard]] std::optional<WideStoreOperands> _wideStore(const DecodedInstruction& instr) const;
    [[nodiscard]] const char* _emitLowered(StubBodyBuilder& body, const DecodedInstruction& instr) const;
    [[nodiscard]] Amd64OnlyMatch _matchMovnts(const DecodedInstruction& instr, const Entry& entry) const;
    [[nodiscard]] Amd64OnlyMatch _matchSse4a(const DecodedInstruction& instr, const Entry& entry, const Entry& registerFormEntry, std::span<const std::uint8_t> trailing) const;
    [[nodiscard]] Amd64OnlyMatch _matchSha256(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const;
    [[nodiscard]] Amd64OnlyMatch _matchSha1(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const;
    [[nodiscard]] Amd64OnlyMatch _matchClzero(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const;
    [[nodiscard]] std::optional<Amd64OnlyMatch> _matchRosetta(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const;
};

std::optional<WideStoreOperands> Amd64OnlyInstructionMatcher::_wideStore(const DecodedInstruction& instr) const {
    if (_target != Amd64OnlyTarget::Rosetta)
        return std::nullopt;
    auto store = DecodeWideStore(instr.Data, instr.Length);
    if (store && store->Masked)
        return std::nullopt;
    return store;
}

Amd64OnlyMatch Amd64OnlyInstructionMatcher::_matchMovnts(const DecodedInstruction& instr, const Entry& entry) const {
    using namespace X64OpcodeConstants;
    const auto opcodeOffset = instr.OpcodeOffset();
    if (opcodeOffset + 2 >= instr.Length)
        throw CodegenException("MOVNTSS/MOVNTSD truncated before its ModRM byte");
    const auto modrm = instr.Data[opcodeOffset + 2];
    if (((modrm >> ModRmModShift) & ModRmModMask) == ModRmModRegister)
        throw CodegenException("MOVNTSS/MOVNTSD with a register operand");
    std::vector<std::uint8_t> replacement(instr.Data, instr.Data + instr.Length);
    replacement[opcodeOffset + 1] = kMovsStoreOpcode;
    return Amd64OnlyMatch{entry.Name, instr.Length, Amd64OnlyLowering::InPlace, std::move(replacement), {}, 0};
}

Amd64OnlyMatch Amd64OnlyInstructionMatcher::_matchSse4a(const DecodedInstruction& instr, const Entry& entry, const Entry& registerFormEntry, std::span<const std::uint8_t> trailing) const {
    const auto operands = DecodeSse4a(instr.Data, instr.Length);
    if (!operands.RegisterForm && trailing.empty()) {
        if (auto inPlace = _lowering.LowerInPlace(operands, instr.Length))
            return Amd64OnlyMatch{entry.Name, instr.Length, Amd64OnlyLowering::InPlace, std::move(*inPlace), {}, 0};
    }
    const auto& name = operands.RegisterForm ? registerFormEntry.Name : entry.Name;
    return _trampoline(name, instr.Length, _outOfLine(instr.Length, trailing, [&](StubBodyBuilder& body) { _lowering.EmitOutOfLine(body, operands); }));
}

Amd64OnlyMatch Amd64OnlyInstructionMatcher::_matchSha256(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const {
    const auto operands = DecodeSha256(instr.Data, instr.Length);
    return _trampoline(_sha256Entry(operands).Name, instr.Length, _outOfLine(instr.Length, trailing, [&](StubBodyBuilder& body) { _sha256Lowering.EmitOutOfLine(body, operands); }));
}

Amd64OnlyMatch Amd64OnlyInstructionMatcher::_matchSha1(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const {
    const auto operands = DecodeSha1(instr.Data, instr.Length);
    return _trampoline(_sha1Entry(operands).Name, instr.Length, _outOfLine(instr.Length, trailing, [&](StubBodyBuilder& body) { _sha1Lowering.EmitOutOfLine(body, operands); }));
}

Amd64OnlyMatch Amd64OnlyInstructionMatcher::_matchClzero(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const {
    const auto operands = DecodeClzero(instr.Data, instr.Length);
    return _trampoline(kClzero.Name, instr.Length, _outOfLine(instr.Length, trailing, [&](StubBodyBuilder& body) { _clzeroLowering.EmitOutOfLine(body, operands); }));
}

std::optional<Amd64OnlyMatch> Amd64OnlyInstructionMatcher::_matchRosetta(const DecodedInstruction& instr, std::span<const std::uint8_t> trailing) const {
    if (_target != Amd64OnlyTarget::Rosetta)
        return std::nullopt;
    // RDSEED becomes RDRAND (/6 instead of /7): both return a random value and set CF.
    if (instr.IsRdseed()) {
        std::vector<std::uint8_t> replacement(instr.Data, instr.Data + instr.Length);
        replacement[instr.OpcodeOffset() + 2] &= static_cast<std::uint8_t>(~(1u << X64OpcodeConstants::ModRmRegShift));
        return Amd64OnlyMatch{kRdseed.Name, instr.Length, Amd64OnlyLowering::InPlace, std::move(replacement), {}, 0};
    }
    // CLWB only writes a cache line back; values do not change.
    if (instr.IsClwb())
        return _inPlace(kClwb, instr.Length, {});
    // Optional: code that checks CPUID never reaches it under Rosetta, which reports no RDPID.
    if (instr.IsRdpid())
        return _trampoline(kRdpid.Name, instr.Length, _outOfLine(instr.Length, trailing, [&](StubBodyBuilder& body) { body.Raw(_rdpidReplacement(instr)); }), true);
    if (const auto store = _wideStore(instr))
        return _trampoline(_wideStoreEntry(*store).Name, instr.Length, _outOfLine(instr.Length, trailing, [&](StubBodyBuilder& body) { _wideStoreLowering.EmitOutOfLine(body, *store); }), true);
    return std::nullopt;
}

const char* Amd64OnlyInstructionMatcher::_emitLowered(StubBodyBuilder& body, const DecodedInstruction& instr) const {
    if (instr.IsExtrq() || instr.IsInsertq()) {
        const auto operands = DecodeSse4a(instr.Data, instr.Length);
        _lowering.EmitOutOfLine(body, operands);
        return _sse4aEntry(operands).Name;
    }
    if (instr.IsSha256()) {
        const auto operands = DecodeSha256(instr.Data, instr.Length);
        _sha256Lowering.EmitOutOfLine(body, operands);
        return _sha256Entry(operands).Name;
    }
    if (instr.IsSha1()) {
        const auto operands = DecodeSha1(instr.Data, instr.Length);
        _sha1Lowering.EmitOutOfLine(body, operands);
        return _sha1Entry(operands).Name;
    }
    if (instr.IsClzero()) {
        const auto operands = DecodeClzero(instr.Data, instr.Length);
        _clzeroLowering.EmitOutOfLine(body, operands);
        return kClzero.Name;
    }
    if (const auto reciprocal = DecodeVexReciprocal(instr.Data, instr.Length)) {
        _reciprocalLowering.EmitOutOfLine(body, *reciprocal);
        return _reciprocalEntry(*reciprocal).Name;
    }
    if (_target == Amd64OnlyTarget::Rosetta && instr.IsRdpid()) {
        body.Raw(_rdpidReplacement(instr));
        return kRdpid.Name;
    }
    if (const auto store = _wideStore(instr)) {
        _wideStoreLowering.EmitOutOfLine(body, *store);
        return _wideStoreEntry(*store).Name;
    }
    return nullptr;
}

std::optional<Amd64OnlyMatch> Amd64OnlyInstructionMatcher::MatchSequence(
    std::span<const std::span<const std::uint8_t>> instructions
) const {
    const X64InstructionDecoder decoder;
    StubBodyBuilder body;
    const char* name = nullptr;
    std::size_t length = 0;
    bool optional = false;
    for (std::size_t index = 0; index < instructions.size(); ++index) {
        const auto& instruction = instructions[index];
        const DecodedInstruction instr{instruction.data(), instruction.size()};
        if (const auto lowered = _emitLowered(body, instr)) {
            if (name == nullptr) {
                name = lowered;
                length = instr.Length;
                optional = DecodeVexReciprocal(instr.Data, instr.Length).has_value() || (_target == Amd64OnlyTarget::Rosetta && instr.IsRdpid()) || _wideStore(instr).has_value();
            }
            body.Advance(instr.Length);
            continue;
        }
        const auto info = decoder.DecodeInstruction(instruction.data(), instruction.size());
        if (info.Length != instruction.size())
            throw CodegenException("Stub instruction does not split into whole instructions");
        if (CanMoveIntoStub(info))
            body.Move(instruction, info.HasRipRelativeDisp ? std::optional<std::size_t>(info.RipRelativeDispOffset) : std::nullopt);
        else if (index + 1 == instructions.size() && CanEndStub(info))
            body.Branch(instruction);
        else
            throw CodegenException("Instruction cannot move into a stub");
    }
    if (name == nullptr)
        return std::nullopt;
    return _trampoline(name, length, body.Finish(), optional);
}

std::optional<Amd64OnlyMatch> Amd64OnlyInstructionMatcher::Match(
    const std::uint8_t* data,
    std::size_t length,
    std::span<const std::uint8_t> trailing
) const {
    const DecodedInstruction instr{data, length};

    if (instr.IsMovntss())
        return _matchMovnts(instr, kMovntss);

    if (instr.IsMovntsd())
        return _matchMovnts(instr, kMovntsd);

    if (instr.IsExtrq())
        return _matchSse4a(instr, kExtrq, kExtrqRegisterForm, trailing);

    if (instr.IsInsertq())
        return _matchSse4a(instr, kInsertq, kInsertqRegisterForm, trailing);

    if (instr.IsSha256())
        return _matchSha256(instr, trailing);

    if (instr.IsSha1())
        return _matchSha1(instr, trailing);

    if (instr.IsMonitorx())
        return _validWait(instr) ? _inPlace(kMonitorx, length, {}) : _unsupported(kMonitorx, length);

    if (instr.IsMwaitx())
        return _validWait(instr) ? _inPlace(kMwaitx, length, std::vector<std::uint8_t>(kPause.Bytes, kPause.Bytes + kPause.Size)) : _unsupported(kMwaitx, length);

    if (const auto reciprocal = DecodeVexReciprocal(data, length)) {
        return _trampoline(_reciprocalEntry(*reciprocal).Name, length, _outOfLine(length, trailing, [&](StubBodyBuilder& body) { _reciprocalLowering.EmitOutOfLine(body, *reciprocal); }), true);
    }

    if (instr.IsClzero())
        return _matchClzero(instr, trailing);

    if (_isClzeroOpcode(instr))
        return _unsupported(kClzero, length);

    if (instr.IsRdpru())
        return _unsupported(kRdpru, length);

    if (instr.IsMcommit())
        return _unsupported(kMcommit, length);

    return _matchRosetta(instr, trailing);
}

}

std::unique_ptr<IAmd64OnlyInstructionMatcher> MakeAmd64OnlyInstructionMatcher(const Amd64OnlyTarget target) {
    return std::make_unique<Amd64OnlyInstructionMatcher>(target);
}

}
