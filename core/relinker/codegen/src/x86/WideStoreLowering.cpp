#include <codegen/x86/WideStoreLowering.hpp>
#include <codegen/x86/X64OpcodeConstants.hpp>
#include <codegen/CodegenException.hpp>
#include <array>

namespace Codegen {

namespace {

using namespace X64OpcodeConstants;

constexpr std::int32_t kHalfWidth = 16;
constexpr std::uint8_t kExtractPayload = static_cast<std::uint8_t>((VexVvvvUnused << VexVvvvShift) | VexLBit | VexPp66);
constexpr std::array<std::uint8_t, 1> kHighHalf = {0x01};

std::array<std::uint8_t, 4> _extractHead(const WideStoreOperands& operands) {
    const auto indexBase = operands.Memory.RexIndexBase;
    return {
        OneByteVex3,
        static_cast<std::uint8_t>(((operands.Source & 8) != 0 ? 0 : VexRBarBit) | ((indexBase & RexXBit) != 0 ? 0 : Vex3XBarBit) | ((indexBase & RexBBit) != 0 ? 0 : Vex3BBarBit) | Vex3Map0F3A),
        kExtractPayload,
        ThreeByte3AExtractf128};
}

}

void WideStoreLowering::EmitOutOfLine(StubBodyBuilder& body, const WideStoreOperands& operands) const {
    if (operands.Masked)
        throw CodegenException("Masked 256-bit vector stores have no lowering");
    auto low = operands.Head;
    low[operands.VectorLengthOffset] &= static_cast<std::uint8_t>(~VexLBit);
    body.Memory(low, operands.Source, operands.Memory, 0, {});
    body.Memory(_extractHead(operands), operands.Source, operands.Memory, kHalfWidth, kHighHalf);
}

LoweredBody WideStoreLowering::LowerOutOfLine(const WideStoreOperands& operands) const {
    StubBodyBuilder body;
    EmitOutOfLine(body, operands);
    return body.Finish();
}

}
