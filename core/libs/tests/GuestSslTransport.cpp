#ifdef _WIN32
#include <winsock2.h>
#else
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <csignal>
#endif

#include "prx/libSceSsl/SslTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SslCertificateFixture.hpp"

#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#include <mbedtls/net_sockets.h>
#include <mbedtls/pk.h>
#include <mbedtls/ssl.h>
#include <mbedtls/x509_crt.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>
#include <thread>

extern "C" {
int APS5_VABI sceSslInit_nid_postfix(std::uint64_t);
int APS5_VABI sceSslTerm_nid_postfix(int);
int APS5_VABI sceSslGetMemoryPoolStats(int, SceSsl::MemoryPoolStats*);
int APS5_VABI sceSslLoadCert(int, int, SceSsl::Data**, SceSsl::Data*, SceSsl::Data*);
int APS5_VABI sceSslCreateConnection(int, int, const char*);
int APS5_VABI sceSslDeleteConnection(int);
int APS5_VABI sceSslSetVerifyCallback(int, int (APS5_VABI *)(int, unsigned int, void**, int, void*), void*);
int APS5_VABI sceSslConnect(int);
int APS5_VABI sceSslRead(int, void*, std::size_t, int);
int APS5_VABI sceSslWrite(int, void*, std::size_t, int);
int APS5_VABI sceSslClose(int);
int APS5_VABI sceSslEnableVerifyOption(int, std::uint32_t);
int APS5_VABI sceSslDisableVerifyOption(int, std::uint32_t);
int APS5_VABI sceSslSetMinSslVersion(int, int);
int APS5_VABI sceSslSetAlpn(int, const char*);
const char* APS5_VABI sceSslGetAlpnSelected(int);
void* APS5_VABI sceSslGetSubjectName(int, void*);
int APS5_VABI sceSslGetNameEntryCount(int, void*);
int APS5_VABI sceSslGetNameEntryInfo(int, void*, int, char*, std::size_t, char*, std::size_t, std::size_t*);
int APS5_VABI sceSslFreeSslCertName(int, void*);
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI connect_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI setsockopt_nid_postfix(int, int, int, const void*, std::uint32_t);
int APS5_VABI close_nid_postfix(int);
int APS5_VABI sceNetInit_nid_postfix();
int APS5_VABI sceNetSocket(const char*, int, int, int);
int APS5_VABI sceNetConnect(int, const void*, std::uint32_t);
int APS5_VABI sceNetSetsockopt(int, int, int, const void*, std::uint32_t);
int APS5_VABI sceNetSocketClose(int);
}

namespace {

constexpr int ParallelConnections = 4;
constexpr int ErrorCnCheck = static_cast<int>(0x8095f00b);
constexpr int ErrorUnknownCa = static_cast<int>(0x8095f00c);
constexpr int ErrorWantPollIn = static_cast<int>(0x8095f013);
constexpr int ErrorWantPollOut = static_cast<int>(0x8095f014);
constexpr int ErrorCallbackCheck = static_cast<int>(0x8095f0fd);
constexpr int ErrorSocketClosed = static_cast<int>(0x8095170d);
constexpr int ErrorReadTimeout = static_cast<int>(0x80951710);
constexpr std::uint32_t ServerVerify = 0x1, CnCheck = 0x4;
constexpr int VersionTls12 = 5;
constexpr int GuestSocketLevel = 0xffff;
constexpr int GuestNonBlocking = 0x1200;
constexpr int GuestReceiveTimeout = 0x1006;
constexpr int WaitRounds = 2000;
const char* ServerProtocols[] = {"http/1.1", nullptr};

enum class Serve { Close, Exchange, Drop, Reset };

struct GuestTimeval {
    std::int64_t seconds;
    std::int64_t microseconds;
};

void Require(bool condition, const char* message) {
    if (condition) return;
    std::fprintf(stderr, "%s\n", message);
    std::exit(1);
}

template <typename TCall>
bool Throws(TCall call) {
    try {
        call();
    } catch (const std::exception&) {
        return true;
    }
    return false;
}

void Settle() { std::this_thread::sleep_for(std::chrono::milliseconds(5)); }

struct CallbackRecord {
    int context;
    int result;
    int connection = 0;
    unsigned int error = 0;
    int count = 0;
    void* leaf = nullptr;
    std::string commonName;
};

int APS5_VABI RecordingCallback(int connection, unsigned int error, void** certificates, int count, void* argument) {
    auto& record = *static_cast<CallbackRecord*>(argument);
    record.connection = connection;
    record.error = error;
    record.count = count;
    if (count > 0 && certificates && certificates[0]) {
        record.leaf = certificates[0];
        void* name = sceSslGetSubjectName(record.context, record.leaf);
        Require(name != nullptr, "the peer certificate handle has no subject name");
        const int entries = sceSslGetNameEntryCount(record.context, name);
        Require(entries > 0, "the peer subject has no entries");
        char oid[16]{};
        char value[64]{};
        std::size_t valueLength = 0;
        Require(sceSslGetNameEntryInfo(record.context, name, entries - 1, oid, sizeof(oid), value, sizeof(value), &valueLength) == 0,
            "read the peer subject's last entry");
        record.commonName = std::string(oid) + "=" + value;
        Require(sceSslFreeSslCertName(record.context, name) == 0, "free the peer subject name");
    }
    return record.result;
}

struct Server {
    mbedtls_net_context listener;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_x509_crt certificate;
    mbedtls_x509_crt authority;
    mbedtls_pk_context key;
    mbedtls_ssl_config config;
    std::uint16_t port = 0;
    std::string failure;

