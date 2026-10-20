#include <atomic>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <iterator>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int COMMON_DIALOG_STATUS_NONE = 0;
constexpr int COMMON_DIALOG_STATUS_INITIALIZED = 1;
constexpr int COMMON_DIALOG_STATUS_RUNNING = 2;
constexpr int COMMON_DIALOG_STATUS_FINISHED = 3;
constexpr int COMMON_DIALOG_ERROR_NOT_INITIALIZED = static_cast<int>(0x81340001u);
constexpr int COMMON_DIALOG_ERROR_ALREADY_INITIALIZED = static_cast<int>(0x81340002u);
constexpr int COMMON_DIALOG_ERROR_PARAM_INVALID = static_cast<int>(0x81340003u);
constexpr int COMMON_DIALOG_ERROR_BUSY = static_cast<int>(0x81340005u);
constexpr int COMMON_DIALOG_ERROR_NO_SERVICE = static_cast<int>(0x81340007u);
constexpr int COMMON_DIALOG_RESULT_USER_CANCELED = 1;
constexpr std::uint32_t LOGIN_DIALOG_PARAM_SIZE = 0x40;
constexpr std::uint32_t LOGIN_DIALOG_SELECTOR_LIMIT = 2;
constexpr std::size_t LOGIN_DIALOG_FIRST_RESERVED_WORD = 0x2C / 4;

bool ValidOpenParam(const void* param) {
 if (param == nullptr) return false;
 std::uint32_t size = 0;
 std::memcpy(&size, param, sizeof(size));
 if (size != LOGIN_DIALOG_PARAM_SIZE) return false;
 std::uint32_t words[LOGIN_DIALOG_PARAM_SIZE / sizeof(std::uint32_t)];
 std::memcpy(words, param, sizeof(words));
 if (words[1] >= LOGIN_DIALOG_SELECTOR_LIMIT) return false;
 for (std::size_t i = LOGIN_DIALOG_FIRST_RESERVED_WORD; i < std::size(words); ++i) {
  if (words[i] != 0) return false;
 }
 return true;
}

std::atomic<int> g_status{COMMON_DIALOG_STATUS_NONE};

}

extern "C" {

int APS5_VABI sceLoginDialogInitialize(void) {
 int expected = COMMON_DIALOG_STATUS_NONE;
 if (!g_status.compare_exchange_strong(expected, COMMON_DIALOG_STATUS_INITIALIZED)) return COMMON_DIALOG_ERROR_ALREADY_INITIALIZED;
 return 0;
}

int APS5_VABI sceLoginDialogOpen(const void* param) {
 if (!ValidOpenParam(param)) return COMMON_DIALOG_ERROR_PARAM_INVALID;
 const int status = g_status.load();
 if (status == COMMON_DIALOG_STATUS_NONE) return COMMON_DIALOG_ERROR_NOT_INITIALIZED;
 if (status == COMMON_DIALOG_STATUS_RUNNING) return COMMON_DIALOG_ERROR_BUSY;
 g_status = COMMON_DIALOG_STATUS_FINISHED;
 return 0;
}

int APS5_VABI sceLoginDialogUpdateStatus(void) {
 return g_status.load();
}

int APS5_VABI sceLoginDialogGetStatus(void) {
 return g_status.load();
}

int APS5_VABI sceLoginDialogGetResult(void* result) {
 if (result == nullptr) return COMMON_DIALOG_ERROR_PARAM_INVALID;
 const int status = g_status.load();
 if (status == COMMON_DIALOG_STATUS_NONE) return COMMON_DIALOG_ERROR_NOT_INITIALIZED;
 const std::int32_t words[] = {COMMON_DIALOG_RESULT_USER_CANCELED, COMMON_DIALOG_ERROR_NO_SERVICE};
 std::memcpy(result, words, sizeof(words));
 return status == COMMON_DIALOG_STATUS_FINISHED ? 0 : COMMON_DIALOG_ERROR_BUSY;
}

int APS5_VABI sceLoginDialogClose(void) {
 if (g_status.load() == COMMON_DIALOG_STATUS_NONE) return COMMON_DIALOG_ERROR_NOT_INITIALIZED;
 g_status = COMMON_DIALOG_STATUS_FINISHED;
 return 0;
}

int APS5_VABI sceLoginDialogTerminate(void) {
 if (g_status.exchange(COMMON_DIALOG_STATUS_NONE) == COMMON_DIALOG_STATUS_NONE) return COMMON_DIALOG_ERROR_NOT_INITIALIZED;
 return 0;
}

}
