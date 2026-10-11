#include "IntermediateRepresentation/IrBuilder.hpp"
#include "Optimization/ConstantFolder.hpp"
#include "Optimization/DeadCodeEliminator.hpp"
#include "Optimization/MaskedSelectEliminator.hpp"
#include "Optimization/ShaderInfoCollector.hpp"
#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>

using namespace ShaderRecompiler;
static void Require(bool value) { if (!value) throw std::runtime_error("packed pixel ancillary regression"); }

constexpr std::uint32_t UnmodelledBits = 0xE000F0FFu;
constexpr std::uint32_t SelectOther = 0x5A3C9E17u;

struct Row {
    std::uint32_t sample;
    std::uint32_t layer;
    bool frontFacing;
};
constexpr std::array<Row, 6> Rows {{{0u, 0u, false}, {0u, 0u, true}, {15u, 0x1FFFu, false}, {15u, 0x1FFFu, true}, {0u, 0x1FFFu, true}, {15u, 0u, false}}};

static IrBlock& Begin(IrProgram& program) {
    program.Resources().stage = IrShaderStage::Pixel;
    program.Resources().resourceTrackingComplete = true;
    auto& block = program.CreateBlock();
    program.SetEntryBlock(block);
    program.BlockOrder().push_back(&block);
    return block;
}
static IrValue& AncillaryBuiltin(IrBuilder& builder) {
    return builder.Emit(IrOpcode::GetBuiltin, IrType::U32, {&builder.Constant(static_cast<std::uint32_t>(StageInputKind::PackedAncillary)), &builder.Constant(0u)});
}
static IrValue& FrontFacingBuiltin(IrBuilder& builder) {
    return builder.Emit(IrOpcode::GetBuiltin, IrType::U1, {&builder.Constant(static_cast<std::uint32_t>(StageInputKind::FrontFacing)), &builder.Constant(0u)});
}
static void End(IrBuilder& builder, IrValue& user) {
    static_cast<void>(builder.Emit(IrOpcode::ReferenceU32, IrType::Void, {&user}));
    static_cast<void>(builder.Emit(IrOpcode::Return, IrType::Void, {}));
}
static IrValue& Build(IrProgram& program, IrOpcode opcode, std::uint32_t offset, std::uint32_t count, bool throughSelect = false) {
    auto& block = Begin(program);
    IrBuilder builder(program);
    builder.SetInsertionPoint(block);
    IrValue& ancillary = AncillaryBuiltin(builder);
    IrValue* source = &ancillary;
    if (throughSelect) {
        source = &builder.Emit(IrOpcode::SelectU32, IrType::U32, {&FrontFacingBuiltin(builder), &ancillary, &builder.Constant(SelectOther)});
    }
    IrValue& user = opcode == IrOpcode::BitwiseOr32 ? builder.Emit(opcode, IrType::U32, {source, &builder.Constant(offset)})
                                                    : builder.Emit(opcode, IrType::U32, {source, &builder.Constant(offset), &builder.Constant(count)});
    End(builder, user);
    return user;
}
static void Lower(IrProgram& program) {
    ConstantFolder().Fold(program);
    DeadCodeEliminator().RemoveIdentities(program);
    DeadCodeEliminator().Eliminate(program);
    const ShaderPixelInputInfo pixel {};
    ShaderInfoCollector().Collect(program, ShaderStageInputInfo {nullptr, &pixel, nullptr});
}
static void ExtractVector(std::uint32_t offset, std::uint32_t count, StageInputKind kind, std::uint32_t fieldOffset) {
    IrProgram program;
    program.Resources().stage = IrShaderStage::Pixel;
    program.Resources().resourceTrackingComplete = true;
    auto& block = program.CreateBlock();
    program.SetEntryBlock(block);
    program.BlockOrder().push_back(&block);
    IrBuilder builder(program);
    builder.SetInsertionPoint(block);
    auto& ancillary = builder.Emit(IrOpcode::GetBuiltin, IrType::U32, {&builder.Constant(static_cast<std::uint32_t>(StageInputKind::PackedAncillary)), &builder.Constant(0u)});
    auto& maskedOffset = builder.BitwiseAnd(builder.Constant(offset), builder.Constant(31u));
    auto& maskedCount = builder.BitwiseAnd(builder.Constant(count), builder.Constant(31u));
    auto& available = builder.ISub(builder.Constant(32u), maskedOffset);
    auto& clampedCount = builder.Emit(IrOpcode::UMin32, IrType::U32, {&maskedCount, &available});
    auto& user = builder.Emit(IrOpcode::BitFieldUExtract, IrType::U32, {&ancillary, &maskedOffset, &clampedCount});
    static_cast<void>(builder.Emit(IrOpcode::ReferenceU32, IrType::Void, {&user}));
    static_cast<void>(builder.Emit(IrOpcode::Return, IrType::Void, {}));
    Lower(program);
    const IrValue* field = user.Argument(0)->Resolve();
    Require(field->Opcode() == IrOpcode::GetBuiltin);
    Require(static_cast<StageInputKind>(field->Argument(0)->Resolve()->ImmediateU32()) == kind);
    Require(user.Argument(1)->Resolve()->ImmediateU32() == fieldOffset);
    Require(user.Argument(2)->Resolve()->ImmediateU32() == count);
}

