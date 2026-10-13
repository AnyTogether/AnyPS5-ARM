#include "Recompiler.hpp"
#include "SpirvBackend/SpirvModule.hpp"
#if ANYPS5_ENABLE_SPIRV_TOOLS
#include "SpirvBackend/SpirvOptimizer.hpp"
#endif
#include <algorithm>
#include <array>
#include <bit>
#include <map>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>

namespace ShaderRecompiler {
namespace {

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(std::string("Mesh pass-through SPIR-V: ") + message);
}

struct Parameter {
    std::uint32_t location;
    std::uint32_t slot;
    bool missing;
};

class PassthroughEmitter {
public:
    PassthroughEmitter(std::uint32_t version, std::uint32_t recordSlots, const std::vector<Parameter>& parameters, bool layered) : builder(version), recordSlots(recordSlots), parameters(parameters), layered(layered) {
    }

    std::vector<std::uint32_t> Emit() {
        builder.EmitCapability(spv::CapabilityShader);
        builder.EmitCapability(spv::CapabilityInt64);
        builder.EmitCapability(spv::CapabilityPhysicalStorageBufferAddresses);
        builder.EmitExtension("SPV_KHR_physical_storage_buffer");
        if (layered) {
            builder.EmitCapability(spv::CapabilityShaderViewportIndexLayerEXT);
            builder.EmitExtension("SPV_EXT_shader_viewport_index_layer");
        }
        builder.AddMemoryModel(spv::AddressingModelPhysicalStorageBuffer64, spv::MemoryModelGLSL450);

        voidType = type(spv::OpTypeVoid);
        boolType = type(spv::OpTypeBool);
        uintType = type(spv::OpTypeInt, 32u, 0u);
        intType = type(spv::OpTypeInt, 32u, 1u);
        ulongType = type(spv::OpTypeInt, 64u, 0u);
        floatType = type(spv::OpTypeFloat, 32u);
        vec4Type = type(spv::OpTypeVector, floatType, 4u);
        uvec4Type = type(spv::OpTypeVector, uintType, 4u);
        const auto functionType = type(spv::OpTypeFunction, voidType);

        const auto words = type(spv::OpTypeArray, uintType, uintConstant(32u));
        builder.AddAnnotation(spv::OpDecorate, words, spv::DecorationArrayStride, 4u);
        const auto block = builder.DecoratedType(spv::OpTypeStruct, {{spv::OpMemberDecorate, {0u, spv::DecorationOffset, 0u}}, {spv::OpDecorate, {spv::DecorationBlock}}}, words);
        push = builder.DefineGlobalVariable(pointer(spv::StorageClassPushConstant, block), spv::StorageClassPushConstant);

        main = builder.AllocateId();
        vertexIndex = addInterface(spv::StorageClassInput, intType);
        builder.AddAnnotation(spv::OpDecorate, vertexIndex, spv::DecorationBuiltIn, spv::BuiltInVertexIndex);
        position = addInterface(spv::StorageClassOutput, vec4Type);
        builder.AddAnnotation(spv::OpDecorate, position, spv::DecorationBuiltIn, spv::BuiltInPosition);
        if (layered) {
            layer = addInterface(spv::StorageClassOutput, intType);
            builder.AddAnnotation(spv::OpDecorate, layer, spv::DecorationBuiltIn, spv::BuiltInLayer);
        }
        for (const auto& parameter : parameters) {
            const auto variable = addInterface(spv::StorageClassOutput, vec4Type);
            builder.AddAnnotation(spv::OpDecorate, variable, spv::DecorationLocation, parameter.location);
            outputs.push_back(variable);
        }
        builder.EmitEntryPoint(spv::ExecutionModelVertex, main, "main", interfaces);
        builder.AddFunction(spv::OpFunction, voidType, main, spv::FunctionControlMaskNone, functionType);
        builder.AddFunction(spv::OpLabel, builder.AllocateId());

        const auto index = result(spv::OpBitcast, uintType, load(intType, vertexIndex));
        const auto primitive = result(spv::OpUDiv, uintType, index, uintConstant(3u));
        const auto corner = result(spv::OpUMod, uintType, index, uintConstant(3u));
        const auto record = loadRecord(uvec4Type, address(1u), primitive, 1u, 0u);
        const auto flags = result(spv::OpCompositeExtract, uintType, record, 3u);
        const auto culled = result(spv::OpINotEqual, boolType, result(spv::OpBitwiseAnd, uintType, flags, uintConstant(0x80000000u)), uintConstant(0u));
        const auto first = result(spv::OpCompositeExtract, uintType, record, 0u);
        const auto second = result(spv::OpCompositeExtract, uintType, record, 1u);
        const auto third = result(spv::OpCompositeExtract, uintType, record, 2u);
        const auto chosen = result(spv::OpSelect, uintType, result(spv::OpIEqual, boolType, corner, uintConstant(0u)), first, result(spv::OpSelect, uintType, result(spv::OpIEqual, boolType, corner, uintConstant(1u)), second, third));
        const auto vertex = result(spv::OpSelect, uintType, culled, uintConstant(0u), chosen);
        const auto vertices = address(0u);
        const auto loaded = loadRecord(vec4Type, vertices, vertex, recordSlots, 0u);
        const auto zero = constant(floatType, 0u);
        const auto origin = result(spv::OpCompositeConstruct, vec4Type, zero, zero, zero, constant(floatType, std::bit_cast<std::uint32_t>(1.0f)));
        store(position, result(spv::OpSelect, vec4Type, culled, origin, loaded));
        for (std::size_t i = 0; i < parameters.size(); ++i) {
            const auto value = parameters[i].missing ? result(spv::OpCompositeConstruct, vec4Type, zero, zero, zero, zero) : loadRecord(vec4Type, vertices, vertex, recordSlots, parameters[i].slot);
            store(outputs[i], value);
        }
        if (layered) store(layer, result(spv::OpBitcast, intType, result(spv::OpBitwiseAnd, uintType, flags, uintConstant(0x7ffu))));
        builder.AddFunction(spv::OpReturn);
        builder.AddFunction(spv::OpFunctionEnd);
        return builder.Finalize();
    }

private:
    template <typename... TArgs>
    std::uint32_t type(spv::Op opcode, TArgs... operands) {
        return builder.Type(opcode, operands...);
    }

