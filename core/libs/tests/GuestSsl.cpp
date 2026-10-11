#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <exception>

extern "C" {
int APS5_VABI sceSslInit_nid_postfix(std::size_t);
int APS5_VABI sceSslTerm_nid_postfix(int);
int APS5_VABI sceSslGetCaCerts(int, void*);
int APS5_VABI sceSslFreeCaCerts(int, void*);
int APS5_VABI sceSslGetCaList(int, void*);
int APS5_VABI sceSslFreeCaList(int, void*);
int APS5_VABI sceSslUnloadCert(int);
int APS5_VABI sceSslGetSubjectName(int, const void*, void**);
int APS5_VABI sceSslGetIssuerName(int, const void*, void**);
int APS5_VABI sceSslGetSerialNumber(int, const void*, const std::uint8_t**, std::size_t*);
int APS5_VABI sceSslGetNameEntryCount(int, const void*);
int APS5_VABI sceSslGetNameEntryInfo(int, const void*, int, char*, std::size_t, std::uint8_t*, std::size_t, std::size_t*);
int APS5_VABI sceSslFreeSslCertName(int, void*);
int APS5_VABI sceSslClose(int);
}

struct SslMemoryPoolStats {
    std::size_t pool_size;
    std::size_t max_inuse_size;
    std::size_t current_inuse_size;
    std::int32_t reserved;
};

extern "C" int APS5_VABI sceSslGetMemoryPoolStats(int, SslMemoryPoolStats*);

static void Require(bool value) { if (!value) std::abort(); }

template <typename TCall>
static bool Throws(TCall call) {
    try {
        call();
    } catch (const std::exception&) {
        return true;
    }
    return false;
}

struct SslCaCerts {
    void* certs;
    std::size_t num;
    void* pool;
};

struct SslCaList {
    void** certs;
    int num;
};

int main() {
    constexpr int notFound = static_cast<int>(0x8095F004);
    constexpr int invalidArg = static_cast<int>(0x8095177A);
    int marker = 0;

    const int context = sceSslInit_nid_postfix(0x10000);
    Require(context > 0);
    SslMemoryPoolStats stats{1, 1, 1, 1};
    Require(sceSslGetMemoryPoolStats(context, &stats) == 0);
    Require(stats.pool_size == 0x10000 && stats.max_inuse_size == 0 && stats.current_inuse_size == 0 && stats.reserved == 0);
    Require(sceSslGetCaCerts(context, nullptr) == invalidArg);
    Require(sceSslFreeCaCerts(context, nullptr) == invalidArg);

    SslCaCerts certs{&marker, 3, &marker};
    Require(sceSslGetCaCerts(context, &certs) == notFound);
    Require(certs.certs == nullptr && certs.num == 0 && certs.pool == nullptr);

    certs = {&marker, 3, &marker};
    Require(sceSslFreeCaCerts(context, &certs) == 0);
    Require(certs.certs == nullptr && certs.num == 0 && certs.pool == nullptr);

    Require(sceSslGetCaList(context, nullptr) == invalidArg);
    Require(sceSslFreeCaList(context, nullptr) == invalidArg);

    void* handle = &marker;
    SslCaList list{&handle, 3};
    Require(sceSslGetCaList(context, &list) == notFound);
    Require(list.certs == nullptr && list.num == 0);
    Require(sceSslFreeCaList(context, &list) == 0);
    Require(list.certs == nullptr && list.num == 0);

    SslCaList foreign{&handle, 1};
    Require(Throws([&] { sceSslFreeCaList(context, &foreign); }));
    foreign = {nullptr, 1};
    Require(Throws([&] { sceSslFreeCaList(context, &foreign); }));
    foreign = {&handle, 0};
    Require(Throws([&] { sceSslFreeCaList(context, &foreign); }));

    void* name = nullptr;
    const std::uint8_t* serial = nullptr;
    std::size_t serialSize = 0;
    char oid[16];
    std::uint8_t value[16];
    std::size_t valueSize = 0;
    Require(sceSslGetSubjectName(context, nullptr, &name) == invalidArg);
    Require(sceSslGetSubjectName(context, &marker, nullptr) == invalidArg);
    Require(sceSslGetIssuerName(context, nullptr, &name) == invalidArg);
    Require(sceSslGetSerialNumber(context, nullptr, &serial, &serialSize) == invalidArg);
    Require(sceSslGetSerialNumber(context, &marker, nullptr, &serialSize) == invalidArg);
    Require(sceSslGetNameEntryCount(context, nullptr) == invalidArg);
    Require(sceSslGetNameEntryInfo(context, nullptr, 0, oid, sizeof(oid), value, sizeof(value), &valueSize) == invalidArg);
    Require(sceSslGetNameEntryInfo(context, &marker, 0, nullptr, sizeof(oid), value, sizeof(value), &valueSize) == invalidArg);
    Require(sceSslFreeSslCertName(context, nullptr) == invalidArg);
    Require(Throws([&] { sceSslGetSubjectName(context, &marker, &name); }));
    Require(Throws([&] { sceSslGetIssuerName(context, &marker, &name); }));
    Require(Throws([&] { sceSslGetSerialNumber(context, &marker, &serial, &serialSize); }));
    Require(Throws([&] { sceSslGetNameEntryCount(context, &marker); }));
    Require(Throws([] { sceSslClose(1); }));
    Require(Throws([&] { sceSslClose(context); }));
    Require(Throws([&] { sceSslGetNameEntryInfo(context, &marker, 0, oid, sizeof(oid), value, sizeof(value), &valueSize); }));
    Require(Throws([&] { sceSslFreeSslCertName(context, &marker); }));
    Require(name == nullptr && serial == nullptr && serialSize == 0 && valueSize == 0);

    Require(sceSslUnloadCert(context) == 0);
    Require(sceSslGetCaList(context, &list) == notFound);
    Require(list.certs == nullptr && list.num == 0);

    Require(sceSslTerm_nid_postfix(context) == 0);
    Require(sceSslGetCaList(context, nullptr) == invalidArg);
    Require(sceSslFreeCaList(context, nullptr) == invalidArg);
    list = {&handle, 3};
    Require(Throws([&] { sceSslGetCaList(context, &list); }));
    Require(Throws([&] { sceSslFreeCaList(context, &list); }));
    Require(Throws([&] { sceSslUnloadCert(context); }));
}