static void ExtractVectorMaskedCopy(std::uint32_t offset, std::uint32_t count, StageInputKind kind, std::uint32_t fieldOffset) {
    IrProgram program;
    program.Resources().stage = IrShaderStage::Pixel;
    program.Resources().resourceTrackingComplete = true;
    auto& block = program.CreateBlock();
    program.SetEntryBlock(block);
    program.BlockOrder().push_back(&block);
    IrBuilder builder(program);
    builder.SetInsertionPoint(block);
    auto& ancillary = builder.Emit(IrOpcode::GetBuiltin, IrType::U32, {&builder.Constant(static_cast<std::uint32_t>(StageInputKind::PackedAncillary)), &builder.Constant(0u)});
    auto& maskedOffset = builder.BitwiseAnd(builder.Constant(offset), builder.Constant(31u));
    auto& maskedCount = builder.BitwiseAnd(builder.Constant(count), builder.Constant(31u));
    auto& available = builder.ISub(builder.Constant(32u), maskedOffset);
    auto& clampedCount = builder.Emit(IrOpcode::UMin32, IrType::U32, {&maskedCount, &available});
    auto& user = builder.Emit(IrOpcode::BitFieldUExtract, IrType::U32, {&ancillary, &maskedOffset, &clampedCount});
    static_cast<void>(builder.Emit(IrOpcode::ReferenceU32, IrType::Void, {&user}));
    auto& lane = builder.Emit(IrOpcode::LaneId, IrType::U32, {});
    auto& active = builder.Emit(IrOpcode::ULessThan32, IrType::Bool, {&lane, &builder.Constant(16u)});
    auto& copy = builder.Emit(IrOpcode::SelectU32, IrType::U32, {&active, &ancillary, &builder.Constant(0u)});
    static_cast<void>(builder.Emit(IrOpcode::ReferenceU32, IrType::Void, {&copy}));
    static_cast<void>(builder.Emit(IrOpcode::Return, IrType::Void, {}));
    ConstantFolder().Fold(program);
    const IrValue* field = user.Argument(0)->Resolve();
    Require(field->Opcode() == IrOpcode::GetBuiltin);
    Require(static_cast<StageInputKind>(field->Argument(0)->Resolve()->ImmediateU32()) == kind);
    Require(user.Argument(1)->Resolve()->ImmediateU32() == fieldOffset);
    Require(user.Argument(2)->Resolve()->ImmediateU32() == count);
}
static void Extract(IrOpcode opcode, std::uint32_t offset, std::uint32_t count, StageInputKind kind, std::uint32_t fieldOffset) {
    IrProgram program;
    auto& user = Build(program, opcode, offset, count);
    Lower(program);
    const IrValue* field = user.Argument(0)->Resolve();
    Require(field->Opcode() == IrOpcode::GetBuiltin);
    Require(static_cast<StageInputKind>(field->Argument(0)->Resolve()->ImmediateU32()) == kind);
    Require(user.Argument(1)->Resolve()->ImmediateU32() == fieldOffset);
    Require(user.Argument(2)->Resolve()->ImmediateU32() == count);
}
static std::uint32_t BitField(std::uint32_t word, std::uint32_t offset, std::uint32_t count, bool isSigned) {
    const std::uint32_t mask = count == 32u ? ~0u : (1u << count) - 1u;
    std::uint32_t bits = (word >> offset) & mask;
    if (isSigned && ((bits >> (count - 1u)) & 1u) != 0u) {
        bits |= ~mask;
    }
    return bits;
}
static std::uint32_t Evaluate(const IrValue* value, const Row& row) {
    value = value->Resolve();
    if (value->HasImmediate()) {
        return value->ImmediateU32();
    }
    switch (value->Opcode()) {
        case IrOpcode::GetBuiltin:
            switch (static_cast<StageInputKind>(Evaluate(value->Argument(0), row))) {
                case StageInputKind::SampleId: return row.sample;
                case StageInputKind::Layer: return row.layer;
                case StageInputKind::FrontFacing: return row.frontFacing ? 1u : 0u;
                default: break;
            }
            break;
        case IrOpcode::ShiftLeftLogical32: return Evaluate(value->Argument(0), row) << Evaluate(value->Argument(1), row);
        case IrOpcode::BitwiseOr32: return Evaluate(value->Argument(0), row) | Evaluate(value->Argument(1), row);
        case IrOpcode::BitFieldUExtract:
        case IrOpcode::BitFieldSExtract:
            return BitField(Evaluate(value->Argument(0), row), Evaluate(value->Argument(1), row), Evaluate(value->Argument(2), row), value->Opcode() == IrOpcode::BitFieldSExtract);
        case IrOpcode::SelectU32: return Evaluate(value->Argument(0), row) != 0u ? Evaluate(value->Argument(1), row) : Evaluate(value->Argument(2), row);
        case IrOpcode::Phi: return Evaluate(value->Argument(row.frontFacing ? 0u : 1u), row);
        default: break;
    }
    throw std::runtime_error("packed pixel ancillary evaluation reached an unsupported value");
}
static std::uint32_t PackedWord(const Row& row) {
    return UnmodelledBits | (row.sample << 8u) | (row.layer << 16u);
}
static void Values(IrOpcode opcode, std::uint32_t offset, std::uint32_t count, bool throughSelect) {
    IrProgram program;
    auto& user = Build(program, opcode, offset, count, throughSelect);
    Lower(program);
    for (const Row& row : Rows) {
        const std::uint32_t word = throughSelect && !row.frontFacing ? SelectOther : PackedWord(row);
        Require(Evaluate(&user, row) == BitField(word, offset, count, opcode == IrOpcode::BitFieldSExtract));
    }
}
static void LateFold() {
    IrProgram program;
    auto& block = Begin(program);
    IrBuilder builder(program);
    builder.SetInsertionPoint(block);
    IrValue& ancillary = AncillaryBuiltin(builder);
    IrValue& offset = builder.Emit(IrOpcode::BitwiseAnd32, IrType::U32, {&builder.Constant(16u), &builder.Constant(31u)});
    IrValue& count = builder.Emit(IrOpcode::UMin32, IrType::U32, {&builder.Constant(11u), &builder.Constant(13u)});
    IrValue& user = builder.Emit(IrOpcode::BitFieldUExtract, IrType::U32, {&ancillary, &offset, &count});
    End(builder, user);
    Lower(program);
    const IrValue* field = user.Argument(0)->Resolve();
    Require(field->Opcode() == IrOpcode::GetBuiltin);
    Require(static_cast<StageInputKind>(field->Argument(0)->Resolve()->ImmediateU32()) == StageInputKind::Layer);
    Require(user.Argument(1)->Resolve()->ImmediateU32() == 0u);
    Require(user.Argument(2)->Resolve()->ImmediateU32() == 11u);
    for (const Row& row : Rows) {
        Require(Evaluate(&user, row) == BitField(PackedWord(row), 16u, 11u, false));
    }
}
static IrValue& Merged(IrProgram& program, IrOpcode opcode, std::uint32_t offset, std::uint32_t count, bool loop) {
    auto& entry = Begin(program);
    auto& carry = program.CreateBlock();
    auto& merge = program.CreateBlock();
    program.BlockOrder().push_back(&carry);
    program.BlockOrder().push_back(&merge);
    IrBuilder builder(program);
    builder.SetInsertionPoint(entry);
    IrValue& ancillary = AncillaryBuiltin(builder);
    IrValue& frontFacing = FrontFacingBuiltin(builder);
    IrValue& phi = program.CreateValue(IrOpcode::Phi, IrType::U32);
    IrValue* other = &builder.Constant(SelectOther);
    if (loop) {
        entry.AddBranch(&carry);
        carry.AddBranch(&carry);
        carry.AddBranch(&merge);
        carry.AppendInstruction(&phi);
        builder.SetInsertionPoint(carry);
        other = &builder.Emit(IrOpcode::SelectU32, IrType::U32, {&frontFacing, &phi, &builder.Constant(SelectOther)});
        phi.AddPhiOperand(&entry, &ancillary);
        phi.AddPhiOperand(&carry, other);
    } else {
        entry.AddBranch(&carry);
        entry.AddBranch(&merge);
        carry.AddBranch(&merge);
        merge.AppendInstruction(&phi);
        phi.AddPhiOperand(&entry, &ancillary);
        phi.AddPhiOperand(&carry, other);
    }
    builder.SetInsertionPoint(merge);
    IrValue& user = opcode == IrOpcode::BitwiseOr32 ? builder.Emit(opcode, IrType::U32, {&phi, &builder.Constant(offset)})
                                                    : builder.Emit(opcode, IrType::U32, {&phi, &builder.Constant(offset), &builder.Constant(count)});
    End(builder, user);
    return user;
}
static void MergedValues(IrOpcode opcode, std::uint32_t offset, std::uint32_t count, bool loop) {
    IrProgram program;
    auto& user = Merged(program, opcode, offset, count, loop);
    Lower(program);
    for (const Row& row : Rows) {
        const std::uint32_t word = row.frontFacing ? PackedWord(row) : SelectOther;
        Require(Evaluate(&user, row) == BitField(word, offset, count, opcode == IrOpcode::BitFieldSExtract));
    }
}
// A reader of other bits, or of the word itself, gets the word rebuilt from its known fields: the
// other bits read as zero, and no packed ancillary input is left.
static std::uint32_t RebuiltWord(const Row& row) {
    return (row.sample << 8u) | (row.layer << 16u);
}
static std::uint32_t Apply(IrOpcode opcode, std::uint32_t word, std::uint32_t offset, std::uint32_t count) {
    return opcode == IrOpcode::BitwiseOr32 ? word | offset : BitField(word, offset, count, opcode == IrOpcode::BitFieldSExtract);
}
static void RequireNoPackedWord(IrProgram& program) {
    for (const auto& block : program.Blocks()) {
        for (const IrValue* inst : block->Instructions()) {
            Require(inst->Opcode() != IrOpcode::GetBuiltin || static_cast<StageInputKind>(inst->Argument(0)->Resolve()->ImmediateU32()) != StageInputKind::PackedAncillary);
        }
    }
}
static void Opaque(IrOpcode opcode, std::uint32_t offset, std::uint32_t count, bool throughSelect = false) {
    IrProgram program;
    auto& user = Build(program, opcode, offset, count, throughSelect);
    Lower(program);
    RequireNoPackedWord(program);
    for (const Row& row : Rows) {
        const std::uint32_t word = throughSelect && !row.frontFacing ? SelectOther : RebuiltWord(row);
        Require(Evaluate(&user, row) == Apply(opcode, word, offset, count));
    }
}
// The word carried through a select into a layer extract is rebuilt from the layer alone: reading the
// sample ID would turn on per-sample shading.
static void ForwardedLayerOnly() {
    IrProgram program;
    static_cast<void>(Build(program, IrOpcode::BitFieldUExtract, 16u, 13u, true));
    Lower(program);
    for (const auto& block : program.Blocks()) {
        for (const IrValue* inst : block->Instructions()) {
            Require(inst->Opcode() != IrOpcode::GetBuiltin || static_cast<StageInputKind>(inst->Argument(0)->Resolve()->ImmediateU32()) != StageInputKind::SampleId);
        }
    }
}
static void MergedOpaque(IrOpcode opcode, std::uint32_t offset, std::uint32_t count, bool loop) {
    IrProgram program;
    auto& user = Merged(program, opcode, offset, count, loop);
    Lower(program);
    RequireNoPackedWord(program);
    for (const Row& row : Rows) {
        const std::uint32_t word = row.frontFacing ? RebuiltWord(row) : SelectOther;
        Require(Evaluate(&user, row) == Apply(opcode, word, offset, count));
    }
}
enum class HelperRead { Export, FullWaveExport, DataTestExport, Ballot };

