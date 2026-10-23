#include "prx/libSceAgcDriver/Execution/include/FrameGeneration.hpp"
#include "prx/libSceAgcDriver/Graphics/include/BufferPool.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Resources.hpp"
#include "prx/libSceAgcDriver/Graphics/shaders/FrameGenCoarse_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/FrameGenFine_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/FrameGenInterpolate_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/FrameGenLuma_spv.h"
#include "prx/libSceAgcDriver/Graphics/shaders/FrameGenSmooth_spv.h"
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

namespace AgcDriver {

namespace {

// Each level a quarter of the one above it, and the block sizes the motion is searched in: 4
// coarse texels (64 pixels) within 6 texels (96 pixels), then 8 texels (32 pixels) of the finer
// level refined within 2 (8 pixels).
constexpr std::uint32_t LevelFactor = 4;
constexpr std::int32_t CoarseBlock = 4;
constexpr std::int32_t CoarseRadius = 6;
constexpr std::int32_t FineBlock = 8;
constexpr std::int32_t FineRadius = 2;
// Neighbouring blocks this many pixels of motion apart count as the same object when steadied.
constexpr float SmoothWithin = 6.0f;

std::uint32_t divideUp(std::uint32_t value, std::uint32_t by) {
    return (value + by - 1) / by;
}

VkExtent2D divideUp(VkExtent2D extent, std::uint32_t by) {
    return {divideUp(extent.width, by), divideUp(extent.height, by)};
}

void check(VkResult result, const char* operation) {
    if (result != VK_SUCCESS) throw std::runtime_error(std::string("frame generation: ") + operation + " failed (" + std::to_string(static_cast<int>(result)) + ")");
}

}

bool FrameGenerationRequested(const char* value) {
    const std::string_view text = value != nullptr ? value : "";
    if (text.empty() || text == "0") return false;
    if (text == "1") return true;
    throw std::runtime_error("ANYPS5_FRAME_GEN must be 1 or 0, not '" + std::string(text) + "'");
}

void FrameGenerationGovernor::begin(bool on, Clock::duration length, Clock::time_point now) {
    generating = on;
    phaseStart = now;
    phaseLength = length;
    counted = 0;
    checkStart = now + Settle;
    checked = 0;
}

// Generation pays where the frames shown grow by a quarter and the game keeps nine in ten of its own.
bool FrameGenerationGovernor::better() const {
    if (!rates[0] || !rates[1]) return rates[1].has_value();
    return *rates[1] >= 0.9 * *rates[0] && 2.0 * *rates[1] >= 1.25 * *rates[0];
}

bool FrameGenerationGovernor::Generate(Clock::time_point now) {
    if (!started) {
        started = true;
        begin(true, Probe, now);
        return generating;
    }
    const auto elapsed = now - phaseStart;
    // Frames in the first moments of a phase still follow the last one.
    if (elapsed >= Settle) {
        ++counted;
        ++checked;
    }
    if (!probing && now - checkStart >= Check) {
        const double rate = static_cast<double>(checked) / std::chrono::duration<double>(now - checkStart).count();
        checkStart = now;
        checked = 0;
        const auto& chosen = rates[generating ? 1 : 0];
        if (chosen && rate < Fall * *chosen) {
            // The scene or the display changed: both are measured again, the other first.
            rates[generating ? 1 : 0] = rate;
            probing = true;
            rates[generating ? 0 : 1].reset();
            begin(!generating, Probe, now);
            return generating;
        }
    }
    if (elapsed < phaseLength) return generating;
    const double seconds = std::chrono::duration<double>(elapsed - Settle).count();
    rates[generating ? 1 : 0] = seconds > 0 ? static_cast<double>(counted) / seconds : 0.0;
    if (probing && !rates[generating ? 0 : 1]) {
        begin(!generating, Probe, now);
    } else if (probing) {
        probing = false;
        begin(better(), Hold, now);
    } else {
        // After holding a choice, the other one is measured again, briefly.
        probing = true;
        begin(!generating, Probe, now);
    }
    return generating;
}

FrameGenerator::FrameGenerator(const Graphics::Context& context, VkFormat format, VkExtent2D extent) : context(context), format(format), extent(extent) {
    if (extent.width < 64 || extent.height < 64) throw std::runtime_error("frame generation: the window is too small");
    const auto supports = [&](VkFormat candidate, VkFormatFeatureFlags features) {
        VkFormatProperties properties{};
        context.formatProperties(context.physical, candidate, &properties);
        return (properties.optimalTilingFeatures & features) == features;
    };
    if (!supports(format, VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT | VK_FORMAT_FEATURE_TRANSFER_DST_BIT | VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT) ||
        !supports(VK_FORMAT_R16_SFLOAT, VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) ||
        !supports(VK_FORMAT_R16G16_SFLOAT, VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) ||
        !supports(VK_FORMAT_R16G16B16A16_SFLOAT, VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT | VK_FORMAT_FEATURE_BLIT_SRC_BIT)) {
        throw std::runtime_error("frame generation: the device lacks the image formats it needs");
    }
    level1 = divideUp(extent, LevelFactor);
    level2 = divideUp(level1, LevelFactor);
    coarseBlocks = divideUp(level2, CoarseBlock);
    fineBlocks = divideUp(level1, FineBlock);
    try {
        constexpr VkImageUsageFlags work = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
        for (auto& frame : history) frame = makeImage(format, extent, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_SAMPLED_BIT);
        previousL1 = makeImage(VK_FORMAT_R16_SFLOAT, level1, work);
        currentL1 = makeImage(VK_FORMAT_R16_SFLOAT, level1, work);
        previousL2 = makeImage(VK_FORMAT_R16_SFLOAT, level2, work);
        currentL2 = makeImage(VK_FORMAT_R16_SFLOAT, level2, work);
        coarse = makeImage(VK_FORMAT_R16G16_SFLOAT, coarseBlocks, work);
        fine = makeImage(VK_FORMAT_R16G16_SFLOAT, fineBlocks, work);
        smooth = makeImage(VK_FORMAT_R16G16_SFLOAT, fineBlocks, work);
        output = makeImage(VK_FORMAT_R16G16B16A16_SFLOAT, extent, VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT);

        VkSamplerCreateInfo samplerInfo{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
        samplerInfo.magFilter = VK_FILTER_LINEAR;
        samplerInfo.minFilter = VK_FILTER_LINEAR;
        samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        samplerInfo.addressModeU = samplerInfo.addressModeV = samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        samplerInfo.maxLod = 0.0f;
        check(context.Function<PFN_vkCreateSampler>("vkCreateSampler")(context.device, &samplerInfo, nullptr, &sampler), "vkCreateSampler");

        std::array<VkDescriptorSetLayoutBinding, 4> bindings{};
        for (std::uint32_t binding = 0; binding < bindings.size(); ++binding) {
            bindings[binding] = {binding, binding < 3 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_COMPUTE_BIT, nullptr};
        }
        VkDescriptorSetLayoutCreateInfo layoutInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
        layoutInfo.bindingCount = static_cast<std::uint32_t>(bindings.size());
        layoutInfo.pBindings = bindings.data();
        check(context.Function<PFN_vkCreateDescriptorSetLayout>("vkCreateDescriptorSetLayout")(context.device, &layoutInfo, nullptr, &setLayout), "vkCreateDescriptorSetLayout");
        const VkPushConstantRange push{VK_SHADER_STAGE_COMPUTE_BIT, 0, 48};
        VkPipelineLayoutCreateInfo pipelineLayoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
        pipelineLayoutInfo.setLayoutCount = 1;
        pipelineLayoutInfo.pSetLayouts = &setLayout;
        pipelineLayoutInfo.pushConstantRangeCount = 1;
        pipelineLayoutInfo.pPushConstantRanges = &push;
        check(context.Function<PFN_vkCreatePipelineLayout>("vkCreatePipelineLayout")(context.device, &pipelineLayoutInfo, nullptr, &pipelineLayout), "vkCreatePipelineLayout");

        const std::array<std::pair<const std::uint32_t*, std::size_t>, PassCount> code{{
            {FRAME_GEN_LUMA_SPV, sizeof(FRAME_GEN_LUMA_SPV)}, {FRAME_GEN_COARSE_SPV, sizeof(FRAME_GEN_COARSE_SPV)}, {FRAME_GEN_FINE_SPV, sizeof(FRAME_GEN_FINE_SPV)},
            {FRAME_GEN_SMOOTH_SPV, sizeof(FRAME_GEN_SMOOTH_SPV)}, {FRAME_GEN_INTERPOLATE_SPV, sizeof(FRAME_GEN_INTERPOLATE_SPV)}}};
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

        const std::array<VkDescriptorPoolSize, 2> sizes{{{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 3 * 2 * SetCount}, {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 2 * SetCount}}};
        VkDescriptorPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
        poolInfo.maxSets = 2 * SetCount;
        poolInfo.poolSizeCount = static_cast<std::uint32_t>(sizes.size());
        poolInfo.pPoolSizes = sizes.data();
        check(context.Function<PFN_vkCreateDescriptorPool>("vkCreateDescriptorPool")(context.device, &poolInfo, nullptr, &pool), "vkCreateDescriptorPool");
        for (std::uint32_t parity = 0; parity < 2; ++parity) {
            std::array<VkDescriptorSetLayout, SetCount> layouts{};
            layouts.fill(setLayout);
            VkDescriptorSetAllocateInfo allocate{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
            allocate.descriptorPool = pool;
            allocate.descriptorSetCount = SetCount;
            allocate.pSetLayouts = layouts.data();
            check(context.Function<PFN_vkAllocateDescriptorSets>("vkAllocateDescriptorSets")(context.device, &allocate, sets[parity].data()), "vkAllocateDescriptorSets");
            const Image& previous = history[parity ^ 1];
            const Image& current = history[parity];
            struct Wiring {
                const Image* inputs[3];
                const Image* out;
            };
            const std::array<Wiring, SetCount> wiring{{
                {{&previous, &previous, &previous}, &previousL1}, {{&current, &current, &current}, &currentL1},
                {{&previousL1, &previousL1, &previousL1}, &previousL2}, {{&currentL1, &currentL1, &currentL1}, &currentL2},
                {{&previousL2, &currentL2, &currentL2}, &coarse}, {{&previousL1, &currentL1, &coarse}, &fine},
                {{&fine, &fine, &fine}, &smooth}, {{&previous, &current, &smooth}, &output}}};
            std::array<VkDescriptorImageInfo, SetCount * 4> infos{};
            std::array<VkWriteDescriptorSet, SetCount * 4> writes{};
            for (std::size_t set = 0; set < SetCount; ++set) {
                for (std::size_t binding = 0; binding < 4; ++binding) {
                    const Image* image = binding < 3 ? wiring[set].inputs[binding] : wiring[set].out;
                    const bool frame = image == &history[0] || image == &history[1];
                    auto& info = infos[set * 4 + binding];
                    info = {binding < 3 ? sampler : VK_NULL_HANDLE, image->view, frame ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL : VK_IMAGE_LAYOUT_GENERAL};
                    writes[set * 4 + binding] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, sets[parity][set], static_cast<std::uint32_t>(binding), 0, 1,
                                                 binding < 3 ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, &info, nullptr, nullptr};
                }
            }
            context.Function<PFN_vkUpdateDescriptorSets>("vkUpdateDescriptorSets")(context.device, static_cast<std::uint32_t>(writes.size()), writes.data(), 0, nullptr);
        }

        VkCommandPoolCreateInfo commandPoolInfo{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
        commandPoolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        commandPoolInfo.queueFamilyIndex = context.queueFamily;
        check(context.Function<PFN_vkCreateCommandPool>("vkCreateCommandPool")(context.device, &commandPoolInfo, nullptr, &commandPool), "vkCreateCommandPool");
        VkCommandBufferAllocateInfo commandInfo{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        commandInfo.commandPool = commandPool;
        commandInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        commandInfo.commandBufferCount = Ring;
        check(context.Function<PFN_vkAllocateCommandBuffers>("vkAllocateCommandBuffers")(context.device, &commandInfo, commandBuffers.data()), "vkAllocateCommandBuffers");
        for (auto& fence : fences) {
            VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
            check(context.Function<PFN_vkCreateFence>("vkCreateFence")(context.device, &fenceInfo, nullptr, &fence), "vkCreateFence");
        }
    } catch (...) {
        release();
        throw;
    }
}

FrameGenerator::~FrameGenerator() {
    release();
}

FrameGenerator::Image FrameGenerator::makeImage(VkFormat imageFormat, VkExtent2D imageExtent, VkImageUsageFlags usage) {
    Image made;
    made.extent = imageExtent;
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = imageFormat;
    info.extent = {imageExtent.width, imageExtent.height, 1};
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
        made.memory = Graphics::AllocateImageMemory(context, allocation, requirements.memoryTypeBits, "vkAllocateMemory frame generation", &made.memoryType);
        made.bytes = allocation.allocationSize;
        check(context.Function<PFN_vkBindImageMemory>("vkBindImageMemory")(context.device, made.image, made.memory, 0), "vkBindImageMemory");
        VkImageViewCreateInfo viewInfo{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        viewInfo.image = made.image;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = imageFormat;
        viewInfo.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        check(context.Function<PFN_vkCreateImageView>("vkCreateImageView")(context.device, &viewInfo, nullptr, &made.view), "vkCreateImageView");
    } catch (...) {
        destroy(made);
        throw;
    }
    return made;
}

void FrameGenerator::destroy(Image& image) noexcept {
    if (image.view != VK_NULL_HANDLE) context.Function<PFN_vkDestroyImageView>("vkDestroyImageView")(context.device, image.view, nullptr);
    if (image.image != VK_NULL_HANDLE) context.Function<PFN_vkDestroyImage>("vkDestroyImage")(context.device, image.image, nullptr);
    Graphics::ReleaseImageMemory(context, image.memory, image.bytes, image.memoryType);
    image = Image{};
}

void FrameGenerator::release() noexcept {
    const auto wait = context.Function<PFN_vkWaitForFences>("vkWaitForFences");
    for (std::size_t slot = 0; slot < Ring; ++slot) {
        if (submitted[slot] && fences[slot] != VK_NULL_HANDLE) wait(context.device, 1, &fences[slot], VK_TRUE, std::numeric_limits<std::uint64_t>::max());
        submitted[slot] = false;
    }
    for (auto& fence : fences) {
        if (fence != VK_NULL_HANDLE) context.Function<PFN_vkDestroyFence>("vkDestroyFence")(context.device, fence, nullptr);
        fence = VK_NULL_HANDLE;
    }
    if (commandPool != VK_NULL_HANDLE) context.Function<PFN_vkDestroyCommandPool>("vkDestroyCommandPool")(context.device, commandPool, nullptr);
    commandPool = VK_NULL_HANDLE;
    commandBuffers = {};
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
    if (pipelineLayout != VK_NULL_HANDLE) context.Function<PFN_vkDestroyPipelineLayout>("vkDestroyPipelineLayout")(context.device, pipelineLayout, nullptr);
    pipelineLayout = VK_NULL_HANDLE;
    if (setLayout != VK_NULL_HANDLE) context.Function<PFN_vkDestroyDescriptorSetLayout>("vkDestroyDescriptorSetLayout")(context.device, setLayout, nullptr);
    setLayout = VK_NULL_HANDLE;
    if (sampler != VK_NULL_HANDLE) context.Function<PFN_vkDestroySampler>("vkDestroySampler")(context.device, sampler, nullptr);
    sampler = VK_NULL_HANDLE;
    for (auto& frame : history) destroy(frame);
    for (Image* image : {&previousL1, &currentL1, &previousL2, &currentL2, &coarse, &fine, &smooth, &output}) destroy(*image);
}

void FrameGenerator::transition(VkCommandBuffer commands, Image& image, VkImageLayout layout, VkPipelineStageFlags from, VkAccessFlags fromAccess, VkPipelineStageFlags to, VkAccessFlags toAccess) {
    VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.srcAccessMask = fromAccess;
    barrier.dstAccessMask = toAccess;
    barrier.oldLayout = image.layout;
    barrier.newLayout = layout;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image.image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    context.Function<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier")(commands, from, to, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    image.layout = layout;
}

void FrameGenerator::computeBarrier(VkCommandBuffer commands) {
    VkMemoryBarrier barrier{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    context.Function<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier")(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &barrier, 0, nullptr, 0, nullptr);
}

void FrameGenerator::dispatch(VkCommandBuffer commands, Pass pass, VkDescriptorSet set, VkExtent2D threads, const std::array<std::int32_t, 8>& integers, float t) {
    struct Push {
        std::array<std::int32_t, 8> integers;
        std::array<float, 4> floats;
    } push{integers, {t, 0.0f, 0.0f, 0.0f}};
    static_assert(sizeof(Push) == 48);
    context.Function<PFN_vkCmdBindPipeline>("vkCmdBindPipeline")(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelines[pass]);
    context.Function<PFN_vkCmdBindDescriptorSets>("vkCmdBindDescriptorSets")(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &set, 0, nullptr);
    context.Function<PFN_vkCmdPushConstants>("vkCmdPushConstants")(commands, pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(push), &push);
    context.Function<PFN_vkCmdDispatch>("vkCmdDispatch")(commands, divideUp(threads.width, 8), divideUp(threads.height, 8), 1);
}

void FrameGenerator::RecordCapture(VkCommandBuffer commands, VkImage image) {
    const auto barrier = context.Function<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier");
    const std::uint32_t slot = newest ^ 1u;
    auto& frame = history[slot];
    VkImageMemoryBarrier source{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    source.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    source.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    source.oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    source.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    source.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    source.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    source.image = image;
    source.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    barrier(commands, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &source);
    // The generation that read this frame last ran before this command buffer on the same queue.
    transition(commands, frame, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_TRANSFER_READ_BIT,
               VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    VkImageCopy copy{};
    copy.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.extent = {extent.width, extent.height, 1};
    context.Function<PFN_vkCmdCopyImage>("vkCmdCopyImage")(commands, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, frame.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
    source.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    source.dstAccessMask = 0;
    source.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    source.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    barrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nullptr, 0, nullptr, 1, &source);
    transition(commands, frame, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
               VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_TRANSFER_READ_BIT);
    newest = slot;
    if (kept < 2) ++kept;
}

void FrameGenerator::RecordBetween(VkCommandBuffer commands, VkImage target) {
    if (kept < 2) throw std::logic_error("frame generation: a frame between needs two kept");
    for (Image* image : {&previousL1, &currentL1, &previousL2, &currentL2, &coarse, &fine, &smooth, &output}) {
        if (image->layout != VK_IMAGE_LAYOUT_GENERAL) {
            transition(commands, *image, VK_IMAGE_LAYOUT_GENERAL, VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_SHADER_READ_BIT,
                       VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_SHADER_READ_BIT);
        }
    }
    // The last generation's reads of the work images ran before this one on the same queue.
    VkMemoryBarrier start{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
    start.srcAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    start.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    context.Function<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier")(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &start, 0, nullptr, 0, nullptr);
    const auto& set = sets[newest];
    const auto w = static_cast<std::int32_t>(extent.width), h = static_cast<std::int32_t>(extent.height);
    const auto w1 = static_cast<std::int32_t>(level1.width), h1 = static_cast<std::int32_t>(level1.height);
    const auto w2 = static_cast<std::int32_t>(level2.width), h2 = static_cast<std::int32_t>(level2.height);
    const auto factor = static_cast<std::int32_t>(LevelFactor);
    dispatch(commands, Luma, set[PreviousL1], level1, {w1, h1, w, h, factor, 0, 0, 0}, 0.0f);
    dispatch(commands, Luma, set[CurrentL1], level1, {w1, h1, w, h, factor, 0, 0, 0}, 0.0f);
    computeBarrier(commands);
    dispatch(commands, Luma, set[PreviousL2], level2, {w2, h2, w1, h1, factor, 0, 0, 0}, 0.0f);
    dispatch(commands, Luma, set[CurrentL2], level2, {w2, h2, w1, h1, factor, 0, 0, 0}, 0.0f);
    computeBarrier(commands);
    dispatch(commands, Coarse, set[CoarseSet], coarseBlocks, {static_cast<std::int32_t>(coarseBlocks.width), static_cast<std::int32_t>(coarseBlocks.height), w2, h2, CoarseBlock, CoarseRadius, 0, 0}, 0.0f);
    computeBarrier(commands);
    // A fine block covers FineBlock / LevelFactor coarse texels; CoarseBlock of those make a coarse block.
    const std::int32_t perCoarse = CoarseBlock * factor / FineBlock;
    dispatch(commands, Fine, set[FineSet], fineBlocks, {static_cast<std::int32_t>(fineBlocks.width), static_cast<std::int32_t>(fineBlocks.height), w1, h1, FineBlock, FineRadius, factor, perCoarse}, static_cast<float>(LevelFactor));
    computeBarrier(commands);
    dispatch(commands, Smooth, set[SmoothSet], fineBlocks, {static_cast<std::int32_t>(fineBlocks.width), static_cast<std::int32_t>(fineBlocks.height), 0, 0, 0, 0, 0, 0}, SmoothWithin);
    computeBarrier(commands);
    dispatch(commands, Interpolate, set[InterpolateSet], extent, {w, h, FineBlock * factor, 0, 0, 0, 0, 0}, 0.5f);
    transition(commands, output, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT);
    Image swapchain{target, VK_NULL_HANDLE, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED, extent, 0, 0};
    transition(commands, swapchain, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    VkImageBlit blit{};
    blit.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    blit.srcOffsets[1] = {w, h, 1};
    blit.dstOffsets[1] = {w, h, 1};
    context.Function<PFN_vkCmdBlitImage>("vkCmdBlitImage")(commands, output.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, target, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_NEAREST);
    transition(commands, swapchain, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0);
}

void FrameGenerator::recordNewest(VkCommandBuffer commands, VkImage target) {
    Image swapchain{target, VK_NULL_HANDLE, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED, extent, 0, 0};
    transition(commands, swapchain, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
    if (kept == 0) {
        const VkClearColorValue black{{0.0f, 0.0f, 0.0f, 1.0f}};
        const VkImageSubresourceRange range{VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        context.Function<PFN_vkCmdClearColorImage>("vkCmdClearColorImage")(commands, target, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &black, 1, &range);
    } else {
        auto& frame = history[newest];
        transition(commands, frame, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT);
        VkImageCopy copy{};
        copy.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        copy.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        copy.extent = {extent.width, extent.height, 1};
        context.Function<PFN_vkCmdCopyImage>("vkCmdCopyImage")(commands, frame.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, target, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
        transition(commands, frame, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_TRANSFER_READ_BIT);
    }
    transition(commands, swapchain, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0);
}

void FrameGenerator::SubmitNewest(VkQueue queue, VkImage target, VkSemaphore done) {
    const auto slot = cursor;
    cursor = (cursor + 1) % Ring;
    if (submitted[slot]) {
        check(context.Function<PFN_vkWaitForFences>("vkWaitForFences")(context.device, 1, &fences[slot], VK_TRUE, std::numeric_limits<std::uint64_t>::max()), "vkWaitForFences");
        submitted[slot] = false;
    }
    check(context.Function<PFN_vkResetFences>("vkResetFences")(context.device, 1, &fences[slot]), "vkResetFences");
    auto commands = commandBuffers[slot];
    check(context.Function<PFN_vkResetCommandBuffer>("vkResetCommandBuffer")(commands, 0), "vkResetCommandBuffer");
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(context.Function<PFN_vkBeginCommandBuffer>("vkBeginCommandBuffer")(commands, &begin), "vkBeginCommandBuffer");
    recordNewest(commands, target);
    check(context.Function<PFN_vkEndCommandBuffer>("vkEndCommandBuffer")(commands), "vkEndCommandBuffer");
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &commands;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &done;
    check(context.Function<PFN_vkQueueSubmit>("vkQueueSubmit")(queue, 1, &submit, fences[slot]), "vkQueueSubmit");
    submitted[slot] = true;
}

}
