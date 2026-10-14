#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_GRAPHICS_INCLUDE_VERTEXINPUT_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_GRAPHICS_INCLUDE_VERTEXINPUT_HPP

#include "prx/libSceAgcDriver/Graphics/include/Shaders.hpp"
#include <algorithm>
#include <cstring>
#include <limits>
#include <optional>
#include <set>
#include <span>
#include <utility>
#include <vector>

namespace AgcDriver::Graphics {

struct VertexFormat {
    VkFormat format;
    std::uint32_t bytes;
    std::uint32_t alignment;
    const char* scalar;
};

// An all-zero V#, or one whose format is the all-ones 127 (Stray binds unused streams with it), fetches
// zeros whatever its address.
inline bool NullVertexDescriptor(const ShaderRecompiler::VertexAttribute& attribute) {
    const auto& fields = attribute.resource.fields;
    const auto format = (fields[3] >> 12u) & 0x7fu;
    return (fields[0] == 0 && fields[1] == 0 && fields[2] == 0 && fields[3] == 0) || format == 0x7fu;
}

inline VertexFormat DecodeVertexFormat(const ShaderRecompiler::VertexAttribute& attribute) {
    Require(attribute.components >= 1 && attribute.components <= 4, "invalid vertex attribute component count");
    if (NullVertexDescriptor(attribute)) {
        const std::array formats{VK_FORMAT_R32_SFLOAT, VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT};
        return {formats[attribute.components - 1], attribute.components * 4u, 4u, "f32"};
    }
    const auto components = attribute.formatComponents == 0u ? attribute.components : attribute.formatComponents;
    Require(components >= 1u && components <= 4u, "invalid vertex format component count");
    const auto format = (attribute.resource.fields[3] >> 12u) & 0x7fu;
    switch (format) {
        case 1: { const std::array formats{VK_FORMAT_R8_UNORM}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 2: { const std::array formats{VK_FORMAT_R8_SNORM}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 3: { const std::array formats{VK_FORMAT_R8_USCALED}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 4: { const std::array formats{VK_FORMAT_R8_SSCALED}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 5: { const std::array formats{VK_FORMAT_R8_UINT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 1u, 1u, "u32"}; }
        case 6: { const std::array formats{VK_FORMAT_R8_SINT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 1u, 1u, "i32"}; }
        case 7: { const std::array formats{VK_FORMAT_R16_UNORM}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 8: { const std::array formats{VK_FORMAT_R16_SNORM}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 9: { const std::array formats{VK_FORMAT_R16_USCALED}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 10: { const std::array formats{VK_FORMAT_R16_SSCALED}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 11: { const std::array formats{VK_FORMAT_R16_UINT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "u32"}; }
        case 12: { const std::array formats{VK_FORMAT_R16_SINT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "i32"}; }
        case 13: { const std::array formats{VK_FORMAT_R16_SFLOAT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 14: { const std::array formats{VK_FORMAT_R8_UNORM, VK_FORMAT_R8G8_UNORM}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 15: { const std::array formats{VK_FORMAT_R8_SNORM, VK_FORMAT_R8G8_SNORM}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 16: { const std::array formats{VK_FORMAT_R8_USCALED, VK_FORMAT_R8G8_USCALED}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 17: { const std::array formats{VK_FORMAT_R8_SSCALED, VK_FORMAT_R8G8_SSCALED}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 18: { const std::array formats{VK_FORMAT_R8_UINT, VK_FORMAT_R8G8_UINT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 1u, 1u, "u32"}; }
        case 19: { const std::array formats{VK_FORMAT_R8_SINT, VK_FORMAT_R8G8_SINT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 1u, 1u, "i32"}; }
        case 20: { const std::array formats{VK_FORMAT_R32_UINT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 4u, 4u, "u32"}; }
        case 21: { const std::array formats{VK_FORMAT_R32_SINT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 4u, 4u, "i32"}; }
        case 22: { const std::array formats{VK_FORMAT_R32_SFLOAT}; const auto count = std::min(components, 1u); return {formats[count - 1], count * 4u, 4u, "f32"}; }
        case 23: { const std::array formats{VK_FORMAT_R16_UNORM, VK_FORMAT_R16G16_UNORM}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 24: { const std::array formats{VK_FORMAT_R16_SNORM, VK_FORMAT_R16G16_SNORM}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 25: { const std::array formats{VK_FORMAT_R16_USCALED, VK_FORMAT_R16G16_USCALED}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 26: { const std::array formats{VK_FORMAT_R16_SSCALED, VK_FORMAT_R16G16_SSCALED}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 27: { const std::array formats{VK_FORMAT_R16_UINT, VK_FORMAT_R16G16_UINT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "u32"}; }
        case 28: { const std::array formats{VK_FORMAT_R16_SINT, VK_FORMAT_R16G16_SINT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "i32"}; }
        case 29: { const std::array formats{VK_FORMAT_R16_SFLOAT, VK_FORMAT_R16G16_SFLOAT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 36: return {VK_FORMAT_B10G11R11_UFLOAT_PACK32, 4u, 4u, "f32"};
        case 50: return {VK_FORMAT_A2B10G10R10_UNORM_PACK32, 4u, 4u, "f32"};
        case 51: return {VK_FORMAT_A2B10G10R10_SNORM_PACK32, 4u, 4u, "f32"};
        case 52: return {VK_FORMAT_A2B10G10R10_USCALED_PACK32, 4u, 4u, "f32"};
        case 53: return {VK_FORMAT_A2B10G10R10_SSCALED_PACK32, 4u, 4u, "f32"};
        case 54: return {VK_FORMAT_A2B10G10R10_UINT_PACK32, 4u, 4u, "u32"};
        case 55: return {VK_FORMAT_A2B10G10R10_SINT_PACK32, 4u, 4u, "i32"};
        case 56: { const std::array formats{VK_FORMAT_R8_UNORM, VK_FORMAT_R8G8_UNORM, VK_FORMAT_R8G8B8_UNORM, VK_FORMAT_R8G8B8A8_UNORM}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 57: { const std::array formats{VK_FORMAT_R8_SNORM, VK_FORMAT_R8G8_SNORM, VK_FORMAT_R8G8B8_SNORM, VK_FORMAT_R8G8B8A8_SNORM}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 58: { const std::array formats{VK_FORMAT_R8_USCALED, VK_FORMAT_R8G8_USCALED, VK_FORMAT_R8G8B8_USCALED, VK_FORMAT_R8G8B8A8_USCALED}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 59: { const std::array formats{VK_FORMAT_R8_SSCALED, VK_FORMAT_R8G8_SSCALED, VK_FORMAT_R8G8B8_SSCALED, VK_FORMAT_R8G8B8A8_SSCALED}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 1u, 1u, "f32"}; }
        case 60: { const std::array formats{VK_FORMAT_R8_UINT, VK_FORMAT_R8G8_UINT, VK_FORMAT_R8G8B8_UINT, VK_FORMAT_R8G8B8A8_UINT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 1u, 1u, "u32"}; }
        case 61: { const std::array formats{VK_FORMAT_R8_SINT, VK_FORMAT_R8G8_SINT, VK_FORMAT_R8G8B8_SINT, VK_FORMAT_R8G8B8A8_SINT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 1u, 1u, "i32"}; }
        case 62: { const std::array formats{VK_FORMAT_R32_UINT, VK_FORMAT_R32G32_UINT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 4u, 4u, "u32"}; }
        case 63: { const std::array formats{VK_FORMAT_R32_SINT, VK_FORMAT_R32G32_SINT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 4u, 4u, "i32"}; }
        case 64: { const std::array formats{VK_FORMAT_R32_SFLOAT, VK_FORMAT_R32G32_SFLOAT}; const auto count = std::min(components, 2u); return {formats[count - 1], count * 4u, 4u, "f32"}; }
        case 65: { const std::array formats{VK_FORMAT_R16_UNORM, VK_FORMAT_R16G16_UNORM, VK_FORMAT_R16G16B16_UNORM, VK_FORMAT_R16G16B16A16_UNORM}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 66: { const std::array formats{VK_FORMAT_R16_SNORM, VK_FORMAT_R16G16_SNORM, VK_FORMAT_R16G16B16_SNORM, VK_FORMAT_R16G16B16A16_SNORM}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 67: { const std::array formats{VK_FORMAT_R16_USCALED, VK_FORMAT_R16G16_USCALED, VK_FORMAT_R16G16B16_USCALED, VK_FORMAT_R16G16B16A16_USCALED}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 68: { const std::array formats{VK_FORMAT_R16_SSCALED, VK_FORMAT_R16G16_SSCALED, VK_FORMAT_R16G16B16_SSCALED, VK_FORMAT_R16G16B16A16_SSCALED}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 69: { const std::array formats{VK_FORMAT_R16_UINT, VK_FORMAT_R16G16_UINT, VK_FORMAT_R16G16B16_UINT, VK_FORMAT_R16G16B16A16_UINT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "u32"}; }
        case 70: { const std::array formats{VK_FORMAT_R16_SINT, VK_FORMAT_R16G16_SINT, VK_FORMAT_R16G16B16_SINT, VK_FORMAT_R16G16B16A16_SINT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "i32"}; }
        case 71: { const std::array formats{VK_FORMAT_R16_SFLOAT, VK_FORMAT_R16G16_SFLOAT, VK_FORMAT_R16G16B16_SFLOAT, VK_FORMAT_R16G16B16A16_SFLOAT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 2u, 2u, "f32"}; }
        case 72: { const std::array formats{VK_FORMAT_R32_UINT, VK_FORMAT_R32G32_UINT, VK_FORMAT_R32G32B32_UINT}; const auto count = std::min(components, 3u); return {formats[count - 1], count * 4u, 4u, "u32"}; }
        case 73: { const std::array formats{VK_FORMAT_R32_SINT, VK_FORMAT_R32G32_SINT, VK_FORMAT_R32G32B32_SINT}; const auto count = std::min(components, 3u); return {formats[count - 1], count * 4u, 4u, "i32"}; }
        case 74: { const std::array formats{VK_FORMAT_R32_SFLOAT, VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32_SFLOAT}; const auto count = std::min(components, 3u); return {formats[count - 1], count * 4u, 4u, "f32"}; }
        case 75: { const std::array formats{VK_FORMAT_R32_UINT, VK_FORMAT_R32G32_UINT, VK_FORMAT_R32G32B32_UINT, VK_FORMAT_R32G32B32A32_UINT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 4u, 4u, "u32"}; }
        case 76: { const std::array formats{VK_FORMAT_R32_SINT, VK_FORMAT_R32G32_SINT, VK_FORMAT_R32G32B32_SINT, VK_FORMAT_R32G32B32A32_SINT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 4u, 4u, "i32"}; }
        case 77: { const std::array formats{VK_FORMAT_R32_SFLOAT, VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT}; const auto count = std::min(components, 4u); return {formats[count - 1], count * 4u, 4u, "f32"}; }
        default: throw std::runtime_error("AGC graphics: unsupported vertex format " + std::to_string(format));
    }
}

inline std::string VertexAttributeSignature(const ShaderRecompiler::VertexAttribute& attribute) {
    const auto format = DecodeVertexFormat(attribute);
    return std::string(format.scalar) + (attribute.components == 1 ? "" : "x" + std::to_string(attribute.components));
}

struct VertexInputLayout {
    std::vector<VkVertexInputBindingDescription> bindings;
    std::vector<VkVertexInputAttributeDescription> attributes;
};

inline VertexInputLayout BuildVertexInputLayout(const Context& context, std::span<const ShaderRecompiler::VertexAttribute> attributes) {
    Require(attributes.size() <= context.limits.maxVertexInputBindings && attributes.size() <= context.limits.maxVertexInputAttributes, "vertex input count exceeds device limits");
    VertexInputLayout result;
    std::set<std::uint32_t> locations;
    for (const auto& attribute : attributes) {
        const auto& fields = attribute.resource.fields;
        const auto format = DecodeVertexFormat(attribute);
        Require(attribute.location < context.limits.maxVertexInputAttributes && locations.insert(attribute.location).second, "invalid or duplicate vertex attribute location");
        Require(attribute.fetchIndex <= 1, "unsupported vertex fetch index");
        Require((fields[1] & 0x80000000u) == 0 && (fields[3] & 0x00800000u) == 0 && (fields[3] >> 30u) == 0, "unsupported vertex buffer descriptor flags");
        const auto stride = (fields[1] >> 16u) & 0x3fffu;
        const auto address = fields[0] | (static_cast<std::uint64_t>(fields[1] & 0xffffu) << 32u);
        Require(NullVertexDescriptor(attribute) || (address != 0 && address % format.alignment == 0 && stride % format.alignment == 0), "unaligned vertex buffer");
        Require(stride <= context.limits.maxVertexInputBindingStride, "vertex stride exceeds device limits");
        Require(context.formatProperties != nullptr, "missing vertex format property query");
        VkFormatProperties properties{};
        context.formatProperties(context.physical, format.format, &properties);
        Require((properties.bufferFeatures & VK_FORMAT_FEATURE_VERTEX_BUFFER_BIT) != 0, "device does not support vertex format " + std::to_string(format.format));
        const auto binding = static_cast<std::uint32_t>(result.bindings.size());
        result.bindings.push_back({binding, stride, attribute.fetchIndex == 0 ? VK_VERTEX_INPUT_RATE_VERTEX : VK_VERTEX_INPUT_RATE_INSTANCE});
        result.attributes.push_back({attribute.location, binding, format.format, 0});
    }
    return result;
}

// The whole byte range a vertex buffer descriptor covers (records * stride, or records when the
// stride is 0): what an indirect draw, whose counts only the GPU knows, copies for the fetch.
inline std::uint32_t VertexBufferOutOfBoundsSelect(const ShaderRecompiler::VertexAttribute& attribute) {
    return (attribute.resource.fields[3] >> 28u) & 3u;
}

inline bool VertexFetchOutOfRange(const ShaderRecompiler::VertexAttribute& attribute) {
    const auto stride = (attribute.resource.fields[1] >> 16u) & 0x3fffu;
    const auto select = VertexBufferOutOfBoundsSelect(attribute);
    return stride == 0 && (select == 2u || select == 3u) && attribute.resource.fields[2] == 0;
}

inline std::uint64_t ZeroStrideAvailableBytes(const ShaderRecompiler::VertexAttribute& attribute) {
    const auto records = attribute.resource.fields[2];
    if (VertexBufferOutOfBoundsSelect(attribute) == 2u && records != 0) return std::max<std::uint64_t>(records, DecodeVertexFormat(attribute).bytes);
    return records;
}

inline std::size_t VertexBufferExtent(const ShaderRecompiler::VertexAttribute& attribute) {
    if (NullVertexDescriptor(attribute)) return DecodeVertexFormat(attribute).bytes;
    const auto stride = (attribute.resource.fields[1] >> 16u) & 0x3fffu;
    const auto records = attribute.resource.fields[2];
    Require(attribute.fetchIndex <= 1, "unsupported vertex fetch index");
    const auto bytes = stride == 0 ? ZeroStrideAvailableBytes(attribute) : static_cast<std::uint64_t>(records) * stride;
    Require(bytes != 0 && bytes <= std::numeric_limits<std::size_t>::max(), "empty or oversized vertex buffer descriptor");
    const auto address = attribute.resource.fields[0] | (static_cast<std::uint64_t>(attribute.resource.fields[1] & 0xffffu) << 32u);
    Require(address != 0 && bytes <= std::numeric_limits<std::uint64_t>::max() - address, "invalid vertex buffer address range");
    return static_cast<std::size_t>(bytes);
}

inline std::size_t VertexBufferReadSize(const ShaderRecompiler::VertexAttribute& attribute, std::uint32_t maxIndex, std::uint32_t instances, std::uint32_t firstInstance = 0) {
    Require(instances != 0, "vertex input requires nonzero instance count");
    Require(firstInstance <= std::numeric_limits<std::uint32_t>::max() - (instances - 1u), "vertex input instance range overflow");
    if (NullVertexDescriptor(attribute)) return DecodeVertexFormat(attribute).bytes;
    const auto stride = (attribute.resource.fields[1] >> 16u) & 0x3fffu;
    const auto records = attribute.resource.fields[2];
    Require(attribute.fetchIndex <= 1, "unsupported vertex fetch index");
    const auto index = attribute.fetchIndex == 0 ? maxIndex : firstInstance + instances - 1u;
    const auto bytes = DecodeVertexFormat(attribute).bytes;
    Require(stride == 0 || VertexBufferOutOfBoundsSelect(attribute) <= 1u || index < records, "vertex fetch exceeds descriptor record count");
    const auto required = static_cast<std::uint64_t>(stride) * index + bytes;
    Require(stride != 0 || required <= ZeroStrideAvailableBytes(attribute), "vertex fetch exceeds descriptor byte range");
    Require(required <= std::numeric_limits<std::size_t>::max(), "vertex fetch exceeds addressable byte range");
    const auto address = attribute.resource.fields[0] | (static_cast<std::uint64_t>(attribute.resource.fields[1] & 0xffffu) << 32u);
    Require(address != 0 && required <= std::numeric_limits<std::uint64_t>::max() - address, "invalid vertex buffer address range");
    return static_cast<std::size_t>(required);
}

inline std::size_t VertexBufferReadOffset(const ShaderRecompiler::VertexAttribute& attribute, std::uint32_t firstVertex, std::uint32_t firstInstance) {
    Require(attribute.fetchIndex <= 1, "unsupported vertex fetch index");
    const auto stride = (attribute.resource.fields[1] >> 16u) & 0x3fffu;
    const auto index = attribute.fetchIndex == 0 ? firstVertex : firstInstance;
    return static_cast<std::size_t>(static_cast<std::uint64_t>(stride) * index);
}

struct VertexFetch {
    std::uint64_t begin;
    std::uint64_t end;
    std::uint32_t stride;
    std::uint32_t fetchIndex;
    std::uint32_t alignment;
};

struct VertexCopyPlan {
    std::vector<std::pair<std::uint64_t, std::uint64_t>> copies;
    std::vector<std::size_t> copyOf;
    std::vector<std::uint64_t> offsets;
    std::vector<std::uint32_t> alignments;
};

inline VertexCopyPlan PlanVertexCopies(std::span<const VertexFetch> fetches) {
    VertexCopyPlan plan;
    plan.copyOf.assign(fetches.size(), 0);
    plan.offsets.assign(fetches.size(), 0);
    std::vector<std::size_t> order(fetches.size());
    for (std::size_t i = 0; i < order.size(); ++i) order[i] = i;
    std::stable_sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
        const auto& x = fetches[a];
        const auto& y = fetches[b];
        if (x.stride != y.stride) return x.stride < y.stride;
        if (x.fetchIndex != y.fetchIndex) return x.fetchIndex < y.fetchIndex;
        return x.begin < y.begin;
    });
    std::size_t lead = fetches.size();
    for (const auto i : order) {
        const auto& fetch = fetches[i];
        Require(fetch.begin < fetch.end && fetch.alignment != 0, "empty vertex fetch range");
        const bool joins = lead != fetches.size() && fetch.stride != 0 && fetches[lead].stride == fetch.stride && fetches[lead].fetchIndex == fetch.fetchIndex && fetch.begin - fetches[lead].begin < fetch.stride && (fetch.begin - fetches[lead].begin) % fetch.alignment == 0;
        if (!joins) {
            lead = i;
            plan.copies.emplace_back(fetch.begin, fetch.end);
            plan.alignments.push_back(fetch.alignment);
        }
        plan.alignments.back() = std::max(plan.alignments.back(), fetch.alignment);
        auto& copy = plan.copies.back();
        copy.second = std::max(copy.second, fetch.end);
        plan.copyOf[i] = plan.copies.size() - 1;
        plan.offsets[i] = fetch.begin - copy.first;
    }
    return plan;
}

inline std::optional<std::uint32_t> ZeroFetchVertex(std::span<const ShaderRecompiler::VertexAttribute> attributes) {
    std::uint32_t zeroFrom = 0;
    for (const auto& attribute : attributes) {
        const auto stride = (attribute.resource.fields[1] >> 16u) & 0x3fffu;
        if (NullVertexDescriptor(attribute) || attribute.fetchIndex != 0 || stride == 0) continue;
        if (VertexBufferOutOfBoundsSelect(attribute) > 1u) return std::nullopt;
        zeroFrom = std::max(zeroFrom, attribute.resource.fields[2]);
    }
    return zeroFrom;
}

inline std::optional<std::uint32_t> ClampDrawIndices(std::span<std::byte> indices, std::uint32_t indexSize, bool skipRestart, std::uint32_t limit) {
    Require(indexSize == 2 || indexSize == 4, "unsupported index size");
    const auto restartIndex = indexSize == 2 ? 0xffffu : 0xffffffffu;
    std::optional<std::uint32_t> highest;
    for (std::size_t offset = 0; offset + indexSize <= indices.size(); offset += indexSize) {
        std::uint32_t index = 0;
        if (indexSize == 2) {
            std::uint16_t value = 0;
            std::memcpy(&value, indices.data() + offset, sizeof(value));
            index = value;
        } else {
            std::memcpy(&index, indices.data() + offset, sizeof(index));
        }
        if (skipRestart && index == restartIndex) continue;
        if (index > limit) {
            index = limit;
            if (indexSize == 2) {
                const auto value = static_cast<std::uint16_t>(index);
                std::memcpy(indices.data() + offset, &value, sizeof(value));
            } else {
                std::memcpy(indices.data() + offset, &index, sizeof(index));
            }
        }
        highest = std::max(highest.value_or(0u), index);
    }
    return highest;
}

inline std::optional<std::uint32_t> HighestDrawIndex(std::span<const std::byte> indices, std::uint32_t indexSize, bool skipRestart) {
    Require(indexSize == 2 || indexSize == 4, "unsupported index size");
    const auto restartIndex = indexSize == 2 ? 0xffffu : 0xffffffffu;
    std::optional<std::uint32_t> highest;
    for (std::size_t offset = 0; offset + indexSize <= indices.size(); offset += indexSize) {
        std::uint32_t index = 0;
        if (indexSize == 2) {
            std::uint16_t value = 0;
            std::memcpy(&value, indices.data() + offset, sizeof(value));
            index = value;
        } else {
            std::memcpy(&index, indices.data() + offset, sizeof(index));
        }
        if (skipRestart && index == restartIndex) continue;
        highest = std::max(highest.value_or(0u), index);
    }
    return highest;
}

inline std::vector<std::uint32_t> MeshRestartTable(std::span<const std::byte> indices, std::uint32_t indexSize) {
    Require(indexSize == 2 || indexSize == 4, "unsupported index size");
    const auto restartIndex = indexSize == 2 ? 0xffffu : 0xffffffffu;
    std::vector<std::uint32_t> starts(indices.size() / indexSize);
    std::uint32_t stripStart = 0;
    bool restarted = false;
    for (std::size_t position = 0; position < starts.size(); ++position) {
        std::uint32_t index = 0;
        if (indexSize == 2) {
            std::uint16_t value = 0;
            std::memcpy(&value, indices.data() + position * 2u, sizeof(value));
            index = value;
        } else {
            std::memcpy(&index, indices.data() + position * 4u, sizeof(index));
        }
        if (index == restartIndex) {
            restarted = true;
            stripStart = static_cast<std::uint32_t>(position) + 1u;
        }
        starts[position] = stripStart;
    }
    if (!restarted) starts.clear();
    return starts;
}

// An index past every vertex descriptor's record count fetches zeros on the GPU, but a copy padded
// with zeros up to it can reach gigabytes (Stray draws quads whose six indices are all 0xffffffff
// with primitive restart off). The largest record count and stride among the per-vertex fetches
// (the zero vertex goes at that record count) or nothing when no fetch depends on the index.
struct IndexedRecords {
    std::uint64_t records = 0;
    std::uint64_t stride = 0;
};

inline IndexedRecords IndexedFetchRecords(std::span<const ShaderRecompiler::VertexAttribute> attributes) {
    IndexedRecords result;
    for (const auto& attribute : attributes) {
        if (attribute.fetchIndex != 0 || NullVertexDescriptor(attribute) || VertexFetchOutOfRange(attribute)) continue;
        const auto stride = (attribute.resource.fields[1] >> 16u) & 0x3fffu;
        if (stride == 0) continue;
        result.records = std::max<std::uint64_t>(result.records, attribute.resource.fields[2]);
        result.stride = std::max<std::uint64_t>(result.stride, stride);
    }
    return result;
}

// Rewrites every index whose vertex (index + firstVertex) is at or past `records` to the zero vertex
// at `records`, restart indices aside when they are skipped; returns the highest index left, or
// nothing when the zero vertex itself would read as the restart index.
inline std::optional<std::uint32_t> RedirectIndicesPastRecords(std::span<std::byte> indices, std::uint32_t indexSize, bool skipRestart, std::uint32_t firstVertex, std::uint64_t records) {
    Require(indexSize == 2 || indexSize == 4, "unsupported index size");
    const auto restartIndex = indexSize == 2 ? 0xffffu : 0xffffffffu;
    if (records < firstVertex || records - firstVertex >= restartIndex) return std::nullopt;
    const auto zeroVertex = static_cast<std::uint32_t>(records - firstVertex);
    std::uint32_t highest = zeroVertex;
    for (std::size_t offset = 0; offset + indexSize <= indices.size(); offset += indexSize) {
        std::uint32_t index = 0;
        std::memcpy(&index, indices.data() + offset, indexSize);
        if (skipRestart && index == restartIndex) continue;
        if (static_cast<std::uint64_t>(index) + firstVertex >= records) {
            index = zeroVertex;
            std::memcpy(indices.data() + offset, &index, indexSize);
        }
        highest = std::max(highest, index);
    }
    return highest;
}

// The list that draws `indices` of `topology` with each primitive's last vertex first, the winding
// kept: what a last-provoking-vertex draw becomes on a device that only provokes with the first.
// `restart` splits the indices into separate runs; a run's incomplete tail draws nothing.
inline std::vector<std::uint32_t> LastVertexFirstList(VkPrimitiveTopology topology, std::span<const std::uint32_t> indices, std::optional<std::uint32_t> restart) {
    std::vector<std::uint32_t> list;
    const auto emit = [&](std::span<const std::uint32_t> run) {
        const auto n = run.size();
        switch (topology) {
            case VK_PRIMITIVE_TOPOLOGY_LINE_LIST:
                for (std::size_t i = 0; i + 2 <= n; i += 2) list.insert(list.end(), {run[i + 1], run[i]});
                break;
            case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP:
                for (std::size_t i = 0; i + 2 <= n; ++i) list.insert(list.end(), {run[i + 1], run[i]});
                break;
            case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST:
                for (std::size_t i = 0; i + 3 <= n; i += 3) list.insert(list.end(), {run[i + 2], run[i], run[i + 1]});
                break;
            case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:
                for (std::size_t i = 0; i + 3 <= n; ++i) {
                    if (i % 2 == 0) list.insert(list.end(), {run[i + 2], run[i], run[i + 1]});
                    else list.insert(list.end(), {run[i + 2], run[i + 1], run[i]});
                }
                break;
            case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN:
                for (std::size_t i = 0; i + 3 <= n; ++i) list.insert(list.end(), {run[i + 2], run[0], run[i + 1]});
                break;
            default:
                Require(false, "last provoking vertex is unsupported for this primitive topology");
        }
    };
    std::size_t begin = 0;
    for (std::size_t i = 0; i <= indices.size(); ++i) {
        if (i < indices.size() && (!restart || indices[i] != *restart)) continue;
        emit(indices.subspan(begin, i - begin));
        begin = i + 1;
    }
    return list;
}

inline std::vector<std::size_t> SoloZeroPaddedFetchIndices(const std::vector<VertexFetch>& fetches, const std::vector<std::size_t>& fetchValid) {
    Require(fetchValid.size() == fetches.size(), "fetch validity does not match the fetch count");
    std::vector<std::size_t> solo;
    for (std::size_t i = 0; i < fetches.size(); ++i) {
        if (fetchValid[i] < fetches[i].end - fetches[i].begin) solo.push_back(i);
    }
    return solo;
}

}

#endif

