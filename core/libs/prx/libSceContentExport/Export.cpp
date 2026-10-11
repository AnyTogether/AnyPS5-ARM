#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>

namespace {
std::atomic<bool> g_initialized{false};
std::mutex g_sessionMutex;
std::set<int> g_sessions;
int g_nextSession = 1;
// SharpProspero's SCE_CONTENT_EXPORT_MAX_EXECUTION.
constexpr std::size_t MAX_SESSIONS = 10;
}

extern "C" {

int APS5_VABI sceContentExportInit2(const ContentExportInitParam2* init_param) {
    if (init_param == nullptr) APS5_INVALID_ARG_EX;
    if (init_param->malloc_func == nullptr || init_param->free_func == nullptr) throw std::invalid_argument(std::string(__func__) + ": missing allocator functions");
    if (init_param->reserved0 != 0 || init_param->reserved1 != 0) throw std::invalid_argument(std::string(__func__) + ": reserved fields are not zero");
    bool expected = false;
    if (!g_initialized.compare_exchange_strong(expected, true)) throw std::logic_error(std::string(__func__) + ": already initialized");
    return 0;
}

int APS5_VABI sceContentExportFinish(int exp_id) {
    if (!g_initialized.load()) throw std::logic_error(std::string(__func__) + ": not initialized");
    std::lock_guard lock(g_sessionMutex);
    if (g_sessions.erase(exp_id) == 0) throw std::invalid_argument(std::string(__func__) + ": unknown export session " + std::to_string(exp_id));
    return 0;
}

int APS5_VABI sceContentExportFromData(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFromFile(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFromFileWithThumbnail(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportStart(void) {
    if (!g_initialized.load()) throw std::logic_error(std::string(__func__) + ": not initialized");
    std::lock_guard lock(g_sessionMutex);
    if (g_sessions.size() >= MAX_SESSIONS) throw std::logic_error(std::string(__func__) + ": too many export sessions");
    while (g_sessions.count(g_nextSession) != 0) g_nextSession = g_nextSession == INT32_MAX ? 1 : g_nextSession + 1;
    const int id = g_nextSession;
    g_nextSession = id == INT32_MAX ? 1 : id + 1;
    g_sessions.insert(id);
    return id;
}

int APS5_VABI sceContentExportGetProgress(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceContentExportCancel(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceContentExportFromDataWithThumbnail(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceContentExportTerm(void) {
    bool expected = true;
    if (!g_initialized.compare_exchange_strong(expected, false)) throw std::logic_error(std::string(__func__) + ": not initialized");
    std::lock_guard lock(g_sessionMutex);
    g_sessions.clear();
    return 0;
}

}