    std::uint32_t constant(std::uint32_t valueType, std::uint32_t value) {
        return builder.Constant(spv::OpConstant, valueType, value);
    }

    std::uint32_t uintConstant(std::uint32_t value) { return constant(uintType, value); }

    std::uint32_t pointer(spv::StorageClass storage, std::uint32_t valueType) {
        return type(spv::OpTypePointer, storage, valueType);
    }

    template <typename... TArgs>
    std::uint32_t result(spv::Op opcode, std::uint32_t resultType, TArgs... operands) {
        const auto id = builder.AllocateId();
        builder.AddFunction(opcode, resultType, id, operands...);
        return id;
    }

    std::uint32_t load(std::uint32_t valueType, std::uint32_t variable) { return result(spv::OpLoad, valueType, variable); }

    void store(std::uint32_t variable, std::uint32_t value) { builder.AddFunction(spv::OpStore, variable, value); }

    std::uint32_t addInterface(spv::StorageClass storage, std::uint32_t valueType) {
        const auto variable = builder.DefineGlobalVariable(pointer(storage, valueType), storage);
        interfaces.push_back(variable);
        return variable;
    }

    std::uint32_t pushWord(std::uint32_t dword) {
        const auto element = result(spv::OpAccessChain, pointer(spv::StorageClassPushConstant, uintType), push, uintConstant(0u), uintConstant(dword));
        return result(spv::OpUConvert, ulongType, load(uintType, element));
    }

    std::uint32_t address(std::uint32_t pair) {
        const auto first = MeshEmulationPushOffsetBytes / 4u + pair * 2u;
        const auto high = result(spv::OpShiftLeftLogical, ulongType, pushWord(first + 1u), uintConstant(32u));
        return result(spv::OpBitwiseOr, ulongType, pushWord(first), high);
    }

