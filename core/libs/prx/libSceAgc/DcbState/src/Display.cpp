#include "prx/libSceAgc/DcbState/include/Display.hpp"

#include "prx/libSceAgc/Command/include/Memory.hpp"
#include "prx/libSceAgc/Command/include/Packet.hpp"
#include "prx/libSceAgcDriver/Execution/include/VideoOutput.hpp"
#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace Agc::Display {

std::uint32_t* WriteFlip(CommandBuffer* buf, std::uint32_t videoOutHandle, std::int32_t displayBufferIndex, std::uint32_t flipMode, std::int64_t flipArg, const char* function) {
    auto* packet = Agc::Command::Allocate(buf, AgcDriver::FlipPacketWords, function);
    packet[0] = AgcDriver::FlipPacketHeader;
    packet[1] = videoOutHandle;
    packet[2] = static_cast<std::uint32_t>(displayBufferIndex);
    packet[3] = flipMode;
    packet[4] = static_cast<std::uint32_t>(static_cast<std::uint64_t>(flipArg));
    packet[5] = static_cast<std::uint32_t>(static_cast<std::uint64_t>(flipArg) >> 32u);
    return packet;
}

}

extern "C" {

uint32_t* APS5_VABI sceAgcDcbSetFlip(CommandBuffer* buf, uint32_t video_out_handle, int32_t display_buffer_index, uint32_t flip_mode, int64_t flip_arg) {
    return Agc::Display::WriteFlip(buf, video_out_handle, display_buffer_index, flip_mode, flip_arg, __func__);
}

uint32_t* APS5_VABI sceAgcDcbPrimeUtcl2(CommandBuffer* buf, const volatile void* address, uint32_t size_in_bytes) {
    return Agc::Command::WritePrimeUtcl2(buf, address, size_in_bytes, __func__);
}

std::uint32_t APS5_VABI sceAgcDcbPrimeUtcl2GetSize() {
    return 20;
}

}
