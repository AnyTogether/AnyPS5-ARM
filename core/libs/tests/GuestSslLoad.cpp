#include "prx/libSceSsl/SslTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SslCertificateFixture.hpp"

#include <cstdio>
#include <cstring>
#include <exception>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

extern "C" {
int APS5_VABI sceSslInit_nid_postfix(std::uint64_t);
int APS5_VABI sceSslTerm_nid_postfix(int);
int APS5_VABI sceSslGetMemoryPoolStats(int, SceSsl::MemoryPoolStats*);
int APS5_VABI sceSslLoadCert(int, int, SceSsl::Data**, SceSsl::Data*, SceSsl::Data*);
int APS5_VABI sceSslUnloadCert(int);
int APS5_VABI sceSslGetCaList(int, SceSsl::CaList*);
int APS5_VABI sceSslFreeCaList(int, SceSsl::CaList*);
int APS5_VABI sceSslGetCaCerts(int, SceSsl::CaCerts*);
int APS5_VABI sceSslFreeCaCerts(int, SceSsl::CaCerts*);
int APS5_VABI sceSslCreateConnection(int, int, const char*);
int APS5_VABI sceSslDeleteConnection(int);
int APS5_VABI sceSslSetVerifyCallback(int, int (APS5_VABI *)(int, unsigned int, void**, int, void*), void*);
}

