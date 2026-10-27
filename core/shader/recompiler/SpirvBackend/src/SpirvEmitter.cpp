#include "SpirvBackend/SpirvBda.hpp"
#include "SpirvBackend/SpirvEmitter.hpp"
#include "SpirvBackend/SpirvEmitterHelpers.hpp"
#include "SpirvBackend/SpirvEmitterState.hpp"
#include "SpirvBackend/SpirvFlowEmitter.hpp"
#include "SpirvBackend/SpirvMemory/SpirvModuleSetup.hpp"
#include "SpirvBackend/SpirvMemory/SpirvSubgroup.hpp"
#include <spirv/unified1/GLSL.std.450.h>
#include <spirv/unified1/spirv.hpp>
#include <algorithm>
#include <bit>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#include <SpirvBackend/SpirvEmitterInstructions.hpp>

namespace ShaderRecompiler {

namespace {

bool IsBlockTerminator(spv::Op op) {
    switch (op) {
    case spv::OpBranch: case spv::OpBranchConditional: case spv::OpSwitch: case spv::OpReturn: case spv::OpReturnValue:
    case spv::OpKill: case spv::OpUnreachable: case spv::OpTerminateInvocation:
        return true;
    default:
        return false;
    }
}

// A loop whose continue target is entered only from the loop's exit test (the header, or a block whose
// other target is the loop merge) keeps the whole body in the continue construct. SPIRV-Cross
// (MoltenVK's MSL path) turns such a loop into a for statement whose increment expression assigns the
// body's values but drops the header phi copies, so the loop variable never advances and the GPU
// hangs (Stray's histogram reduction). Such a loop gets an empty continue block instead: the back
// edges branch to it, it branches to the header, and the header phis name it as their predecessor;
// the old target becomes an ordinary body block.
std::vector<std::uint32_t> SplitContinueBodies(std::vector<std::uint32_t> words) {
    if (words.size() < 5) return words;
    struct Block {
        std::size_t label = 0;
        std::size_t terminator = 0;
    };
    std::unordered_map<std::uint32_t, Block> blocks;
    std::unordered_map<std::uint32_t, std::vector<std::uint32_t>> predecessors;
    struct Loop {
        std::uint32_t header;
        std::uint32_t merge;
        std::uint32_t target;
        std::size_t instruction;
    };
    std::vector<Loop> loops;
    std::uint32_t current = 0;
    for (std::size_t cursor = 5; cursor < words.size();) {
        const auto count = words[cursor] >> 16u;
        const auto op = static_cast<spv::Op>(words[cursor] & 0xffffu);
        if (count == 0 || cursor + count > words.size()) return words;
        if (op == spv::OpLabel) {
            current = words[cursor + 1];
            blocks[current].label = cursor;
        } else if (op == spv::OpLoopMerge && current != 0) {
            loops.push_back({current, words[cursor + 1], words[cursor + 2], cursor});
        } else if (IsBlockTerminator(op) && current != 0) {
            blocks[current].terminator = cursor;
            if (op == spv::OpBranch) predecessors[words[cursor + 1]].push_back(current);
            if (op == spv::OpBranchConditional) {
                predecessors[words[cursor + 2]].push_back(current);
                if (words[cursor + 3] != words[cursor + 2]) predecessors[words[cursor + 3]].push_back(current);
            }
            if (op == spv::OpSwitch) {
                // The default target, then (literal, label) pairs of 32-bit selectors.
                for (std::size_t operand = 2; operand < count; operand += 2) predecessors[words[cursor + operand]].push_back(current);
            }
            current = 0;
        }
        cursor += count;
    }
    struct Added {
        std::uint32_t id;
        std::uint32_t header;
    };
    // Keyed by the terminator of the block the added continue block follows.
    std::unordered_map<std::size_t, Added> inserts;
    auto bound = words[3];
    for (const auto& loop : loops) {
        const auto& header = blocks[loop.header];
        const auto entries = predecessors.find(loop.target);
        if (loop.target == loop.header || entries == predecessors.end() || header.terminator == 0) continue;
        const bool exitTestOnly = std::ranges::all_of(entries->second, [&](std::uint32_t from) {
            if (from == loop.header) return true;
            const auto terminator = blocks[from].terminator;
            return static_cast<spv::Op>(words[terminator] & 0xffffu) == spv::OpBranchConditional && (words[terminator + 2] == loop.merge || words[terminator + 3] == loop.merge);
        });
        if (!exitTestOnly) continue;
        // Back edges come from blocks laid out after the header (structured order).
        std::vector<std::uint32_t> backEdges;
        for (const auto from : predecessors[loop.header]) {
            if (blocks[from].label > header.label && blocks[from].terminator != 0) backEdges.push_back(from);
        }
        if (backEdges.empty()) continue;
        const auto added = bound++;
        words[loop.instruction + 2] = added;
        std::size_t last = 0;
        for (const auto from : backEdges) {
            const auto terminator = blocks[from].terminator;
            const auto count = words[terminator] >> 16u;
            for (std::size_t operand = 1; operand < count; ++operand) {
                const auto op = static_cast<spv::Op>(words[terminator] & 0xffffu);
                const bool label = op == spv::OpBranch || (op == spv::OpBranchConditional && operand >= 2 && operand <= 3) || (op == spv::OpSwitch && operand % 2 == 0);
                if (label && words[terminator + operand] == loop.header) words[terminator + operand] = added;
            }
            last = std::max(last, terminator);
        }
        // The header phis now take the back-edge values from the added block.
        for (std::size_t cursor = header.label; cursor < header.terminator;) {
            const auto count = words[cursor] >> 16u;
            if (static_cast<spv::Op>(words[cursor] & 0xffffu) == spv::OpPhi) {
                // (value, parent) pairs follow the result type and id; several back edges merge into one.
                std::vector<std::uint32_t> kept(words.begin() + static_cast<std::ptrdiff_t>(cursor), words.begin() + static_cast<std::ptrdiff_t>(cursor + 3));
                bool merged = false;
                for (std::size_t operand = 3; operand + 1 < count; operand += 2) {
                    const bool back = std::ranges::find(backEdges, words[cursor + operand + 1]) != backEdges.end();
                    if (back && backEdges.size() > 1) return words;
                    if (back && merged) continue;
                    kept.push_back(words[cursor + operand]);
                    kept.push_back(back ? added : words[cursor + operand + 1]);
                    merged |= back;
                }
                std::copy(kept.begin(), kept.end(), words.begin() + static_cast<std::ptrdiff_t>(cursor));
            }
            cursor += count;
        }
        inserts.emplace(last, Added{added, loop.header});
    }
    if (inserts.empty()) return words;
    words[3] = bound;
    std::vector<std::uint32_t> result;
    result.reserve(words.size() + inserts.size() * 4);
    result.insert(result.end(), words.begin(), words.begin() + 5);
    for (std::size_t cursor = 5; cursor < words.size();) {
        const auto count = words[cursor] >> 16u;
        result.insert(result.end(), words.begin() + static_cast<std::ptrdiff_t>(cursor), words.begin() + static_cast<std::ptrdiff_t>(cursor + count));
        if (const auto insert = inserts.find(cursor); insert != inserts.end()) {
            result.insert(result.end(), {(2u << 16u) | spv::OpLabel, insert->second.id, (2u << 16u) | spv::OpBranch, insert->second.header});
        }
        cursor += count;
    }
    return result;
}


std::uint32_t SubgroupStageBit(IrShaderStage stage) {
    switch (stage) {
    case IrShaderStage::Local:
    case IrShaderStage::Vertex: return 0x1u;
    case IrShaderStage::TessellationControl: return 0x2u;
    case IrShaderStage::TessellationEvaluation: return 0x4u;
    case IrShaderStage::Pixel: return 0x10u;
    case IrShaderStage::Mesh: return 0x80u;
    default: return 0xffffffffu;
    }
}


std::string FailureText(const IrProgram& program) {
    char hash[24];
    std::snprintf(hash, sizeof(hash), "%llx", static_cast<unsigned long long>(program.Resources().shaderHash));
    return std::string("SPIR-V emission failed: hash=0x") + hash + " stage=" + std::to_string(static_cast<unsigned>(program.Resources().stage));
}

[[noreturn]] void FailProgram(const IrProgram& program, const char* reason) {
    throw std::runtime_error(FailureText(program) + " reason=" + reason);
}

const ShaderWorkgroupInputInfo* ShaderWorkgroupInputFor(const SpirvEmitterState& state) {
    switch (state.program.Resources().stage) {
    case IrShaderStage::Compute:
        if (state.inputInfo.compute == nullptr) {
            FailProgram(state.program, "compute input info is missing");
        }
        return state.inputInfo.compute;
    case IrShaderStage::Mesh:
        if (state.inputInfo.vertex == nullptr) {
            FailProgram(state.program, "vertex input info is missing");
        }
        return &state.inputInfo.vertex->mesh;
    default:
        return nullptr;
    }
}

// Lanes of one guest wave run in lockstep, so a lane reads LDS another lane of its wave wrote without a
// barrier. Host invocations need one; it can be issued wherever the guest wave's control flow is
// uniform across the barrier's scope: the host subgroup when it holds exactly one guest wave, or the
// workgroup when the workgroup is a single wave.
std::uint32_t WaveLdsScope(const IrProgram& program, const ShaderWorkgroupInputInfo* workgroup, std::uint32_t laneCount) {
    if (program.Resources().stage != IrShaderStage::Compute || workgroup == nullptr) return 0;
    bool writes = false;
    for (const auto* block : program.BlockOrder()) {
        for (const auto* instruction : block->Instructions()) {
            const auto access = SharedAccessOf(instruction->Opcode());
            writes |= access != SharedAccess::None && access != SharedAccess::Read;
        }
    }
    if (!writes) return 0;
    const auto threads = std::max(workgroup->threadsNum[0], 1u) * std::max(workgroup->threadsNum[1], 1u) * std::max(workgroup->threadsNum[2], 1u);
    // A single-wave workgroup gets workgroup-scope barriers: on NVIDIA a subgroup-scope
    // OpControlBarrier did not make one lane's LDS writes visible to the others (Bink's decode
    // shaders read half their block as zeros), while the workgroup scope does. Debug aid:
    // APS5_WAVE_LDS_SUBGROUP=1 restores the subgroup scope for comparison.
    static const bool preferSubgroup = std::getenv("APS5_WAVE_LDS_SUBGROUP") != nullptr;
    if (!preferSubgroup && threads <= program.WaveSize()) return spv::ScopeWorkgroup;
    // A wave64 program kept at one lane per invocation (APS5_SINGLE_LANE reports a 64-wide host) spans
    // two real subgroups, so only the workgroup scope covers it; hosts wider than 32 lanes are not
    // distinguished from that case and get the same, still correct, scope.
    if (laneCount == 2u || (program.WaveSize() == workgroup->hostSubgroupSize && workgroup->hostSubgroupSize <= 32u)) return spv::ScopeSubgroup;
    return threads <= program.WaveSize() ? spv::ScopeWorkgroup : 0u;
}

}

SpirvEmitterState::SpirvEmitterState(const IrProgram& program, const ShaderStageInputInfo& inputInfo, bool meshAsCompute) : module(program.Resources().stage == IrShaderStage::Mesh && !meshAsCompute ? 0x00010400u : 0x00010300u), program(program), inputInfo(inputInfo), requirements(AnalyzeProgramRequirements(program)), meshAsCompute(meshAsCompute && program.Resources().stage == IrShaderStage::Mesh) {
}

SpirvValueEmitContext::SpirvValueEmitContext(SpirvEmitterState& state) : state(state) {
}

std::uint32_t SpirvValueEmitContext::Def(const IrValue* value) {
    if (value == nullptr) {
        Fail("direct SPIR-V emitter received a null value");
    }
    IrValue* resolved = value->Resolve();
    if (resolved == nullptr) {
        Fail("direct SPIR-V emitter received a non-value argument");
    }
    if (resolved->HasImmediate()) {
        switch (resolved->Type()) {
        case IrType::Bool:
            return ConstantBool(state, resolved->ImmediateBool());
        case IrType::U8:
            return ConstantU32(state, resolved->ImmediateU8());
        case IrType::U16:
            return ConstantU32(state, resolved->ImmediateU16());
        case IrType::U32:
            return ConstantU32(state, resolved->ImmediateU32());
        case IrType::U64:
            return ConstantU64(state, resolved->ImmediateU64());
        case IrType::F16:
            return ConstantU32(state, resolved->ImmediateF16Bits());
        case IrType::F32:
            return ConstantF32(state, std::bit_cast<std::uint32_t>(resolved->ImmediateF32()));
        default:
            break;
        }
    }
    return Result(*resolved);
}

std::uint32_t SpirvValueEmitContext::Arg(const IrValue& inst, std::size_t index) {
    return Def(inst.Argument(index));
}

std::uint32_t SpirvValueEmitContext::HalfArg(const IrValue& inst, std::size_t index, std::uint32_t half) {
    return half == this->half ? Arg(inst, index) : otherHalf->Arg(inst, index);
}

std::uint32_t SpirvValueEmitContext::Ballot(const IrValue* predicate) {
    const auto ballotType = TypeU32Vector(state, 4u);
    const auto low = EmitLaneBallot(state, otherHalf == nullptr || half == 0u ? Def(predicate) : otherHalf->Def(predicate));
    if (otherHalf == nullptr) {
        return EmitWaveBallot(state, low);
    }
    const auto lowWord = state.module.AllocateId();
    const auto highWord = state.module.AllocateId();
    const auto ballot = state.module.AllocateId();
    const auto high = EmitLaneBallot(state, half == 1u ? Def(predicate) : otherHalf->Def(predicate));
    state.module.AddFunction(spv::OpCompositeExtract, TypeU32(state), lowWord, low, 0u);
    state.module.AddFunction(spv::OpCompositeExtract, TypeU32(state), highWord, high, 0u);
    state.module.AddFunction(spv::OpCompositeConstruct, ballotType, ballot, lowWord, highWord, ConstantU32(state, 0u), ConstantU32(state, 0u));
    return ballot;
}

std::uint32_t SpirvValueEmitContext::FirstLane(std::uint32_t ballot) {
    if (otherHalf == nullptr) {
        const auto result = state.module.AllocateId();
        EmitSubgroupBallotFindLsb(state, result, ballot);
        return result;
    }
    const auto low = state.module.AllocateId();
    const auto high = state.module.AllocateId();
    const auto lowFirst = state.module.AllocateId();
    const auto highFirst = state.module.AllocateId();
    const auto lowActive = state.module.AllocateId();
    const auto result = state.module.AllocateId();
    state.module.AddFunction(spv::OpCompositeExtract, TypeU32(state), low, ballot, 0u);
    state.module.AddFunction(spv::OpCompositeExtract, TypeU32(state), high, ballot, 1u);
    state.module.AddFunction(spv::OpExtInst, TypeU32(state), lowFirst, GlslStd450(state), GLSLstd450FindILsb, low);
    state.module.AddFunction(spv::OpExtInst, TypeU32(state), highFirst, GlslStd450(state), GLSLstd450FindILsb, high);
    state.module.AddFunction(spv::OpINotEqual, TypeBool(state), lowActive, low, ConstantU32(state, 0u));
    state.module.AddFunction(spv::OpSelect, TypeU32(state), result, lowActive, lowFirst, EmitAddU32(state, highFirst, ConstantU32(state, 32u)));
    return result;
}

std::uint32_t SpirvValueEmitContext::Shuffle(const IrValue& inst, std::size_t index, std::uint32_t lane) {
    const auto type = TypeId(state, inst.Argument(index)->Type());
    if (otherHalf == nullptr) return EmitLaneShuffle(state, type, Arg(inst, index), EmitHostSubgroupLane(state, lane));
    const auto physicalLane = EmitBinaryU32(state, spv::OpBitwiseAnd, lane, ConstantU32(state, 31u));
    const auto inHigh = state.module.AllocateId();
    const auto value = state.module.AllocateId();
    const auto low = EmitLaneShuffle(state, type, HalfArg(inst, index, 0u), physicalLane);
    const auto high = EmitLaneShuffle(state, type, HalfArg(inst, index, 1u), physicalLane);
    state.module.AddFunction(spv::OpINotEqual, TypeBool(state), inHigh, EmitBinaryU32(state, spv::OpBitwiseAnd, lane, ConstantU32(state, 32u)), ConstantU32(state, 0u));
    state.module.AddFunction(spv::OpSelect, type, value, inHigh, high, low);
    return value;
}

std::uint32_t SpirvValueEmitContext::ShuffleInHalf(const IrValue& inst, std::size_t index, std::uint32_t lane) {
    if (!state.spannedWave) return Shuffle(inst, index, lane);
    const auto result = state.module.AllocateId();
    EmitSubgroupShuffleInHalf(state, TypeId(state, inst.Argument(index)->Type()), result, Arg(inst, index), lane);
    return result;
}

std::uint32_t SpirvValueEmitContext::Result(const IrValue& inst) {
    if (const auto found = definitions.find(&inst); found != definitions.end()) {
        return found->second;
    }
    const auto id = state.module.AllocateId();
    definitions.emplace(&inst, id);
    return id;
}

std::uint32_t SpirvValueEmitContext::Define(const IrValue& inst, std::uint32_t value) {
    if (const auto found = definitions.find(&inst); found != definitions.end()) {
        if (found->second != value) {
            state.module.AddFunction(spv::OpCopyObject, TypeId(state, inst.Type()), found->second, value);
        }
        return found->second;
    }
    definitions.emplace(&inst, value);
    return value;
}

std::uint32_t SpirvValueEmitContext::ResourceIndex(const IrValue* value, IrOpcode opcode) {
    const IrValue* resolved = value != nullptr ? value->Resolve() : nullptr;
    if (resolved == nullptr || resolved->Opcode() != opcode) {
        Fail("typed resource handle has the wrong producer");
    }
    return resolved->Flags<std::uint32_t>();
}

const IrValue* SpirvValueEmitContext::ImageAddress(const IrValue* value) {
    const IrValue* resolved = value != nullptr ? value->Resolve() : nullptr;
    if (resolved == nullptr || resolved->Opcode() != IrOpcode::MakeImageAddress) {
        Fail("typed image address was not constructed by MakeImageAddress");
    }
    return resolved;
}

const MemoryInfo& SpirvValueEmitContext::Memory(const IrValue& inst) const {
    return state.program.Resources().memoryInfo.at(inst.Flags<MemoryFlags>().index);
}

const ExportInfo& SpirvValueEmitContext::Export(const IrValue& inst) const {
    return state.program.Metadata().exportInfo.at(inst.Flags<ExportFlags>().index);
}

std::uint32_t SpirvValueEmitContext::Label(const IrBlock* block) const {
    return state.labels.at(block);
}

[[noreturn]] void SpirvValueEmitContext::Fail(const char* reason) const {
    FailProgram(state.program, reason);
}

[[noreturn]] void SpirvValueEmitContext::Fail(const IrValue& inst, const char* reason) const {
    throw std::runtime_error(FailureText(state.program) + " opcode=" + std::string(IrOpcodeName(inst.Opcode())) + " reason=" + reason);
}

std::vector<std::uint32_t> SpirvEmitter::Emit(const IrProgram& program, const CompiledBindingLayout& bindings, const SpirvTargetOptions& target) const {
    return Emit(program, ShaderStageInputInfo {}, bindings, target);
}

std::vector<std::uint32_t> SpirvEmitter::Emit(const IrProgram& program, const ShaderStageInputInfo& inputInfo, const CompiledBindingLayout& bindings, const SpirvTargetOptions& target, SpirvEmitInfo* info) const {
    if (program.Resources().stage != IrShaderStage::Compute && program.Resources().stage != IrShaderStage::Vertex && program.Resources().stage != IrShaderStage::Pixel && program.Resources().stage != IrShaderStage::Mesh && program.Resources().stage != IrShaderStage::Local && program.Resources().stage != IrShaderStage::TessellationControl && program.Resources().stage != IrShaderStage::TessellationEvaluation) {
        FailProgram(program, "binary SPIR-V emitter received an unsupported shader stage");
    }
    if (!program.Resources().srtPlanComplete || !program.Resources().resourceTrackingComplete || !program.Metadata().shaderInfoComplete || !program.Metadata().bindingLayoutComplete) {
        FailProgram(program, "SPIR-V emitter requires a fully planned native shader program");
    }
    ValidateProgram(program, true);
    ValidateBdaTarget(program, target);
    SpirvEmitterState state(program, inputInfo, target.meshAsCompute);
    state.module.RequireVersion(target.spirvVersion);
    state.spirvVersion = target.spirvVersion;
    state.supportedCapabilities = target.supportedCapabilities;
    state.supportedExtensions = target.supportedExtensions;
    state.nonConstantImageOffsets = target.nonConstantImageOffsets;
    state.narrowSubgroupClock = target.narrowSubgroupClock;
    state.float64DenormPreserve = target.float64DenormPreserve;
    state.depthRangeRemap = target.depthRangeRemap;
    state.registrationModules = target.registrationModules;
    state.fragmentDescriptorSet = target.fragmentDescriptorSet;
    state.contractFloat = target.contractFloat;
    state.meshBarycentricPixel = target.meshBarycentricPixel;
    state.meshBarycentricVertex = target.meshBarycentricVertex;
    state.barycentricSmoothLocation = target.barycentricSmoothLocation;
    state.barycentricLinearLocation = target.barycentricLinearLocation;
    state.barycentricPositionsLocation = target.barycentricPositionsLocation;
    state.meshExportedLocations = target.meshExportedLocations;
    state.meshPerVertexLocations = target.meshPerVertexLocations;
    state.float16DenormPreserve = target.float16DenormPreserve;
    state.robustBufferAccess2 = target.robustBufferAccess2;
    state.exactRobustLoads = target.robustBufferAccess2 && target.exactRobustLoads;
    state.float32FlushToZero = target.float32FlushToZero;
    state.waveLdsMemoryBarriers = target.waveLdsMemoryBarriers;
    state.float32DenormPreserve = target.float32DenormPreserve;
    state.fusedExactArithmetic = target.fusedExactArithmetic;
    state.deviceScopeLdsMemoryBarriers = target.deviceScopeLdsMemoryBarriers;
    state.hostSubgroupSize = target.subgroupSize;
    state.singleLane = (target.subgroupStages & SubgroupStageBit(state.meshAsCompute ? IrShaderStage::Compute : program.Resources().stage)) == 0u;
    state.singleSampleImages = std::find(target.supportedCapabilities.begin(), target.supportedCapabilities.end(), static_cast<std::uint32_t>(spv::CapabilityStorageImageMultisample)) == target.supportedCapabilities.end();
    if (target.largePixelFunctionLdsBuffer && program.Resources().stage == IrShaderStage::Pixel && state.requirements.functionLds && state.requirements.functionLdsDwords > target.pixelFunctionStorageDwords) {
        state.pixelFunctionLdsBuffer = true;
        state.requirements.subgroupLocalInvocationId = true;
        state.requirements.subgroupBallot = true;
    }
    if (state.requirements.ldsLock && LdsInDeviceMemory(state) && std::find(target.supportedCapabilities.begin(), target.supportedCapabilities.end(), static_cast<std::uint32_t>(spv::CapabilityInt64Atomics)) != target.supportedCapabilities.end()) {
        state.requirements.ldsLock = false;
        state.requirements.ldsBufferInt64Atomics = true;
    }
    const bool int64Atomics = std::ranges::find(state.supportedCapabilities, static_cast<std::uint32_t>(spv::CapabilityInt64Atomics)) != state.supportedCapabilities.end();
    state.requirements.bufferU64View = state.requirements.bufferInt64Atomics || (state.requirements.coherentBufferPairs && int64Atomics);
    if (HostSubgroupSingleLane(state)) {
        state.requirements.subgroupBallot = false;
        state.requirements.subgroupShuffle = false;
        state.requirements.subgroupLocalInvocationId = false;
    }
    state.splitSubgroup = !HostSubgroupSingleLane(state) && program.WaveSize() == 32u && target.subgroupSize > 32u;
    if (state.splitSubgroup && (state.requirements.subgroupBallot || state.requirements.subgroupShuffle)) state.requirements.subgroupLocalInvocationId = true;
    const auto* workgroup = ShaderWorkgroupInputFor(state);
    const bool halfHost = workgroup != nullptr && program.WaveSize() == 64u && workgroup->hostSubgroupSize == 32u;
    state.spannedWave = halfHost && target.spannedWaves && program.Resources().stage == IrShaderStage::Compute && !state.requirements.computeDerivatives && std::max(workgroup->threadsNum[0], 1u) * std::max(workgroup->threadsNum[1], 1u) * std::max(workgroup->threadsNum[2], 1u) == 64u;
    state.laneCount = halfHost && !state.spannedWave ? 2u : 1u;
    if (state.spannedWave) {
        state.requirements.subgroupLocalInvocationId = true;
        state.requirements.subgroupBallot = true;
        state.requirements.subgroupShuffle = true;
    }
    if (state.laneCount == 2u) state.sharedLaneValues = WaveUniformValues(program);
    if (program.Resources().stage == IrShaderStage::Compute && workgroup != nullptr) {
        // The key comes from a subgroup ballot (ReadFirstLane), so the slot is uniform over the
        // workgroup only when the workgroup is one wave held by one host subgroup; a wave64 program
        // kept at one lane per invocation spans two subgroups (see WaveLdsScope).
        const auto threads = std::max(workgroup->threadsNum[0], 1u) * std::max(workgroup->threadsNum[1], 1u) * std::max(workgroup->threadsNum[2], 1u);
        const bool oneSubgroup = state.laneCount == 2u || state.spannedWave || (program.WaveSize() == workgroup->hostSubgroupSize && workgroup->hostSubgroupSize <= 32u);
        state.tableIndexNonUniform = threads > program.WaveSize() || !oneSubgroup;
    }
    state.waveLdsScope = WaveLdsScope(program, workgroup, state.laneCount);
    if (const char* guard = std::getenv("APS5_LOOP_GUARD")) state.loopGuardLimit = static_cast<std::uint32_t>(std::strtoul(guard, nullptr, 0));
    // Stopped invocations would leave the wave LDS barriers incomplete.
    state.bdaStopsInvocations = state.waveLdsScope == 0 && !state.spannedWave && BdaInvocationsMayStop(program) && program.Resources().stage != IrShaderStage::Mesh;
    EmitModuleHeader(state, bindings);
    EmitProgram(state);
    state.module.EmitEntryPoint(state.meshAsCompute ? static_cast<std::uint32_t>(spv::ExecutionModelGLCompute) : ExecutionModelForStage(state.program.Resources().stage), state.mainFunc, "main", state.interfaceVariables);
    if (info != nullptr) {
        info->fullSubgroups = state.spannedWave;
        info->functionLdsBuffer = state.pixelFunctionLdsBuffer;
    }
    return SplitContinueBodies(state.module.Finalize());
}

}
