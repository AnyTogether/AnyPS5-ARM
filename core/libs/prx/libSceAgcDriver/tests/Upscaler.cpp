#include "prx/libSceAgcDriver/Execution/include/Fsr1Upscaler.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Resources.hpp"
#include <SDL_loadso.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using namespace AgcDriver::Graphics;
using AgcDriver::Fsr1Upscaler;

constexpr int VulkanTestSkipped = 77;
constexpr VkExtent2D Source{64, 64};
constexpr VkExtent2D Output{128, 128};
constexpr VkExtent2D Window{160, 128};
constexpr VkOffset2D At{16, 0};
constexpr int Marker = 7;

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

class Device {
public:
    Device() {
#ifdef _WIN32
        library = SDL_LoadObject("vulkan-1.dll");
#elif defined(__APPLE__)
        library = SDL_LoadObject("libvulkan.1.dylib");
#else
        library = SDL_LoadObject("libvulkan.so.1");
#endif
        Require(library != nullptr, "cannot load Vulkan");
        try {
            instanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(SDL_LoadFunction(library, "vkGetInstanceProcAddr"));
            Require(instanceProc != nullptr, "missing Vulkan instance resolver");
            VkApplicationInfo application{VK_STRUCTURE_TYPE_APPLICATION_INFO};
            application.apiVersion = VK_API_VERSION_1_1;
            VkInstanceCreateInfo info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
            info.pApplicationInfo = &application;
#ifdef __APPLE__
            const char* portability = "VK_KHR_portability_enumeration";
            info.flags = 0x00000001;
            info.enabledExtensionCount = 1;
            info.ppEnabledExtensionNames = &portability;
#endif
            Check(function<PFN_vkCreateInstance>("vkCreateInstance")(&info, nullptr, &instance), "vkCreateInstance");
            std::uint32_t count = 0;
            const auto enumerate = function<PFN_vkEnumeratePhysicalDevices>("vkEnumeratePhysicalDevices");
            Check(enumerate(instance, &count, nullptr), "vkEnumeratePhysicalDevices");
            Require(count != 0, "no Vulkan device");
            std::vector<VkPhysicalDevice> devices(count);
            Check(enumerate(instance, &count, devices.data()), "vkEnumeratePhysicalDevices");
            context.physical = devices.front();
            const auto queues = function<PFN_vkGetPhysicalDeviceQueueFamilyProperties>("vkGetPhysicalDeviceQueueFamilyProperties");
            queues(context.physical, &count, nullptr);
            std::vector<VkQueueFamilyProperties> families(count);
            queues(context.physical, &count, families.data());
            std::uint32_t family = 0;
            while (family < count && (families[family].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 0) ++family;
            Require(family < count, "no Vulkan graphics queue");
            const float priority = 1;
            VkDeviceQueueCreateInfo queue{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
            queue.queueFamilyIndex = family;
            queue.queueCount = 1;
            queue.pQueuePriorities = &priority;
            VkDeviceCreateInfo device{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
            device.queueCreateInfoCount = 1;
            device.pQueueCreateInfos = &queue;
#ifdef __APPLE__
            const char* subset = "VK_KHR_portability_subset";
            device.enabledExtensionCount = 1;
            device.ppEnabledExtensionNames = &subset;
#endif
            Check(function<PFN_vkCreateDevice>("vkCreateDevice")(context.physical, &device, nullptr, &context.device), "vkCreateDevice");
            context.deviceProc = function<PFN_vkGetDeviceProcAddr>("vkGetDeviceProcAddr");
            function<PFN_vkGetPhysicalDeviceMemoryProperties>("vkGetPhysicalDeviceMemoryProperties")(context.physical, &context.memory);
            VkPhysicalDeviceProperties properties{};
            function<PFN_vkGetPhysicalDeviceProperties>("vkGetPhysicalDeviceProperties")(context.physical, &properties);
            context.limits = properties.limits;
            context.formatProperties = function<PFN_vkGetPhysicalDeviceFormatProperties>("vkGetPhysicalDeviceFormatProperties");
            context.imageFormatProperties = function<PFN_vkGetPhysicalDeviceImageFormatProperties>("vkGetPhysicalDeviceImageFormatProperties");
            context.queueFamily = family;
            context.Function<PFN_vkGetDeviceQueue>("vkGetDeviceQueue")(context.device, family, 0, &context.queue);
            VkCommandPoolCreateInfo pool{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
            pool.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
            pool.queueFamilyIndex = family;
            Check(context.Function<PFN_vkCreateCommandPool>("vkCreateCommandPool")(context.device, &pool, nullptr, &context.pool), "vkCreateCommandPool");
        } catch (...) {
            release();
            throw;
        }
    }

    ~Device() { release(); }
    const Context& GetContext() const { return context; }

private:
    template<typename TFunction>
    TFunction function(const char* name) const {
        const auto result = reinterpret_cast<TFunction>(instanceProc(instance, name));
        Require(result != nullptr, name);
        return result;
    }

    void release() noexcept {
        if (context.pool != VK_NULL_HANDLE) context.Function<PFN_vkDestroyCommandPool>("vkDestroyCommandPool")(context.device, context.pool, nullptr);
        context.bufferPool.reset();
        if (context.device != VK_NULL_HANDLE) function<PFN_vkDestroyDevice>("vkDestroyDevice")(context.device, nullptr);
        if (instance != VK_NULL_HANDLE) function<PFN_vkDestroyInstance>("vkDestroyInstance")(instance, nullptr);
        if (library != nullptr) SDL_UnloadObject(library);
    }

    void* library = nullptr;
    PFN_vkGetInstanceProcAddr instanceProc = nullptr;
    VkInstance instance = VK_NULL_HANDLE;
    Context context{};
};

class Picture {
public:
    Picture(const Context& context, VkFormat format, VkExtent2D extent) : context(context), extent(extent) {
        VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        info.imageType = VK_IMAGE_TYPE_2D;
        info.format = format;
        info.extent = {extent.width, extent.height, 1};
        info.mipLevels = 1;
        info.arrayLayers = 1;
        info.samples = VK_SAMPLE_COUNT_1_BIT;
        info.tiling = VK_IMAGE_TILING_OPTIMAL;
        info.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        Check(context.Function<PFN_vkCreateImage>("vkCreateImage")(context.device, &info, nullptr, &image), "vkCreateImage picture");
        VkMemoryRequirements requirements{};
        context.Function<PFN_vkGetImageMemoryRequirements>("vkGetImageMemoryRequirements")(context.device, image, &requirements);
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = context.MemoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        Check(context.Function<PFN_vkAllocateMemory>("vkAllocateMemory")(context.device, &allocation, nullptr, &memory), "vkAllocateMemory picture");
        Check(context.Function<PFN_vkBindImageMemory>("vkBindImageMemory")(context.device, image, memory, 0), "vkBindImageMemory picture");
    }
    ~Picture() {
        context.Function<PFN_vkDestroyImage>("vkDestroyImage")(context.device, image, nullptr);
        context.Function<PFN_vkFreeMemory>("vkFreeMemory")(context.device, memory, nullptr);
    }
    Picture(const Picture&) = delete;
    Picture& operator=(const Picture&) = delete;
    VkImage Handle() const { return image; }
    VkExtent2D Extent() const { return extent; }

private:
    const Context& context;
    VkExtent2D extent;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
};

void barrier(const Context& context, VkCommandBuffer commands, VkImage image, VkImageLayout from, VkImageLayout to) {
    VkImageMemoryBarrier transition{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    transition.srcAccessMask = VK_ACCESS_MEMORY_WRITE_BIT;
    transition.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    transition.oldLayout = from;
    transition.newLayout = to;
    transition.srcQueueFamilyIndex = transition.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    transition.image = image;
    transition.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    context.Function<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier")(commands, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &transition);
}

void run(const Context& context, const std::function<void(VkCommandBuffer)>& record) {
    VkCommandBufferAllocateInfo allocate{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    allocate.commandPool = context.pool;
    allocate.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocate.commandBufferCount = 1;
    VkCommandBuffer commands = VK_NULL_HANDLE;
    Check(context.Function<PFN_vkAllocateCommandBuffers>("vkAllocateCommandBuffers")(context.device, &allocate, &commands), "vkAllocateCommandBuffers");
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    Check(context.Function<PFN_vkBeginCommandBuffer>("vkBeginCommandBuffer")(commands, &begin), "vkBeginCommandBuffer");
    record(commands);
    Check(context.Function<PFN_vkEndCommandBuffer>("vkEndCommandBuffer")(commands), "vkEndCommandBuffer");
    VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkFence fence = VK_NULL_HANDLE;
    Check(context.Function<PFN_vkCreateFence>("vkCreateFence")(context.device, &fenceInfo, nullptr, &fence), "vkCreateFence");
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &commands;
    Check(context.Function<PFN_vkQueueSubmit>("vkQueueSubmit")(context.queue, 1, &submit, fence), "vkQueueSubmit");
    Check(context.Function<PFN_vkWaitForFences>("vkWaitForFences")(context.device, 1, &fence, VK_TRUE, std::numeric_limits<std::uint64_t>::max()), "vkWaitForFences");
    context.Function<PFN_vkDestroyFence>("vkDestroyFence")(context.device, fence, nullptr);
    context.Function<PFN_vkFreeCommandBuffers>("vkFreeCommandBuffers")(context.device, context.pool, 1, &commands);
}

using Grey = std::vector<int>;

Grey testImage() {
    Grey shades(static_cast<std::size_t>(Source.width) * Source.height);
    for (std::uint32_t y = 0; y < Source.height; ++y) {
        for (std::uint32_t x = 0; x < Source.width; ++x) {
            const bool square = x >= 20 && x < 44 && y >= 20 && y < 44;
            const bool stripe = x >= 4 && x < 12 && (y / 4) % 2 == 0;
            shades[y * Source.width + x] = square ? 230 : stripe ? 200 : 40;
        }
    }
    return shades;
}

std::vector<std::uint8_t> bgra(const Grey& shades) {
    std::vector<std::uint8_t> bytes(shades.size() * 4);
    for (std::size_t index = 0; index < shades.size(); ++index) {
        bytes[index * 4] = bytes[index * 4 + 1] = bytes[index * 4 + 2] = static_cast<std::uint8_t>(shades[index]);
        bytes[index * 4 + 3] = 255;
    }
    return bytes;
}

void upload(const Context& context, VkCommandBuffer commands, const Buffer& staging, const Picture& picture, VkImageLayout to) {
    barrier(context, commands, picture.Handle(), VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    VkBufferImageCopy copy{};
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.imageExtent = {picture.Extent().width, picture.Extent().height, 1};
    context.Function<PFN_vkCmdCopyBufferToImage>("vkCmdCopyBufferToImage")(commands, staging.Handle(), picture.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
    barrier(context, commands, picture.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, to);
}

int channel(std::uint32_t word, VkFormat format) {
    if (format == VK_FORMAT_A2B10G10R10_UNORM_PACK32) return static_cast<int>(((word >> 10) & 0x3ffu) * 255u + 511u) / 1023;
    return static_cast<int>((word >> 8) & 0xffu);
}

struct Upscaled {
    Grey window;
    Grey shades;
};

Upscaled upscale(const Context& context, float sharpness, VkFormat windowFormat = VK_FORMAT_B8G8R8A8_UNORM) {
    Fsr1Upscaler upscaler(context, windowFormat, sharpness);
    upscaler.Resize(Source, Output);
    require(upscaler.Matches(Source, Output) && !upscaler.Matches(Source, Window), "the upscaler does not report the extents it was sized for");
    Picture source(context, VK_FORMAT_B8G8R8A8_UNORM, Source);
    Picture window(context, windowFormat, Window);
    const auto pixels = bgra(testImage());
    Buffer staging(context, pixels.size(), VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    std::memcpy(staging.Bytes().data(), pixels.data(), pixels.size());
    const std::size_t bytes = static_cast<std::size_t>(Window.width) * Window.height * 4;
    Buffer readback(context, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    run(context, [&](VkCommandBuffer commands) {
        upload(context, commands, staging, source, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
        barrier(context, commands, window.Handle(), VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        VkClearColorValue marker{};
        marker.float32[0] = marker.float32[1] = marker.float32[2] = static_cast<float>(Marker) / 255.0f;
        marker.float32[3] = 1.0f;
        const VkImageSubresourceRange range{VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        context.Function<PFN_vkCmdClearColorImage>("vkCmdClearColorImage")(commands, window.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &marker, 1, &range);
        barrier(context, commands, window.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        upscaler.Record(commands, source.Handle(), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, 0, window.Handle(), At);
        barrier(context, commands, window.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
        VkBufferImageCopy copy{};
        copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        copy.imageExtent = {Window.width, Window.height, 1};
        context.Function<PFN_vkCmdCopyImageToBuffer>("vkCmdCopyImageToBuffer")(commands, window.Handle(), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.Handle(), 1, &copy);
        RecordMemoryBarrier(context, commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_HOST_READ_BIT);
    });
    Upscaled result;
    result.window.resize(static_cast<std::size_t>(Window.width) * Window.height);
    const auto data = readback.Bytes();
    for (std::size_t index = 0; index < result.window.size(); ++index) {
        std::uint32_t word = 0;
        std::memcpy(&word, data.data() + index * 4, sizeof(word));
        result.window[index] = channel(word, windowFormat);
    }
    result.shades.resize(static_cast<std::size_t>(Output.width) * Output.height);
    for (std::uint32_t y = 0; y < Output.height; ++y) {
        for (std::uint32_t x = 0; x < Output.width; ++x) result.shades[y * Output.width + x] = result.window[(y + At.y) * Window.width + x + At.x];
    }
    return result;
}

Grey nearest(const Grey& shades) {
    Grey result(static_cast<std::size_t>(Output.width) * Output.height);
    for (std::uint32_t y = 0; y < Output.height; ++y) {
        for (std::uint32_t x = 0; x < Output.width; ++x) result[y * Output.width + x] = shades[(y * Source.height / Output.height) * Source.width + x * Source.width / Output.width];
    }
    return result;
}

Grey bilinear(const Grey& shades) {
    Grey result(static_cast<std::size_t>(Output.width) * Output.height);
    const auto at = [&](int x, int y) {
        x = std::clamp(x, 0, static_cast<int>(Source.width) - 1);
        y = std::clamp(y, 0, static_cast<int>(Source.height) - 1);
        return static_cast<double>(shades[static_cast<std::size_t>(y) * Source.width + static_cast<std::size_t>(x)]);
    };
    for (std::uint32_t y = 0; y < Output.height; ++y) {
        for (std::uint32_t x = 0; x < Output.width; ++x) {
            const double u = (x + 0.5) * Source.width / Output.width - 0.5;
            const double v = (y + 0.5) * Source.height / Output.height - 0.5;
            const int left = static_cast<int>(std::floor(u));
            const int top = static_cast<int>(std::floor(v));
            const double fx = u - left, fy = v - top;
            const double upper = at(left, top) * (1 - fx) + at(left + 1, top) * fx;
            const double lower = at(left, top + 1) * (1 - fx) + at(left + 1, top + 1) * fx;
            result[y * Output.width + x] = static_cast<int>(std::lround(upper * (1 - fy) + lower * fy));
        }
    }
    return result;
}

int shade(const Grey& shades, std::uint32_t x, std::uint32_t y) {
    return shades[y * Output.width + x];
}

int edgeStep(const Grey& shades) {
    int steepest = 0;
    for (std::uint32_t y = 44; y < 84; ++y) {
        for (std::uint32_t x = 30; x < 50; ++x) steepest = std::max(steepest, std::abs(shade(shades, x + 1, y) - shade(shades, x, y)));
    }
    return steepest;
}

std::size_t differing(const Grey& a, const Grey& b, int by) {
    std::size_t count = 0;
    for (std::size_t index = 0; index < a.size(); ++index) count += std::abs(a[index] - b[index]) > by ? 1 : 0;
    return count;
}

void extentsTests() {
    require(Fsr1Upscaler::Upscales({64, 64}, {128, 128}), "64x64 to 128x128 is not an upscale");
    require(!Fsr1Upscaler::Upscales({128, 128}, {128, 128}) && !Fsr1Upscaler::Upscales({128, 128}, {64, 64}) && !Fsr1Upscaler::Upscales({64, 64}, {128, 64}), "an image no smaller than the window counts as upscaled");
    require(!Fsr1Upscaler::Upscales({0, 0}, {128, 128}), "an empty image counts as upscaled");
}

void fillsItsRectAndNothingElse(const Context& context) {
    const auto made = upscale(context, 0.2f);
    for (std::uint32_t y = 0; y < Window.height; ++y) {
        for (std::uint32_t x = 0; x < Window.width; ++x) {
            const bool inside = x >= static_cast<std::uint32_t>(At.x) && x < At.x + Output.width && y >= static_cast<std::uint32_t>(At.y) && y < At.y + Output.height;
            const int value = made.window[y * Window.width + x];
            if (!inside) require(value == Marker, "a pixel outside the upscaled rect changed at " + std::to_string(x) + "," + std::to_string(y));
            else require(value != Marker, "the upscaled rect was not written at " + std::to_string(x) + "," + std::to_string(y));
        }
    }
    require(std::abs(shade(made.shades, 64, 64) - 230) <= 6, "the middle of the square is not the square's shade: " + std::to_string(shade(made.shades, 64, 64)));
    require(std::abs(shade(made.shades, 110, 110) - 40) <= 6, "the flat background changed: " + std::to_string(shade(made.shades, 110, 110)));
}

void edgesStaySharperThanBilinear(const Context& context) {
    const auto made = upscale(context, 0.2f);
    const auto shades = testImage();
    const auto plainNearest = nearest(shades);
    const auto plainBilinear = bilinear(shades);
    const auto nearestDiffers = differing(made.shades, plainNearest, 8);
    const auto bilinearDiffers = differing(made.shades, plainBilinear, 8);
    std::cout << "edge step: fsr " << edgeStep(made.shades) << ", bilinear " << edgeStep(plainBilinear) << ", nearest " << edgeStep(plainNearest) << "; pixels off by more than 8: from nearest " << nearestDiffers
              << ", from bilinear " << bilinearDiffers << '\n';
    require(nearestDiffers > 200, "the upscaled image is a nearest-neighbour copy");
    require(bilinearDiffers > 200, "the upscaled image is a bilinear copy");
    require(edgeStep(made.shades) >= edgeStep(plainBilinear) + 20, "the square's edge is no sharper than bilinear: " + std::to_string(edgeStep(made.shades)) + " against " + std::to_string(edgeStep(plainBilinear)));
}

void sharpnessChangesTheResult(const Context& context) {
    const auto sharpest = upscale(context, 0.0f);
    const auto softest = upscale(context, 2.0f);
    const auto changed = differing(sharpest.shades, softest.shades, 2);
    std::cout << "sharpness 0 against 2: " << changed << " pixels differ, edge step " << edgeStep(sharpest.shades) << " against " << edgeStep(softest.shades) << '\n';
    require(changed > 100, "sharpness 0 and 2 give the same image");
    require(edgeStep(sharpest.shades) > edgeStep(softest.shades), "sharpness 0 is not sharper than 2");
}

void wideWorkFormatMatches(const Context& context) {
    VkFormatProperties properties{};
    context.formatProperties(context.physical, VK_FORMAT_A2B10G10R10_UNORM_PACK32, &properties);
    if ((properties.optimalTilingFeatures & (VK_FORMAT_FEATURE_BLIT_DST_BIT | VK_FORMAT_FEATURE_TRANSFER_SRC_BIT)) != (VK_FORMAT_FEATURE_BLIT_DST_BIT | VK_FORMAT_FEATURE_TRANSFER_SRC_BIT)) {
        std::cout << "the device lacks blits into A2B10G10R10; the 16-bit float work images were not tried\n";
        return;
    }
    {
        Fsr1Upscaler wide(context, VK_FORMAT_A2B10G10R10_UNORM_PACK32, 0.2f);
        require(wide.WorkFormat() == VK_FORMAT_R16G16B16A16_SFLOAT, "a 10-bit window does not get 16-bit float work images");
        Fsr1Upscaler narrow(context, VK_FORMAT_B8G8R8A8_UNORM, 0.2f);
        require(narrow.WorkFormat() == VK_FORMAT_R8G8B8A8_UNORM, "an 8-bit window does not get 8-bit work images");
    }
    const auto eight = upscale(context, 0.2f);
    const auto ten = upscale(context, 0.2f, VK_FORMAT_A2B10G10R10_UNORM_PACK32);
    require(differing(eight.shades, ten.shades, 3) < 64, "the 16-bit float path differs from the 8-bit one");
}

}

int main() {
    try {
        extentsTests();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::unique_ptr<Device> device;
    try {
        device = std::make_unique<Device>();
    } catch (const std::exception& error) {
        std::cout << "skipped, no usable Vulkan device: " << error.what() << '\n';
        return VulkanTestSkipped;
    }
    try {
        const auto& context = device->GetContext();
        fillsItsRectAndNothingElse(context);
        edgesStaySharperThanBilinear(context);
        sharpnessChangesTheResult(context);
        wideWorkFormatMatches(context);
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::cout << "FSR 1 upscaler tests passed\n";
    return 0;
}
