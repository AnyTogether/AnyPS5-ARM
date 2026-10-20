#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

extern "C" {

int APS5_VABI sceAppInstUtilInitialize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilTerminate(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppInstallAll(void* reserved) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppInstallTitleDir(const char* titleId, const char* titleDir, void* reserved) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppIsInInstalling(int32_t* installing) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppIsInUpdating() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppExists(const char* titleId, int32_t* exists) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppGetSize() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppInstallPkg() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppPrepareOverwritePkg() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppRecoverApp() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppUnInstall(const char* titleId) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppUnInstallAddcont() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppUnInstallPat() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppUnInstallTheme() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilAppUnInstallTypes() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilGetInstallProgressInfo() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilGetInstallProgress() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceAppInstUtilGetPrimaryAppSlot() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