struct HelperProgram {
    IrValue* written = nullptr;
    IrValue* layer = nullptr;
    IrValue* exported = nullptr;
};

static HelperProgram HelperOnly(IrProgram& program, HelperRead read, std::uint32_t chain = 0u) {
    auto& entry = Begin(program);
    auto& body = program.CreateBlock();
    auto& merge = program.CreateBlock();
    program.BlockOrder().push_back(&body);
    program.BlockOrder().push_back(&merge);
    entry.AddBranch(&body);
    entry.AddBranch(&merge);
    body.AddBranch(&merge);
    IrBuilder builder(program);
    builder.SetInsertionPoint(entry);
    IrValue& helper = builder.Emit(IrOpcode::GetBuiltin, IrType::U32, {&builder.Constant(static_cast<std::uint32_t>(StageInputKind::HelperInvocation)), &builder.Constant(0u)});
    IrValue& live = builder.IEqual(helper, builder.Constant(0u));
    IrValue& ancillary = AncillaryBuiltin(builder);
    IrValue& layer = builder.Emit(IrOpcode::BitFieldUExtract, IrType::U32, {&ancillary, &builder.Constant(16u), &builder.Constant(11u)});
    IrValue& target = builder.Select(live, layer, builder.Constant(0u));
    IrValue& tested = builder.LogicalAnd(live, FrontFacingBuiltin(builder));
    IrValue& written = builder.Select(read == HelperRead::DataTestExport ? tested : live, builder.Constant(SelectOther), ancillary);
    builder.SetInsertionPoint(body);
    IrValue& squared = builder.Emit(IrOpcode::FPMul32, IrType::F32, {&builder.BitCastF32(written), &builder.BitCastF32(written)});
    IrValue& killed = builder.Select(tested, builder.BitCastU32(squared), written);
    IrValue& exec = program.CreateValue(IrOpcode::Phi, IrType::Bool);
    IrValue& value = program.CreateValue(IrOpcode::Phi, IrType::U32);
    merge.AppendInstruction(&exec);
    merge.AppendInstruction(&value);
    exec.AddPhiOperand(&entry, &live);
    exec.AddPhiOperand(&body, &tested);
    value.AddPhiOperand(&entry, &written);
    value.AddPhiOperand(&body, &killed);
    builder.SetInsertionPoint(merge);
    IrValue* shaded = &value;
    for (std::uint32_t step = 0; step < chain; ++step) shaded = &builder.IAdd(*shaded, helper);
    IrValue& data = builder.Emit(IrOpcode::CompositeConstructU32x4, IrType::U32x4, {shaded, &target, &builder.Constant(0u), &builder.Constant(0u)});
    program.Metadata().exportInfo.push_back(ExportInfo {.kind = ExportTargetKind::Mrt, .index = 0u, .en = 0xFu, .done = true, .vm = true});
    IrValue& guard = read == HelperRead::FullWaveExport ? builder.ConstantBool(true) : exec;
    static_cast<void>(builder.Emit(IrOpcode::SetAttribute, IrType::Void, {&data, &guard}, ExportFlags {0u, 0u}));
    if (read == HelperRead::Ballot) {
        IrValue& ballot = builder.Emit(IrOpcode::Ballot, IrType::U32x4, {&builder.INotEqual(value, builder.Constant(0u))});
        static_cast<void>(builder.Emit(IrOpcode::ReferenceU32, IrType::Void, {&builder.CompositeExtract(ballot, 0u)}));
    }
    static_cast<void>(builder.Emit(IrOpcode::Return, IrType::Void, {}));
    return HelperProgram {&written, &layer, &value};
}
static void LowerMasked(IrProgram& program) {
    ConstantFolder().Fold(program);
    DeadCodeEliminator().RemoveIdentities(program);
    DeadCodeEliminator().Eliminate(program);
    static_cast<void>(MaskedSelectEliminator().Eliminate(program));
    DeadCodeEliminator().Eliminate(program);
    const ShaderPixelInputInfo pixel {};
    ShaderInfoCollector().Collect(program, ShaderStageInputInfo {nullptr, &pixel, nullptr});
}
static void HelperLanesOnly(std::uint32_t chain = 0u) {
    IrProgram program;
    const HelperProgram built = HelperOnly(program, HelperRead::Export, chain);
    LowerMasked(program);
    for (const IrBlock* block : program.BlockOrder()) {
        for (const IrValue* inst : block->Instructions()) {
            Require(inst->Opcode() != IrOpcode::GetBuiltin || static_cast<StageInputKind>(inst->Argument(0)->Resolve()->ImmediateU32()) != StageInputKind::PackedAncillary);
        }
    }
    Require(built.written->Parent() == nullptr);
    const IrValue* field = built.layer->Argument(0)->Resolve();
    Require(field->Opcode() == IrOpcode::GetBuiltin && static_cast<StageInputKind>(field->Argument(0)->Resolve()->ImmediateU32()) == StageInputKind::Layer);
    const IrValue* entryValue = built.exported->Argument(0)->Resolve();
    Require(entryValue->HasImmediate() && entryValue->ImmediateU32() == SelectOther);
}
// Where helper lanes may read the whole word, it is rebuilt from the typed inputs instead of refused.
static void HelperLanesRebuilt(HelperRead read, std::uint32_t chain = 0u) {
    IrProgram program;
    static_cast<void>(HelperOnly(program, read, chain));
    LowerMasked(program);
    RequireNoPackedWord(program);
}
enum class LoopRead { ExportAfter, ExportInside, UniformLoop, RevivedExportInside };

