#ifndef CORE_LIBS_PRX_LIBSCEAGC_DCBSTATE_INCLUDE_DISPLAY_HPP
#define CORE_LIBS_PRX_LIBSCEAGC_DCBSTATE_INCLUDE_DISPLAY_HPP

#include <cstdint>
#include "SceTypes.hpp"

namespace Agc::Display {

std::uint32_t* WriteFlip(CommandBuffer* buf, std::uint32_t videoOutHandle, std::int32_t displayBufferIndex, std::uint32_t flipMode, std::int64_t flipArg, const char* function);

}

#endif
