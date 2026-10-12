#ifndef CODEGEN_X86_WIDESTOREOPERANDS_HPP
#define CODEGEN_X86_WIDESTOREOPERANDS_HPP

#include <codegen/x86/StubBodyBuilder.hpp>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace Codegen {

enum class WideStoreKind : std::uint8_t {
    Movups,
    Movupd,
    Movaps,
    Movapd,
    Movdqa,
    Movdqu,
    Movntps,
    Movntpd,
    Movntdq,
    Maskmovps,
    Maskmovpd,
    Pmaskmovd,
    Pmaskmovq
};

struct WideStoreOperands {
    WideStoreKind Kind;
    bool Masked;
    std::uint8_t Source;
    std::vector<std::uint8_t> Head;
    std::size_t VectorLengthOffset;
    MemoryOperand Memory;
};

[[nodiscard]] std::optional<WideStoreOperands> DecodeWideStore(const std::uint8_t* data, std::size_t length);

}

#endif
