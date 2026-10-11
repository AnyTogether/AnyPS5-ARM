#include "IntermediateRepresentation/IrProgram.hpp"
#include "Optimization/MaskedSelectEliminator.hpp"
#include "RdnaDecoder/RdnaInstruction.hpp"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <functional>
#include <initializer_list>
#include <utility>

using namespace ShaderRecompiler;

namespace {

struct Builder {
    IrProgram program;
    IrBlock* block = nullptr;

    Builder() {
        block = &newBlock();
        program.SetEntryBlock(*block);
    }

    IrBlock& newBlock() {
        auto& created = program.CreateBlock();
        program.BlockOrder().push_back(&created);
        return created;
    }

    IrValue& constant(std::uint32_t value) {
        auto& created = program.CreateValue(IrOpcode::Void, IrType::U32);
        created.SetImmediateU32(value);
        return created;
    }

    IrValue& emit(IrOpcode opcode, IrType type, std::initializer_list<IrValue*> arguments, std::uint64_t flags = 0) {
        auto& created = program.CreateValue(opcode, type, flags);
        for (auto* argument : arguments) created.AddArgument(argument);
        block->AppendInstruction(&created);
        return created;
    }

    IrValue& lane() {
        return emit(IrOpcode::LaneId, IrType::U32, {});
    }

    IrValue& mask(std::uint32_t lanes) {
        return emit(IrOpcode::ULessThan32, IrType::Bool, {&lane(), &constant(lanes)});
    }

    IrValue& select(IrValue& condition, IrValue& active, IrValue& inactive) {
        return emit(IrOpcode::SelectU32, IrType::U32, {&condition, &active, &inactive});
    }

    IrValue& add(IrValue& value, std::uint32_t immediate) {
        return emit(IrOpcode::IAdd32, IrType::U32, {&value, &constant(immediate)});
    }

    IrValue& logicalAnd(IrValue& left, IrValue& right) {
        return emit(IrOpcode::LogicalAnd, IrType::Bool, {&left, &right});
    }

    IrValue& threadBit(IrValue& low, IrValue& high) {
        auto& laneId = lane();
        auto& word = select(emit(IrOpcode::ULessThan32, IrType::Bool, {&laneId, &constant(32u)}), low, high);
        auto& shift = emit(IrOpcode::BitwiseAnd32, IrType::U32, {&laneId, &constant(31u)});
        auto& shifted = emit(IrOpcode::ShiftRightLogical32, IrType::U32, {&word, &shift});
        auto& bit = emit(IrOpcode::BitwiseAnd32, IrType::U32, {&shifted, &constant(1u)});
        return emit(IrOpcode::INotEqual32, IrType::Bool, {&bit, &constant(0u)});
    }

    IrValue& ballotBit(IrValue& predicate) {
        auto& ballot = emit(IrOpcode::Ballot, IrType::U32x4, {&predicate});
        auto& low = emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&ballot, &constant(0u)});
        auto& high = emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&ballot, &constant(1u)});
        return threadBit(low, high);
    }

    std::pair<IrValue*, IrValue*> ballotWords(IrValue& predicate) {
        auto& ballot = emit(IrOpcode::Ballot, IrType::U32x4, {&predicate});
        return {&emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&ballot, &constant(0u)}), &emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&ballot, &constant(1u)})};
    }

    IrValue& wordAnd(IrValue& left, IrValue& right) {
        return emit(IrOpcode::BitwiseAnd32, IrType::U32, {&left, &right});
    }

    IrValue& phi(IrType type, IrBlock& predecessor, IrValue& incoming) {
        auto& created = program.CreateValue(IrOpcode::Phi, type);
        block->AppendInstruction(&created);
        created.AddPhiOperand(&predecessor, &incoming);
        return created;
    }

    void keep(IrValue& value) {
        (void)emit(IrOpcode::ReferenceU32, IrType::Void, {&value});
    }

    std::uint32_t eliminate() {
        return MaskedSelectEliminator{}.Eliminate(program).removedSelects;
    }
};

bool removed(const IrValue& value) {
    return value.Parent() == nullptr;
}

