#ifndef CORE_SHADER_RECOMPILER_FLATAPERTURES_HPP
#define CORE_SHADER_RECOMPILER_FLATAPERTURES_HPP

#include <cstdint>

namespace ShaderRecompiler {

inline constexpr std::uint32_t SharedApertureHigh = 0x80000000u;
inline constexpr std::uint32_t PrivateApertureHigh = 0x70000000u;
inline constexpr std::uint64_t SharedApertureBase = static_cast<std::uint64_t>(SharedApertureHigh) << 32u;
inline constexpr std::uint64_t SharedApertureLimit = SharedApertureBase | 0xffffffffu;
inline constexpr std::uint64_t PrivateApertureBase = static_cast<std::uint64_t>(PrivateApertureHigh) << 32u;
inline constexpr std::uint64_t PrivateApertureLimit = PrivateApertureBase | 0xffffffffu;

}

#endif