static IrValue& LaneBit(IrBuilder& builder, IrValue& low, IrValue& high) {
    IrValue& lane = builder.Emit(IrOpcode::LaneId, IrType::U32, {});
    IrValue& word = builder.Select(builder.Emit(IrOpcode::ULessThan32, IrType::Bool, {&lane, &builder.Constant(32u)}), low, high);
    IrValue& shifted = builder.Emit(IrOpcode::ShiftRightLogical32, IrType::U32, {&word, &builder.BitwiseAnd(lane, builder.Constant(31u))});
    return builder.INotEqual(builder.BitwiseAnd(shifted, builder.Constant(1u)), builder.Constant(0u));
}
static HelperProgram HelperLoop(IrProgram& program, LoopRead read) {
    auto& entry = Begin(program);
    auto& header = program.CreateBlock();
    auto& exit = program.CreateBlock();
    program.BlockOrder().push_back(&header);
    program.BlockOrder().push_back(&exit);
    entry.AddBranch(&header);
    header.AddBranch(&header);
    header.AddBranch(&exit);
    IrBuilder builder(program);
    builder.SetInsertionPoint(entry);
    IrValue& helper = builder.Emit(IrOpcode::GetBuiltin, IrType::U32, {&builder.Constant(static_cast<std::uint32_t>(StageInputKind::HelperInvocation)), &builder.Constant(0u)});
    IrValue& live = builder.IEqual(helper, builder.Constant(0u));
    IrValue& ancillary = AncillaryBuiltin(builder);
    IrValue& layer = builder.Emit(IrOpcode::BitFieldUExtract, IrType::U32, {&ancillary, &builder.Constant(16u), &builder.Constant(11u)});
    IrValue& target = builder.Select(live, layer, builder.Constant(0u));
    IrValue& written = builder.Select(live, builder.Constant(SelectOther), ancillary);
    IrValue& frontFacing = FrontFacingBuiltin(builder);
    IrValue& saved = builder.Emit(IrOpcode::Ballot, IrType::U32x4, {&live});
    IrValue& savedLow = builder.CompositeExtract(saved, 0u);
    IrValue& savedHigh = builder.CompositeExtract(saved, 1u);
    IrValue& low = program.CreateValue(IrOpcode::Phi, IrType::U32);
    IrValue& high = program.CreateValue(IrOpcode::Phi, IrType::U32);
    IrValue& value = program.CreateValue(IrOpcode::Phi, IrType::U32);
    header.AppendInstruction(&low);
    header.AppendInstruction(&high);
    header.AppendInstruction(&value);
    low.AddPhiOperand(&entry, &savedLow);
    high.AddPhiOperand(&entry, &savedHigh);
    value.AddPhiOperand(&entry, &written);
    builder.SetInsertionPoint(header);
    IrValue& loopExec = read == LoopRead::UniformLoop ? live : LaneBit(builder, low, high);
    IrValue& squared = builder.Emit(IrOpcode::FPMul32, IrType::F32, {&builder.BitCastF32(value), &builder.BitCastF32(value)});
    IrValue& next = builder.Select(loopExec, builder.BitCastU32(squared), value);
    IrValue& stay = builder.Emit(IrOpcode::Ballot, IrType::U32x4, {&frontFacing});
    IrValue& stayLow = builder.CompositeExtract(stay, 0u);
    IrValue& stayHigh = builder.CompositeExtract(stay, 1u);
    const bool revived = read == LoopRead::RevivedExportInside;
    low.AddPhiOperand(&header, revived ? &stayLow : &builder.BitwiseAnd(low, stayLow));
    high.AddPhiOperand(&header, revived ? &stayHigh : &builder.BitwiseAnd(high, stayHigh));
    value.AddPhiOperand(&header, &next);
    program.Metadata().exportInfo.push_back(ExportInfo {.kind = ExportTargetKind::Mrt, .index = 0u, .en = 0xFu, .done = true, .vm = true});
    const auto exportValue = [&](IrValue& guard) {
        IrValue& data = builder.Emit(IrOpcode::CompositeConstructU32x4, IrType::U32x4, {&value, &target, &builder.Constant(0u), &builder.Constant(0u)});
        static_cast<void>(builder.Emit(IrOpcode::SetAttribute, IrType::Void, {&data, &guard}, ExportFlags {0u, 0u}));
    };
    if (read == LoopRead::ExportInside || revived) exportValue(loopExec);
    builder.SetInsertionPoint(exit);
    if (read == LoopRead::ExportAfter) exportValue(LaneBit(builder, savedLow, savedHigh));
    if (read == LoopRead::UniformLoop) exportValue(live);
    static_cast<void>(builder.Emit(IrOpcode::Return, IrType::Void, {}));
    return HelperProgram {&written, &layer, &value};
}
static void HelperLoopOnly(LoopRead read) {
    IrProgram program;
    const HelperProgram built = HelperLoop(program, read);
    LowerMasked(program);
    for (const IrBlock* block : program.BlockOrder()) {
        for (const IrValue* inst : block->Instructions()) {
            Require(inst->Opcode() != IrOpcode::GetBuiltin || static_cast<StageInputKind>(inst->Argument(0)->Resolve()->ImmediateU32()) != StageInputKind::PackedAncillary);
        }
    }
    Require(built.written->Parent() == nullptr);
    const IrValue* field = built.layer->Argument(0)->Resolve();
    Require(field->Opcode() == IrOpcode::GetBuiltin && static_cast<StageInputKind>(field->Argument(0)->Resolve()->ImmediateU32()) == StageInputKind::Layer);
    const IrValue* entryValue = built.exported->Argument(0)->Resolve();
    Require(entryValue->HasImmediate() && entryValue->ImmediateU32() == SelectOther);
}
static void HelperLoopRebuilt(LoopRead read) {
    IrProgram program;
    static_cast<void>(HelperLoop(program, read));
    LowerMasked(program);
    RequireNoPackedWord(program);
}
int main() {
    Extract(IrOpcode::BitFieldUExtract, 8u, 4u, StageInputKind::SampleId, 0u);
    Extract(IrOpcode::BitFieldUExtract, 9u, 2u, StageInputKind::SampleId, 1u);
    Extract(IrOpcode::BitFieldUExtract, 16u, 13u, StageInputKind::Layer, 0u);
    Extract(IrOpcode::BitFieldSExtract, 20u, 9u, StageInputKind::Layer, 4u);
    Values(IrOpcode::BitFieldUExtract, 8u, 4u, false);
    Values(IrOpcode::BitFieldSExtract, 8u, 4u, false);
    Values(IrOpcode::BitFieldUExtract, 9u, 2u, false);
    Values(IrOpcode::BitFieldUExtract, 16u, 13u, false);
    Values(IrOpcode::BitFieldSExtract, 20u, 9u, false);
    Values(IrOpcode::BitFieldUExtract, 28u, 1u, false);
    LateFold();
    Values(IrOpcode::BitFieldUExtract, 8u, 4u, true);
    Values(IrOpcode::BitFieldUExtract, 16u, 13u, true);
    Values(IrOpcode::BitFieldSExtract, 20u, 9u, true);
    ForwardedLayerOnly();
    ExtractVector(16u, 11u, StageInputKind::Layer, 0u);
    ExtractVectorMaskedCopy(16u, 11u, StageInputKind::Layer, 0u);
    ExtractVectorMaskedCopy(8u, 4u, StageInputKind::SampleId, 0u);
    ExtractVector(8u, 4u, StageInputKind::SampleId, 0u);
    Opaque(IrOpcode::BitwiseOr32, 1u, 0u);
    Opaque(IrOpcode::BitwiseOr32, 1u, 0u, true);
    Opaque(IrOpcode::BitFieldUExtract, 2u, 4u);
    Opaque(IrOpcode::BitFieldUExtract, 10u, 4u);
    Opaque(IrOpcode::BitFieldUExtract, 13u, 2u);
    Opaque(IrOpcode::BitFieldUExtract, 16u, 14u);
    Opaque(IrOpcode::BitFieldUExtract, 0u, 2u);
    Opaque(IrOpcode::BitFieldUExtract, 7u, 1u);
    Opaque(IrOpcode::BitFieldUExtract, 12u, 4u);
    Opaque(IrOpcode::BitFieldUExtract, 29u, 1u);
    Opaque(IrOpcode::BitFieldUExtract, 8u, 0u);
    Opaque(IrOpcode::BitFieldUExtract, 0u, 2u, true);
    Opaque(IrOpcode::BitFieldSExtract, 12u, 4u, true);
    MergedValues(IrOpcode::BitFieldUExtract, 8u, 4u, false);
    MergedValues(IrOpcode::BitFieldUExtract, 16u, 13u, false);
    MergedValues(IrOpcode::BitFieldSExtract, 20u, 9u, false);
    MergedValues(IrOpcode::BitFieldUExtract, 16u, 11u, true);
    MergedOpaque(IrOpcode::BitwiseOr32, 1u, 0u, false);
    MergedOpaque(IrOpcode::BitFieldUExtract, 12u, 4u, false);
    MergedOpaque(IrOpcode::BitFieldUExtract, 0u, 2u, true);
    HelperLanesOnly();
    HelperLanesOnly(6000u);
    HelperLanesRebuilt(HelperRead::FullWaveExport);
    HelperLanesRebuilt(HelperRead::DataTestExport);
    HelperLanesRebuilt(HelperRead::Ballot);
    HelperLanesRebuilt(HelperRead::FullWaveExport, 6000u);
    HelperLoopOnly(LoopRead::ExportAfter);
    HelperLoopOnly(LoopRead::ExportInside);
    HelperLoopOnly(LoopRead::UniformLoop);
    HelperLoopRebuilt(LoopRead::RevivedExportInside);
}
