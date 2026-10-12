#include <codegen/IAmd64OnlyConverter.hpp>
#include <codegen/IInstructionScanner.hpp>
#include <codegen/CodegenException.hpp>
#include <codegen/x86/Amd64OnlySubstitutionTable.hpp>
#include <codegen/x86/X64InstructionDecoder.hpp>
#include <codegen/x86/X64OpcodeConstants.hpp>
#include <codegen/x86/IAmd64OnlyInstructionMatcher.hpp>
#include <codegen/x86/StubBodyBuilder.hpp>
#include <algorithm>
#include <limits>
#include <memory>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <vector>

namespace Codegen {

namespace {

template<typename TOperation>
auto _atFileOffset(const Domain::FileByteOffset base, const TOperation& operation) {
    try {
        return operation();
    } catch (const CodegenException& e) {
        throw CodegenException(e.what(), base + e.FailureOffset);
    }
}

constexpr std::int64_t kShortJumpSize = 2;
constexpr std::uint64_t kIslandSearchBytes = 0x100;

struct Placement {
    std::vector<TrampolineSite> Sites;
    std::vector<std::size_t> Claimed;
    std::vector<std::size_t> Consumed;
    std::size_t ReplacementLength = 0;
};

class WindowPlacer {
public:
    WindowPlacer(
        std::vector<std::uint8_t>& seg,
        const std::vector<InstructionMatch>& matches,
        const Domain::ProgramHeader& ph,
        const std::set<std::uint64_t>& branchTargets,
        const std::set<std::size_t>& pending,
        const std::set<std::size_t>& claimed,
        const IAmd64OnlyInstructionMatcher& matcher
    ) : _seg(seg), _matches(matches), _ph(ph), _branchTargets(branchTargets), _pending(pending), _claimed(claimed), _matcher(matcher) {}

    [[nodiscard]] std::optional<Placement> Window(const std::size_t index) const {
        if (index + 1 < _matches.size() && (_pending.contains(index + 1) || _movable(index + 1, true))) {
            if (auto placement = _relocate(index, index, index + 1))
                return placement;
        }
        if (index > 0 && _movable(index - 1, false))
            return _relocate(index, index - 1, index);
        return std::nullopt;
    }

    [[nodiscard]] std::optional<Placement> Island(const std::size_t index) {
        const auto store = _address(index);
        for (std::size_t distance = 1;; ++distance) {
            bool inReach = false;
            for (const bool before : {true, false}) {
                if (before ? distance > index : index + distance >= _matches.size())
                    continue;
                const auto start = before ? index - distance : index + distance;
                if (_address(start) + kIslandSearchBytes < store || _address(start) > store + kIslandSearchBytes)
                    continue;
                inReach = true;
                if (auto placement = _islandAt(index, start))
                    return placement;
            }
            if (!inReach)
                return std::nullopt;
        }
    }

private:
    std::vector<std::uint8_t>& _seg;
    const std::vector<InstructionMatch>& _matches;
    const Domain::ProgramHeader& _ph;
    const std::set<std::uint64_t>& _branchTargets;
    const std::set<std::size_t>& _pending;
    const std::set<std::size_t>& _claimed;
    const IAmd64OnlyInstructionMatcher& _matcher;
    X64InstructionDecoder _decoder;

    [[nodiscard]] std::uint64_t _address(const std::size_t index) const { return _ph.MappedAddress + _matches[index].Offset; }
    [[nodiscard]] std::uint64_t _end(const std::size_t index) const { return _address(index) + _matches[index].Length; }
    [[nodiscard]] std::span<const std::uint8_t> _bytes(const std::size_t index) const { return {_seg.data() + _matches[index].Offset, _matches[index].Length}; }
    [[nodiscard]] DecodedInstructionInfo _info(const std::size_t index) const { return _decoder.DecodeInstruction(_seg.data() + _matches[index].Offset, _matches[index].Length); }

    [[nodiscard]] bool _entered(const std::uint64_t start, const std::uint64_t end) const {
        const auto hit = _branchTargets.upper_bound(start);
        return hit != _branchTargets.end() && *hit < end;
    }

    [[nodiscard]] bool _blocksFollowing(const std::size_t index) const {
        const auto kind = _info(index).FlowKind;
        return kind != ControlFlowKind::Sequential && kind != ControlFlowKind::ConditionalBranch;
    }

    [[nodiscard]] bool _movable(const std::size_t index, const bool last) const {
        return !_claimed.contains(index) && !_pending.contains(index) && (last || !_blocksFollowing(index));
    }