    Server() {
        mbedtls_net_init(&listener);
        mbedtls_entropy_init(&entropy);
        mbedtls_ctr_drbg_init(&drbg);
        mbedtls_x509_crt_init(&certificate);
        mbedtls_x509_crt_init(&authority);
        mbedtls_pk_init(&key);
        mbedtls_ssl_config_init(&config);
        Require(mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy, nullptr, 0) == 0, "seed server random generator");
        Require(mbedtls_x509_crt_parse(&certificate, reinterpret_cast<const unsigned char*>(ServerPem), sizeof(ServerPem)) == 0,
            "parse server certificate");
        Require(mbedtls_x509_crt_parse(&authority, reinterpret_cast<const unsigned char*>(RootPem), sizeof(RootPem)) == 0,
            "parse client authority");
        Require(mbedtls_pk_parse_key(&key, reinterpret_cast<const unsigned char*>(ServerKey), sizeof(ServerKey), nullptr, 0,
            mbedtls_ctr_drbg_random, &drbg) == 0, "parse server key");
        Require(mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_SERVER, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT) == 0,
            "configure server");
        mbedtls_ssl_conf_rng(&config, mbedtls_ctr_drbg_random, &drbg);
        Require(mbedtls_ssl_conf_own_cert(&config, &certificate, &key) == 0, "set server certificate");
        mbedtls_ssl_conf_authmode(&config, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&config, &authority, nullptr);
        Require(mbedtls_ssl_conf_alpn_protocols(&config, ServerProtocols) == 0, "set server protocols");
        Require(mbedtls_net_bind(&listener, "127.0.0.1", "0", MBEDTLS_NET_PROTO_TCP) == 0, "bind loopback listener");
        sockaddr_in address{};
#ifdef _WIN32
        int size = sizeof(address);
#else
        socklen_t size = sizeof(address);
#endif
        Require(getsockname(listener.fd, reinterpret_cast<sockaddr*>(&address), &size) == 0, "read listener port");
        port = ntohs(address.sin_port);
    }

    ~Server() {
        mbedtls_ssl_config_free(&config);
        mbedtls_pk_free(&key);
        mbedtls_x509_crt_free(&authority);
        mbedtls_x509_crt_free(&certificate);
        mbedtls_ctr_drbg_free(&drbg);
        mbedtls_entropy_free(&entropy);
        mbedtls_net_free(&listener);
    }

    void Serve(Serve mode, bool requireClientCertificate = true) {
        mbedtls_ssl_conf_authmode(&config, requireClientCertificate ? MBEDTLS_SSL_VERIFY_REQUIRED : MBEDTLS_SSL_VERIFY_NONE);
        mbedtls_net_context client;
        mbedtls_net_init(&client);
        mbedtls_ssl_context ssl;
        mbedtls_ssl_init(&ssl);
        if (mbedtls_net_accept(&listener, &client, nullptr, 0, nullptr) != 0 || mbedtls_ssl_setup(&ssl, &config) != 0) {
            failure = "server accept or setup failed";
        } else {
            mbedtls_ssl_set_bio(&ssl, &client, mbedtls_net_send, mbedtls_net_recv, nullptr);
            const int handshake = mbedtls_ssl_handshake(&ssl);
            if (handshake != 0) failure = "server handshake failed, error " + std::to_string(handshake);
            else if (mode == Serve::Exchange) Exchange(ssl);
            else if (mode == Serve::Close) mbedtls_ssl_close_notify(&ssl);
            else if (mode == Serve::Reset) Reset(ssl, client);
        }
        mbedtls_ssl_free(&ssl);
        mbedtls_net_free(&client);
    }

    void Reset(mbedtls_ssl_context& ssl, mbedtls_net_context& client) {
        unsigned char signal = 0;
        if (mbedtls_ssl_read(&ssl, &signal, 1) != 1) {
            failure = "server did not receive the byte before the reset";
            return;
        }
        linger immediate{1, 0};
        setsockopt(client.fd, SOL_SOCKET, SO_LINGER, reinterpret_cast<const char*>(&immediate), sizeof(immediate));
#ifdef _WIN32
        closesocket(client.fd);
#else
        close(client.fd);
#endif
        client.fd = -1;
    }

    void Exchange(mbedtls_ssl_context& ssl) {
        std::array<unsigned char, 4> request{};
        std::size_t received = 0;
        while (received < request.size()) {
            const int result = mbedtls_ssl_read(&ssl, request.data() + received, request.size() - received);
            if (result <= 0) {
                failure = "server read failed, error " + std::to_string(result);
                return;
            }
            received += static_cast<std::size_t>(result);
        }
        if (std::memcmp(request.data(), "ping", 4) != 0) {
            failure = "server received the wrong request";
            return;
        }
        if (mbedtls_ssl_write(&ssl, reinterpret_cast<const unsigned char*>("pong"), 4) != 4) {
            failure = "server write failed";
            return;
        }
        if (mbedtls_ssl_close_notify(&ssl) != 0) failure = "server close notify failed";
    }
};

