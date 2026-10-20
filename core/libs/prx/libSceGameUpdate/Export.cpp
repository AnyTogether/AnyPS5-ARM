#include <atomic>
#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

// Update checks need the network, which is not available; requests fail so the game skips the check.
static constexpr int SCE_GAME_UPDATE_ERROR_OFFLINE = static_cast<int>(0x80D50001);
static constexpr int SCE_GAME_UPDATE_ERROR_NOT_INITIALIZED = static_cast<int>(0x80412801);
static constexpr int SCE_GAME_UPDATE_ERROR_ALREADY_INITIALIZED = static_cast<int>(0x80412802);
static constexpr int SCE_GAME_UPDATE_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80412803);
static constexpr int SCE_GAME_UPDATE_ERROR_INVALID_SIZE = static_cast<int>(0x80412804);
static constexpr int SCE_GAME_UPDATE_ERROR_REQUEST_NOT_FOUND = static_cast<int>(0x80412805);

static_assert(sizeof(GameUpdateCheckParam) == 0x30);
static_assert(sizeof(GameUpdateCheckResult) == 0x30);

static std::atomic<bool> g_initialized{false};

static int CheckRequestId(int request_id) {
    if (request_id <= 0) {
        return SCE_GAME_UPDATE_ERROR_REQUEST_NOT_FOUND;
    }
    if (!g_initialized.load()) {
        return SCE_GAME_UPDATE_ERROR_NOT_INITIALIZED;
    }
    return SCE_GAME_UPDATE_ERROR_REQUEST_NOT_FOUND;
}

static bool HasNonZeroReserved(const GameUpdateCheckParam* param) {
    for (std::uint32_t word : param->reserved) {
        if (word != 0) {
            return true;
        }
    }
    return false;
}

extern "C" {

int APS5_VABI sceGameUpdateAbortRequest(int request_id) {
    return CheckRequestId(request_id);
}

int APS5_VABI sceGameUpdateCheck(int request_id, const GameUpdateCheckParam* param, GameUpdateCheckResult* result) {
    if (request_id <= 0) {
        return SCE_GAME_UPDATE_ERROR_REQUEST_NOT_FOUND;
    }
    if (param == nullptr || result == nullptr) {
        return SCE_GAME_UPDATE_ERROR_INVALID_ARGUMENT;
    }
    if (param->size != sizeof(GameUpdateCheckParam) || result->size != sizeof(GameUpdateCheckResult)) {
        return SCE_GAME_UPDATE_ERROR_INVALID_SIZE;
    }
    if (param->option != 0 || HasNonZeroReserved(param)) {
        return SCE_GAME_UPDATE_ERROR_INVALID_ARGUMENT;
    }
    return CheckRequestId(request_id);
}

int APS5_VABI sceGameUpdateCreateRequest(void) {
    if (!g_initialized.load()) {
        return SCE_GAME_UPDATE_ERROR_NOT_INITIALIZED;
    }
    return SCE_GAME_UPDATE_ERROR_OFFLINE;
}

int APS5_VABI sceGameUpdateDeleteRequest(int request_id) {
    return CheckRequestId(request_id);
}

int APS5_VABI sceGameUpdateGetAddcontLatestVersion(uint32_t service_label, const void* entitlement_label, GameUpdateAddcontVersionInfo* info) {
    (void)service_label;
    if (info == nullptr) {
        return SCE_GAME_UPDATE_ERROR_INVALID_ARGUMENT;
    }
    if (entitlement_label == nullptr) {
        return SCE_GAME_UPDATE_ERROR_INVALID_ARGUMENT;
    }
    if (!g_initialized.load()) {
        return SCE_GAME_UPDATE_ERROR_NOT_INITIALIZED;
    }
    if (info->size < sizeof(GameUpdateAddcontVersionInfo)) {
        return SCE_GAME_UPDATE_ERROR_INVALID_SIZE;
    }
    const std::size_t size = info->size;
    *info = {};
    info->size = size;
    info->found = false;
    return 0;
}

int APS5_VABI sceGameUpdateInitialize(void) {
    if (g_initialized.exchange(true)) {
        return SCE_GAME_UPDATE_ERROR_ALREADY_INITIALIZED;
    }
    return 0;
}

int APS5_VABI sceGameUpdateTerminate(void) {
    if (!g_initialized.exchange(false)) {
        return SCE_GAME_UPDATE_ERROR_NOT_INITIALIZED;
    }
    return 0;
}

}