    [[nodiscard]] TrampolineSite _site(const std::uint64_t start, const std::size_t length, LoweredBody body) const {
        const auto offset = static_cast<std::size_t>(start - _ph.MappedAddress);
        return {
            static_cast<Domain::FileByteOffset>(_ph.Offset + offset),
            static_cast<Domain::VirtualAddress>(start),
            length,
            std::vector<std::uint8_t>(_seg.begin() + static_cast<std::ptrdiff_t>(offset), _seg.begin() + static_cast<std::ptrdiff_t>(offset + length)),
            std::move(body.Bytes),
            body.ReturnBranchOffset,
            std::move(body.Relocations)
        };
    }

    [[nodiscard]] std::optional<Placement> _relocate(const std::size_t index, const std::size_t first, const std::size_t last) const {
        if (_entered(_address(first), _end(last)))
            return std::nullopt;
        StubBodyBuilder body;
        Placement placement;
        try {
            for (auto k = first; k <= last; ++k) {
                if (_pending.contains(k)) {
                    _matcher.EmitOutOfLine(body, _bytes(k));
                    if (k != index)
                        placement.Consumed.push_back(k);
                } else {
                    body.MoveControlFlow(_bytes(k), _info(k));
                }
                placement.Claimed.push_back(k);
            }
        } catch (const CodegenException&) {
            return std::nullopt;
        }
        placement.Sites.push_back(_site(_address(first), static_cast<std::size_t>(_end(last) - _address(first)), body.Finish()));
        placement.ReplacementLength = placement.Sites.back().Body.size();
        return placement;
    }

    [[nodiscard]] std::optional<Placement> _islandAt(const std::size_t index, const std::size_t start) {
        using Amd64OnlySubstitutionTable::kJmpRel32;
        std::size_t head = 0;
        for (auto last = start; last < _matches.size(); ++last) {
            if (!_movable(last, true) || _entered(_address(start), _end(last)))
                return std::nullopt;
            if (head == 0 && _end(last) - _address(start) >= kJmpRel32.Size)
                head = static_cast<std::size_t>(_end(last) - _address(start));
            const auto island = _address(start) + head;
            const auto reach = static_cast<std::int64_t>(island) - static_cast<std::int64_t>(_address(index) + kShortJumpSize);
            if (head != 0 && (reach < std::numeric_limits<std::int8_t>::min() || reach > std::numeric_limits<std::int8_t>::max()))
                return std::nullopt;
            if (head != 0 && _end(last) >= island + kJmpRel32.Size) {
                try {
                    return _buildIsland(index, start, last, head);
                } catch (const CodegenException&) {
                    return std::nullopt;
                }
            }
            if (_blocksFollowing(last))
                return std::nullopt;
        }
        return std::nullopt;
    }

    [[nodiscard]] Placement _buildIsland(const std::size_t index, const std::size_t start, const std::size_t last, const std::size_t head) {
        using Amd64OnlySubstitutionTable::kJmpRel32;
        const auto windowStart = _address(start);
        const auto windowEnd = _end(last);
        const auto island = windowStart + head;
        const auto store = _address(index);
        Placement placement;

        StubBodyBuilder moved;
        for (auto k = start; k <= last; ++k) {
            moved.MoveControlFlow(_bytes(k), _info(k));
            placement.Claimed.push_back(k);
        }
        if (!_blocksFollowing(last))
            moved.JumpTo(static_cast<std::int64_t>(windowEnd - windowStart));
        placement.Sites.push_back(_site(windowStart, head, moved.Finish()));

        StubBodyBuilder lowered;
        lowered.Seek(static_cast<std::int64_t>(store) - static_cast<std::int64_t>(island));
        _matcher.EmitOutOfLine(lowered, _bytes(index));
        lowered.JumpTo(static_cast<std::int64_t>(_end(index)) - static_cast<std::int64_t>(island));
        placement.Sites.push_back(_site(island, kJmpRel32.Size, lowered.Finish()));
        placement.ReplacementLength = placement.Sites.back().Body.size();
        placement.Claimed.push_back(index);

        const auto offset = _matches[index].Offset;
        std::fill_n(_seg.begin() + static_cast<std::ptrdiff_t>(offset), _matches[index].Length, Amd64OnlySubstitutionTable::kTrapFill);
        _seg[offset] = X64OpcodeConstants::OneByteJmpRel8;
        _seg[offset + 1] = static_cast<std::uint8_t>(static_cast<std::int8_t>(static_cast<std::int64_t>(island) - static_cast<std::int64_t>(store + kShortJumpSize)));
        return placement;
    }
};

class Amd64OnlyConverter : public IAmd64OnlyConverter {
public:
    explicit Amd64OnlyConverter(const Amd64OnlyTarget target) : _matcher(MakeAmd64OnlyInstructionMatcher(target)) {}

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

    std::unique_ptr<IAmd64OnlyInstructionMatcher> _matcher;
    std::unique_ptr<IInstructionScanner> _scanner = MakeInstructionScanner();

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

