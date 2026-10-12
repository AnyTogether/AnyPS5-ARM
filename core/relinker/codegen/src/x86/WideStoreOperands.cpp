#include <codegen/x86/WideStoreOperands.hpp>
#include <codegen/x86/X64OpcodeConstants.hpp>
#include <codegen/CodegenException.hpp>
#include <utility>

namespace Codegen {

namespace {

using namespace X64OpcodeConstants;

bool _segmentOverride(const std::uint8_t byte) {
    return byte == PrefixSegCs || byte == PrefixSegSs || byte == PrefixSegDs || byte == PrefixSegEs || byte == PrefixSegFs || byte == PrefixSegGs;
}

bool _rex(const std::uint8_t byte) {
    return byte >= RexMin && byte <= RexMax;
}

std::optional<WideStoreKind> _packedKind(const std::uint8_t pp, const WideStoreKind single, const WideStoreKind packedDouble) {
    if (pp == VexPpNone)
        return single;
    if (pp == VexPp66)
        return packedDouble;
    return std::nullopt;
}

std::optional<WideStoreKind> _kind(const std::uint8_t map, const std::uint8_t opcode, const std::uint8_t pp, const bool wide) {
    if (map == Vex3Map0F) {
        switch (opcode) {
        case TwoByteMovupsStore:
            return _packedKind(pp, WideStoreKind::Movups, WideStoreKind::Movupd);
        case TwoByteMovapsStore:
            return _packedKind(pp, WideStoreKind::Movaps, WideStoreKind::Movapd);
        case TwoByteMovntps:
            return _packedKind(pp, WideStoreKind::Movntps, WideStoreKind::Movntpd);
        case TwoByteMovdqu:
            if (pp == VexPp66)
                return WideStoreKind::Movdqa;
            if (pp == VexPpF3)
                return WideStoreKind::Movdqu;
            return std::nullopt;
        case TwoByteMovntdq:
            if (pp == VexPp66)
                return WideStoreKind::Movntdq;
            return std::nullopt;
        default:
            return std::nullopt;
        }
    }
    if (map == Vex3Map0F38 && pp == VexPp66) {
        switch (opcode) {
        case ThreeByte38Maskmovps:
            return WideStoreKind::Maskmovps;
        case ThreeByte38Maskmovpd:
            return WideStoreKind::Maskmovpd;
        case ThreeByte38Pmaskmov:
            return wide ? WideStoreKind::Pmaskmovq : WideStoreKind::Pmaskmovd;
        default:
            return std::nullopt;
        }
    }
    return std::nullopt;
}

bool _masked(const WideStoreKind kind) {
    return kind == WideStoreKind::Maskmovps || kind == WideStoreKind::Maskmovpd || kind == WideStoreKind::Pmaskmovd || kind == WideStoreKind::Pmaskmovq;
}

}

std::optional<WideStoreOperands> DecodeWideStore(const std::uint8_t* data, const std::size_t length) {
    std::size_t pos = 0;
    std::vector<std::uint8_t> prefixes;
    bool rex = false;
    bool addressSize = false;
    bool legacy = false;
    while (pos < length && data[pos] != OneByteVex2 && data[pos] != OneByteVex3) {
        const auto byte = data[pos];
        if (_rex(byte)) {
            rex = true;
            ++pos;
            continue;
        }
        if (_segmentOverride(byte))
            prefixes.push_back(byte);
        else if (byte == PrefixAddressSize)
            addressSize = true;
        else if (byte == PrefixOperandSize || byte == PrefixRepne || byte == PrefixRep || byte == PrefixLock)
            legacy = true;
        else
            return std::nullopt;
        rex = false;
        ++pos;
    }
    if (pos >= length)
        return std::nullopt;
    const bool vex2 = data[pos] == OneByteVex2;
    const auto vexLength = vex2 ? Vex2PrefixLength : Vex3PrefixLength;
    const auto opcodeOffset = pos + vexLength;
    if (opcodeOffset >= length)
        return std::nullopt;
    const auto byte1 = data[pos + 1];
    auto map = Vex3Map0F;
    auto payload = byte1;
    std::uint8_t indexBase = 0;
    if (!vex2) {
        map = static_cast<std::uint8_t>(byte1 & Vex3MapMask);
        payload = data[pos + 2];
        indexBase = static_cast<std::uint8_t>(((byte1 & Vex3XBarBit) == 0 ? RexXBit : 0) | ((byte1 & Vex3BBarBit) == 0 ? RexBBit : 0));
    }
    const bool wide = !vex2 && (payload & Vex3WBit) != 0;
    const auto kind = _kind(map, data[opcodeOffset], static_cast<std::uint8_t>(payload & VexPpMask), wide);
    if (!kind || (payload & VexLBit) == 0)
        return std::nullopt;
    const auto modRmOffset = opcodeOffset + 1;
    if (modRmOffset >= length)
        throw CodegenException("256-bit vector store truncated before its ModRM byte");
    const auto modrm = data[modRmOffset];
    if (((modrm >> ModRmModShift) & ModRmModMask) == ModRmModRegister)
        return std::nullopt;
    const bool masked = _masked(*kind);
    if (!masked && addressSize)
        throw CodegenException("256-bit vector store with an address-size prefix");
    if (!masked && legacy)
        throw CodegenException("66, F2, F3 or LOCK prefix before the VEX byte of a 256-bit vector store");
    if (!masked && rex)
        throw CodegenException("REX prefix directly before the VEX byte of a 256-bit vector store");
    if (!masked && ((payload >> VexVvvvShift) & VexVvvvMask) != VexVvvvUnused)
        throw CodegenException("256-bit vector store with a VEX.vvvv register");
    WideStoreOperands operands{
        *kind,
        masked,
        static_cast<std::uint8_t>(((modrm >> ModRmRegShift) & ModRmRegMask) | ((byte1 & VexRBarBit) == 0 ? 8 : 0)),
        std::vector<std::uint8_t>(data + pos, data + modRmOffset),
        vexLength - 1,
        DecodeMemoryOperand(data, length, modRmOffset, static_cast<std::uint8_t>(RexMin | indexBase), std::move(prefixes))};
    if (modRmOffset + operands.Memory.EncodedSize != length)
        throw CodegenException("256-bit vector store does not end with its memory operand");
    return operands;
}

}