bool expect(const char* name, bool condition) {
    if (!condition) std::fprintf(stderr, "%s\n", name);
    return condition;
}

bool run(const char* name, const std::function<bool()>& test) {
    try {
        return expect(name, test());
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s: %s\n", name, error.what());
        return false;
    }
}

}

int main() {
    bool passed = true;

    passed &= run("a write read only under its own exec must lose its select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& next = b.select(exec, b.add(written, 2u), old);
        b.keep(next);
        return b.eliminate() == 1u && removed(written) && !removed(next);
    });

    passed &= run("a write read under a wider exec must keep its select", [] {
        Builder b;
        auto& wide = b.mask(32u);
        auto& exec = b.logicalAnd(wide, b.mask(16u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& next = b.select(wide, b.add(written, 2u), old);
        b.keep(next);
        return b.eliminate() == 0u && !removed(written);
    });

    passed &= run("a write read under a narrower exec must lose its select", [] {
        Builder b;
        auto& exec = b.mask(32u);
        auto& narrow = b.logicalAnd(exec, b.mask(16u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& next = b.select(narrow, b.add(written, 2u), old);
        b.keep(next);
        return b.eliminate() == 1u && removed(written);
    });

    passed &= run("a write whose old lanes flow into the next write must keep its select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& next = b.select(exec, b.add(old, 2u), written);
        b.keep(next);
        return b.eliminate() == 0u && !removed(written);
    });

    passed &= run("a chain of writes under one exec must collapse once the last one goes", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& first = b.select(exec, b.add(old, 1u), old);
        auto& second = b.select(exec, b.add(first, 2u), first);
        auto& sink = b.select(exec, b.add(second, 3u), old);
        b.keep(sink);
        return b.eliminate() == 2u && removed(first) && removed(second) && !removed(sink);
    });

    passed &= run("a write read through thousands of lane-local values still loses its select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        IrValue* value = &written;
        for (std::uint32_t step = 0; step < 6000u; ++step) value = &b.add(*value, step);
        b.keep(b.select(exec, *value, old));
        return b.eliminate() == 1u && removed(written);
    });

    passed &= run("thousands of lane-local values ending in a wider read keep the select", [] {
        Builder b;
        auto& wide = b.mask(32u);
        auto& exec = b.logicalAnd(wide, b.mask(16u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        IrValue* value = &written;
        for (std::uint32_t step = 0; step < 6000u; ++step) value = &b.add(*value, step);
        b.keep(b.select(wide, *value, old));
        return b.eliminate() == 0u && !removed(written);
    });

    passed &= run("cross-lane reads must keep the select", [] {
        bool ok = true;
        for (const IrOpcode opcode : {IrOpcode::ReadFirstLane, IrOpcode::DppMoveU32, IrOpcode::BpermuteU32, IrOpcode::Permlane16U32, IrOpcode::SwizzleU32}) {
            Builder b;
            auto& exec = b.mask(16u);
            auto& old = b.lane();
            auto& written = b.select(exec, b.add(old, 1u), old);
            auto& read = b.emit(opcode, IrType::U32, {&written, &exec});
            b.keep(b.select(exec, read, old));
            ok &= b.eliminate() == 0u && !removed(written);
        }
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& ballot = b.emit(IrOpcode::Ballot, IrType::U32x4, {&b.emit(IrOpcode::INotEqual32, IrType::Bool, {&written, &b.constant(0u)})});
        b.keep(b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&ballot, &b.constant(0u)}));
        return ok && b.eliminate() == 0u && !removed(written);
    });

    passed &= run("a branch condition derived from the write keeps the select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& taken = b.emit(IrOpcode::INotEqual32, IrType::Bool, {&written, &b.constant(0u)});
        (void)b.emit(IrOpcode::Reference, IrType::Void, {&taken});
        return b.eliminate() == 0u && !removed(written);
    });

    passed &= run("a compare masked by the same exec must not keep the select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& compare = b.logicalAnd(exec, b.emit(IrOpcode::INotEqual32, IrType::Bool, {&written, &b.constant(0u)}));
        auto& ballot = b.emit(IrOpcode::Ballot, IrType::U32x4, {&compare});
        b.keep(b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&ballot, &b.constant(0u)}));
        return b.eliminate() == 1u && removed(written);
    });

    passed &= run("an exec rebuilt from a ballot of a narrower mask implies the write's exec", [] {
        Builder b;
        auto& exec = b.mask(48u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& later = b.ballotBit(b.logicalAnd(exec, b.mask(40u)));
        auto& next = b.select(later, b.add(written, 2u), old);
        b.keep(next);
        return b.eliminate() == 1u && removed(written);
    });

    passed &= run("an exec rebuilt from a ballot of a wider mask keeps the select", [] {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(40u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& later = b.ballotBit(wide);
        b.keep(b.select(later, b.add(written, 2u), old));
        return b.eliminate() == 0u && !removed(written);
    });

    passed &= run("a select under the full wave's exec must go whatever reads it", [] {
        Builder b;
        auto& full = b.threadBit(b.constant(0xffffffffu), b.constant(0xffffffffu));
        auto& old = b.lane();
        auto& written = b.select(full, b.add(old, 1u), old);
        b.keep(written);
        return b.eliminate() != 0u && removed(written);
    });

    passed &= run("a partial wave's exec is not the full wave", [] {
        Builder b;
        auto& partial = b.threadBit(b.constant(0xffffffffu), b.constant(0x0000ffffu));
        auto& old = b.lane();
        auto& written = b.select(partial, b.add(old, 1u), old);
        b.keep(written);
        return b.eliminate() == 0u && !removed(written);
    });

    const auto diamond = [](bool wideRead) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(16u));
        auto& old = b.lane();
        IrBlock& head = *b.block;
        IrBlock& body = b.newBlock();
        IrBlock& merge = b.newBlock();
        head.AddBranch(&body);
        head.AddBranch(&merge);
        body.AddBranch(&merge);
        b.block = &body;
        auto& written = b.select(exec, b.add(old, 1u), old);
        b.block = &merge;
        auto& phi = b.program.CreateValue(IrOpcode::Phi, IrType::U32);
        merge.AppendInstruction(&phi);
        phi.AddPhiOperand(&head, &old);
        phi.AddPhiOperand(&body, &written);
        b.keep(b.select(wideRead ? wide : exec, b.add(phi, 2u), old));
        return std::pair{b.eliminate(), removed(written)};
    };

    passed &= run("a write merged by a phi and read under its own exec must lose its select", [&] {
        const auto [count, gone] = diamond(false);
        return count == 1u && gone;
    });

    passed &= run("a write merged by a phi and read under the wider exec must keep its select", [&] {
        const auto [count, gone] = diamond(true);
        return count == 0u && !gone;
    });

    const auto mergedExec = [](bool wideBranch, bool loopMerge) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(32u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        IrBlock& head = *b.block;
        IrBlock& body = b.newBlock();
        IrBlock& merge = b.newBlock();
        head.AddBranch(&body);
        head.AddBranch(&merge);
        body.AddBranch(&merge);
        b.block = &body;
        auto& killed = b.logicalAnd(wideBranch ? wide : exec, b.mask(16u));
        auto& phi = b.program.CreateValue(IrOpcode::Phi, IrType::Bool);
        merge.AppendInstruction(&phi);
        phi.AddPhiOperand(&head, &exec);
        phi.AddPhiOperand(&body, &killed);
        if (loopMerge) {
            IrBlock& exit = b.newBlock();
            merge.AddBranch(&merge);
            merge.AddBranch(&exit);
            phi.AddPhiOperand(&merge, &phi);
            b.block = &exit;
        } else {
            b.block = &merge;
        }
        b.keep(b.select(phi, b.add(written, 2u), old));
        return std::pair{b.eliminate(), removed(written)};
    };

    passed &= run("an exec merged by a phi whose every incoming exec implies the write's exec drops the select", [&] {
        const auto [count, gone] = mergedExec(false, false);
        return count == 1u && gone;
    });

    passed &= run("an exec merged by a phi with a wider incoming exec keeps the select", [&] {
        const auto [count, gone] = mergedExec(true, false);
        return count == 0u && !gone;
    });

    passed &= run("an exec carried around a loop whose every incoming exec implies the write's exec drops the select", [&] {
        const auto [count, gone] = mergedExec(false, true);
        return count == 1u && gone;
    });

    passed &= run("an exec carried around a loop with a wider incoming exec keeps the select", [&] {
        const auto [count, gone] = mergedExec(true, true);
        return count == 0u && !gone;
    });

    const auto mergedWords = [](bool wideBranch) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(40u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& saved = b.emit(IrOpcode::Ballot, IrType::U32x4, {&exec});
        auto& savedLow = b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&saved, &b.constant(0u)});
        auto& savedHigh = b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&saved, &b.constant(1u)});
        IrBlock& head = *b.block;
        IrBlock& body = b.newBlock();
        IrBlock& merge = b.newBlock();
        head.AddBranch(&body);
        head.AddBranch(&merge);
        body.AddBranch(&merge);
        b.block = &body;
        auto& survived = b.emit(IrOpcode::Ballot, IrType::U32x4, {&b.logicalAnd(wideBranch ? wide : exec, b.mask(24u))});
        auto& survivedLow = b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&survived, &b.constant(0u)});
        auto& survivedHigh = b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&survived, &b.constant(1u)});
        auto& low = b.program.CreateValue(IrOpcode::Phi, IrType::U32);
        auto& high = b.program.CreateValue(IrOpcode::Phi, IrType::U32);
        merge.AppendInstruction(&low);
        merge.AppendInstruction(&high);
        low.AddPhiOperand(&head, &savedLow);
        low.AddPhiOperand(&body, &survivedLow);
        high.AddPhiOperand(&head, &savedHigh);
        high.AddPhiOperand(&body, &survivedHigh);
        b.block = &merge;
        b.keep(b.select(b.threadBit(low, high), b.add(written, 2u), old));
        return std::pair{b.eliminate(), removed(written)};
    };

    passed &= run("an exec rebuilt from mask words merged by phis implies the write's exec", [&] {
        const auto [count, gone] = mergedWords(false);
        return count == 1u && gone;
    });

    passed &= run("an exec rebuilt from merged mask words with a wider incoming ballot keeps the select", [&] {
        const auto [count, gone] = mergedWords(true);
        return count == 0u && !gone;
    });

    const auto chained = [](bool wideRoot) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(32u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        IrValue* later = wideRoot ? &wide : &exec;
        for (std::uint32_t kill = 0; kill < 24u; ++kill) later = &b.logicalAnd(*later, b.mask(31u - kill));
        b.keep(b.select(*later, b.add(written, 2u), old));
        return std::pair{b.eliminate(), removed(written)};
    };

    passed &= run("an exec narrowed by a long chain of kills still implies the write's exec", [&] {
        const auto [count, gone] = chained(false);
        return count == 1u && gone;
    });

    passed &= run("a long chain of kills rooted at a wider exec keeps the select", [&] {
        const auto [count, gone] = chained(true);
        return count == 0u && !gone;
    });

    passed &= run("a write in a loop must keep its select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        IrBlock& head = *b.block;
        IrBlock& loop = b.newBlock();
        IrBlock& exit = b.newBlock();
        head.AddBranch(&loop);
        loop.AddBranch(&loop);
        loop.AddBranch(&exit);
        b.block = &loop;
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& next = b.select(exec, b.add(written, 2u), old);
        b.keep(next);
        return b.eliminate() == 0u && !removed(written);
    });

    const auto laterLoop = [](bool wideRead) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(16u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        IrBlock& head = *b.block;
        IrBlock& loop = b.newBlock();
        head.AddBranch(&loop);
        loop.AddBranch(&loop);
        b.block = &loop;
        b.keep(b.select(wideRead ? wide : exec, b.add(written, 2u), old));
        return std::pair{b.eliminate(), removed(written)};
    };

    passed &= run("a write read inside a later loop under its own exec loses its select", [&] {
        const auto [count, gone] = laterLoop(false);
        return count == 1u && gone;
    });

    passed &= run("a write read inside a later loop under a wider exec keeps its select", [&] {
        const auto [count, gone] = laterLoop(true);
        return count == 0u && !gone;
    });

    enum class Latch { Narrowed, Revived };
    const auto carried = [](Latch latch, bool readInside) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(40u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        const auto [savedLow, savedHigh] = b.ballotWords(exec);
        IrBlock& entry = *b.block;
        IrBlock& header = b.newBlock();
        IrBlock& exit = b.newBlock();
        entry.AddBranch(&header);
        header.AddBranch(&header);
        header.AddBranch(&exit);
        b.block = &header;
        auto& low = b.phi(IrType::U32, entry, *savedLow);
        auto& high = b.phi(IrType::U32, entry, *savedHigh);
        auto& value = b.phi(IrType::U32, entry, written);
        auto& loopExec = b.threadBit(low, high);
        auto& next = b.select(loopExec, b.add(value, 2u), value);
        if (readInside) b.keep(b.select(loopExec, b.add(value, 3u), old));
        if (latch == Latch::Narrowed) {
            const auto [stayLow, stayHigh] = b.ballotWords(b.mask(24u));
            low.AddPhiOperand(&header, &b.wordAnd(low, *stayLow));
            high.AddPhiOperand(&header, &b.wordAnd(high, *stayHigh));
        } else {
            const auto [revivedLow, revivedHigh] = b.ballotWords(wide);
            low.AddPhiOperand(&header, revivedLow);
            high.AddPhiOperand(&header, revivedHigh);
        }
        value.AddPhiOperand(&header, &next);
        b.block = &exit;
        b.keep(b.select(b.threadBit(*savedLow, *savedHigh), b.add(value, 4u), old));
        return std::pair{b.eliminate(), removed(written)};
    };

    passed &= run("a write carried through a loop whose exec is saved, narrowed and restored loses its select", [&] {
        const auto [count, gone] = carried(Latch::Narrowed, false);
        return count == 1u && gone;
    });

    passed &= run("a write read inside a loop under the loop's narrowed exec loses its select", [&] {
        const auto [count, gone] = carried(Latch::Narrowed, true);
        return count == 1u && gone;
    });

    passed &= run("a lane that becomes active again inside a loop and reads the write keeps the select", [&] {
        const auto [count, gone] = carried(Latch::Revived, true);
        return count == 0u && !gone;
    });

    passed &= run("a lane that becomes active again inside a loop but never reads the write lets the select go", [&] {
        const auto [count, gone] = carried(Latch::Revived, false);
        return count == 1u && gone;
    });

    passed &= run("an exec proven only by assuming a loop phi is forgotten once that phi turns out wider", [] {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(40u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        const auto [savedLow, savedHigh] = b.ballotWords(exec);
        IrBlock& entry = *b.block;
        IrBlock& header = b.newBlock();
        IrBlock& kill = b.newBlock();
        IrBlock& revive = b.newBlock();
        IrBlock& latch = b.newBlock();
        IrBlock& exit = b.newBlock();
        entry.AddBranch(&header);
        header.AddBranch(&kill);
        header.AddBranch(&revive);
        kill.AddBranch(&latch);
        revive.AddBranch(&latch);
        latch.AddBranch(&header);
        latch.AddBranch(&exit);
        b.block = &header;
        auto& low = b.phi(IrType::U32, entry, *savedLow);
        auto& high = b.phi(IrType::U32, entry, *savedHigh);
        (void)b.select(b.threadBit(low, high), written, old);
        b.block = &kill;
        const auto [stayLow, stayHigh] = b.ballotWords(b.mask(24u));
        auto& killedLow = b.wordAnd(low, *stayLow);
        auto& killedHigh = b.wordAnd(high, *stayHigh);
        b.keep(b.select(b.threadBit(killedLow, killedHigh), written, old));
        b.block = &revive;
        const auto [revivedLow, revivedHigh] = b.ballotWords(wide);
        b.block = &latch;
        auto& mergedLow = b.phi(IrType::U32, kill, killedLow);
        auto& mergedHigh = b.phi(IrType::U32, kill, killedHigh);
        mergedLow.AddPhiOperand(&revive, revivedLow);
        mergedHigh.AddPhiOperand(&revive, revivedHigh);
        low.AddPhiOperand(&latch, &mergedLow);
        high.AddPhiOperand(&latch, &mergedHigh);
        return b.eliminate() == 0u && !removed(written);
    });

    passed &= run("a write mask computed inside an earlier loop does not let that loop's phis stand for it", [] {
        Builder b;
        auto& old = b.lane();
        IrBlock& entry = *b.block;
        IrBlock& header = b.newBlock();
        IrBlock& exit = b.newBlock();
        entry.AddBranch(&header);
        header.AddBranch(&header);
        header.AddBranch(&exit);
        b.block = &header;
        auto& low = b.phi(IrType::U32, entry, b.constant(0u));
        auto& high = b.phi(IrType::U32, entry, b.constant(0u));
        auto& bound = b.phi(IrType::U32, entry, b.constant(64u));
        auto& exec = b.emit(IrOpcode::ULessThan32, IrType::Bool, {&b.lane(), &bound});
        const auto [stayLow, stayHigh] = b.ballotWords(exec);
        low.AddPhiOperand(&header, stayLow);
        high.AddPhiOperand(&header, stayHigh);
        bound.AddPhiOperand(&header, &b.emit(IrOpcode::ISub32, IrType::U32, {&bound, &b.constant(8u)}));
        b.block = &exit;
        auto& written = b.select(exec, b.add(old, 1u), old);
        b.keep(b.select(b.threadBit(low, high), b.add(written, 2u), old));
        return b.eliminate() == 0u && !removed(written);
    });

    const auto sample = [](IrShaderStage stage, std::uint32_t sampleFlags, IrOpcode opcode = IrOpcode::ImageSampleRaw) {
        Builder b;
        b.program.Resources().stage = stage;
        MemoryInfo memory;
        memory.kind = ResourceKind::Image;
        memory.imageSampleFlags = sampleFlags;
        b.program.Resources().memoryInfo.push_back(memory);
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& address = b.emit(IrOpcode::MakeImageAddress, IrType::ImageAddress, {&written, &old});
        auto& image = b.emit(IrOpcode::GetImageResource, IrType::ImageResource, {});
        auto& sampler = b.emit(IrOpcode::GetSamplerResource, IrType::SamplerResource, {});
        MemoryFlags flags{0u, 0u};
        std::uint64_t bits = 0;
        std::memcpy(&bits, &flags, sizeof(flags));
        auto& sampled = b.emit(opcode, IrType::U32x4, {&image, &sampler, &address}, bits);
        b.keep(b.select(exec, b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&sampled, &b.constant(0u)}), old));
        b.eliminate();
        return removed(written);
    };

    passed &= run("an implicit-LOD pixel sample reads its quad's coordinates and keeps the select", [&] {
        return !sample(IrShaderStage::Pixel, 0u);
    });

    passed &= run("an explicit-LOD sample reads only its lane and drops the select", [&] {
        return sample(IrShaderStage::Pixel, RdnaImageSampleFlagLevelZero) && sample(IrShaderStage::Mesh, 0u);
    });

    passed &= run("a pixel gather without an LOD of its own takes it from the quad and keeps the select", [&] {
        return !sample(IrShaderStage::Pixel, 0u, IrOpcode::ImageGatherRaw) && !sample(IrShaderStage::Pixel, RdnaImageSampleFlagBias, IrOpcode::ImageGatherRaw);
    });

    passed &= run("a gather with an explicit LOD reads only its lane and drops the select", [&] {
        return sample(IrShaderStage::Pixel, RdnaImageSampleFlagLevelZero, IrOpcode::ImageGatherRaw) && sample(IrShaderStage::Pixel, RdnaImageSampleFlagLod, IrOpcode::ImageGatherRaw) &&
               sample(IrShaderStage::Mesh, 0u, IrOpcode::ImageGatherRaw);
    });

    passed &= run("an image size query reads only its lane's level and drops the select", [] {
        Builder b;
        auto& exec = b.mask(16u);
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        auto& address = b.emit(IrOpcode::MakeImageAddress, IrType::ImageAddress, {&written});
        auto& size = b.emit(IrOpcode::ImageQueryDimensions, IrType::U32x4, {&b.emit(IrOpcode::GetImageResource, IrType::ImageResource, {}), &address});
        b.keep(b.select(exec, b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&size, &b.constant(0u)}), old));
        return b.eliminate() == 1u && removed(written);
    });

    const auto guarded = [](IrOpcode opcode, bool sameExec, bool asActive) {
        Builder b;
        auto& wide = b.mask(48u);
        auto& exec = b.logicalAnd(wide, b.mask(16u));
        auto& old = b.lane();
        auto& written = b.select(exec, b.add(old, 1u), old);
        IrValue& active = asActive ? b.emit(IrOpcode::INotEqual32, IrType::Bool, {&written, &b.constant(0u)}) : sameExec ? exec : wide;
        switch (opcode) {
            case IrOpcode::WriteSharedU32:
                b.emit(opcode, IrType::Void, {&old, &written, &active});
                break;
            case IrOpcode::LoadBufferU32:
                b.keep(b.select(exec, b.emit(opcode, IrType::U32, {&b.emit(IrOpcode::GetBufferResource, IrType::BufferResource, {}), &written, &b.constant(0u), &b.constant(0u), &active}), old));
                break;
            case IrOpcode::ImageRead: {
                auto& address = b.emit(IrOpcode::MakeImageAddress, IrType::ImageAddress, {&written, &old});
                auto& image = b.emit(IrOpcode::GetImageResource, IrType::ImageResource, {});
                auto& read = b.emit(opcode, IrType::U32x4, {&image, &address, &active});
                b.keep(b.select(exec, b.emit(IrOpcode::CompositeExtractU32x4, IrType::U32, {&read, &b.constant(0u)}), old));
                break;
            }
            case IrOpcode::ImageWrite: {
                auto& address = b.emit(IrOpcode::MakeImageAddress, IrType::ImageAddress, {&old, &old});
                auto& texel = b.emit(IrOpcode::CompositeConstructU32x4, IrType::U32x4, {&written, &old, &old, &old});
                b.emit(opcode, IrType::Void, {&b.emit(IrOpcode::GetImageResource, IrType::ImageResource, {}), &address, &texel, &active});
                break;
            }
            default:
                b.emit(opcode, IrType::Void, {&b.emit(IrOpcode::CompositeConstructU32x4, IrType::U32x4, {&written, &old, &old, &old}), &active});
                break;
        }
        b.eliminate();
        return removed(written);
    };

    passed &= run("a store, load or export whose exec implies the write's exec drops the select", [&] {
        return guarded(IrOpcode::WriteSharedU32, true, false) && guarded(IrOpcode::LoadBufferU32, true, false) && guarded(IrOpcode::ImageRead, true, false) && guarded(IrOpcode::SetAttribute, true, false);
    });

    passed &= run("a store, load or export under a wider exec keeps the select", [&] {
        return !guarded(IrOpcode::WriteSharedU32, false, false) && !guarded(IrOpcode::LoadBufferU32, false, false) && !guarded(IrOpcode::ImageRead, false, false) && !guarded(IrOpcode::SetAttribute, false, false);
    });

    passed &= run("an image write under the write's exec drops the select, under a wider exec or as its exec keeps it", [&] {
        return guarded(IrOpcode::ImageWrite, true, false) && !guarded(IrOpcode::ImageWrite, false, false) && !guarded(IrOpcode::ImageWrite, true, true);
    });

    passed &= run("a value used as a store's exec keeps the select", [&] {
        return !guarded(IrOpcode::WriteSharedU32, true, true);
    });

    passed &= run("an atomic keeps the select", [&] {
        return !guarded(IrOpcode::SharedAtomicIAdd32, true, false);
    });

    return passed ? 0 : 1;
}
