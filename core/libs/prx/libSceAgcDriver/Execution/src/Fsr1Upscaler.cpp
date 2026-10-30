#include "prx/libSceAgcDriver/Execution/include/Fsr1Upscaler.hpp"
#include "prx/libSceAgcDriver/Graphics/include/BufferPool.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Resources.hpp"
#include "prx/libSceAgcDriver/Graphics/shaders/Fsr1Easu_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/Fsr1EasuWide_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/Fsr1Rcas_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/Fsr1RcasWide_spv.h"
#include <cmath>
#include <stdexcept>
#include <stdint.h>
#include <string>
#include <utility>

#define A_CPU 1
#if defined(__GNUC__) || defined(__clang__)
#define A_GCC 1
#endif
#include "ffx_a.h"
#include "ffx_fsr1.h"

namespace AgcDriver {
namespace {

constexpr VkFormatFeatureFlags WorkFeatures = VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT | VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT;

struct EasuConstants {
    std::array<std::uint32_t, 16> con;
    std::array<std::uint32_t, 2> size;
};

struct RcasConstants {
    std::array<std::uint32_t, 4> con;
    std::array<std::uint32_t, 2> size;
};

std::uint32_t divideUp(std::uint32_t value, std::uint32_t by) {
    return (value + by - 1) / by;
}

bool narrow(VkFormat format) {
    switch (format) {
        case VK_FORMAT_B8G8R8A8_UNORM:
        case VK_FORMAT_B8G8R8A8_SRGB:
        case VK_FORMAT_R8G8B8A8_UNORM:
        case VK_FORMAT_R8G8B8A8_SRGB:
        case VK_FORMAT_A8B8G8R8_UNORM_PACK32:
        case VK_FORMAT_A8B8G8R8_SRGB_PACK32:
            return true;
        default:
            return false;
    }
}

void check(VkResult result, const char* operation) {
    if (result != VK_SUCCESS) throw std::runtime_error(std::string("FSR 1: ") + operation + " failed (" + std::to_string(static_cast<int>(result)) + ")");
}

}

Fsr1Upscaler::Fsr1Upscaler(const Graphics::Context& context, VkFormat destinationFormat, float sharpness) : context(context), sharpness(sharpness) {
    if (!std::isfinite(sharpness) || sharpness < 0.0f) throw std::invalid_argument("FSR 1: the sharpness must be zero or more stops");
    const auto supports = [&](VkFormat format, VkFormatFeatureFlags features) {
        VkFormatProperties properties{};
        context.formatProperties(context.physical, format, &properties);
        return (properties.optimalTilingFeatures & features) == features;
    };
    if (!supports(destinationFormat, VK_FORMAT_FEATURE_BLIT_DST_BIT)) throw std::runtime_error("FSR 1: the device lacks blits into the window's format");
    if (narrow(destinationFormat) && supports(VK_FORMAT_R8G8B8A8_UNORM, WorkFeatures)) workFormat = VK_FORMAT_R8G8B8A8_UNORM;
    else if (supports(VK_FORMAT_R16G16B16A16_SFLOAT, WorkFeatures)) workFormat = VK_FORMAT_R16G16B16A16_SFLOAT;
    else throw std::runtime_error("FSR 1: the device lacks a storage image format it can blit");
    const bool wide = workFormat == VK_FORMAT_R16G16B16A16_SFLOAT;
    try {
        VkSamplerCreateInfo samplerInfo{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
        samplerInfo.magFilter = VK_FILTER_NEAREST;
        samplerInfo.minFilter = VK_FILTER_NEAREST;
        samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        samplerInfo.addressModeU = samplerInfo.addressModeV = samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        samplerInfo.maxLod = 0.0f;
        check(context.Function<PFN_vkCreateSampler>("vkCreateSampler")(context.device, &samplerInfo, nullptr, &sampler), "vkCreateSampler");
        const std::array<VkDescriptorSetLayoutBinding, 2> bindings{{{0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}, {1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr}}};
        VkDescriptorSetLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
        layoutInfo.bindingCount = static_cast<std::uint32_t>(bindings.size());
        layoutInfo.pBindings = bindings.data();
        check(context.Function<PFN_vkCreateDescriptorSetLayout>("vkCreateDescriptorSetLayout")(context.device, &layoutInfo, nullptr, &setLayout), "vkCreateDescriptorSetLayout");
        const VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(EasuConstants)};
        VkPipelineLayoutCreateInfo pipelineLayoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
        pipelineLayoutInfo.setLayoutCount = 1;
        pipelineLayoutInfo.pSetLayouts = &setLayout;
        pipelineLayoutInfo.pushConstantRangeCount = 1;
        pipelineLayoutInfo.pPushConstantRanges = &push;
        check(context.Function<PFN_vkCreatePipelineLayout>("vkCreatePipelineLayout")(context.device, &pipelineLayoutInfo, nullptr, &pipelineLayout), "vkCreatePipelineLayout");
        const std::array<std::pair<const std::uint32_t*, std::size_t>, PassCount> code{{
            wide ? std::pair<const std::uint32_t*, std::size_t>{FSR1_EASU_WIDE_SPV, sizeof(FSR1_EASU_WIDE_SPV)} : std::pair<const std::uint32_t*, std::size_t>{FSR1_EASU_SPV, sizeof(FSR1_EASU_SPV)},
            wide ? std::pair<const std::uint32_t*, std::size_t>{FSR1_RCAS_WIDE_SPV, sizeof(FSR1_RCAS_WIDE_SPV)} : std::pair<const std::uint32_t*, std::size_t>{FSR1_RCAS_SPV, sizeof(FSR1_RCAS_SPV)}}};
        for (std::size_t pass = 0; pass < PassCount; ++pass) {
            VkShaderModuleCreateInfo moduleInfo{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
            moduleInfo.codeSize = code[pass].second;
            moduleInfo.pCode = code[pass].first;
            check(context.Function<PFN_vkCreateShaderModule>("vkCreateShaderModule")(context.device, &moduleInfo, nullptr, &modules[pass]), "vkCreateShaderModule");
            VkComputePipelineCreateInfo pipelineInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
            pipelineInfo.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
            pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
            pipelineInfo.stage.module = modules[pass];
            pipelineInfo.stage.pName = "main";
            pipelineInfo.layout = pipelineLayout;
            auto pipelineCacheLock = context.LockPipelineCacheForUse();
            check(context.Function<PFN_vkCreateComputePipelines>("vkCreateComputePipelines")(context.device, context.pipelineCache, 1, &pipelineInfo, nullptr, &pipelines[pass]), "vkCreateComputePipelines");
        }
        const std::array<VkDescriptorPoolSize, 2> sizes{{{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, PassCount}, {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, PassCount}}};
        VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
        poolInfo.maxSets = PassCount;
        poolInfo.poolSizeCount = static_cast<std::uint32_t>(sizes.size());
        poolInfo.pPoolSizes = sizes.data();
        check(context.Function<PFN_vkCreateDescriptorPool>("vkCreateDescriptorPool")(context.device, &poolInfo, nullptr, &pool), "vkCreateDescriptorPool");
        const std::array<VkDescriptorSetLayout, PassCount> layouts{setLayout, setLayout};
        VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        allocate.descriptorPool = pool;
        allocate.descriptorSetCount = PassCount;
        allocate.pSetLayouts = layouts.data();
        check(context.Function<PFN_vkAllocateDescriptorSets>("vkAllocateDescriptorSets")(context.device, &allocate, sets.data()), "vkAllocateDescriptorSets");
    } catch (...) {
        release();
        throw;
    }
}

Fsr1Upscaler::~Fsr1Upscaler() {
    release();
}

bool Fsr1Upscaler::Upscales(VkExtent2D source, VkExtent2D output) {
    return source.width != 0 && source.height != 0 && output.width > source.width && output.height > source.height;
}

bool Fsr1Upscaler::Matches(VkExtent2D source, VkExtent2D target) const {
    return input.image != VK_NULL_HANDLE && input.extent.width == source.width && input.extent.height == source.height && output.extent.width == target.width && output.extent.height == target.height;
}

Fsr1Upscaler::Image Fsr1Upscaler::makeImage(VkExtent2D extent, VkImageUsageFlags usage) {
    Image made;
    made.extent = extent;
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = workFormat;
    info.extent = {extent.width, extent.height, 1};
    info.mipLevels = 1;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    check(context.Function<PFN_vkCreateImage>("vkCreateImage")(context.device, &info, nullptr, &made.image), "vkCreateImage");
    try {
        VkMemoryRequirements requirements{};
        context.Function<PFN_vkGetImageMemoryRequirements>("vkGetImageMemoryRequirements")(context.device, made.image, &requirements);
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = context.MemoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        made.memory = Graphics::AllocateImageMemory(context, allocation, requirements.memoryTypeBits, "vkAllocateMemory FSR 1", &made.memoryType);
        made.bytes = allocation.allocationSize;
        check(context.Function<PFN_vkBindImageMemory>("vkBindImageMemory")(context.device, made.image, made.memory, 0), "vkBindImageMemory");
        VkImageViewCreateInfo viewInfo{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        viewInfo.image = made.image;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = workFormat;
        viewInfo.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        check(context.Function<PFN_vkCreateImageView>("vkCreateImageView")(context.device, &viewInfo, nullptr, &made.view), "vkCreateImageView");
    } catch (...) {
        destroy(made);
        throw;
    }
    return made;
}

void Fsr1Upscaler::destroy(Image& image) noexcept {
    if (image.view != VK_NULL_HANDLE) context.Function<PFN_vkDestroyImageView>("vkDestroyImageView")(context.device, image.view, nullptr);
    if (image.image != VK_NULL_HANDLE) context.Function<PFN_vkDestroyImage>("vkDestroyImage")(context.device, image.image, nullptr);
    if (image.memory != VK_NULL_HANDLE) Graphics::ReleaseImageMemory(context, image.memory, image.bytes, image.memoryType);
    image = Image{};
}

void Fsr1Upscaler::releaseImages() noexcept {
    destroy(input);
    destroy(easu);
    destroy(output);
}

void Fsr1Upscaler::release() noexcept {
    releaseImages();
    for (auto& pipeline : pipelines) {
        if (pipeline != VK_NULL_HANDLE) context.Function<PFN_vkDestroyPipeline>("vkDestroyPipeline")(context.device, pipeline, nullptr);
        pipeline = VK_NULL_HANDLE;
    }
    for (auto& module : modules) {
        if (module != VK_NULL_HANDLE) context.Function<PFN_vkDestroyShaderModule>("vkDestroyShaderModule")(context.device, module, nullptr);
        module = VK_NULL_HANDLE;
    }
    if (pool != VK_NULL_HANDLE) context.Function<PFN_vkDestroyDescriptorPool>("vkDestroyDescriptorPool")(context.device, pool, nullptr);
    pool = VK_NULL_HANDLE;
    sets = {};
    if (pipelineLayout != VK_NULL_HANDLE) context.Function<PFN_vkDestroyPipelineLayout>("vkDestroyPipelineLayout")(context.device, pipelineLayout, nullptr);
    pipelineLayout = VK_NULL_HANDLE;
    if (setLayout != VK_NULL_HANDLE) context.Function<PFN_vkDestroyDescriptorSetLayout>("vkDestroyDescriptorSetLayout")(context.device, setLayout, nullptr);
    setLayout = VK_NULL_HANDLE;
    if (sampler != VK_NULL_HANDLE) context.Function<PFN_vkDestroySampler>("vkDestroySampler")(context.device, sampler, nullptr);
    sampler = VK_NULL_HANDLE;
}

void Fsr1Upscaler::Resize(VkExtent2D source, VkExtent2D target) {
    if (!Upscales(source, target)) throw std::invalid_argument("FSR 1: the output must be larger than the source in both directions");
    if (Matches(source, target)) return;
    releaseImages();
    try {
        input = makeImage(source, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
        easu = makeImage(target, VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
        output = makeImage(target, VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
    } catch (...) {
        releaseImages();
        throw;
    }
    const std::array<VkDescriptorImageInfo, 4> infos{{
        {sampler, input.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}, {VK_NULL_HANDLE, easu.view, VK_IMAGE_LAYOUT_GENERAL},
        {sampler, easu.view, VK_IMAGE_LAYOUT_GENERAL}, {VK_NULL_HANDLE, output.view, VK_IMAGE_LAYOUT_GENERAL}}};
    std::array<VkWriteDescriptorSet, 4> writes{};
    for (std::size_t index = 0; index < writes.size(); ++index) {
        const bool sampled = index % 2 == 0;
        writes[index] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, sets[index / 2], static_cast<std::uint32_t>(index % 2), 0, 1,
                         sampled ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, &infos[index], nullptr, nullptr};
    }
    context.Function<PFN_vkUpdateDescriptorSets>("vkUpdateDescriptorSets")(context.device, static_cast<std::uint32_t>(writes.size()), writes.data(), 0, nullptr);
}

void Fsr1Upscaler::transition(VkCommandBuffer commands, VkImage image, VkImageLayout from, VkImageLayout to, VkPipelineStageFlags fromStage, VkAccessFlags fromAccess, VkPipelineStageFlags toStage, VkAccessFlags toAccess) const {
    VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.srcAccessMask = fromAccess;
    barrier.dstAccessMask = toAccess;
    barrier.oldLayout = from;
    barrier.newLayout = to;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    context.Function<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier")(commands, fromStage, toStage, 0, 0, nullptr, 0, nullptr, 1, &barrier);
}

void Fsr1Upscaler::dispatch(VkCommandBuffer commands, Pass pass, const void* constants, std::uint32_t bytes) const {
    context.Function<PFN_vkCmdBindPipeline>("vkCmdBindPipeline")(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelines[pass]);
    context.Function<PFN_vkCmdBindDescriptorSets>("vkCmdBindDescriptorSets")(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &sets[pass], 0, nullptr);
    context.Function<PFN_vkCmdPushConstants>("vkCmdPushConstants")(commands, pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, bytes, constants);
    context.Function<PFN_vkCmdDispatch>("vkCmdDispatch")(commands, divideUp(output.extent.width, 8), divideUp(output.extent.height, 8), 1);
}

void Fsr1Upscaler::Record(VkCommandBuffer commands, VkImage source, VkImageLayout layout, std::uint32_t layer, VkImage destination, VkOffset2D at) {
    if (input.image == VK_NULL_HANDLE) throw std::logic_error("FSR 1: Record before Resize");
    if (source == VK_NULL_HANDLE || destination == VK_NULL_HANDLE) throw std::invalid_argument("FSR 1: no source or destination image");
    const auto blit = context.Function<PFN_vkCmdBlitImage>("vkCmdBlitImage");
    const auto inWidth = static_cast<std::int32_t>(input.extent.width), inHeight = static_cast<std::int32_t>(input.extent.height);
    const auto outWidth = static_cast<std::int32_t>(output.extent.width), outHeight = static_cast<std::int32_t>(output.extent.height);
    transition(commands, input.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    VkImageBlit copy{};
    copy.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, layer, 1};
    copy.srcOffsets[1] = {inWidth, inHeight, 1};
    copy.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.dstOffsets[1] = {inWidth, inHeight, 1};
    blit(commands, source, layout, input.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy, VK_FILTER_NEAREST);
    transition(commands, input.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT);
    transition(commands, easu.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
    EasuConstants easuConstants{};
    FsrEasuCon(&easuConstants.con[0], &easuConstants.con[4], &easuConstants.con[8], &easuConstants.con[12], static_cast<AF1>(inWidth), static_cast<AF1>(inHeight), static_cast<AF1>(inWidth),
               static_cast<AF1>(inHeight), static_cast<AF1>(outWidth), static_cast<AF1>(outHeight));
    easuConstants.size = {output.extent.width, output.extent.height};
    dispatch(commands, Easu, &easuConstants, sizeof(easuConstants));
    transition(commands, easu.image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT);
    transition(commands, output.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT);
    RcasConstants rcasConstants{};
    FsrRcasCon(rcasConstants.con.data(), static_cast<AF1>(sharpness));
    rcasConstants.size = {output.extent.width, output.extent.height};
    dispatch(commands, Rcas, &rcasConstants, sizeof(rcasConstants));
    transition(commands, output.image, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT);
    VkImageBlit place{};
    place.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    place.srcOffsets[1] = {outWidth, outHeight, 1};
    place.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    place.dstOffsets[0] = {at.x, at.y, 0};
    place.dstOffsets[1] = {at.x + outWidth, at.y + outHeight, 1};
    blit(commands, output.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, destination, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &place, VK_FILTER_NEAREST);
}

}
