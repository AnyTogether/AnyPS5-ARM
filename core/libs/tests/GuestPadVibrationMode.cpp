#include "SceTypes.hpp"
#include "prx/libScePad/include/Pad.hpp"
#include <cstdlib>
#include <initializer_list>

extern "C" {
int APS5_VABI scePadInit_nid_postfix(void);
int APS5_VABI scePadOpen_nid_postfix(int userId, int type, int index, const void* param);
int APS5_VABI scePadClose_nid_postfix(int handle);
int APS5_VABI scePadSetVibrationMode(int handle, int mode);
}

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    for (int handle : {-1, 0, 1, 12345})
        for (int mode : {-1, 0, 1, 4})
            Require(scePadSetVibrationMode(handle, mode) == PAD_ERROR_NOT_INITIALIZED);

    Require(scePadInit_nid_postfix() == PAD_OK);
    for (int handle : {-1, 0, 12345}) {
        Require(scePadSetVibrationMode(handle, -1) == PAD_ERROR_INVALID_ARG);
        Require(scePadSetVibrationMode(handle, 0) == PAD_ERROR_INVALID_ARG);
        for (int mode : {1, 2, 3, 4, 5})
            Require(scePadSetVibrationMode(handle, mode) == PAD_ERROR_INVALID_HANDLE);
    }

    const int handle = scePadOpen_nid_postfix(0x10000000, 0, 0, nullptr);
    Require(handle > 0);
    Require(scePadSetVibrationMode(handle, 0) == PAD_ERROR_INVALID_ARG);
    Require(scePadSetVibrationMode(handle, 1) == PAD_OK);
    Require(scePadClose_nid_postfix(handle) == PAD_OK);
}
