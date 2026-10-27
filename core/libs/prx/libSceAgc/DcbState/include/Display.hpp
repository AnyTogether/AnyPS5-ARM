#ifndef CORE_LIBS_PRX_LIBSCEAGC_DCBSTATE_INCLUDE_DISPLAY_HPP
#define CORE_LIBS_PRX_LIBSCEAGC_DCBSTATE_INCLUDE_DISPLAY_HPP

#include <cstdint>
#include "SceTypes.hpp"
#include "SceShaders.hpp"

extern "C" {

uint32_t* APS5_VABI sceAgcDcbSetFlip(CommandBuffer* buf, uint32_t videoOutHandle, int32_t displayBufferIndex, uint32_t flipMode, int64_t flipArg);
uint32_t* APS5_VABI sceAgcDcbPrimeUtcl2(CommandBuffer* buf, const volatile void* address, uint32_t sizeInBytes);
std::uint32_t APS5_VABI sceAgcDcbPrimeUtcl2GetSize();

}


namespace Agc::Display {

std::uint32_t* WriteFlip(CommandBuffer* buf, std::uint32_t videoOutHandle, std::int32_t displayBufferIndex, std::uint32_t flipMode, std::int64_t flipArg, const char* function);

}

#endif
