#include "IntermediateRepresentation/IrBuilder.hpp"
#include "Optimization/ConstantFolder.hpp"
#include "Optimization/DeadCodeEliminator.hpp"
#include <cstdio>
#include <stdexcept>

using namespace ShaderRecompiler;

namespace {

void Require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void CheckDiamond(unsigned mode) {
    IrProgram program;
    for (std::uint32_t id = 0; id < 4u; ++id) {
        auto& block = program.CreateBlock();
        program.BlockOrder().push_back(&block);
        BlockInfo info;
        info.id = id;
        info.terminator.kind = TerminatorKind::Return;
        program.Metadata().blockInfo.push_back(info);
    }
    auto& entry = *program.BlockOrder()[0];
    auto& left = *program.BlockOrder()[1];
    auto& right = *program.BlockOrder()[2];
    auto& merge = *program.BlockOrder()[3];
    program.SetEntryBlock(entry);
    entry.AddBranch(&left);
    entry.AddBranch(&right);
    left.AddBranch(&merge);
    right.AddBranch(&merge);
    auto& entryInfo = program.Metadata().blockInfo[0];
    entryInfo.terminator.kind = TerminatorKind::ConditionalBranch;
    entryInfo.terminator.trueBlock = 1u;
    entryInfo.terminator.falseBlock = 2u;
    for (std::uint32_t id = 1; id < 3u; ++id) {
        program.Metadata().blockInfo[id].terminator.kind = TerminatorKind::Branch;
        program.Metadata().blockInfo[id].terminator.trueBlock = 3u;
    }
    IrBuilder builder(program);
    builder.SetInsertionPoint(entry);
    auto& lane = builder.Emit(IrOpcode::LaneId, IrType::U32, {});
    auto& limit = builder.Constant(16u);
    auto& condition = builder.Emit(IrOpcode::ULessThan32, IrType::Bool, {&lane, &limit});
    entryInfo.condition = &condition;
    auto& one = builder.Constant(1u);
    auto& two = builder.Constant(2u);
    IrValue* first = &lane;
    IrValue* second = &lane;
    if (mode == 0u || mode == 1u) {
        builder.SetInsertionPoint(left);
        first = mode == 0u ? &builder.Emit(IrOpcode::SelectU32, IrType::U32, {&condition, &one, &two}) : &builder.Emit(IrOpcode::LaneId, IrType::U32, {});
        builder.SetInsertionPoint(right);
        second = mode == 0u ? &builder.Emit(IrOpcode::SelectU32, IrType::U32, {&condition, &one, &two}) : &builder.Emit(IrOpcode::LaneId, IrType::U32, {});
    } else if (mode == 3u || mode == 4u) {
        first = &one;
        second = &program.CreateValue(IrOpcode::Void, IrType::U32);
        second->SetImmediateU32(mode == 3u ? 1u : 2u);
    }
    builder.SetInsertionPoint(merge);
    auto& phi = builder.Emit(IrOpcode::Phi, IrType::U32, {});
    phi.AddPhiOperand(&left, first);
    phi.AddPhiOperand(&right, second);
    auto& reference = builder.Emit(IrOpcode::ReferenceU32, IrType::Void, {&phi});
    ValidateProgram(program, true);
    ConstantFolder{}.Fold(program);
    DeadCodeEliminator{}.RemoveIdentities(program);
    DeadCodeEliminator{}.Eliminate(program);
    ValidateProgram(program, true);
    const auto* result = reference.Argument(0)->Resolve();
    if (mode == 0u || mode == 1u || mode == 4u) {
        Require(result == &phi && phi.Argument(0) == first && phi.Argument(1) == second, "phi lost distinct branch definitions or constants");
    } else {
        Require(result == first, "phi did not fold identical definitions or equal constants");
    }
}

}

int main() {
    try {
        for (unsigned mode = 0; mode < 5u; ++mode) CheckDiamond(mode);
        std::puts("constant phi dominance tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
