#include "prx/libSceAgcDriver/Execution/include/DisplayFormat.hpp"

namespace AgcDriver {
namespace {

constexpr std::uint64_t PixelFormatUnormBit = 0x0100000000000000ull;
constexpr std::uint64_t PixelFormatR8G8B8A8 = 0x8000000022000000ull;
constexpr std::uint64_t PixelFormatR16G16B16A16Float = 0xc001000622000000ull;
constexpr std::uint64_t PixelFormatB16G16R16A16Float = 0xc001000600000000ull;

}

bool DisplayTenBit(std::uint64_t pixelFormat) {
    return (pixelFormat & PixelFormatUnormBit) != 0;
}

bool DisplayRedLow(std::uint64_t pixelFormat) {
    return (pixelFormat & ~PixelFormatUnormBit) == PixelFormatR8G8B8A8 || pixelFormat == PixelFormatR16G16B16A16Float;
}

bool DisplayHalfFloat(std::uint64_t pixelFormat) {
    return pixelFormat == PixelFormatR16G16B16A16Float || pixelFormat == PixelFormatB16G16R16A16Float;
}

std::uint32_t DisplayTexelBytes(std::uint64_t pixelFormat) {
    return DisplayHalfFloat(pixelFormat) ? 8u : 4u;
}

VkFormat DisplayTexelFormat(std::uint64_t pixelFormat) {
    if (DisplayHalfFloat(pixelFormat)) return VK_FORMAT_R16G16B16A16_SFLOAT;
    const bool redLow = DisplayRedLow(pixelFormat);
    if (DisplayTenBit(pixelFormat)) return redLow ? VK_FORMAT_A2B10G10R10_UNORM_PACK32 : VK_FORMAT_A2R10G10B10_UNORM_PACK32;
    return redLow ? VK_FORMAT_R8G8B8A8_UNORM : VK_FORMAT_B8G8R8A8_UNORM;
}

ResidentPresent ResidentPresentPath(VkFormat storage, std::uint64_t pixelFormat, bool blitSource) {
    if (DisplayHalfFloat(pixelFormat)) return storage == VK_FORMAT_R16G16B16A16_SFLOAT ? ResidentPresent::Convert : ResidentPresent::None;
    const bool tenBit = DisplayTenBit(pixelFormat);
    if (!tenBit && blitSource && storage == DisplayTexelFormat(pixelFormat)) return ResidentPresent::Blit;
    switch (storage) {
        case VK_FORMAT_A2B10G10R10_UNORM_PACK32:
        case VK_FORMAT_A2R10G10B10_UNORM_PACK32:
            return tenBit ? ResidentPresent::Convert : ResidentPresent::None;
        case VK_FORMAT_R8G8B8A8_UNORM:
        case VK_FORMAT_R8G8B8A8_SRGB:
        case VK_FORMAT_B8G8R8A8_UNORM:
        case VK_FORMAT_B8G8R8A8_SRGB:
            return tenBit ? ResidentPresent::None : ResidentPresent::Convert;
        default:
            return ResidentPresent::None;
    }
}

}