namespace {

constexpr int NotFound = static_cast<int>(0x8095F004);

void Check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename TAction>
void Throws(TAction action) {
    bool caught = false;
    try { action(); } catch (const std::exception&) { caught = true; }
    Check(caught, "unsupported or malformed load was accepted");
}

SceSsl::Data Data(const char* text) {
    return {reinterpret_cast<std::uint8_t*>(const_cast<char*>(text)), std::strlen(text)};
}

SceSsl::MemoryPoolStats Stats(int id) {
    SceSsl::MemoryPoolStats stats{};
    Check(sceSslGetMemoryPoolStats(id, &stats) == 0, "stats failed");
    Check(stats.currentInuseSize <= stats.maxInuseSize && stats.maxInuseSize <= stats.poolSize && !stats.reserved,
        "pool accounting bounds failed");
    return stats;
}

void CheckRoot(const SceSsl::CaCerts& snapshot) {
    Check(snapshot.num == 1 && snapshot.certs[0].size == RootDer.size(), "CA count or DER size differs");
    Check(std::memcmp(snapshot.certs[0].ptr, RootDer.data(), RootDer.size()) == 0, "CA bytes changed");
}

void Lifecycle() {
    const int id = sceSslInit_nid_postfix(1024 * 1024);
    std::string original = RootPem;
    auto data = Data(original.c_str());
    auto* pointer = &data;
    Check(sceSslLoadCert(id, 1, &pointer, nullptr, nullptr) == 0, "initial CA load failed");
    original.assign(original.size(), '?');
    Check(Stats(id).currentInuseSize > RootDer.size(), "loaded certificate is not retained/accounted");
    SceSsl::CaCerts bytes{};
    Check(sceSslGetCaCerts(id, &bytes) == 0, "encoded CA query failed");
    CheckRoot(bytes);
    SceSsl::CaList handles{};
    Check(sceSslGetCaList(id, &handles) == 0 && handles.num == 1 && handles.certs[0], "CA handle absent");
    const int other = sceSslInit_nid_postfix(1024 * 1024);
    SceSsl::CaList empty{};
    Check(sceSslGetCaList(other, &empty) == NotFound, "CA escaped its context");
    auto foreign = handles;
    Throws([&] { sceSslFreeCaList(other, &foreign); });
    Check(sceSslUnloadCert(id) == 0, "unload failed");
    Check(sceSslGetCaList(id, &empty) == NotFound && !empty.certs && !empty.num, "unload retained active CA");
    CheckRoot(bytes);
    Check(sceSslFreeCaList(id, &handles) == 0 && !handles.certs && !handles.num, "handle snapshot release failed");
    Check(sceSslFreeCaCerts(id, &bytes) == 0 && !bytes.certs && !bytes.pool && !bytes.num, "encoded snapshot release failed");
    Check(Stats(id).currentInuseSize == 0, "certificate allocation leaked after release");
    Throws([&] { sceSslFreeCaList(id, &foreign); });
    Check(sceSslTerm_nid_postfix(id) == 0 && sceSslTerm_nid_postfix(other) == 0, "term failed");
}

void ConnectionLifetime() {
    const int id = sceSslInit_nid_postfix(1024 * 1024);
    const int connection = sceSslCreateConnection(id, -1, "example.invalid");
    const int other = sceSslInit_nid_postfix(1024 * 1024);
    Check(connection > 0 && connection != id && connection != other, "SSL handles overlap");
    auto data = Data(RootPem);
    auto* pointer = &data;
    Check(sceSslLoadCert(id, 1, &pointer, nullptr, nullptr) == 0, "CA load with a connection failed");
    Check(sceSslSetVerifyCallback(connection, nullptr, nullptr) == 0, "certificate load invalidated the connection");
    SceSsl::CaCerts bytes{};
    Check(sceSslGetCaCerts(id, &bytes) == 0, "CA query with a connection failed");
    CheckRoot(bytes);
    SceSsl::CaCerts empty{};
    Check(sceSslGetCaCerts(other, &empty) == NotFound, "CA escaped into another context");
    SceSsl::MemoryPoolStats stats{};
    Check(sceSslGetMemoryPoolStats(connection, &stats) == static_cast<int>(0x8095F006), "connection accepted as context");
    const int retained = sceSslCreateConnection(id, -1, "example.invalid");
    Check(retained > 0 && retained != connection && retained != other, "SSL connection handle was reused");
    Check(sceSslDeleteConnection(connection) == 0, "connection deletion failed");
    Check(sceSslUnloadCert(id) == 0, "credential unload failed with a retained connection");
    CheckRoot(bytes);
    Check(sceSslSetVerifyCallback(retained, nullptr, nullptr) == 0, "credential unload invalidated the connection");
    Check(sceSslFreeCaCerts(id, &bytes) == 0 && Stats(id).currentInuseSize == 0, "CA snapshot leaked with a retained connection");
    Check(sceSslTerm_nid_postfix(id) == 0, "context termination failed with a retained connection");
    Throws([&] { sceSslSetVerifyCallback(retained, nullptr, nullptr); });
    Check(sceSslDeleteConnection(retained) == 0, "terminated context's connection cannot be released");
    Check(sceSslGetCaCerts(other, &empty) == NotFound, "unrelated context was invalidated");
    Check(sceSslTerm_nid_postfix(other) == 0, "unrelated context termination failed");
}

void AtomicFailures() {
    const int id = sceSslInit_nid_postfix(1024 * 1024);
    SceSsl::Data der{const_cast<std::uint8_t*>(RootDer.data()), RootDer.size()};
    auto* pointer = &der;
    Check(sceSslLoadCert(id, 1, &pointer, nullptr, nullptr) == 0, "DER CA load failed");
    const auto before = Stats(id).currentInuseSize;
    auto bad = Data("not a certificate");
    SceSsl::Data* mixed[]{&der, &bad};
    Throws([&] { sceSslLoadCert(id, 2, mixed, nullptr, nullptr); });
    Check(Stats(id).currentInuseSize == before, "failed chain changed live allocation");
    SceSsl::CaCerts bytes{};
    Check(sceSslGetCaCerts(id, &bytes) == 0, "CA vanished after failure");
    CheckRoot(bytes);
    Check(sceSslFreeCaCerts(id, &bytes) == 0, "snapshot free failed");
    Throws([&] { sceSslLoadCert(id, -1, nullptr, nullptr, nullptr); });
    Throws([&] { sceSslLoadCert(id, 1, nullptr, nullptr, nullptr); });
    SceSsl::Data* absent = nullptr;
    Throws([&] { sceSslLoadCert(id, 1, &absent, nullptr, nullptr); });
    Throws([&] { sceSslLoadCert(id, 0, nullptr, &der, nullptr); });
    Check(Stats(id).currentInuseSize == before, "argument failure changed retained CA");
    Check(sceSslTerm_nid_postfix(id) == 0, "term failed");
    Throws([&] { sceSslLoadCert(id, 1, &pointer, nullptr, nullptr); });
    const int tiny = sceSslInit_nid_postfix(32);
    Throws([&] { sceSslLoadCert(tiny, 1, &pointer, nullptr, nullptr); });
    Check(Stats(tiny).currentInuseSize == 0, "failed small-pool load leaked");
    Check(sceSslTerm_nid_postfix(tiny) == 0, "small-pool term failed");
}

void ClientIdentity() {
    const int id = sceSslInit_nid_postfix(1024 * 1024);
    auto client = Data(ClientPem);
    auto key = Data(ClientKey);
    auto wrong = Data(RootKey);
    Check(sceSslLoadCert(id, 0, nullptr, &client, &key) == 0, "client identity load failed");
    const auto before = Stats(id).currentInuseSize;
    Check(before > 0, "identity not retained");
    Throws([&] { sceSslLoadCert(id, 0, nullptr, &client, &wrong); });
    Check(Stats(id).currentInuseSize == before, "mismatched key changed identity");
    Check(sceSslUnloadCert(id) == 0 && Stats(id).currentInuseSize == 0, "identity release failed");
    Check(sceSslTerm_nid_postfix(id) == 0, "identity term failed");
}

}

int main() {
    try {
        Lifecycle();
        AtomicFailures();
        ClientIdentity();
        ConnectionLifetime();
        std::vector<std::thread> workers;
        for (int i = 0; i < 3; ++i) workers.emplace_back([] { for (int n = 0; n < 4; ++n) Lifecycle(); });
        for (auto& worker : workers) worker.join();
        std::puts("SSL load lifecycle passed");
    } catch (const std::exception& error) {
        std::fprintf(stderr, "SSL load lifecycle failed: %s\n", error.what());
        return 1;
    }
}
