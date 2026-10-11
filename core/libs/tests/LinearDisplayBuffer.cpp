#include "prx/libSceAgcDriver/Execution/include/DisplayBuffer.hpp"
#include "prx/libSceAgcDriver/Execution/include/DisplayFormat.hpp"
#include "prx/libSceAgcDriver/Graphics/include/HalfFloatScanout.hpp"
#include "prx/libSceAgcDriver/Graphics/include/TextureSwizzleEquations.hpp"
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <stdexcept>
#include <tuple>

static void Require(bool condition) { if (!condition) std::abort(); }
template<typename TAction> static void Reject(TAction action) {
    bool rejected = false;
    try { action(); } catch (const std::exception&) { rejected = true; }
    Require(rejected);
}

static std::size_t EquationOffset(std::uint32_t elementBytes, std::uint32_t blocksPerRow, std::uint32_t blockHeight, std::uint32_t x, std::uint32_t y) {
    const auto* equation = AgcDriver::Graphics::FindTextureSwizzleEquation(27u, elementBytes);
    Require(equation != nullptr);
    std::size_t offset = 0;
    for (std::uint32_t bit = 0; bit < 16u; ++bit) {
        const auto mask = equation->bits[bit];
        offset |= static_cast<std::size_t>(std::popcount((x & mask & 0xfffu) ^ ((y << 12u) & mask & 0xfff000u)) & 1) << bit;
    }
    const auto blockWidth = 65536u / elementBytes / blockHeight;
    return (static_cast<std::size_t>(y / blockHeight) * blocksPerRow + x / blockWidth) * 65536u + offset;
}

static void HalfFloatCodes() {
    for (std::uint32_t bits = 0; bits <= 0xffffu; ++bits) {
        const auto exponent = static_cast<int>((bits >> 10u) & 0x1fu);
        const auto mantissa = static_cast<double>(bits & 0x3ffu);
        const double magnitude = exponent == 0 ? std::ldexp(mantissa, -24) : exponent == 31 ? (mantissa == 0 ? INFINITY : NAN) : std::ldexp(1024.0 + mantissa, exponent - 25);
        const double value = (bits & 0x8000u) != 0u ? -magnitude : magnitude;
        unsigned color = 0;
        unsigned alpha = 0;
        if (value > 0) {
            const double clamped = std::min(value, 1.0);
            const double encoded = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * std::pow(clamped, 1.0 / 2.4) - 0.055;
            color = static_cast<unsigned>(std::floor(encoded * 255.0 + 0.5));
            alpha = static_cast<unsigned>(std::floor(clamped * 255.0 + 0.5));
        }
        Require(AgcDriver::Graphics::HalfFloatScanoutCode(static_cast<std::uint16_t>(bits), false) == color);
        Require(AgcDriver::Graphics::HalfFloatScanoutCode(static_cast<std::uint16_t>(bits), true) == alpha);
    }
}

