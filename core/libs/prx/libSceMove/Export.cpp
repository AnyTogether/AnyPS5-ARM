#include <cstdint>
#include <cstddef>
#include <mutex>
#include <unordered_map>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libSceUserService/UserService.hpp"

namespace {

constexpr int MOVE_OK = 0;
constexpr int MOVE_NO_CONTROLLER_CONNECTED = 1;
constexpr int MOVE_ERROR_NOT_INIT = static_cast<int>(0x80EE0001);
constexpr int MOVE_ERROR_ALREADY_INIT = static_cast<int>(0x80EE0002);
constexpr int MOVE_ERROR_INVALID_ARG = static_cast<int>(0x80EE0003);
constexpr int32_t MOVE_FIRST_HANDLE = 0x30B0100;
constexpr int32_t MOVE_HANDLE_STEP = 0x100;

std::mutex stateMutex;
bool initialized = false;
int32_t nextHandle = MOVE_FIRST_HANDLE;
struct Slot {
    int32_t type;
    int32_t index;
};

std::unordered_map<int32_t, Slot> openHandles;

int checkHandle(const char* function, int32_t handle) {
    std::lock_guard lock(stateMutex);
    if (!initialized) return MOVE_ERROR_NOT_INIT;
    if (!openHandles.contains(handle)) NotImplemented_nid_no_patch(function);
    return MOVE_OK;
}

}

extern "C" {

int APS5_VABI sceMoveInit(void) {
    std::lock_guard lock(stateMutex);
    if (initialized) return MOVE_ERROR_ALREADY_INIT;
    initialized = true;
    return MOVE_OK;
}

int APS5_VABI sceMoveTerm(void) {
    std::lock_guard lock(stateMutex);
    if (!initialized) return MOVE_ERROR_NOT_INIT;
    initialized = false;
    openHandles.clear();
    return MOVE_OK;
}

int APS5_VABI sceMoveOpen(int32_t userId, int32_t type, int32_t index) {
    std::lock_guard lock(stateMutex);
    if (!initialized) return MOVE_ERROR_NOT_INIT;
    if (userId != USER_SERVICE_INITIAL_USER_ID) NotImplemented_nid_no_patch(__func__);
    for (const auto& [openHandle, slot] : openHandles) {
        if (slot.type == type && slot.index == index) NotImplemented_nid_no_patch(__func__);
    }
    const int32_t handle = nextHandle;
    nextHandle += MOVE_HANDLE_STEP;
    openHandles.emplace(handle, Slot{type, index});
    return handle;
}

int APS5_VABI sceMoveClose(int32_t handle) {
    std::lock_guard lock(stateMutex);
    if (!initialized) return MOVE_ERROR_NOT_INIT;
    if (openHandles.erase(handle) == 0) NotImplemented_nid_no_patch(__func__);
    return MOVE_OK;
}

int APS5_VABI sceMoveGetDeviceInfo(int32_t handle, void* info) {
    if (const int result = checkHandle(__func__, handle); result != MOVE_OK) return result;
    if (!info) return MOVE_ERROR_INVALID_ARG;
    return MOVE_NO_CONTROLLER_CONNECTED;
}

int APS5_VABI sceMoveGetExtensionPortInfo(int32_t handle, void* data) {
    if (const int result = checkHandle(__func__, handle); result != MOVE_OK) return result;
    if (!data) return MOVE_ERROR_INVALID_ARG;
    return MOVE_NO_CONTROLLER_CONNECTED;
}

int APS5_VABI sceMoveReadStateLatest(int32_t handle, void* data) {
    if (const int result = checkHandle(__func__, handle); result != MOVE_OK) return result;
    if (!data) return MOVE_ERROR_INVALID_ARG;
    return MOVE_NO_CONTROLLER_CONNECTED;
}

int APS5_VABI sceMoveReadStateRecent(int32_t handle, int64_t timestamp, void* data, int32_t* outCount) {
    if (const int result = checkHandle(__func__, handle); result != MOVE_OK) return result;
    if (timestamp < 0 || !data || !outCount) return MOVE_ERROR_INVALID_ARG;
    return MOVE_NO_CONTROLLER_CONNECTED;
}

int APS5_VABI sceMoveSetVibration(int32_t handle, uint8_t motor) {
    (void)motor;
    if (const int result = checkHandle(__func__, handle); result != MOVE_OK) return result;
    return MOVE_NO_CONTROLLER_CONNECTED;
}

int APS5_VABI sceMoveSetLightSphere(int32_t handle, uint8_t red, uint8_t green, uint8_t blue) {
    (void)red;
    (void)green;
    (void)blue;
    if (const int result = checkHandle(__func__, handle); result != MOVE_OK) return result;
    return MOVE_NO_CONTROLLER_CONNECTED;
}

int APS5_VABI sceMoveResetLightSphere(int32_t handle) {
    return checkHandle(__func__, handle);
}

}