    std::uint32_t loadRecord(std::uint32_t valueType, std::uint32_t base, std::uint32_t record, std::uint32_t slots, std::uint32_t slot) {
        const auto entry = result(spv::OpIAdd, uintType, result(spv::OpIMul, uintType, record, uintConstant(slots)), uintConstant(slot));
        const auto offset = result(spv::OpIMul, ulongType, result(spv::OpUConvert, ulongType, entry), constant64(16u));
        const auto element = result(spv::OpConvertUToPtr, pointer(spv::StorageClassPhysicalStorageBuffer, valueType), result(spv::OpIAdd, ulongType, base, offset));
        const auto value = builder.AllocateId();
        builder.AddFunction(spv::OpLoad, valueType, value, element, spv::MemoryAccessAlignedMask, 16u);
        return value;
    }

    std::uint32_t constant64(std::uint32_t value) {
        return builder.Constant(spv::OpConstant, ulongType, value, 0u);
    }

    SpirvModule builder;
    std::uint32_t recordSlots;
    const std::vector<Parameter>& parameters;
    bool layered;
    std::vector<std::uint32_t> interfaces;
    std::vector<std::uint32_t> outputs;
    std::uint32_t main = 0;
    std::uint32_t push = 0;
    std::uint32_t vertexIndex = 0;
    std::uint32_t position = 0;
    std::uint32_t layer = 0;
    std::uint32_t voidType = 0;
    std::uint32_t boolType = 0;
    std::uint32_t uintType = 0;
    std::uint32_t intType = 0;
    std::uint32_t ulongType = 0;
    std::uint32_t floatType = 0;
    std::uint32_t vec4Type = 0;
    std::uint32_t uvec4Type = 0;
};

}

MeshEmulationSlots EmulatedMeshSlots(const MeshConfiguration& mesh) {
    return {std::min(mesh.maxVertices, mesh.threadsPerGroup), std::min(mesh.maxPrimitives, mesh.threadsPerGroup)};
}

RecompileResult BuildMeshPassthroughVertexShader(const RecompileResult& mesh, const RecompileResult& fragment, const SpirvTarget& target, bool layered) {
    require(mesh.meshEmulation == MeshEmulationRole::Compute, "the mesh program was not compiled as a compute shader");
    require(target.spirvVersion >= 0x00010300u && target.spirvVersion <= 0x00010500u, "unsupported SPIR-V target version");
    const auto supports = [&](spv::Capability capability) { return std::find(target.supportedCapabilities.begin(), target.supportedCapabilities.end(), static_cast<std::uint32_t>(capability)) != target.supportedCapabilities.end(); };
    require(supports(spv::CapabilityInt64), "the device has no shaderInt64");
    require(!layered || supports(spv::CapabilityShaderViewportIndexLayerEXT), "a layered draw needs VK_EXT_shader_viewport_index_layer");
    std::vector<Parameter> parameters;
    std::set<std::uint32_t> locations;
    for (const auto& input : fragment.fragmentParameters) {
        require(input.location < 32 && locations.insert(input.location).second, "invalid fragment parameter location");
        require(!input.custom, "custom per-vertex interpolation is unsupported");
        const auto found = std::find(mesh.parameterExports.begin(), mesh.parameterExports.end(), input.sourceLocation);
        parameters.push_back({input.location, static_cast<std::uint32_t>(found - mesh.parameterExports.begin()) + 1u, found == mesh.parameterExports.end()});
    }
    const auto recordSlots = static_cast<std::uint32_t>(mesh.parameterExports.size()) + 1u;
    std::vector<std::uint32_t> key{target.vulkanVersion, target.spirvVersion, recordSlots, layered ? 1u : 0u, mesh.hostSubgroupSize};
    for (const auto& parameter : parameters) key.insert(key.end(), {parameter.location, parameter.slot, parameter.missing ? 1u : 0u});
    static std::mutex cacheMutex;
    static std::map<std::vector<std::uint32_t>, RecompileResult> cache;
    std::lock_guard lock(cacheMutex);
    if (const auto found = cache.find(key); found != cache.end()) return found->second;
    PassthroughEmitter emitter(target.spirvVersion, recordSlots, parameters, layered);
    RecompileResult result;
    result.spirv = emitter.Emit();
    result.meshEmulation = MeshEmulationRole::Passthrough;
    result.hostSubgroupSize = mesh.hostSubgroupSize;
#if ANYPS5_ENABLE_SPIRV_TOOLS
    result.spirv = ValidateAndOptimizeSpirv(result.spirv, target.vulkanVersion, target.spirvVersion);
#endif
    cache.emplace(std::move(key), result);
    return result;
}

}