struct Sockets {
    bool net;

    int Open(std::uint16_t port) const {
        const int descriptor = net ? sceNetSocket("ssl", 2, 1, 6) : socket_nid_postfix(2, 1, 6);
        Require(descriptor >= 0, "create guest socket");
        std::array<std::uint8_t, 16> address{16, 2, static_cast<std::uint8_t>(port >> 8), static_cast<std::uint8_t>(port), 127, 0, 0, 1};
        Require((net ? sceNetConnect(descriptor, address.data(), 16) : connect_nid_postfix(descriptor, address.data(), 16)) == 0,
            "connect guest socket");
        return descriptor;
    }

    int Set(int descriptor, int option, const void* value, std::uint32_t length) const {
        return net ? sceNetSetsockopt(descriptor, GuestSocketLevel, option, value, length)
                   : setsockopt_nid_postfix(descriptor, GuestSocketLevel, option, value, length);
    }

    int Close(int descriptor) const { return net ? sceNetSocketClose(descriptor) : close_nid_postfix(descriptor); }
};

std::size_t InUse(int context) {
    SceSsl::MemoryPoolStats stats{};
    Require(sceSslGetMemoryPoolStats(context, &stats) == 0, "read pool statistics");
    return stats.currentInuseSize;
}

}

int main(int argc, char** argv) {
    Require(argc == 2 && (std::strcmp(argv[1], "kernel") == 0 || std::strcmp(argv[1], "net") == 0), "usage: kernel|net");
#ifndef _WIN32
    std::signal(SIGPIPE, SIG_IGN);
#endif
    const Sockets sockets{std::strcmp(argv[1], "net") == 0};
    if (sockets.net) Require(sceNetInit_nid_postfix() == 0, "initialize libSceNet");
    Server server;
    std::thread serving([&] {
        server.Serve(Serve::Close, false);
        server.Serve(Serve::Close, false);
        server.Serve(Serve::Close, false);
        server.Serve(Serve::Close);
        server.Serve(Serve::Close);
        server.Serve(Serve::Close);
        server.Serve(Serve::Exchange);
        server.Serve(Serve::Exchange);
        server.Serve(Serve::Drop);
        server.Serve(Serve::Reset);
        if (sockets.net) server.Serve(Serve::Exchange);
        for (int index = 0; index < ParallelConnections; ++index) server.Serve(Serve::Exchange);
    });

    const int empty = sceSslInit_nid_postfix(256 * 1024);
    const int untrustedSocket = sockets.Open(server.port);
    const int untrusted = sceSslCreateConnection(empty, untrustedSocket, "localhost");
    Require(sceSslConnect(untrusted) == ErrorUnknownCa, "a server certificate without a loaded CA passed the initial verify options");
    Require(sceSslConnect(untrusted) == ErrorUnknownCa, "a second connect did not repeat the verification result");
    std::array<char, 16> scratch{};
    Require(Throws([&] { sceSslRead(untrusted, scratch.data(), 1, 0); }), "a connection that failed verification was readable");
    Require(sceSslClose(untrusted) == 0, "close a connection that failed verification");
    Require(sceSslDeleteConnection(untrusted) == 0 && sockets.Close(untrustedSocket) == 0, "release the untrusted connection");

    const int unverifiedSocket = sockets.Open(server.port);
    const int unverified = sceSslCreateConnection(empty, unverifiedSocket, "localhost");
    Require(sceSslDisableVerifyOption(unverified, ServerVerify) == 0, "disable server verification");
    Require(sceSslConnect(unverified) == 0, "with server verification disabled no loaded CA is no failure");
    Require(sceSslGetAlpnSelected(unverified) == nullptr, "a protocol was selected without an ALPN list");
    Require(sceSslRead(unverified, scratch.data(), scratch.size(), 0) == 0, "close notify did not end the unverified stream");
    Require(sceSslDeleteConnection(unverified) == 0 && sockets.Close(unverifiedSocket) == 0, "release the unverified connection");

    CallbackRecord accepting{empty, 0};
    const int acceptedSocket = sockets.Open(server.port);
    const int accepted = sceSslCreateConnection(empty, acceptedSocket, "localhost");
    Require(sceSslSetVerifyCallback(accepted, RecordingCallback, &accepting) == 0, "set the accepting verify callback");
    Require(sceSslConnect(accepted) == 0, "a verify callback that returns 0 did not accept the connection");
    Require(accepting.connection == accepted && accepting.error == static_cast<unsigned int>(ErrorUnknownCa),
        "the verify callback did not receive the connection and its verification result");
    Require(accepting.count == 1 && accepting.commonName == "CN=localhost", "the verify callback did not receive the peer chain");
    Require(sceSslRead(accepted, scratch.data(), scratch.size(), 0) == 0, "an accepted connection was not readable");
    Require(sceSslDeleteConnection(accepted) == 0 && sockets.Close(acceptedSocket) == 0, "release the accepted connection");
    Require(Throws([&] { sceSslGetSubjectName(empty, accepting.leaf); }), "a peer certificate handle outlived its connection");
    Require(sceSslTerm_nid_postfix(empty) == 0, "release the context without CA");

    const int context = sceSslInit_nid_postfix(1024 * 1024);
    std::string root = RootPem;
    SceSsl::Data authority{reinterpret_cast<std::uint8_t*>(root.data()), root.size()};
    auto* authorities = &authority;
    std::string clientCertificate = ClientPem, clientKey = ClientKey;
    SceSsl::Data certificate{reinterpret_cast<std::uint8_t*>(clientCertificate.data()), clientCertificate.size()};
    SceSsl::Data key{reinterpret_cast<std::uint8_t*>(clientKey.data()), clientKey.size()};
    Require(sceSslLoadCert(context, 1, &authorities, &certificate, &key) == 0, "load the fixture root and client certificate");
    const auto loaded = InUse(context);

    const int closed = sceSslCreateConnection(context, 1000, "localhost");
    Require(Throws([&] { sceSslConnect(closed); }), "a handshake over a closed descriptor was attempted");
    Require(sceSslClose(closed) == 0, "close a connection that never connected");
    Require(sceSslDeleteConnection(closed) == 0, "delete connection over a closed descriptor");

    const int mismatchSocket = sockets.Open(server.port);
    const int mismatch = sceSslCreateConnection(context, mismatchSocket, "example.com");
    Require(sceSslConnect(mismatch) == ErrorCnCheck, "a certificate for another host passed the host name check");
    Require(sceSslConnect(mismatch) == ErrorCnCheck, "a second connect did not repeat the host name result");
    Require(Throws([&] { sceSslRead(mismatch, root.data(), 1, 0); }), "a failed verification left the connection usable");
    Require(sceSslDeleteConnection(mismatch) == 0 && sockets.Close(mismatchSocket) == 0, "release the mismatched connection");

    const int lenientSocket = sockets.Open(server.port);
    const int lenient = sceSslCreateConnection(context, lenientSocket, "example.com");
    Require(sceSslDisableVerifyOption(lenient, CnCheck) == 0, "disable the host name check");
    Require(sceSslConnect(lenient) == 0, "a disabled host name check still failed the handshake");
    Require(sceSslDeleteConnection(lenient) == 0 && sockets.Close(lenientSocket) == 0, "release the lenient connection");

    CallbackRecord rejecting{context, -1};
    const int rejectedSocket = sockets.Open(server.port);
    const int rejected = sceSslCreateConnection(context, rejectedSocket, "localhost");
    Require(sceSslSetVerifyCallback(rejected, RecordingCallback, &rejecting) == 0, "set the rejecting verify callback");
    Require(sceSslConnect(rejected) == ErrorCallbackCheck, "a negative verify callback result did not fail the connect");
    Require(rejecting.error == 0 && rejecting.count == 1, "the verify callback did not see a passed chain");
    Require(sceSslConnect(rejected) == ErrorCallbackCheck, "a second connect did not repeat the callback result");
    Require(Throws([&] { sceSslRead(rejected, scratch.data(), 1, 0); }), "a rejected connection was readable");
    Require(sceSslDeleteConnection(rejected) == 0 && sockets.Close(rejectedSocket) == 0, "release the rejected connection");

    const int descriptor = sockets.Open(server.port);
    const int connection = sceSslCreateConnection(context, descriptor, "localhost");
    std::array<char, 16> buffer{};
    Require(sceSslSetMinSslVersion(connection, VersionTls12) == 0 && sceSslSetAlpn(connection, "h2,http/1.1") == 0, "set version and ALPN");
    Require(sceSslGetAlpnSelected(connection) == nullptr, "a protocol was selected before the handshake");
    Require(Throws([&] { sceSslRead(connection, buffer.data(), buffer.size(), 0); }), "read before the handshake");
    Require(Throws([&] { sceSslWrite(connection, buffer.data(), buffer.size(), 0); }), "write before the handshake");
    Require(sceSslConnect(connection) == 0, "handshake with the loopback server");
    Require(InUse(context) > loaded, "the connection is not charged to the context pool");
    Require(sceSslConnect(connection) == 0, "a second connect after success did not return the same result");
    const char* selected = sceSslGetAlpnSelected(connection);
    Require(selected && std::strcmp(selected, "http/1.1") == 0, "the negotiated ALPN protocol is not reported");
    Require(Throws([&] { sceSslWrite(connection, buffer.data(), 1, 1); }), "unknown write flags were accepted");
    Require(Throws([&] { sceSslRead(connection, buffer.data(), 1, 3); }), "peek was accepted");
    char request[] = "ping";
    Require(sceSslWrite(connection, request, 4, 0) == 4, "write the request");
    Require(sceSslRead(connection, buffer.data(), buffer.size(), 0) == 4 && std::memcmp(buffer.data(), "pong", 4) == 0, "read the reply");
    Require(sceSslRead(connection, buffer.data(), buffer.size(), 1) == 0, "close notify did not end the stream");
    Require(sceSslClose(connection) == 0, "close the connection");
    Require(Throws([&] { sceSslRead(connection, buffer.data(), buffer.size(), 0); }), "a closed connection was readable");
    Require(Throws([&] { sceSslConnect(connection); }), "a closed connection reconnected");
    Require(sceSslClose(connection) == 0, "a second close failed");
    Require(sceSslDeleteConnection(connection) == 0, "delete the connection");
    Require(InUse(context) == loaded, "the connection's pool memory was not returned");
    Require(sockets.Close(descriptor) == 0, "the socket did not stay open after the connection was deleted");

    const int pollingSocket = sockets.Open(server.port);
    const int enabled = 1;
    Require(sockets.Set(pollingSocket, GuestNonBlocking, &enabled, sizeof(enabled)) == 0, "make the guest socket non-blocking");
    const int polling = sceSslCreateConnection(context, pollingSocket, "localhost");
    int rounds = 0;
    for (int result; (result = sceSslConnect(polling)) != 0; Settle()) {
        Require(result == ErrorWantPollIn || result == ErrorWantPollOut, "a non-blocking handshake failed instead of asking to poll");
        Require(++rounds < WaitRounds, "a non-blocking handshake did not finish");
    }
    Require(sceSslRead(polling, buffer.data(), buffer.size(), 0) == ErrorWantPollIn, "a non-blocking read with nothing to read did not ask to poll");
    Require(sceSslWrite(polling, request, 4, 0) == 4, "write the non-blocking request");
    int received;
    for (rounds = 0; (received = sceSslRead(polling, buffer.data(), buffer.size(), 0)) == ErrorWantPollIn; Settle())
        Require(++rounds < WaitRounds, "the non-blocking reply did not arrive");
    Require(received == 4 && std::memcmp(buffer.data(), "pong", 4) == 0, "read the non-blocking reply");
    for (rounds = 0; (received = sceSslRead(polling, buffer.data(), buffer.size(), 0)) == ErrorWantPollIn; Settle())
        Require(++rounds < WaitRounds, "the non-blocking close notify did not arrive");
    Require(received == 0, "close notify did not end the non-blocking stream");
    Require(sceSslClose(polling) == 0 && sceSslDeleteConnection(polling) == 0 && sockets.Close(pollingSocket) == 0,
        "release the non-blocking connection");

    const int droppedSocket = sockets.Open(server.port);
    const int dropped = sceSslCreateConnection(context, droppedSocket, "localhost");
    Require(sceSslConnect(dropped) == 0, "handshake before the server drops the connection");
    Require(sceSslRead(dropped, buffer.data(), buffer.size(), 0) == 0, "a stream that ended without close notify did not end the read");
    Require(sceSslDeleteConnection(dropped) == 0 && sockets.Close(droppedSocket) == 0, "release the dropped connection");

    const int resetSocket = sockets.Open(server.port);
    const int reset = sceSslCreateConnection(context, resetSocket, "localhost");
    Require(sceSslConnect(reset) == 0, "handshake before the server resets the connection");
    Require(sceSslWrite(reset, request, 1, 0) == 1, "write the byte the server resets after");
    Require(sceSslRead(reset, buffer.data(), buffer.size(), 0) == ErrorSocketClosed, "a reset did not report the closed socket");
    Require(sceSslDeleteConnection(reset) == 0 && sockets.Close(resetSocket) == 0, "release the reset connection");

    if (sockets.net) {
        const int timedSocket = sockets.Open(server.port);
        const GuestTimeval timeout{0, 200000};
        Require(sockets.Set(timedSocket, GuestReceiveTimeout, &timeout, sizeof(timeout)) == 0, "set the receive timeout");
        const int timed = sceSslCreateConnection(context, timedSocket, "localhost");
        Require(sceSslConnect(timed) == 0, "handshake over the socket with a receive timeout");
        Require(sceSslRead(timed, buffer.data(), buffer.size(), 0) == ErrorReadTimeout, "an expired receive timeout did not report the timeout");
        Require(sceSslWrite(timed, request, 4, 0) == 4, "write the request after a timeout");
        Require(sceSslRead(timed, buffer.data(), buffer.size(), 0) == 4 && std::memcmp(buffer.data(), "pong", 4) == 0, "read the reply after a timeout");
        Require(sceSslRead(timed, buffer.data(), buffer.size(), 0) == 0, "close notify did not end the timed stream");
        Require(sceSslDeleteConnection(timed) == 0 && sockets.Close(timedSocket) == 0, "release the timed connection");
    }

    std::array<std::thread, ParallelConnections> clients;
    for (auto& client : clients) {
        client = std::thread([&] {
            const int parallelSocket = sockets.Open(server.port);
            const int parallel = sceSslCreateConnection(context, parallelSocket, "localhost");
            std::array<char, 16> reply{};
            char ping[] = "ping";
            Require(sceSslConnect(parallel) == 0 && sceSslWrite(parallel, ping, 4, 0) == 4, "parallel handshake or write");
            Require(sceSslRead(parallel, reply.data(), reply.size(), 0) == 4 && std::memcmp(reply.data(), "pong", 4) == 0, "parallel reply");
            Require(sceSslRead(parallel, reply.data(), reply.size(), 0) == 0, "parallel end of stream");
            Require(sceSslClose(parallel) == 0 && sceSslDeleteConnection(parallel) == 0 && sockets.Close(parallelSocket) == 0,
                "release parallel connection");
        });
    }
    for (auto& client : clients) client.join();
    Require(InUse(context) == loaded, "parallel connections did not return their pool memory");

    serving.join();
    Require(server.failure.empty(), server.failure.c_str());
    Require(sceSslTerm_nid_postfix(context) == 0, "terminate the context");
}
