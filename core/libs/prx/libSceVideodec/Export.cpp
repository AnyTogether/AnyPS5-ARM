#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

extern "C" {

int APS5_VABI sceVideodecCreateDecoder(const void* pCfgInfoIn, const void* pRsrcInfoIn, void* pCtrlOut) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceVideodecDecode(void* pCtrlIn, const void* pInputDataIn, void* pFrameBufferInOut, void* pPictureInfoOut) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceVideodecDeleteDecoder(void* pCtrlIn) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceVideodecFlush(void* pCtrlIn, void* pFrameBufferInOut, void* pPictureInfoOut) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceVideodecReset(void* pCtrlIn) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
