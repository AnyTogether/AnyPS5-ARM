#include <cstdint>
#include <stdexcept>
#include <string>
#include <prx/libc/include/General.hpp>

#include "SceShaders.hpp"
#include "prx/libSceAgc/Shader/include/ShaderConstants.hpp"

namespace {

constexpr std::uint32_t IdxExportFormatMask = 0xfu;
constexpr std::uint32_t IdxExportFormatTwoComponents = 2u;
constexpr std::uint32_t TwoComponentPrimPayload = 8u;

}

extern "C" {

int APS5_VABI sceAgcGetGsPrimPayload(std::uint32_t* payload, const Shader* gs) {
    if (payload == nullptr || gs == nullptr || (gs->num_cx_registers != 0 && gs->cx_registers == nullptr)) APS5_INVALID_ARG_EX;
    std::uint32_t result = 0;
    for (std::uint32_t i = 0; i < gs->num_cx_registers; ++i) {
        if (gs->cx_registers[i].offset != ShaderRegs::SPI_SHADER_IDX_FORMAT) continue;
        if ((gs->cx_registers[i].value & IdxExportFormatMask) == IdxExportFormatTwoComponents) result = TwoComponentPrimPayload;
        break;
    }
    *payload = result;
    return 0;
}

}