static void HalfFloatDisplay() {
    constexpr std::uint64_t rgba16Float = 0xc001000622000000ull;
    const std::array<std::uint16_t, 24> halves{0x3c00, 0x3800, 0x0000, 0x3c00, 0xbc00, 0x4000, 0x7e00, 0x3800, 0x1234, 0x1234, 0x1234, 0x1234,
        0x7c00, 0x3400, 0x1419, 0x0000, 0x0001, 0x3555, 0x3c00, 0x3c00, 0x1234, 0x1234, 0x1234, 0x1234};
    std::array<std::byte, 48> input{};
    std::memcpy(input.data(), halves.data(), input.size());
    AgcDriver::DisplayBuffer buffer{65536, rgba16Float, 2, 2, 1, 3};
    Require(AgcDriver::DisplayBufferSize(buffer) == input.size());
    const auto pixels = AgcDriver::DecodeDisplayBuffer(buffer, input);
    const std::array<unsigned, 16> expected{0, 188, 255, 255, 0, 255, 0, 128, 3, 137, 255, 0, 255, 156, 0, 255};
    Require(pixels.size() == expected.size());
    for (unsigned i = 0; i < pixels.size(); ++i) Require(std::to_integer<unsigned>(pixels[i]) == expected[i]);
    Require(AgcDriver::DisplayBufferOffset(buffer, 1, 1) == 32);
    buffer.pixelFormat = 0xc001000600000000ull;
    const auto swapped = AgcDriver::DecodeDisplayBuffer(buffer, input);
    const std::array<unsigned, 16> blueFirst{255, 188, 0, 255, 0, 255, 0, 128, 255, 137, 3, 0, 0, 156, 255, 255};
    for (unsigned i = 0; i < swapped.size(); ++i) Require(std::to_integer<unsigned>(swapped[i]) == blueFirst[i]);
    Require(AgcDriver::DisplayHalfFloat(buffer.pixelFormat) && !AgcDriver::DisplayRedLow(buffer.pixelFormat) && AgcDriver::DisplayTexelFormat(buffer.pixelFormat) == VK_FORMAT_R16G16B16A16_SFLOAT);
    Require(AgcDriver::DisplayTexelFormat(rgba16Float) == VK_FORMAT_R16G16B16A16_SFLOAT && AgcDriver::DisplayTexelBytes(rgba16Float) == 8 && AgcDriver::DisplayRedLow(rgba16Float) && !AgcDriver::DisplayTenBit(rgba16Float));
    Require(AgcDriver::ResidentPresentPath(VK_FORMAT_R16G16B16A16_SFLOAT, rgba16Float, true) == AgcDriver::ResidentPresent::Convert);
    Require(AgcDriver::ResidentPresentPath(VK_FORMAT_R8G8B8A8_UNORM, rgba16Float, true) == AgcDriver::ResidentPresent::None);
    Require(AgcDriver::ResidentPresentPath(VK_FORMAT_R16G16B16A16_SFLOAT, 0x8000000022000000ull, true) == AgcDriver::ResidentPresent::None);
    buffer = {65536, rgba16Float, 3840, 2160};
    Require(AgcDriver::DisplayBufferSize(buffer) == 30u * 34u * 65536u);
    buffer.dccAddress = 0x20000;
    Reject([&] { AgcDriver::DisplayBufferSize(buffer); });
    buffer.dccAddress = 0;
    buffer.pixelFormat = 0xc001000700000000ull;
    Reject([&] { AgcDriver::DisplayBufferSize(buffer); });
    for (const auto [pixelFormat, elementBytes, blockHeight] : {std::tuple{rgba16Float, 8u, 64u}, std::tuple{std::uint64_t{0x8000000000000000ull}, 4u, 128u}}) {
        buffer = {65536, pixelFormat, 300, 200};
        for (std::uint32_t y = 0; y < buffer.height; ++y) {
            for (std::uint32_t x = 0; x < buffer.width; ++x) Require(AgcDriver::DisplayBufferOffset(buffer, x, y) == EquationOffset(elementBytes, 3, blockHeight, x, y));
        }
    }
}

int main() {
    AgcDriver::DisplayBuffer buffer{65536, 0x8000000000000000ull, 2, 2, 1, 3};
    const std::array<unsigned char, 24> input{1,2,3,4, 5,6,7,8, 99,99,99,99,
        9,10,11,12, 13,14,15,16, 99,99,99,99};
    const auto source = std::as_bytes(std::span(input));
    Require(AgcDriver::DisplayBufferSize(buffer) == input.size());
    auto pixels = AgcDriver::DecodeDisplayBuffer(buffer, source);
    Require(pixels.size() == 16);
    for (unsigned i = 0; i < pixels.size(); ++i) Require(std::to_integer<unsigned>(pixels[i]) == i + 1);
    buffer.pixelFormat = 0x8000000022000000ull;
    pixels = AgcDriver::DecodeDisplayBuffer(buffer, source);
    const std::array<unsigned char, 16> swapped{3,2,1,4, 7,6,5,8, 11,10,9,12, 15,14,13,16};
    for (unsigned i = 0; i < pixels.size(); ++i) Require(std::to_integer<unsigned>(pixels[i]) == swapped[i]);
    Reject([&] { AgcDriver::DecodeDisplayBuffer(buffer, source.first(23)); });
    buffer.pitchInPixel = 1;
    Reject([&] { AgcDriver::DisplayBufferSize(buffer); });
    buffer.pitchInPixel = 0;
    Require(AgcDriver::DisplayBufferSize(buffer) == 16);
    buffer.tilingMode = 2;
    Reject([&] { AgcDriver::DisplayBufferSize(buffer); });
    buffer.tilingMode = 0;
    Require(AgcDriver::DisplayBufferSize(buffer) == 65536);
    HalfFloatCodes();
    HalfFloatDisplay();
}
