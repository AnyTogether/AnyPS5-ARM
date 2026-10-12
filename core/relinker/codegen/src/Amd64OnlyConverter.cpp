#include <codegen/IAmd64OnlyConverter.hpp>
#include <codegen/IInstructionScanner.hpp>
#include <codegen/CodegenException.hpp>
#include <codegen/x86/Amd64OnlySubstitutionTable.hpp>
#include <codegen/x86/X64InstructionDecoder.hpp>
#include <codegen/x86/IAmd64OnlyInstructionMatcher.hpp>
#include <codegen/x86/StubBodyBuilder.hpp>
#include <codegen/x86/X64OpcodeConstants.hpp>
#include <algorithm>
#include <memory>
#include <set>
#include <span>
#include <string>
#include <vector>

namespace Codegen {

namespace {

bool _isPadding(const std::span<const std::uint8_t> instruction, const DecodedInstructionInfo& info) {
    using namespace X64OpcodeConstants;
    if (info.IsTwoByteOpcode)
        return info.Opcode == TwoByteNopModRm;
    return info.Opcode == OneByteNop && std::all_of(instruction.begin(), instruction.begin() + static_cast<std::ptrdiff_t>(info.OpcodeOffset), [](const std::uint8_t byte) { return byte == PrefixOperandSize; });
}

template<typename TOperation>
auto _atFileOffset(const Domain::FileByteOffset base, const TOperation& operation) {
    try {
        return operation();
    } catch (const CodegenException& e) {
        throw CodegenException(e.what(), base + e.FailureOffset);
    }
}

class Amd64OnlyConverter : public IAmd64OnlyConverter {
public:
    explicit Amd64OnlyConverter(const Amd64OnlyTarget target) : _target(target), _matcher(MakeAmd64OnlyInstructionMatcher(target)) {}

    [[nodiscard]] ConvertResult Convert(
        std::vector<std::uint8_t> fileBytes,
        const std::vector<Domain::ProgramHeader>& codeSegments
    ) const override;

private:
    struct Pending {
        std::size_t Index;
        InstructionMatch Instruction;
        Amd64OnlyMatch Substitution;
    };

    struct SitePlan {
        std::size_t First;
        std::size_t End;
        std::vector<std::span<const std::uint8_t>> Instructions;
    };

    Amd64OnlyTarget _target;
    std::unique_ptr<IAmd64OnlyInstructionMatcher> _matcher;
    std::unique_ptr<IInstructionScanner> _scanner = MakeInstructionScanner();

    [[nodiscard]] SitePlan _planSite(
        const std::vector<std::uint8_t>& seg,
        const std::vector<InstructionMatch>& matches,
        std::size_t index,
        const Domain::ProgramHeader& ph,
        const std::set<std::uint64_t>& branchTargets,
        std::size_t coveredEnd
    ) const;

    void _convertSegment(
        std::vector<std::uint8_t>& fileBytes,
        const Domain::ProgramHeader& ph,
        ConvertResult& result
    ) const;

