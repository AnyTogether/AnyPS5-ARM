#include "prx/libc/include/General.hpp"
#include <cstdint>

extern "C" {

int APS5_VABI sceOpusCeltDecInitialize(std::uint32_t*) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceOpusCeltDecTerminate(std::uint32_t*) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceOpusCeltDecGetSize(int) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceOpusCeltDecCreateEx(std::uint32_t*, void*, int, int) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceOpusCeltDecDecode(void*, const std::uint8_t*, int, std::int16_t*, int) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceOpusCeltDecDestroy(void*) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
