#include "prx/libSceAgcDriver/Execution/include/FrameGeneration.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Resources.hpp"
#include <SDL_loadso.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
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
using AgcDriver::FrameGenerator;

constexpr int VulkanTestSkipped = 77;
constexpr VkExtent2D Extent{256, 128};
constexpr VkFormat Format = VK_FORMAT_B8G8R8A8_UNORM;

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
            // MoltenVK is a portability driver: the loader lists it only when asked to.
            const char* portability = "VK_KHR_portability_enumeration";
            info.flags = 0x00000001; // VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
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

// A swapchain image's stand-in: what the game drew, then left for presentation.
class Frame {
public:
    explicit Frame(const Context& context) : context(context) {
        VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        info.imageType = VK_IMAGE_TYPE_2D;
        info.format = Format;
        info.extent = {Extent.width, Extent.height, 1};
        info.mipLevels = 1;
        info.arrayLayers = 1;
        info.samples = VK_SAMPLE_COUNT_1_BIT;
        info.tiling = VK_IMAGE_TILING_OPTIMAL;
        info.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        Check(context.Function<PFN_vkCreateImage>("vkCreateImage")(context.device, &info, nullptr, &image), "vkCreateImage frame");
        VkMemoryRequirements requirements{};
        context.Function<PFN_vkGetImageMemoryRequirements>("vkGetImageMemoryRequirements")(context.device, image, &requirements);
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = context.MemoryType(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        Check(context.Function<PFN_vkAllocateMemory>("vkAllocateMemory")(context.device, &allocation, nullptr, &memory), "vkAllocateMemory frame");
        Check(context.Function<PFN_vkBindImageMemory>("vkBindImageMemory")(context.device, image, memory, 0), "vkBindImageMemory frame");
    }
    ~Frame() {
        context.Function<PFN_vkDestroyImage>("vkDestroyImage")(context.device, image, nullptr);
        context.Function<PFN_vkFreeMemory>("vkFreeMemory")(context.device, memory, nullptr);
    }
    Frame(const Frame&) = delete;
    Frame& operator=(const Frame&) = delete;
    VkImage Handle() const { return image; }

private:
    const Context& context;
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

// Records with `record`, submits waiting on `wait` (if any) and waits for the GPU.
void run(const Context& context, const std::function<void(VkCommandBuffer)>& record, VkSemaphore wait = VK_NULL_HANDLE) {
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
    const VkPipelineStageFlags stage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.waitSemaphoreCount = wait != VK_NULL_HANDLE ? 1 : 0;
    submit.pWaitSemaphores = &wait;
    submit.pWaitDstStageMask = &stage;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &commands;
    Check(context.Function<PFN_vkQueueSubmit>("vkQueueSubmit")(context.queue, 1, &submit, fence), "vkQueueSubmit");
    Check(context.Function<PFN_vkWaitForFences>("vkWaitForFences")(context.device, 1, &fence, VK_TRUE, std::numeric_limits<std::uint64_t>::max()), "vkWaitForFences");
    context.Function<PFN_vkDestroyFence>("vkDestroyFence")(context.device, fence, nullptr);
    context.Function<PFN_vkFreeCommandBuffers>("vkFreeCommandBuffers")(context.device, context.pool, 1, &commands);
}

// A grey picture with a lighter gradient, and a white square at `left`, `top`.
std::vector<std::uint8_t> picture(std::uint32_t left, std::uint32_t top) {
    std::vector<std::uint8_t> pixels(static_cast<std::size_t>(Extent.width) * Extent.height * 4);
    for (std::uint32_t y = 0; y < Extent.height; ++y) {
        for (std::uint32_t x = 0; x < Extent.width; ++x) {
            const bool square = x >= left && x < left + 32 && y >= top && y < top + 32;
            const auto shade = static_cast<std::uint8_t>(square ? 255 : 40 + (x / 16) % 2 * 10);
            auto* pixel = &pixels[(static_cast<std::size_t>(y) * Extent.width + x) * 4];
            pixel[0] = pixel[1] = pixel[2] = shade;
            pixel[3] = 255;
        }
    }
    return pixels;
}

// Draws `pixels` into `frame`, leaving it in PRESENT_SRC, and lets the generator keep it.
void present(const Context& context, FrameGenerator& generator, const Frame& frame, const std::vector<std::uint8_t>& pixels) {
    Buffer upload(context, pixels.size(), VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    std::memcpy(upload.Bytes().data(), pixels.data(), pixels.size());
    run(context, [&](VkCommandBuffer commands) {
        barrier(context, commands, frame.Handle(), VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        VkBufferImageCopy copy{};
        copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        copy.imageExtent = {Extent.width, Extent.height, 1};
        context.Function<PFN_vkCmdCopyBufferToImage>("vkCmdCopyBufferToImage")(commands, upload.Handle(), frame.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
        barrier(context, commands, frame.Handle(), VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
        generator.RecordCapture(commands, frame.Handle());
    });
}

std::vector<std::uint8_t> readBack(const Context& context, const Frame& target, VkSemaphore wait) {
    const std::size_t bytes = static_cast<std::size_t>(Extent.width) * Extent.height * 4;
    Buffer readback(context, bytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT);
    run(context, [&](VkCommandBuffer commands) {
        barrier(context, commands, target.Handle(), VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
        VkBufferImageCopy copy{};
        copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        copy.imageExtent = {Extent.width, Extent.height, 1};
        context.Function<PFN_vkCmdCopyImageToBuffer>("vkCmdCopyImageToBuffer")(commands, target.Handle(), VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.Handle(), 1, &copy);
        RecordMemoryBarrier(context, commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_HOST_READ_BIT);
    }, wait);
    const auto data = readback.Bytes();
    std::vector<std::uint8_t> result(bytes);
    std::memcpy(result.data(), data.data(), bytes);
    return result;
}

// The frame between the last two kept, read back as BGRA bytes.
std::vector<std::uint8_t> between(const Context& context, FrameGenerator& generator, const Frame& target) {
    run(context, [&](VkCommandBuffer commands) { generator.RecordBetween(commands, target.Handle()); });
    return readBack(context, target, VK_NULL_HANDLE);
}

// The newest frame kept, as the game's frame after a generated one, read back as BGRA bytes.
std::vector<std::uint8_t> newest(const Context& context, FrameGenerator& generator, const Frame& target) {
    VkSemaphoreCreateInfo semaphoreInfo{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    VkSemaphore done = VK_NULL_HANDLE;
    Check(context.Function<PFN_vkCreateSemaphore>("vkCreateSemaphore")(context.device, &semaphoreInfo, nullptr, &done), "vkCreateSemaphore");
    generator.SubmitNewest(context.queue, target.Handle(), done);
    auto result = readBack(context, target, done);
    context.Function<PFN_vkDestroySemaphore>("vkDestroySemaphore")(context.device, done, nullptr);
    return result;
}

int shade(const std::vector<std::uint8_t>& pixels, std::uint32_t x, std::uint32_t y) {
    return pixels[(static_cast<std::size_t>(y) * Extent.width + x) * 4 + 1];
}

// A square moving 16 pixels right is drawn 8 pixels along in the frame between, whole, not as
// two faded copies.
void movingSquareIsHalfway(const Context& context) {
    FrameGenerator generator(context, Format, Extent);
    Frame first(context), second(context), target(context);
    present(context, generator, first, picture(64, 48));
    present(context, generator, second, picture(80, 48));
    require(generator.Kept() == 2, "two frames were not kept");
    const auto made = between(context, generator, target);
    const std::uint32_t row = 64;
    for (std::uint32_t x = 74; x < 102; ++x) {
        require(shade(made, x, row) > 200, "the square is not whole halfway, at x=" + std::to_string(x) + ": " + std::to_string(shade(made, x, row)));
    }
    require(shade(made, 66, row) < 100, "the square's old place is still lit: " + std::to_string(shade(made, 66, row)));
    require(shade(made, 109, row) < 100, "the square's new place is lit early: " + std::to_string(shade(made, 109, row)));
    require(std::abs(shade(made, 20, 10) - shade(picture(0, 200), 20, 10)) <= 4, "the still background changed");
}

// With nothing moving, the frame between is the frame.
void stillPictureStays(const Context& context) {
    FrameGenerator generator(context, Format, Extent);
    Frame first(context), second(context), target(context);
    const auto still = picture(100, 40);
    present(context, generator, first, still);
    present(context, generator, second, still);
    const auto made = between(context, generator, target);
    for (std::uint32_t y = 0; y < Extent.height; y += 7) {
        for (std::uint32_t x = 0; x < Extent.width; x += 5) {
            require(std::abs(shade(made, x, y) - shade(still, x, y)) <= 2, "a still pixel changed at " + std::to_string(x) + "," + std::to_string(y));
        }
    }
}

// The game's frame after a generated one is the newest kept, unchanged.
void newestIsTheGamesFrame(const Context& context) {
    FrameGenerator generator(context, Format, Extent);
    Frame first(context), second(context), target(context);
    present(context, generator, first, picture(10, 10));
    present(context, generator, second, picture(150, 60));
    const auto made = newest(context, generator, target);
    const auto expected = picture(150, 60);
    require(made == expected, "the game's frame after a generated one is not the newest kept");
}

// A display of `refresh` Hz and a game that could run at `game` fps: two presents a frame when
// generating, so the game gets at most half the refresh then.
struct Simulation {
    double refresh;
    double game;
    // From this many seconds in, the display runs at `laterRefresh` (Low Power Mode turned on).
    double changeAt = 1e9;
    double laterRefresh = 0;
};

// The share of game frames generated between `from` and 30 s in.
double generatedShare(const Simulation& simulation, double from = 5) {
    AgcDriver::FrameGenerationGovernor governor;
    using Clock = AgcDriver::FrameGenerationGovernor::Clock;
    const auto start = Clock::time_point{} + std::chrono::hours(1);
    auto now = start;
    std::uint64_t frames = 0, generated = 0;
    while (now - start < std::chrono::seconds(30)) {
        const bool generating = governor.Generate(now);
        const double at = std::chrono::duration<double>(now - start).count();
        if (at >= from) {
            ++frames;
            if (generating) ++generated;
        }
        const double refresh = at >= simulation.changeAt ? simulation.laterRefresh : simulation.refresh;
        const double rate = generating ? std::min(simulation.game, refresh / 2) : std::min(simulation.game, refresh);
        now += std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(1.0 / rate));
    }
    return static_cast<double>(generated) / static_cast<double>(frames);
}

void governorTests() {
    require(generatedShare({120, 60}) > 0.8, "a 60 fps game on a 120 Hz display does not get generated frames");
    require(generatedShare({60, 60}) < 0.2, "a 60 fps game on a 60 Hz display (Low Power Mode) is halved by generation");
    require(generatedShare({60, 25}) > 0.8, "a 25 fps game on a 60 Hz display does not get generated frames");
    require(generatedShare({120, 120}) < 0.2, "a game already at the display's rate is halved by generation");
    require(generatedShare({120, 40}) > 0.8, "a 40 fps game on a 120 Hz display does not get generated frames");
    require(generatedShare({120, 60, 10, 60}, 13) < 0.2, "generation stays on for long after the display slowed to 60 Hz");
    require(generatedShare({60, 60, 10, 120}, 13) > 0.6, "generation does not come back soon after the display sped up to 120 Hz");
}

void requestTests() {
    require(!AgcDriver::FrameGenerationRequested(nullptr) && !AgcDriver::FrameGenerationRequested("") && !AgcDriver::FrameGenerationRequested("0"), "frame generation is on without ANYPS5_FRAME_GEN=1");
    require(AgcDriver::FrameGenerationRequested("1"), "ANYPS5_FRAME_GEN=1 does not turn frame generation on");
    bool named = false;
    try {
        static_cast<void>(AgcDriver::FrameGenerationRequested("yes"));
    } catch (const std::exception& error) {
        named = std::string(error.what()).find("ANYPS5_FRAME_GEN") != std::string::npos;
    }
    require(named, "an ANYPS5_FRAME_GEN other than 1 or 0 was accepted or not named");
}

}

int main() {
    try {
        requestTests();
        governorTests();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::unique_ptr<Device> device;
    try {
        device = std::make_unique<Device>();
    } catch (const std::exception& error) {
        std::cout << "skipped, no Vulkan device: " << error.what() << '\n';
        return VulkanTestSkipped;
    }
    try {
        const auto& context = device->GetContext();
        newestIsTheGamesFrame(context);
        stillPictureStays(context);
        movingSquareIsHalfway(context);
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::cout << "frame generation tests passed\n";
    return 0;
}
