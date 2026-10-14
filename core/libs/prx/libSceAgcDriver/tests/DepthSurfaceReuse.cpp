#include "GraphicsTests.hpp"
#include "prx/libSceAgcDriver/Graphics/include/DepthSurface.hpp"
#include "prx/libSceAgcDriver/Graphics/include/GuestTextureResource.hpp"
#include "prx/libSceAgcDriver/Graphics/include/Texture.hpp"
#include <array>
#include <cstdint>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace {

using namespace AgcDriver::Graphics;

constexpr std::uint32_t FormatR8Uint = 5;
constexpr std::uint32_t FormatR16Unorm = 7;
constexpr std::uint32_t FormatR16Uint = 11;
constexpr std::uint32_t FormatR32Uint = 20;
constexpr std::uint32_t FormatR32Float = 22;
constexpr std::uint32_t FormatR11G11B10Float = 36;
constexpr std::uint32_t FormatR8G8B8A8Unorm = 56;
constexpr std::uint32_t TileStandard64KB = 0x9;
constexpr std::uint32_t TileDepth64KB = 0x18;
constexpr std::uint32_t TileRenderTarget64KB = 0x1b;
constexpr std::uint32_t Type2D = 9;
constexpr std::uint32_t Type2DArray = 13;

std::uintptr_t nextHandle = 0x1000;

template<typename THandle>
THandle newHandle() {
    return reinterpret_cast<THandle>(nextHandle += 0x10);
}

VkFormat lastImageFormat = VK_FORMAT_UNDEFINED;
std::vector<VkImage> createdImages;
std::vector<std::tuple<VkImage, VkImage, VkImageAspectFlags>> imageCopies;
VkImage lastImage = VK_NULL_HANDLE;
std::vector<VkImage> clearedImages;

