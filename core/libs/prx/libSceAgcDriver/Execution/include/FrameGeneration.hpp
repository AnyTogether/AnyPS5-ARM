#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_FRAMEGENERATION_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_FRAMEGENERATION_HPP

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include "prx/libSceAgcDriver/Graphics/include/Context.hpp"
#include <array>
#include <chrono>
#include <cstdint>
#include <optional>

namespace AgcDriver {

// Frame generation (ANYPS5_FRAME_GEN=1): a frame made between each two the game presents, shown
// before the second. Every presented frame is kept as it went to the window (two at a time); the
// motion between the last two is found on the GPU, block by block, from their brightness at 1/16
// and 1/4 of their size, and the frame halfway along it is drawn over the game's swapchain image,
// which is presented; the game's frame follows in the next image, copied from the one kept.
// Nothing comes from the game but its frames, and one swapchain image is held at a time, all a
// three-image swapchain allows.
bool FrameGenerationRequested(const char* value);

// Whether a game frame gets a generated one before it. Generating makes two presents of each
// frame, so where the display cannot show twice the game's rate (a 60 Hz display, or a game
// already at the display's rate) it would halve the game's frames. The governor measures the
// game's frame rate with and without generation and keeps generating only where that shows
// clearly more frames and keeps almost all the game's own; it looks again now and then.
class FrameGenerationGovernor {
public:
    using Clock = std::chrono::steady_clock;
    static constexpr Clock::duration Probe = std::chrono::milliseconds(1500);
    static constexpr Clock::duration Settle = std::chrono::milliseconds(250);
    static constexpr Clock::duration Hold = std::chrono::seconds(12);
    // While a choice is held, the game's rate is checked this often; a fall below Fall of the
    // rate it was chosen at measures both again at once.
    static constexpr Clock::duration Check = std::chrono::seconds(1);
    static constexpr double Fall = 0.85;

    // Called once for each game frame, at its present: whether it gets a generated frame.
    bool Generate(Clock::time_point now);
    // The game frames per second measured last with and without generation.
    std::optional<double> RateOn() const { return rates[1]; }
    std::optional<double> RateOff() const { return rates[0]; }
    // Whether the current choice is only being measured, not decided.
    bool Probing() const { return probing; }

private:
    void begin(bool on, Clock::duration length, Clock::time_point now);
    bool better() const;

    bool started = false;
    bool generating = true;
    bool probing = true;
    Clock::time_point phaseStart{};
    Clock::duration phaseLength{};
    std::uint64_t counted = 0;
    Clock::time_point checkStart{};
    std::uint64_t checked = 0;
    std::array<std::optional<double>, 2> rates{};
};

class FrameGenerator {
public:
    FrameGenerator(const Graphics::Context& context, VkFormat format, VkExtent2D extent);
    ~FrameGenerator();
    FrameGenerator(const FrameGenerator&) = delete;
    FrameGenerator& operator=(const FrameGenerator&) = delete;

    bool Matches(VkFormat format, VkExtent2D extent) const { return format == this->format && extent.width == this->extent.width && extent.height == this->extent.height; }

    // Records, in the frame's own command buffer after it is in `image` (a swapchain image in
    // PRESENT_SRC, left so), its copy as the newest frame kept.
    void RecordCapture(VkCommandBuffer commands, VkImage image);

    // Frames kept since the generator was made, up to two.
    std::uint32_t Kept() const { return kept; }

    // Records, after RecordCapture with two frames kept, the frame between the last two into
    // `target` (a swapchain image, left PRESENT_SRC).
    void RecordBetween(VkCommandBuffer commands, VkImage target);

    // Submits, after the captures, the newest frame kept (black before one is) into `target` (a
    // swapchain image, left PRESENT_SRC), signalling `done`.
    void SubmitNewest(VkQueue queue, VkImage target, VkSemaphore done);

private:
    struct Image {
        VkImage image = VK_NULL_HANDLE;
        VkImageView view = VK_NULL_HANDLE;
        VkDeviceMemory memory = VK_NULL_HANDLE;
        VkImageLayout layout = VK_IMAGE_LAYOUT_UNDEFINED;
        VkExtent2D extent{};
        VkDeviceSize bytes = 0;
        std::uint32_t memoryType = 0;
    };
    enum Pass : std::size_t { Luma, Coarse, Fine, Smooth, Interpolate, PassCount };
    // The descriptor sets, for the newest frame kept in history[0] or history[1].
    enum Set : std::size_t { PreviousL1, CurrentL1, PreviousL2, CurrentL2, CoarseSet, FineSet, SmoothSet, InterpolateSet, SetCount };

    Image makeImage(VkFormat imageFormat, VkExtent2D imageExtent, VkImageUsageFlags usage);
    void destroy(Image& image) noexcept;
    void release() noexcept;
    void transition(VkCommandBuffer commands, Image& image, VkImageLayout layout, VkPipelineStageFlags from, VkAccessFlags fromAccess, VkPipelineStageFlags to, VkAccessFlags toAccess);
    void dispatch(VkCommandBuffer commands, Pass pass, VkDescriptorSet set, VkExtent2D threads, const std::array<std::int32_t, 8>& integers, float t);
    void computeBarrier(VkCommandBuffer commands);
    void recordNewest(VkCommandBuffer commands, VkImage target);

    Graphics::Context context;
    VkFormat format;
    VkExtent2D extent;
    VkExtent2D level1{};
    VkExtent2D level2{};
    VkExtent2D coarseBlocks{};
    VkExtent2D fineBlocks{};
    std::array<Image, 2> history{};
    Image previousL1, currentL1, previousL2, currentL2, coarse, fine, smooth, output;
    std::uint32_t newest = 1;
    std::uint32_t kept = 0;
    VkSampler sampler = VK_NULL_HANDLE;
    VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    std::array<std::array<VkDescriptorSet, SetCount>, 2> sets{};
    std::array<VkShaderModule, PassCount> modules{};
    std::array<VkPipeline, PassCount> pipelines{};
    VkCommandPool commandPool = VK_NULL_HANDLE;
    static constexpr std::size_t Ring = 3;
    std::array<VkCommandBuffer, Ring> commandBuffers{};
    std::array<VkFence, Ring> fences{};
    std::array<bool, Ring> submitted{};
    std::size_t cursor = 0;
};

}

#endif
