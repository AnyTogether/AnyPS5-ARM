#include "SpirvBackend/SpirvAluEmitter.hpp"
#include "SpirvBackend/SpirvEmitterHelpers.hpp"
#include "SpirvBackend/SpirvEmitterInstructions.hpp"
#include <stdexcept>

namespace ShaderRecompiler {

void EmitAluValue(SpirvModule& module, const IrValue& value, std::uint32_t resultId) {
    throw std::runtime_error("EmitAluValue not implemented");
}

void EmitAluValue(SpirvValueEmitContext& context, const IrValue& value, std::uint32_t resultId) {
    throw std::runtime_error("EmitAluValue not implemented");
}

void EmitGetThreadBitScalarRegister(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetThreadBitScalarRegister(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetScalarMaskTag(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetScalarMaskTag(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetScalarRegister(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetScalarRegister(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetVectorRegister(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetVectorRegister(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

std::uint32_t VectorWindowElement(SpirvValueEmitContext& ctx, const IrValue& inst) {
    auto& state = ctx.state;
    const auto pointer = state.module.AllocateId();
    state.module.AddFunction(spv::OpAccessChain, TypePointer(state, spv::StorageClassFunction, TypeU32(state)), pointer, state.vectorWindowVariable.at(state.laneHalf), ctx.Arg(inst, 0u));
    return pointer;
}

void EmitLoadVectorWindow(SpirvValueEmitContext& ctx, const IrValue& inst) {
    const auto value = ctx.state.module.AllocateId();
    ctx.state.module.AddFunction(spv::OpLoad, TypeU32(ctx.state), value, VectorWindowElement(ctx, inst));
    ctx.Define(inst, value);
}

void EmitStoreVectorWindow(SpirvValueEmitContext& ctx, const IrValue& inst) {
    ctx.state.module.AddFunction(spv::OpStore, VectorWindowElement(ctx, inst), ctx.Arg(inst, 1u));
}

void EmitGetGotoVariable(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetGotoVariable(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetScc(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetScc(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetExec(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetExec(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetExecLo(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetExecLo(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetExecHi(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetExecHi(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetVcc(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetVcc(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetVccLo(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetVccLo(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetVccHi(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetVccHi(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitGetM0(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

void EmitSetM0(SpirvValueEmitContext& ctx, const IrValue& inst) {
    EmitUnreachable(ctx, inst);
}

}