VKAPI_ATTR VkResult VKAPI_CALL createImage(VkDevice, const VkImageCreateInfo* info, const VkAllocationCallbacks*, VkImage* image) {
    lastImageFormat = info->format;
    *image = newHandle<VkImage>();
    createdImages.push_back(*image);
    lastImage = *image;
    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL imageMemoryRequirements(VkDevice, VkImage, VkMemoryRequirements* requirements) {
    *requirements = {65536, 65536, 1};
}

VKAPI_ATTR VkResult VKAPI_CALL allocateMemory(VkDevice, const VkMemoryAllocateInfo*, const VkAllocationCallbacks*, VkDeviceMemory* memory) {
    *memory = newHandle<VkDeviceMemory>();
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL bindImageMemory(VkDevice, VkImage, VkDeviceMemory, VkDeviceSize) {
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL createImageView(VkDevice, const VkImageViewCreateInfo*, const VkAllocationCallbacks*, VkImageView* view) {
    *view = newHandle<VkImageView>();
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL allocateCommandBuffers(VkDevice, const VkCommandBufferAllocateInfo*, VkCommandBuffer* commands) {
    *commands = newHandle<VkCommandBuffer>();
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL createFence(VkDevice, const VkFenceCreateInfo*, const VkAllocationCallbacks*, VkFence* fence) {
    *fence = newHandle<VkFence>();
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL beginCommandBuffer(VkCommandBuffer, const VkCommandBufferBeginInfo*) {
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL endCommandBuffer(VkCommandBuffer) {
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL queueSubmit(VkQueue, std::uint32_t, const VkSubmitInfo*, VkFence) {
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL waitForFences(VkDevice, std::uint32_t, const VkFence*, VkBool32, std::uint64_t) {
    return VK_SUCCESS;
}

VKAPI_ATTR VkResult VKAPI_CALL getFenceStatus(VkDevice, VkFence) {
    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL freeCommandBuffers(VkDevice, VkCommandPool, std::uint32_t, const VkCommandBuffer*) {}
VKAPI_ATTR void VKAPI_CALL destroyFence(VkDevice, VkFence, const VkAllocationCallbacks*) {}
VKAPI_ATTR void VKAPI_CALL destroyImageView(VkDevice, VkImageView, const VkAllocationCallbacks*) {}
VKAPI_ATTR void VKAPI_CALL destroyImage(VkDevice, VkImage, const VkAllocationCallbacks*) {}
VKAPI_ATTR void VKAPI_CALL freeMemory(VkDevice, VkDeviceMemory, const VkAllocationCallbacks*) {}
VKAPI_ATTR void VKAPI_CALL cmdPipelineBarrier(VkCommandBuffer, VkPipelineStageFlags, VkPipelineStageFlags, VkDependencyFlags, std::uint32_t, const VkMemoryBarrier*, std::uint32_t, const VkBufferMemoryBarrier*, std::uint32_t, const VkImageMemoryBarrier*) {}
VKAPI_ATTR void VKAPI_CALL cmdClearDepthStencilImage(VkCommandBuffer, VkImage image, VkImageLayout, const VkClearDepthStencilValue*, std::uint32_t, const VkImageSubresourceRange*) {
    clearedImages.push_back(image);
}
VKAPI_ATTR void VKAPI_CALL cmdCopyImage(VkCommandBuffer, VkImage source, VkImageLayout, VkImage destination, VkImageLayout, std::uint32_t count, const VkImageCopy* regions) {
    for (std::uint32_t i = 0; i < count; ++i) imageCopies.emplace_back(source, destination, regions[i].dstSubresource.aspectMask);
}

VKAPI_ATTR void VKAPI_CALL formatProperties(VkPhysicalDevice, VkFormat, VkFormatProperties* properties) {
    *properties = {};
    properties->optimalTilingFeatures = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
}

VKAPI_ATTR void VKAPI_CALL formatPropertiesWithoutD16S8(VkPhysicalDevice, VkFormat format, VkFormatProperties* properties) {
    *properties = {};
    if (format != VK_FORMAT_D16_UNORM_S8_UINT) properties->optimalTilingFeatures = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
}

VKAPI_ATTR void VKAPI_CALL formatPropertiesOnlyD32S8(VkPhysicalDevice, VkFormat format, VkFormatProperties* properties) {
    *properties = {};
    if (format == VK_FORMAT_D32_SFLOAT_S8_UINT) properties->optimalTilingFeatures = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
}

PFN_vkVoidFunction VKAPI_CALL deviceProc(VkDevice, const char* name) {
    static const std::map<std::string_view, PFN_vkVoidFunction> table{
        {"vkCreateImage", reinterpret_cast<PFN_vkVoidFunction>(createImage)},
        {"vkGetImageMemoryRequirements", reinterpret_cast<PFN_vkVoidFunction>(imageMemoryRequirements)},
        {"vkAllocateMemory", reinterpret_cast<PFN_vkVoidFunction>(allocateMemory)},
        {"vkBindImageMemory", reinterpret_cast<PFN_vkVoidFunction>(bindImageMemory)},
        {"vkCreateImageView", reinterpret_cast<PFN_vkVoidFunction>(createImageView)},
        {"vkAllocateCommandBuffers", reinterpret_cast<PFN_vkVoidFunction>(allocateCommandBuffers)},
        {"vkCreateFence", reinterpret_cast<PFN_vkVoidFunction>(createFence)},
        {"vkBeginCommandBuffer", reinterpret_cast<PFN_vkVoidFunction>(beginCommandBuffer)},
        {"vkEndCommandBuffer", reinterpret_cast<PFN_vkVoidFunction>(endCommandBuffer)},
        {"vkQueueSubmit", reinterpret_cast<PFN_vkVoidFunction>(queueSubmit)},
        {"vkWaitForFences", reinterpret_cast<PFN_vkVoidFunction>(waitForFences)},
        {"vkGetFenceStatus", reinterpret_cast<PFN_vkVoidFunction>(getFenceStatus)},
        {"vkFreeCommandBuffers", reinterpret_cast<PFN_vkVoidFunction>(freeCommandBuffers)},
        {"vkDestroyFence", reinterpret_cast<PFN_vkVoidFunction>(destroyFence)},
        {"vkDestroyImageView", reinterpret_cast<PFN_vkVoidFunction>(destroyImageView)},
        {"vkDestroyImage", reinterpret_cast<PFN_vkVoidFunction>(destroyImage)},
        {"vkFreeMemory", reinterpret_cast<PFN_vkVoidFunction>(freeMemory)},
        {"vkCmdPipelineBarrier", reinterpret_cast<PFN_vkVoidFunction>(cmdPipelineBarrier)},
        {"vkCmdClearDepthStencilImage", reinterpret_cast<PFN_vkVoidFunction>(cmdClearDepthStencilImage)},
        {"vkCmdCopyImage", reinterpret_cast<PFN_vkVoidFunction>(cmdCopyImage)}
    };
    const auto it = table.find(name);
    return it == table.end() ? nullptr : it->second;
}

struct View {
    std::uint64_t address;
    std::uint32_t format;
    std::uint32_t width;
    std::uint32_t height;
    std::uint32_t tileMode = TileDepth64KB;
    std::uint32_t type = Type2D;
    std::uint32_t lastArray = 0;
};

std::array<std::uint32_t, 8> tsharp(const View& view) {
    std::array<std::uint32_t, 8> words{};
    const auto base = view.address >> 8u;
    const auto widthMinus1 = view.width - 1u;
    const auto heightMinus1 = view.height - 1u;
    words[0] = static_cast<std::uint32_t>(base);
    words[1] = static_cast<std::uint32_t>((base >> 32u) & 0xffu) | ((view.format & 0x1ffu) << 20u) | ((widthMinus1 & 0x3u) << 30u);
    words[2] = ((widthMinus1 >> 2u) & 0xfffu) | ((heightMinus1 & 0x3fffu) << 14u);
    words[3] = 4u | (5u << 3u) | (6u << 6u) | (7u << 9u) | ((view.tileMode & 0x1fu) << 20u) | ((view.type & 0xfu) << 28u);
    words[4] = view.lastArray & 0x1fffu;
    return words;
}

std::shared_ptr<Texture> lookup(const Context& context, const View& view) {
    const auto words = tsharp(view);
    return DepthSurfaceTexture(context, words, DecodeTextureResource(words), VkComponentMapping{});
}

void TestD16StencilFallback(const Context& context) {
    Require(HostDepthFormat(context, VK_FORMAT_D16_UNORM_S8_UINT) == VK_FORMAT_D16_UNORM_S8_UINT && HostDepthBiasConstant(context, VK_FORMAT_D16_UNORM_S8_UINT, 2.0f) == 2.0f, "a device with D16_UNORM_S8_UINT must keep it and its depth bias");
    static int withoutTag = 0;
    Context without = context;
    without.physical = reinterpret_cast<VkPhysicalDevice>(&withoutTag);
    without.formatProperties = formatPropertiesWithoutD16S8;
    constexpr std::uint64_t d16s8 = 0x70000000;
    constexpr std::uint64_t d16s8Stencil = 0x70800000;
    Require(HostDepthFormat(without, VK_FORMAT_D16_UNORM_S8_UINT) == VK_FORMAT_D24_UNORM_S8_UINT, "a device without D16_UNORM_S8_UINT must store it as D24_UNORM_S8_UINT");
    Require(HostDepthFormat(without, VK_FORMAT_D32_SFLOAT_S8_UINT) == VK_FORMAT_D32_SFLOAT_S8_UINT && HostDepthFormat(without, VK_FORMAT_D16_UNORM) == VK_FORMAT_D16_UNORM, "only D16_UNORM_S8_UINT is replaced");
    DepthSurfaceView(without, {d16s8, d16s8Stencil, {256, 256}, VK_FORMAT_D16_UNORM_S8_UINT, 1.0f, 0});
    Require(lastImageFormat == VK_FORMAT_D24_UNORM_S8_UINT, "a D16_UNORM_S8_UINT surface was not created as D24_UNORM_S8_UINT on a device without it");
    Require(lookup(without, {d16s8, FormatR16Unorm, 256, 256}) != nullptr, "an R16 view of a D16 surface stored as D24 must still sample its depth plane");
    Require(lookup(without, {d16s8Stencil, FormatR8Uint, 256, 256}) != nullptr, "an 8-bit view of the stencil plane of a D16 surface stored as D24 must sample it");
    Require(HostDepthBiasConstant(without, VK_FORMAT_D16_UNORM_S8_UINT, 2.0f) == 512.0f, "a 16-bit depth bias must be scaled by 256 for D24 storage");
    Require(HostDepthBiasConstant(without, VK_FORMAT_D32_SFLOAT_S8_UINT, 2.0f) == 2.0f, "a D32 depth bias must not be scaled");
    const auto refused = [&](const View& view) {
        try {
            lookup(without, view);
        } catch (const std::runtime_error& error) {
            return std::string_view(error.what()).find("a depth plane that the device stores in another depth format is not implemented") != std::string_view::npos;
        }
        return false;
    };
    Require(refused({d16s8, FormatR16Unorm, 256, 256, TileDepth64KB, Type2DArray, 1}), "two slices of a D16 surface stored as D24 must be refused, as the plane copy would read the wider image as 16-bit texels");
    Require(refused({d16s8, FormatR16Uint, 256, 256, TileStandard64KB}), "an R16_UINT view of a D16 surface stored as D24 must be refused");
    std::string storageError;
    try {
        const auto words = tsharp({d16s8, FormatR16Unorm, 256, 256});
        DepthSurfaceStorage(without, words, DecodeTextureResource(words), 0);
    } catch (const std::runtime_error& error) {
        storageError = error.what();
    }
    Require(storageError.find("depth plane") != std::string::npos && storageError.find("stored as") != std::string::npos, "storage access to the depth plane of a D16 surface stored as D24 must throw");
    ClearDepthSurfaces(without.device);

    static int onlyTag = 0;
    Context only = context;
    only.physical = reinterpret_cast<VkPhysicalDevice>(&onlyTag);
    only.formatProperties = formatPropertiesOnlyD32S8;
    Require(HostDepthFormat(only, VK_FORMAT_D16_UNORM_S8_UINT) == VK_FORMAT_D32_SFLOAT_S8_UINT, "a device with neither D16 nor D24 stencil formats must store D16_UNORM_S8_UINT as D32_SFLOAT_S8_UINT");
    Require(HostDepthBiasConstant(only, VK_FORMAT_D16_UNORM_S8_UINT, 0.0f) == 0.0f, "a zero depth bias needs no scaling");
    bool threw = false;
    try {
        HostDepthBiasConstant(only, VK_FORMAT_D16_UNORM_S8_UINT, 2.0f);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw, "a constant 16-bit depth bias on D32_SFLOAT_S8_UINT storage must throw");
}

}

void RunDepthSurfaceReuseTests() {
    static int deviceTag = 0;
    Context context{};
    context.device = reinterpret_cast<VkDevice>(&deviceTag);
    context.deviceProc = deviceProc;
    context.formatProperties = formatProperties;
    context.memory.memoryTypeCount = 1;
    context.memory.memoryTypes[0].propertyFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    context.limits.maxFramebufferWidth = 16384;
    context.limits.maxFramebufferHeight = 16384;
    context.limits.maxFramebufferLayers = 1;
    TestD16StencilFallback(context);
    constexpr std::uint64_t depth32 = 0x40000000;
    constexpr std::uint64_t depth16 = 0x50000000;
    constexpr std::uint64_t depthStencil = 0x60000000;
    constexpr std::uint64_t stencil = 0x60800000;
    DepthSurfaceView(context, {depth32, 0, {384, 384}, VK_FORMAT_D32_SFLOAT, 1.0f, 0});
    DepthSurfaceView(context, {depth16, 0, {256, 256}, VK_FORMAT_D16_UNORM, 1.0f, 0});
    DepthSurfaceView(context, {depthStencil, stencil, {320, 180}, VK_FORMAT_D32_SFLOAT_S8_UINT, 1.0f, 0});

    Require(lookup(context, {depth32, FormatR32Float, 384, 384}) != nullptr, "an R32F view of a D32 surface's own extent must sample its depth plane");
    Require(lookup(context, {depth16, FormatR16Unorm, 256, 256}) != nullptr, "an R16 view of a D16 surface's own extent must sample its depth plane");
    Require(lookup(context, {depth32, FormatR32Uint, 384, 384}) != nullptr, "a 32-bit raw depth bits view of a D32 surface must sample its depth plane");
    Require(lookup(context, {depth16, FormatR16Uint, 256, 256}) != nullptr, "a 16-bit raw depth bits view of a D16 surface must sample its depth plane");

    Require(lookup(context, {depth32, FormatR32Float, 192, 192}) == nullptr, "a view of another extent over a depth surface must be read as reused memory");
    Require(lookup(context, {depth32, FormatR11G11B10Float, 384, 384}) == nullptr, "an R11G11B10 view of a D32 surface's own extent must be read as reused memory");
    Require(lookup(context, {depth32, FormatR32Float, 512, 512, TileDepth64KB, Type2DArray, 5}) == nullptr, "a 2D array view of another extent over a depth surface must be read as reused memory");
    Require(lookup(context, {depth32, FormatR32Uint, 384, 384, TileRenderTarget64KB}) == nullptr, "an R32 uint view without a depth layout must be read as reused memory");
    Require(lookup(context, {depth16, FormatR32Float, 256, 256}) == nullptr, "an R32F view of a D16 surface's own extent must be read as reused memory");

    Require(lookup(context, {stencil, FormatR8Uint, 320, 180}) != nullptr, "an 8-bit view of a stencil plane's own extent must sample the stencil plane");
    Require(lookup(context, {stencil, FormatR8G8B8A8Unorm, 320, 180, TileRenderTarget64KB}) == nullptr, "an RGBA8 view of a stencil plane's own extent must be read as reused memory");
    Require(lookup(context, {stencil, FormatR32Float, 320, 180}) == nullptr, "an R32F view of a stencil plane's own extent must be read as reused memory");

    const auto storageAliasesDepth = [&](const Context& owner, const View& view) {
        const auto words = tsharp(view);
        return DepthSurfaceAt(owner, words, DecodeTextureResource(words));
    };
    Require(storageAliasesDepth(context, {depth32, FormatR32Float, 384, 384}), "storage access to the actual D32 plane must remain rejected");
    Require(storageAliasesDepth(context, {depth16, FormatR16Uint, 256, 256}), "raw D16 storage access must remain rejected");
    Require(!storageAliasesDepth(context, {depth32, FormatR32Float, 128, 128}), "temporary memory reused at a different extent is not a depth storage alias");
    Require(!storageAliasesDepth(context, {depth32, FormatR11G11B10Float, 384, 384}), "temporary memory reused for a color format is not a depth storage alias");
    Require(!storageAliasesDepth(context, {depth32, FormatR32Uint, 384, 384, TileRenderTarget64KB}), "raw integer color memory without a depth layout is not a depth storage alias");
    auto otherDevice = context;
    static int otherDeviceTag = 0;
    otherDevice.device = reinterpret_cast<VkDevice>(&otherDeviceTag);
    Require(!storageAliasesDepth(otherDevice, {depth32, FormatR32Float, 384, 384}), "a depth surface on another device must not block a storage lookup");

    constexpr std::uint64_t stencil16 = 0x60000000;
    DepthSurfaceView(context, {depth16, stencil16, {128, 128}, VK_FORMAT_D16_UNORM_S8_UINT, 1.0f, 0});
    Require(!storageAliasesDepth(context, {depth16, FormatR16Unorm, 256, 256}), "an older depth extent at the same address must not override the newest surface");
    Require(storageAliasesDepth(context, {depth16, FormatR16Unorm, 128, 128}), "the newest depth extent must still reject actual storage access");
    Require(storageAliasesDepth(context, {stencil16, FormatR8Uint, 128, 128}), "storage access to the actual stencil plane must remain rejected");
    Require(!storageAliasesDepth(context, {stencil16, FormatR11G11B10Float, 128, 128}), "a stencil address reused for color is not a stencil storage alias");

    constexpr std::uint64_t shared = 0x70000000;
    constexpr std::uint64_t stencilA = 0x71000000;
    constexpr std::uint64_t stencilB = 0x72000000;
    constexpr std::uint64_t otherDepth = 0x73000000;
    const auto pairing = [&](std::uint64_t depth, std::uint64_t stencil) {
        const auto before = createdImages.size();
        DepthSurfaceView(context, {depth, stencil, {256, 256}, VK_FORMAT_D32_SFLOAT_S8_UINT, 1.0f, 0});
        return createdImages.size() != before ? createdImages[before] : VK_NULL_HANDLE;
    };
    const auto withA = pairing(shared, stencilA);
    imageCopies.clear();
    const auto withB = pairing(shared, stencilB);
    Require(withA != VK_NULL_HANDLE && withB != VK_NULL_HANDLE && withA != withB, "each depth/stencil pairing must have its own image");
    Require(imageCopies.size() == 1 && imageCopies[0] == std::make_tuple(withA, withB, static_cast<VkImageAspectFlags>(VK_IMAGE_ASPECT_DEPTH_BIT)), "a depth plane paired with another stencil plane must carry its depth over");
    imageCopies.clear();
    pairing(shared, stencilB);
    Require(imageCopies.empty(), "drawing again with the same pairing must not copy");
    pairing(shared, stencilA);
    Require(imageCopies.size() == 1 && imageCopies[0] == std::make_tuple(withB, withA, static_cast<VkImageAspectFlags>(VK_IMAGE_ASPECT_DEPTH_BIT)), "returning to the first pairing must carry the depth written through the second");
    imageCopies.clear();
    const auto otherWithA = pairing(otherDepth, stencilA);
    Require(imageCopies.size() == 1 && imageCopies[0] == std::make_tuple(withA, otherWithA, static_cast<VkImageAspectFlags>(VK_IMAGE_ASPECT_STENCIL_BIT)), "a stencil plane paired with another depth plane must carry its stencil over");
    {
        constexpr std::uint64_t arrayBase = 0x80000000;
        constexpr std::uint64_t htile = 0x81000000;
        constexpr VkExtent2D extent{1024, 512};
        const auto sliceHtile = HtileMetadataBytes(extent);
        DepthTarget first{arrayBase, 0, extent, VK_FORMAT_D32_SFLOAT, 1.0f, 0};
        first.htileAddress = htile;
        DepthTarget second{arrayBase + DepthSliceBytes(extent, 4u), 0, extent, VK_FORMAT_D32_SFLOAT, 1.0f, 0};
        second.htileAddress = htile + sliceHtile;
        DepthSurfaceView(context, first);
        const auto firstImage = lastImage;
        DepthSurfaceView(context, second);
        const auto secondImage = lastImage;
        const auto clearsAfter = [&](std::size_t bytes) {
            clearedImages.clear();
            NoteHtileDepthClear(htile, static_cast<std::size_t>(bytes));
            DepthSurfaceView(context, first);
            DepthSurfaceView(context, second);
            return clearedImages;
        };
        Require(clearsAfter(sliceHtile) == std::vector<VkImage>{firstImage}, "an HTILE clear of the first slice must clear that slice alone");
        Require(clearsAfter(2u * sliceHtile) == std::vector<VkImage>{firstImage, secondImage}, "an HTILE clear over both slices must clear both");
    }

    ClearDepthSurfaces(context.device);
}
