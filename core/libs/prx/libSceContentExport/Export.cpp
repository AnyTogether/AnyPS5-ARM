#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <limits>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>

namespace {
constexpr std::size_t MaxExecution = 10;
std::atomic<bool> g_initialized{false};
std::mutex g_sessionMutex;
std::set<std::int32_t> g_sessions;
std::int32_t g_lastSessionId = 0;

void RequireSession(const char* function, std::int32_t expId) {
    if (!g_initialized.load()) throw std::logic_error(std::string(function) + ": not initialized");
    if (!g_sessions.contains(expId)) throw std::invalid_argument(std::string(function) + ": unknown export session");
}
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

int APS5_VABI sceContentExportFinish(std::int32_t expId) {
    std::lock_guard lock(g_sessionMutex);
    RequireSession(__func__, expId);
    g_sessions.erase(expId);
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

int APS5_VABI sceContentExportAddToFavorites(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportDataProvideFunction(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFree(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFrom(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFromFileForSf(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFromFileWithContentIdList(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportFromFileWithTitleIdList(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportInit(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportMalloc(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportRemoveFromFavorites(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportRenameContent(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportValidateContents(void) {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceContentExportStart(void) {
    std::lock_guard lock(g_sessionMutex);
    if (!g_initialized.load()) throw std::logic_error(std::string(__func__) + ": not initialized");
    if (g_sessions.size() >= MaxExecution) throw std::runtime_error(std::string(__func__) + ": behaviour beyond 10 live export sessions is unknown");
    if (g_lastSessionId == std::numeric_limits<std::int32_t>::max()) throw std::runtime_error(std::string(__func__) + ": export session ids exhausted");
    g_sessions.insert(++g_lastSessionId);
    return g_lastSessionId;
}

int APS5_VABI sceContentExportGetProgress(std::int32_t expId) {
    std::lock_guard lock(g_sessionMutex);
    RequireSession(__func__, expId);
    throw std::runtime_error(std::string(__func__) + ": progress of a session with no running export is unknown");
}

int APS5_VABI sceContentExportCancel(std::int32_t expId) {
    std::lock_guard lock(g_sessionMutex);
    RequireSession(__func__, expId);
    throw std::runtime_error(std::string(__func__) + ": cancelling a session with no running export is unknown");
}

int APS5_VABI sceContentExportFromDataWithThumbnail(std::int32_t expId, const ContentExportParam* param, const ContentExportCallbackParam* contentCallbackParam,
    const char* thumbnailType, const ContentExportCallbackParam* thumbnailCallbackParam, char* path, std::size_t pathBufferLength) {
    std::lock_guard lock(g_sessionMutex);
    RequireSession(__func__, expId);
    throw std::runtime_error(std::string(__func__) + ": the host has no media library to export into");
}

int APS5_VABI sceContentExportTerm(void) {
    std::lock_guard lock(g_sessionMutex);
    if (!g_sessions.empty()) throw std::runtime_error(std::string(__func__) + ": terminating with live export sessions is unknown");
    bool expected = true;
    if (!g_initialized.compare_exchange_strong(expected, false)) throw std::logic_error(std::string(__func__) + ": not initialized");
    return 0;
}

}