    std::set<std::size_t> pendingIndices;
    for (const auto& item : pending)
        pendingIndices.insert(item.Index);
    std::set<std::size_t> claimed;
    std::set<std::size_t> consumed;
    for (const auto& item : pending) {
        if (consumed.contains(item.Index))
            continue;
        const auto& match = item.Instruction;
        const auto& substitution = item.Substitution;
        const auto fileOffset = static_cast<Domain::FileByteOffset>(ph.Offset + match.Offset);
        const auto address = static_cast<Domain::VirtualAddress>(ph.MappedAddress + match.Offset);
        std::size_t replacementLength = 0;

        switch (substitution.Lowering) {
        case Amd64OnlyLowering::InPlace: {
            if (substitution.ReplacementBytes.size() != match.Length)
                throw CodegenException("Intel substitution changes the instruction length", fileOffset);
            std::copy(substitution.ReplacementBytes.begin(), substitution.ReplacementBytes.end(), seg.begin() + static_cast<std::ptrdiff_t>(match.Offset));
            replacementLength = substitution.ReplacementBytes.size();
            ++result.ReplacedCount;
            break;
        }
        case Amd64OnlyLowering::Trampoline: {
            if (substitution.RelocatableWindow && match.Length < Amd64OnlySubstitutionTable::kJmpRel32.Size) {
                WindowPlacer placer(seg, matches, ph, branchTargets, pendingIndices, claimed, *_matcher);
                auto placement = placer.Window(item.Index);
                if (!placement)
                    placement = placer.Island(item.Index);
                if (!placement)
                    throw CodegenException("No room for a jump to the stub of " + substitution.InstructionName + " within its neighbours or a nearby island", fileOffset);
                for (auto& site : placement->Sites)
                    result.Trampolines.push_back(std::move(site));
                claimed.insert(placement->Claimed.begin(), placement->Claimed.end());
                consumed.insert(placement->Consumed.begin(), placement->Consumed.end());
                replacementLength = placement->ReplacementLength;
                break;
            }
            std::vector<std::size_t> taken;
            try {
                std::size_t siteLength = match.Length;
                auto stub = substitution;
                if (siteLength < Amd64OnlySubstitutionTable::kJmpRel32.Size) {
                    const X64InstructionDecoder decoder;
                    std::vector<std::span<const std::uint8_t>> sequence{std::span<const std::uint8_t>(seg.data() + match.Offset, match.Length)};
                    std::size_t trailingBytes = 0;
                    for (auto next = item.Index + 1; siteLength < Amd64OnlySubstitutionTable::kJmpRel32.Size; ++next) {
                        if (next >= matches.size() || matches[next].Offset != match.Offset + siteLength)
                            throw CodegenException("AMD-only instruction too short for a jump and not followed by an instruction", fileOffset);
                        const auto& following = matches[next];
                        const std::span<const std::uint8_t> bytes(seg.data() + following.Offset, following.Length);
                        const auto info = decoder.DecodeInstruction(bytes.data(), bytes.size());
                        const bool amdOnly = _matcher->Match(bytes.data(), bytes.size()).has_value();
                        if (amdOnly && trailingBytes == 0) {
                            sequence.push_back(bytes);
                            taken.push_back(next);
                        } else if (amdOnly || info.FlowKind != ControlFlowKind::Sequential || info.HasBranchTarget) {
                            throw CodegenException("AMD-only instruction too short for a jump is followed by an instruction that cannot move", ph.Offset + following.Offset);
                        } else {
                            trailingBytes += following.Length;
                        }
                        siteLength += following.Length;
                    }
                    const std::span<const std::uint8_t> trailing(seg.data() + match.Offset + siteLength - trailingBytes, trailingBytes);
                    auto relocated = _atFileOffset(fileOffset, [&] { return _matcher->MatchSequence(sequence, trailing); });
                    if (!relocated.has_value() || relocated->Lowering != Amd64OnlyLowering::Trampoline)
                        throw CodegenException("AMD-only instruction sequence has no out-of-line lowering", fileOffset);
                    stub = std::move(*relocated);
                }
                const auto hit = branchTargets.upper_bound(address);
                if (hit != branchTargets.end() && *hit < address + siteLength)
                    throw CodegenException("Branch enters an AMD-only instruction", ph.Offset + (*hit - ph.MappedAddress));
                const auto begin = seg.begin() + static_cast<std::ptrdiff_t>(match.Offset);
                result.Trampolines.push_back({
                    fileOffset,
                    address,
                    siteLength,
                    std::vector<std::uint8_t>(begin, begin + static_cast<std::ptrdiff_t>(siteLength)),
                    stub.StubBody,
                    stub.ReturnBranchOffset,
                    stub.Relocations
                });
                replacementLength = stub.StubBody.size();
                consumed.insert(taken.begin(), taken.end());
                for (auto k = item.Index; k < matches.size() && matches[k].Offset < match.Offset + siteLength; ++k)
                    claimed.insert(k);
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
