#include <codegen/x86/MaskedStoreLowering.hpp>
#include <codegen/x86/X64OpcodeConstants.hpp>
#include <codegen/CodegenException.hpp>
#include <array>
#include <limits>

namespace Codegen {

namespace {

constexpr std::uint8_t kVexMap0F38 = 0x02;
constexpr std::uint8_t kPp66 = 0x01;
constexpr std::uint8_t kVexW = 0x80;
constexpr std::uint8_t kVexLength256 = 0x04;
constexpr std::uint8_t kVmaskmovpsStore = 0x2E;
constexpr std::uint8_t kVmaskmovpdStore = 0x2F;
constexpr std::uint8_t kVpmaskmovStore = 0x8E;
constexpr std::uint8_t kRexW = 0x48;
constexpr std::uint8_t kRexX = 0x02;
constexpr std::uint8_t kRexB = 0x01;
constexpr std::uint8_t kLea = 0x8D;
constexpr std::int64_t kSavedBytes = 128 + 4 * 8;

constexpr std::array<std::uint8_t, 9> kSave = {
    0x48, 0x8D, 0x64, 0x24, 0x80,
    0x9C,
    0x50,
    0x51,
    0x52,
};

constexpr std::array<std::uint8_t, 16> kAlignScratch = {
    0x48, 0x89, 0xE2,
    0x48, 0x83, 0xE4, 0xE0,
    0x48, 0x83, 0xEC, 0x40,
    0x48, 0x89, 0x54, 0x24, 0x20,
};

constexpr std::array<std::uint8_t, 17> kRestore = {
    0x48, 0x8B, 0x64, 0x24, 0x20,
    0x5A,
    0x59,
    0x58,
    0x9D,
    0x48, 0x8D, 0xA4, 0x24, 0x80, 0x00, 0x00, 0x00,
};

void _appendU32(std::vector<std::uint8_t>& bytes, const std::uint32_t value) {
    for (std::size_t index = 0; index < X64OpcodeConstants::Disp32Size; ++index)
        bytes.push_back(static_cast<std::uint8_t>(value >> (index * 8)));
}

}

std::optional<MaskedStoreOperands> DecodeVexMaskedStore(const std::uint8_t* data, const std::size_t length) {
    using namespace X64OpcodeConstants;
    std::size_t pos = 0;
    const bool addressSize = pos < length && data[pos] == PrefixAddressSize;
    if (addressSize)
        ++pos;
    if (pos + Vex3PrefixLength + 2 > length || data[pos] != OneByteVex3 || (data[pos + 1] & Vex3MapMask) != kVexMap0F38)
        return std::nullopt;
    const auto inverted = data[pos + 1];
    const auto payload = data[pos + 2];
    const auto opcode = data[pos + Vex3PrefixLength];
    if ((payload & 0x03) != kPp66)
        return std::nullopt;
    const bool w = (payload & kVexW) != 0;
    std::uint8_t elementBytes = 0;
    if (opcode == kVmaskmovpsStore && !w)
        elementBytes = 4;
    else if (opcode == kVmaskmovpdStore && !w)
        elementBytes = 8;
    else if (opcode == kVpmaskmovStore)
        elementBytes = w ? 8 : 4;
    else
        return std::nullopt;
    const auto modRmOffset = pos + Vex3PrefixLength + 1;
    const auto modrm = data[modRmOffset];
    const auto mod = static_cast<std::uint8_t>((modrm >> ModRmModShift) & ModRmModMask);
    const auto rm = static_cast<std::uint8_t>(modrm & ModRmRmMask);
    if (mod == ModRmModRegister)
        return std::nullopt;
    auto cursor = modRmOffset + 1;
    std::optional<std::uint8_t> sib;
    if (rm == ModRmRmSibPresent) {
        if (cursor >= length)
            return std::nullopt;
        sib = data[cursor++];
    }
    const bool extendedBase = (inverted & 0x20) == 0;
    const bool extendedIndex = (inverted & 0x40) == 0;
    const bool ripRelative = mod == ModRmModIndirect && rm == ModRmRmRipRelative;
    const bool absolute = mod == ModRmModIndirect && sib.has_value() && (*sib & SibBaseMask) == SibBaseDisp32;
    const std::size_t displacementSize = mod == ModRmModDisp8 ? Disp8Size : (mod == ModRmModDisp32 || ripRelative || absolute) ? Disp32Size : 0;
    if (cursor + displacementSize != length)
        return std::nullopt;
    std::int64_t displacement = 0;
    if (displacementSize == Disp8Size) {
        displacement = static_cast<std::int8_t>(data[cursor]);
    } else if (displacementSize == Disp32Size) {
        std::uint32_t value = 0;
        for (std::size_t index = 0; index < Disp32Size; ++index)
            value |= static_cast<std::uint32_t>(data[cursor + index]) << (index * 8);
        displacement = static_cast<std::int32_t>(value);
    }

    MaskedStoreOperands operands;
    operands.Source = static_cast<std::uint8_t>(((modrm >> ModRmRegShift) & ModRmRegMask) | ((inverted & 0x80) == 0 ? 8 : 0));
    operands.Mask = static_cast<std::uint8_t>(~(payload >> 3) & 0x0F);
    operands.ElementBytes = elementBytes;
    operands.Wide = (payload & kVexLength256) != 0;

    const bool stackBase = sib.has_value() && (*sib & SibBaseMask) == ModRmRmSibPresent && !extendedBase;
    auto& lea = operands.AddressLea;
    if (addressSize)
        lea.push_back(PrefixAddressSize);
    lea.push_back(static_cast<std::uint8_t>(kRexW | (extendedIndex ? kRexX : 0) | (extendedBase ? kRexB : 0)));
    lea.push_back(kLea);
    if (stackBase) {
        const auto adjusted = displacement + kSavedBytes;
        if (adjusted > std::numeric_limits<std::int32_t>::max())
            throw CodegenException("Masked store stack displacement does not fit after saving registers");
        lea.push_back(static_cast<std::uint8_t>((ModRmModDisp32 << ModRmModShift) | rm));
        lea.push_back(*sib);
        _appendU32(lea, static_cast<std::uint32_t>(static_cast<std::int32_t>(adjusted)));
        return operands;
    }
    lea.push_back(static_cast<std::uint8_t>((mod << ModRmModShift) | rm));
    if (sib)
        lea.push_back(*sib);
    if (ripRelative) {
        operands.RipDisplacementOffset = lea.size();
        operands.RipTarget = static_cast<std::int64_t>(length) + displacement;
        _appendU32(lea, 0);
    } else {
        lea.insert(lea.end(), data + cursor, data + cursor + displacementSize);
    }
    return operands;
}

void MaskedStoreLowering::EmitOutOfLine(StubBodyBuilder& body, const MaskedStoreOperands& operands) const {
    body.Raw(kSave);
    if (operands.RipDisplacementOffset)
        body.RipRelative(operands.AddressLea, *operands.RipDisplacementOffset, operands.RipTarget);
    else
        body.Raw(operands.AddressLea);
    body.Raw(kAlignScratch);
    const auto length = static_cast<std::uint8_t>(operands.Wide ? kVexLength256 : 0);
    const std::array<std::uint8_t, 6> spill = {
        X64OpcodeConstants::OneByteVex3,
        static_cast<std::uint8_t>(((operands.Source & 8) == 0 ? 0x80 : 0) | 0x61),
        static_cast<std::uint8_t>(0x7A | length),
        0x7F,
        static_cast<std::uint8_t>(((operands.Source & 7) << 3) | 0x04),
        0x24,
    };
    body.Raw(spill);
    const std::array<std::uint8_t, 5> signs = {
        X64OpcodeConstants::OneByteVex3,
        static_cast<std::uint8_t>(0xC1 | ((operands.Mask & 8) == 0 ? 0x20 : 0)),
        static_cast<std::uint8_t>(0x78 | length | (operands.ElementBytes == 8 ? kPp66 : 0)),
        0x50,
        static_cast<std::uint8_t>(0xC8 | (operands.Mask & 7)),
    };
    body.Raw(signs);
    const bool quad = operands.ElementBytes == 8;
    const auto count = (operands.Wide ? 32 : 16) / operands.ElementBytes;
    for (std::uint32_t element = 0; element < count; ++element) {
        const auto offset = static_cast<std::uint8_t>(element * operands.ElementBytes);
        const auto bit = std::uint32_t{1} << element;
        std::vector<std::uint8_t> copy;
        if (quad)
            copy.push_back(kRexW);
        copy.insert(copy.end(), {0x8B, 0x54, 0x24, offset});
        if (quad)
            copy.push_back(kRexW);
        copy.insert(copy.end(), {0x89, 0x50, offset});
        const std::array<std::uint8_t, 8> test = {
            0xF7, 0xC1,
            static_cast<std::uint8_t>(bit), static_cast<std::uint8_t>(bit >> 8), static_cast<std::uint8_t>(bit >> 16), static_cast<std::uint8_t>(bit >> 24),
            0x74, static_cast<std::uint8_t>(copy.size()),
        };
        body.Raw(test);
        body.Raw(copy);
    }
    body.Raw(kRestore);
}

}
