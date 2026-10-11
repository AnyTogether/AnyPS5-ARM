#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <stdexcept>
#include <string>

namespace {
std::atomic<bool> g_initialized{false};
// Error codes and the row limit from SharpProspero's ContentSearch bindings.
constexpr int CONTENT_SEARCH_ERROR_NOT_INITIALIZED = static_cast<int>(0x809D1001);
constexpr int CONTENT_SEARCH_ERROR_LIMIT_TOO_BIG = static_cast<int>(0x809D100A);
constexpr std::uint32_t CONTENT_SEARCH_MAX_LIMIT = 92;
}

extern "C" {

int APS5_VABI sceContentSearchInit(const ContentSearchInitParam* init_param) {
    if (init_param == nullptr) APS5_INVALID_ARG_EX;
    bool expected = false;
    if (!g_initialized.compare_exchange_strong(expected, true)) throw std::logic_error(std::string(__func__) + ": already initialized");
    return 0;
}

// The host has no content library, so no metadata handle is ever opened.
int APS5_VABI sceContentSearchCloseMetadata(int metadata_id) {
    if (!g_initialized.load()) return CONTENT_SEARCH_ERROR_NOT_INITIALIZED;
    throw std::invalid_argument(std::string(__func__) + ": unknown metadata id " + std::to_string(metadata_id));
}

int APS5_VABI sceContentSearchGetMetadataFieldInfo(int metadata_id, const char* field, int* type, int* size) {
    if (field == nullptr || type == nullptr || size == nullptr) APS5_INVALID_ARG_EX;
    if (!g_initialized.load()) return CONTENT_SEARCH_ERROR_NOT_INITIALIZED;
    throw std::invalid_argument(std::string(__func__) + ": unknown metadata id " + std::to_string(metadata_id));
}

int APS5_VABI sceContentSearchGetMetadataValue(int metadata_id, const char* field, void* value) {
    if (field == nullptr || value == nullptr) APS5_INVALID_ARG_EX;
    if (!g_initialized.load()) return CONTENT_SEARCH_ERROR_NOT_INITIALIZED;
    throw std::invalid_argument(std::string(__func__) + ": unknown metadata id " + std::to_string(metadata_id));
}

int APS5_VABI sceContentSearchOpenMetadata(const char* file_path, int* metadata_id) {
    if (file_path == nullptr || metadata_id == nullptr) APS5_INVALID_ARG_EX;
    if (!g_initialized.load()) return CONTENT_SEARCH_ERROR_NOT_INITIALIZED;
    throw std::runtime_error(std::string(__func__) + ": no content at " + file_path);
}

// The content library is empty: every search matches no rows.
int APS5_VABI sceContentSearchSearchContent(const void* column_set, std::uint32_t column_set_length, const void* order_by, std::uint32_t order_by_length,
                                            std::uint32_t offset, std::uint32_t limit, std::int64_t* num_of_content, void* infos, std::int64_t* last_update_id) {
    (void)offset;
    if (num_of_content == nullptr || (column_set == nullptr && column_set_length != 0) || (order_by == nullptr && order_by_length != 0) ||
        (infos == nullptr && limit != 0)) {
        APS5_INVALID_ARG_EX;
    }
    if (!g_initialized.load()) return CONTENT_SEARCH_ERROR_NOT_INITIALIZED;
    if (limit > CONTENT_SEARCH_MAX_LIMIT) return CONTENT_SEARCH_ERROR_LIMIT_TOO_BIG;
    *num_of_content = 0;
    if (last_update_id != nullptr) *last_update_id = 0;
    return 0;
}

int APS5_VABI sceContentSearchTerm(void) {
    bool expected = true;
    if (!g_initialized.compare_exchange_strong(expected, false)) throw std::logic_error(std::string(__func__) + ": not initialized");
    return 0;
}

}
