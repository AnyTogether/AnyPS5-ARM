#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

extern "C" {

int APS5_VABI sceRegMgrGetBin() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceRegMgrGetInt(int32_t optionId, int32_t* outInt) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceRegMgrGetStr(int32_t optionId, char* outString, std::size_t stringLength) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceRegMgrSetBin() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceRegMgrSetInt(int32_t optionId, int32_t inInt) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceRegMgrSetStr(int32_t optionId, const char* inStirng, std::size_t stringLength) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
std::int32_t APS5_VABI sceRegMgrNonSysGetInt(std::int64_t key, std::int32_t unk, std::int32_t* data) {
    (void)key;
    (void)unk;
    (void)data;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
