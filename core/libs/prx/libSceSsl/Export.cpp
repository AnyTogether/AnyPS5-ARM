#include <cstdint>
#include <cstddef>
#include <cstring>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <map>
#include <mutex>
#include <stdexcept>
#include <string>

// No network is emulated: contexts, templates and requests can be created, but any request
// that would touch the network fails with the library's network error.
static constexpr int ERROR_NETWORK = static_cast<int>(0x80435001);
static std::atomic<int> g_nextHandle{1};
static std::mutex g_poolsMutex;
static std::map<int, uint64_t> g_pools;

namespace {

constexpr int ERROR_NOT_FOUND = static_cast<int>(0x8095F004);
constexpr int ERROR_INVALID_ARG = static_cast<int>(0x8095177A);
constexpr int ERROR_INVALID_ID = static_cast<int>(0x8095F006);
constexpr int ERROR_INVALID_VALUE = static_cast<int>(0x8095F007);

struct SslData {
    char* ptr;
    size_t size;
};

struct SslMemoryPoolStats {
    size_t pool_size;
    size_t max_inuse_size;
    size_t current_inuse_size;
    int32_t reserved;
};

struct SslCaCerts {
    SslData* certs;
    size_t num;
    void* pool;
};

struct SslCaList {
    void** certs;
    int num;
};
static_assert(sizeof(SslCaList) == 16);

void RequireContext(const char* function, int sslCtxId) {
    std::lock_guard lock(g_poolsMutex);
    if (!g_pools.contains(sslCtxId)) throw std::invalid_argument(std::string(function) + ": unknown context");
}

// No certificate is ever handed out (no CA list, and no connection reaches a server), so any
// certificate or certificate name a title passes in cannot have come from this library.
[[noreturn]] void ForeignObject(const char* function, const char* object) {
    throw std::invalid_argument(std::string(function) + ": " + object + " not returned by libSceSsl");
}

int CertNameQuery(const char* function, int sslCtxId, const void* cert, void* certName) {
    if (!cert || !certName) return ERROR_INVALID_ARG;
    RequireContext(function, sslCtxId);
    ForeignObject(function, "certificate");
}

int NameQuery(const char* function, int sslCtxId, const void* certName) {
    if (!certName) return ERROR_INVALID_ARG;
    RequireContext(function, sslCtxId);
    ForeignObject(function, "certificate name");
}

}

extern "C" {

int APS5_VABI sceSslFreeCaCerts(int ssl_ctx_id, void* ca_certs) {
    (void)ssl_ctx_id;
    if (!ca_certs) return ERROR_INVALID_ARG;
    *static_cast<SslCaCerts*>(ca_certs) = {};
    return 0;
}

int APS5_VABI sceSslGetCaCerts(int ssl_ctx_id, void* ca_certs) {
    (void)ssl_ctx_id;
    if (!ca_certs) return ERROR_INVALID_ARG;
    *static_cast<SslCaCerts*>(ca_certs) = {};
    return ERROR_NOT_FOUND;
}

int APS5_VABI sceSslGetCaList(int sslCtxId, SslCaList* caList) {
    if (!caList) return ERROR_INVALID_ARG;
    RequireContext(__func__, sslCtxId);
    *caList = {};
    return ERROR_NOT_FOUND;
}

int APS5_VABI sceSslFreeCaList(int sslCtxId, SslCaList* caList) {
    if (!caList) return ERROR_INVALID_ARG;
    RequireContext(__func__, sslCtxId);
    if (caList->certs || caList->num) throw std::invalid_argument("sceSslFreeCaList: list not returned by sceSslGetCaList");
    return 0;
}

int APS5_VABI sceSslInit_nid_postfix(uint64_t pool_size) {
    const int id = g_nextHandle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard lock(g_poolsMutex);
    g_pools[id] = pool_size;
    return id;
}

int APS5_VABI sceSslTerm_nid_postfix(int ssl_ctx_id) {
    std::lock_guard lock(g_poolsMutex);
    g_pools.erase(ssl_ctx_id);
    return 0;
}

// This library exports no sceSslCreateConnection, so no connection id can have come from it.
int APS5_VABI sceSslClose(int sslConnectionId) {
    throw std::invalid_argument("sceSslClose: connection " + std::to_string(sslConnectionId) + " not created by libSceSsl");
}

int APS5_VABI sceSslGetSerialNumber(int sslCtxId, const void* cert, const uint8_t** data, size_t* size) {
    if (!cert || !data || !size) return ERROR_INVALID_ARG;
    RequireContext(__func__, sslCtxId);
    ForeignObject(__func__, "certificate");
}

int APS5_VABI sceSslLoadCert() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslUnloadCert(int sslCtxId) {
    RequireContext(__func__, sslCtxId);
    return 0;
}

int APS5_VABI sceSslGetMemoryPoolStats(int ssl_ctx_id, SslMemoryPoolStats* stats) {
    if (stats == nullptr) return ERROR_INVALID_VALUE;
    std::lock_guard lock(g_poolsMutex);
    const auto pool = g_pools.find(ssl_ctx_id);
    if (pool == g_pools.end()) {
        std::memset(stats, 0, sizeof(*stats));
        return ERROR_INVALID_ID;
    }
    *stats = {static_cast<size_t>(pool->second), 0, 0, 0};
    return 0;
}

int APS5_VABI sceSslFreeSslCertName(int sslCtxId, void* certName) {
    return NameQuery(__func__, sslCtxId, certName);
}

int APS5_VABI sceSslDisableVerifyOption(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslGetAlpnSelected(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslSetAlpn(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslSetMinSslVersion(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslGetIssuerName(int sslCtxId, const void* cert, void** certName) {
    return CertNameQuery(__func__, sslCtxId, cert, certName);
}

int APS5_VABI sceSslGetNameEntryCount(int sslCtxId, const void* certName) {
    return NameQuery(__func__, sslCtxId, certName);
}

int APS5_VABI sceSslGetNameEntryInfo(int sslCtxId, const void* certName, int entryNum, char* oidName, size_t maxOidNameLen,
                                     uint8_t* value, size_t maxValueLen, size_t* valueLen) {
    (void)entryNum;
    if (!oidName || !value || !valueLen || maxOidNameLen == 0 || maxValueLen == 0) return ERROR_INVALID_ARG;
    return NameQuery(__func__, sslCtxId, certName);
}

// A null buffer asks only for the size of the PEM text.
int APS5_VABI sceSslGetPem(int sslCtxId, const void* cert, char* pem, size_t* pemSize) {
    (void)pem;
    if (!cert || !pemSize) return ERROR_INVALID_ARG;
    RequireContext(__func__, sslCtxId);
    ForeignObject(__func__, "certificate");
}

int APS5_VABI sceSslGetSubjectName(int sslCtxId, const void* cert, void** certName) {
    return CertNameQuery(__func__, sslCtxId, cert, certName);
}

int APS5_VABI sceSslCreateConnection(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslDeleteConnection(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslEnableVerifyOption(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslConnect(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslRead(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceSslWrite(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
