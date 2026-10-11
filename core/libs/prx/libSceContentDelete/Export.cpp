#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <stdexcept>
#include <string>

namespace {
std::atomic<bool> g_initialized{false};
}

extern "C" {

int APS5_VABI sceContentDeleteInitialize(const ContentDeleteInitParam* init_param) {
    if (init_param == nullptr) APS5_INVALID_ARG_EX;
    bool expected = false;
    if (!g_initialized.compare_exchange_strong(expected, true)) throw std::logic_error(std::string(__func__) + ": already initialized");
    return 0;
}

// The host has no content library, so no path names content that could be deleted.
int APS5_VABI sceContentDeleteByPath(const char* content_path) {
    if (content_path == nullptr) APS5_INVALID_ARG_EX;
    if (!g_initialized.load()) throw std::logic_error(std::string(__func__) + ": not initialized");
    throw std::runtime_error(std::string(__func__) + ": no content at " + content_path);
}

int APS5_VABI sceContentDeleteTerminate(void) {
    bool expected = true;
    if (!g_initialized.compare_exchange_strong(expected, false)) throw std::logic_error(std::string(__func__) + ": not initialized");
    return 0;
}

}