    [[nodiscard]] static std::set<std::uint64_t> _collectBranchTargets(
        const std::vector<std::uint8_t>& seg,
        const std::vector<InstructionMatch>& matches,
        const Domain::ProgramHeader& ph
    );
};

std::set<std::uint64_t> Amd64OnlyConverter::_collectBranchTargets(
    const std::vector<std::uint8_t>& seg,
    const std::vector<InstructionMatch>& matches,
    const Domain::ProgramHeader& ph
) {
    const X64InstructionDecoder decoder;
    std::set<std::uint64_t> targets;
    for (const auto& match : matches) {
        const auto info = decoder.DecodeInstruction(seg.data() + match.Offset, match.Length);
        if (!info.HasBranchTarget || info.HasRipRelativeDisp)
            continue;
        const auto target = static_cast<std::int64_t>(ph.MappedAddress + match.Offset + info.Length) + info.BranchDisp;
        if (target >= 0)
            targets.insert(static_cast<std::uint64_t>(target));
    }
    return targets;
}

Amd64OnlyConverter::SitePlan Amd64OnlyConverter::_planSite(
    const std::vector<std::uint8_t>& seg,
    const std::vector<InstructionMatch>& matches,
    const std::size_t index,
    const Domain::ProgramHeader& ph,
    const std::set<std::uint64_t>& branchTargets,
    const std::size_t coveredEnd
) const {
    constexpr auto kJumpSize = Amd64OnlySubstitutionTable::kJmpRel32.Size;
    const X64InstructionDecoder decoder;
    const auto fileOffset = static_cast<Domain::FileByteOffset>(ph.Offset + matches[index].Offset);
    const auto bytesOf = [&](const std::size_t at) { return std::span<const std::uint8_t>(seg.data() + matches[at].Offset, matches[at].Length); };
    const auto matchOf = [&](const std::size_t at) { return _matcher->Match(seg.data() + matches[at].Offset, matches[at].Length); };
    const auto decode = [&](const std::size_t at) { return decoder.DecodeInstruction(seg.data() + matches[at].Offset, matches[at].Length); };
    const auto follows = [&](const std::size_t at) { return at < matches.size() && matches[at].Offset == matches[at - 1].Offset + matches[at - 1].Length; };
    const auto targetInside = [&](const std::size_t at) {
        const auto start = ph.MappedAddress + matches[at].Offset;
        const auto hit = branchTargets.lower_bound(start);
        return hit != branchTargets.end() && *hit < start + matches[at].Length;
    };

    SitePlan plan{index, index + 1, {bytesOf(index)}};
    std::size_t length = matches[index].Length;
    const auto take = [&] {
        length += matches[plan.End].Length;
        plan.Instructions.push_back(bytesOf(plan.End++));
    };
    const auto mergeAdjacent = [&] {
        while (follows(plan.End) && !targetInside(plan.End)) {
            const auto following = matchOf(plan.End);
            if (!following.has_value() || following->Lowering != Amd64OnlyLowering::Trampoline)
                return;
            take();
        }
    };
    mergeAdjacent();
    while (length < kJumpSize) {
        if (!follows(plan.End)) {
            if (_target != Amd64OnlyTarget::Rosetta)
                throw CodegenException("AMD-only instruction too short for a jump and not followed by an instruction", fileOffset);
            break;
        }
        if (targetInside(plan.End) || matchOf(plan.End).has_value())
            break;
        const auto info = decode(plan.End);
        if (CanMoveIntoStub(info)) {
            take();
            if (_target == Amd64OnlyTarget::Rosetta)
                mergeAdjacent();
            continue;
        }
        if (_target == Amd64OnlyTarget::Rosetta && CanEndStub(info))
            take();
        break;
    }
    if (length >= kJumpSize)
        return plan;
    if (_target != Amd64OnlyTarget::Rosetta)
        throw CodegenException("AMD-only instruction too short for a jump is followed by an instruction that cannot move", ph.Offset + matches[plan.End].Offset);

    while (length < kJumpSize) {
        if (plan.First == 0 || plan.First == coveredEnd || !follows(plan.First))
            throw CodegenException("AMD-only instruction too short for a jump has no preceding instruction that can move", fileOffset);
        const auto previous = plan.First - 1;
        const auto info = decode(previous);
        if (!CanMoveIntoStub(info) || matchOf(previous).has_value() || _isPadding(bytesOf(previous), info))
            throw CodegenException("AMD-only instruction too short for a jump is preceded by an instruction that cannot move", ph.Offset + matches[previous].Offset);
        length += matches[previous].Length;
        plan.Instructions.insert(plan.Instructions.begin(), bytesOf(previous));
        plan.First = previous;
    }
    return plan;
}

void Amd64OnlyConverter::_convertSegment(
    std::vector<std::uint8_t>& fileBytes,
    const Domain::ProgramHeader& ph,
    ConvertResult& result
) const {
    const auto segOffset = static_cast<std::size_t>(ph.Offset);
    const auto segSize = static_cast<std::size_t>(ph.FileSize);
    if (segOffset > fileBytes.size() || segSize > fileBytes.size() - segOffset)
        throw CodegenException("Code segment exceeds the file", ph.Offset);

    std::vector<std::uint8_t> seg(
        fileBytes.begin() + static_cast<std::ptrdiff_t>(segOffset),
        fileBytes.begin() + static_cast<std::ptrdiff_t>(segOffset + segSize)
    );

    const auto matches = _atFileOffset(ph.Offset, [&] { return _scanner->ScanCodeSection(seg, 0, seg.size()); });

    std::vector<Pending> pending;
    for (std::size_t index = 0; index < matches.size(); ++index) {
        const auto& match = matches[index];
        auto substitution = _atFileOffset(ph.Offset + match.Offset, [&] { return _matcher->Match(seg.data() + match.Offset, match.Length); });
        if (substitution.has_value())
            pending.push_back({index, match, std::move(*substitution)});
    }
    if (pending.empty())
        return;

    const bool needsBranchTargets = std::any_of(pending.begin(), pending.end(), [](const Pending& item) {
        return item.Substitution.Lowering == Amd64OnlyLowering::Trampoline;
    });
    const auto branchTargets = needsBranchTargets ? _collectBranchTargets(seg, matches, ph) : std::set<std::uint64_t>{};

    std::set<std::size_t> consumed;
    std::size_t coveredEnd = 0;
    for (const auto& item : pending) {
        if (consumed.contains(item.Index))
            continue;
        const auto& match = item.Instruction;
        const auto& substitution = item.Substitution;
        const auto fileOffset = static_cast<Domain::FileByteOffset>(ph.Offset + match.Offset);
        std::size_t replacementLength = 0;

        switch (substitution.Lowering) {
        case Amd64OnlyLowering::InPlace: {
            if (substitution.ReplacementBytes.size() != match.Length)
                throw CodegenException("Intel substitution changes the instruction length", fileOffset);
            std::copy(substitution.ReplacementBytes.begin(), substitution.ReplacementBytes.end(), seg.begin() + static_cast<std::ptrdiff_t>(match.Offset));
            replacementLength = substitution.ReplacementBytes.size();
            ++result.ReplacedCount;
            coveredEnd = item.Index + 1;
            break;
        }
        case Amd64OnlyLowering::Trampoline: {
            try {
                const auto plan = _planSite(seg, matches, item.Index, ph, branchTargets, coveredEnd);
                auto stub = substitution;
                if (plan.Instructions.size() > 1) {
                    auto relocated = _atFileOffset(fileOffset, [&] { return _matcher->MatchSequence(plan.Instructions); });
                    if (!relocated.has_value() || relocated->Lowering != Amd64OnlyLowering::Trampoline)
                        throw CodegenException("AMD-only instruction sequence has no out-of-line lowering", fileOffset);
                    stub = std::move(*relocated);
                }
                const auto siteOffset = matches[plan.First].Offset;
                const auto siteLength = static_cast<std::size_t>(matches[plan.End - 1].Offset + matches[plan.End - 1].Length - siteOffset);
                const auto siteAddress = static_cast<Domain::VirtualAddress>(ph.MappedAddress + siteOffset);
                const auto hit = branchTargets.upper_bound(siteAddress);
                if (hit != branchTargets.end() && *hit < siteAddress + siteLength)
                    throw CodegenException("Branch enters an AMD-only instruction", ph.Offset + (*hit - ph.MappedAddress));
                const auto begin = seg.begin() + static_cast<std::ptrdiff_t>(siteOffset);
                result.Trampolines.push_back({
                    static_cast<Domain::FileByteOffset>(ph.Offset + siteOffset),
                    siteAddress,
                    siteLength,
                    std::vector<std::uint8_t>(begin, begin + static_cast<std::ptrdiff_t>(siteLength)),
                    stub.StubBody,
                    stub.ReturnBranchOffset,
                    stub.Relocations
                });
                replacementLength = stub.StubBody.size();
                for (auto covered = plan.First; covered < plan.End; ++covered)
                    consumed.insert(covered);
                coveredEnd = plan.End;
            } catch (const CodegenException&) {
                if (!substitution.Optional)
                    throw;
                ++result.KeptCount;
                result.Reports.push_back({substitution.InstructionName, fileOffset, match.Length, 0, Amd64OnlyLowering::Kept});
                continue;
            }
            break;
        }
        case Amd64OnlyLowering::Kept:
        case Amd64OnlyLowering::Unsupported:
            throw CodegenException("AMD-only instruction without Intel lowering: " + substitution.InstructionName, fileOffset);
        }

        result.Reports.push_back({substitution.InstructionName, fileOffset, match.Length, replacementLength, substitution.Lowering});
    }

    if (seg.size() != segSize)
        throw CodegenException("Code segment size changed during Intel conversion", ph.Offset);
    std::copy(seg.begin(), seg.end(), fileBytes.begin() + static_cast<std::ptrdiff_t>(segOffset));
}

ConvertResult Amd64OnlyConverter::Convert(
    std::vector<std::uint8_t> fileBytes,
    const std::vector<Domain::ProgramHeader>& codeSegments
) const {
    ConvertResult result{};
    for (const auto& ph : codeSegments)
        _convertSegment(fileBytes, ph, result);
    result.Bytes = std::move(fileBytes);
    return result;
}

}

std::unique_ptr<IAmd64OnlyConverter> MakeAmd64OnlyConverter(const Amd64OnlyTarget target) {
    return std::make_unique<Amd64OnlyConverter>(target);
}

}
