#ifndef CODEGEN_X86_MASKEDSTORELOWERING_HPP
#define CODEGEN_X86_MASKEDSTORELOWERING_HPP

#include <codegen/x86/StubBodyBuilder.hpp>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace Codegen {

struct MaskedStoreOperands {
    std::uint8_t Source;
    std::uint8_t Mask;
    std::uint8_t ElementBytes;
    bool Wide;
    std::vector<std::uint8_t> AddressLea;
    std::optional<std::size_t> RipDisplacementOffset;
    std::int64_t RipTarget = 0;
};

[[nodiscard]] std::optional<MaskedStoreOperands> DecodeVexMaskedStore(const std::uint8_t* data, std::size_t length);

class MaskedStoreLowering {
public:
    void EmitOutOfLine(StubBodyBuilder& body, const MaskedStoreOperands& operands) const;
};

}

#endif
