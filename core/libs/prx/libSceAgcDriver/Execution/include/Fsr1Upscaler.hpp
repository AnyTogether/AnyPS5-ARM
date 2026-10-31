#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_FSR1UPSCALER_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_FSR1UPSCALER_HPP

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include "prx/libSceAgcDriver/Graphics/include/Context.hpp"
#include <array>
#include <cstddef>
#include <cstdint>

namespace AgcDriver {

class Fsr1Upscaler {
public:
    Fsr1Upscaler(const Graphics::Context& context, VkFormat destinationFormat, float sharpness);
    ~Fsr1Upscaler();
    Fsr1Upscaler(const Fsr1Upscaler&) = delete;
    Fsr1Upscaler& operator=(const Fsr1Upscaler&) = delete;

    static bool Upscales(VkExtent2D source, VkExtent2D output);
    bool Matches(VkExtent2D source, VkExtent2D output) const;
    void Resize(VkExtent2D source, VkExtent2D output);
    void Record(VkCommandBuffer commands, VkImage source, VkImageLayout layout, std::uint32_t layer, VkImage destination, VkOffset2D at);
    VkExtent2D Source() const { return input.extent; }
    VkExtent2D Output() const { return output.extent; }
    VkFormat WorkFormat() const { return workFormat; }
    float Sharpness() const { return sharpness; }

private:
    struct Image {
        VkImage image = VK_NULL_HANDLE;
        VkImageView view = VK_NULL_HANDLE;
        VkDeviceMemory memory = VK_NULL_HANDLE;
        VkExtent2D extent{};
        VkDeviceSize bytes = 0;
        std::uint32_t memoryType = 0;
    };
    enum Pass : std::size_t { Easu, Rcas, PassCount };

    Image makeImage(VkExtent2D extent, VkImageUsageFlags usage);
    void destroy(Image& image) noexcept;
    void releaseImages() noexcept;
    void release() noexcept;
    void transition(VkCommandBuffer commands, VkImage image, VkImageLayout from, VkImageLayout to, VkPipelineStageFlags fromStage, VkAccessFlags fromAccess, VkPipelineStageFlags toStage, VkAccessFlags toAccess) const;
    void dispatch(VkCommandBuffer commands, Pass pass, const void* constants, std::uint32_t bytes) const;

    Graphics::Context context;
    VkFormat workFormat = VK_FORMAT_UNDEFINED;
    float sharpness;
    Image input;
    Image easu;
    Image output;
    VkSampler sampler = VK_NULL_HANDLE;
    VkDescriptorSetLayout setLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    std::array<VkDescriptorSet, PassCount> sets{};
    std::array<VkShaderModule, PassCount> modules{};
    std::array<VkPipeline, PassCount> pipelines{};
};

}

#endif
