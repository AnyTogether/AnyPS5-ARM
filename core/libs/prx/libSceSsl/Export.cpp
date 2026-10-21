#ifdef _WIN32
#include <winsock2.h>
#else
#include <sys/socket.h>
#include <cerrno>
#endif

#include "SslTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libkernel/Socket/include/SocketPoll.hpp"

#include <mbedtls/asn1.h>
#include <mbedtls/base64.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#include <mbedtls/error.h>
#include <mbedtls/md.h>
#include <mbedtls/net_sockets.h>
#include <mbedtls/oid.h>
#include <mbedtls/pem.h>
#include <mbedtls/pk.h>
#include <mbedtls/platform.h>
#include <mbedtls/platform_util.h>
#include <mbedtls/ssl.h>
#include <mbedtls/x509_crt.h>

#include <algorithm>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr int ErrorNotFound = static_cast<int>(0x8095f004);
constexpr int ErrorInvalidArg = static_cast<int>(0x8095177a);
constexpr int ErrorInvalidId = static_cast<int>(0x8095f006);
constexpr int ErrorInvalidCert = static_cast<int>(0x8095f00a);
constexpr int ErrorCnCheck = static_cast<int>(0x8095f00b);
constexpr int ErrorUnknownCa = static_cast<int>(0x8095f00c);
constexpr int ErrorNotAfterCheck = static_cast<int>(0x8095f00d);
constexpr int ErrorNotBeforeCheck = static_cast<int>(0x8095f00e);
constexpr int ErrorFatalAlert = static_cast<int>(0x8095f010);
constexpr int ErrorWantPollIn = static_cast<int>(0x8095f013);
constexpr int ErrorWantPollOut = static_cast<int>(0x8095f014);
constexpr int ErrorSocketClosed = static_cast<int>(0x8095170d);
constexpr int ErrorCallbackCheck = static_cast<int>(0x8095f0fd);
constexpr int ErrorInvalidValue = static_cast<int>(0x8095f007);
constexpr int ErrorBadLength = static_cast<int>(0x80951773);
constexpr int ErrorBadRecord = static_cast<int>(0x80951d55);
constexpr int ErrorNetBadDescriptor = static_cast<int>(0x80410109);
constexpr int ErrorNetPipe = static_cast<int>(0x80410120);
constexpr int ErrorNetReset = static_cast<int>(0x80410136);
constexpr int ErrorKernelInvalid = static_cast<int>(0x80020016);
constexpr std::uint32_t FlagServerVerify = 0x1;
constexpr std::uint32_t FlagCnCheck = 0x4;
constexpr std::uint32_t FlagNotAfterCheck = 0x8;
constexpr std::uint32_t FlagNotBeforeCheck = 0x10;
constexpr std::uint32_t FlagKnownCaCheck = 0x20;
constexpr std::uint32_t VerifyOptionMask = 0x3f;
constexpr std::uint32_t InitialVerifyOptions = FlagServerVerify | FlagCnCheck | FlagKnownCaCheck;

constexpr std::int64_t TicksPerSecond = 1000000;
constexpr std::int64_t TicksPerMinute = 60 * TicksPerSecond;
constexpr std::int64_t TicksPerHour = 60 * TicksPerMinute;
constexpr std::int64_t TicksPerDay = 24 * TicksPerHour;
constexpr std::int64_t UnixEpochDays = 719162;

std::int64_t DaysFromCivil(std::int64_t year, unsigned month, unsigned day) {
    year -= month <= 2;
    const std::int64_t era = (year >= 0 ? year : year - 399) / 400;
    const auto yearOfEra = static_cast<unsigned>(year - era * 400);
    const unsigned dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1;
    const unsigned dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
    return era * 146097 + static_cast<std::int64_t>(dayOfEra) - 719468 + UnixEpochDays;
}

std::uint64_t TimeToTick(const mbedtls_x509_time& time) {
    return static_cast<std::uint64_t>(DaysFromCivil(time.year, time.mon, time.day)) * TicksPerDay
        + time.hour * TicksPerHour + time.min * TicksPerMinute + time.sec * TicksPerSecond;
}

struct Pool {
    std::size_t size, current = 0, peak = 0;
    std::mutex mutex;
};

struct alignas(std::max_align_t) Allocation {
    Pool* pool;
    std::size_t size;
};

thread_local Pool* currentPool = nullptr;
thread_local bool currentPoolExhausted = false;

void* PoolCalloc(std::size_t count, std::size_t size) noexcept {
    if (!currentPool) return nullptr;
    if (size && count > std::numeric_limits<std::size_t>::max() / size) {
        currentPoolExhausted = true;
        return nullptr;
    }
    const auto bytes = count * size;
    std::lock_guard lock(currentPool->mutex);
    if (bytes > currentPool->size - currentPool->current || bytes > std::numeric_limits<std::size_t>::max() - sizeof(Allocation)) {
        currentPoolExhausted = true;
        return nullptr;
    }
    auto* allocation = static_cast<Allocation*>(std::calloc(1, sizeof(Allocation) + bytes));
    if (!allocation) {
        currentPoolExhausted = true;
        return nullptr;
    }
    allocation->pool = currentPool;
    allocation->size = bytes;
    currentPool->current += bytes;
    currentPool->peak = std::max(currentPool->peak, currentPool->current);
    return allocation + 1;
}

void PoolFree(void* pointer) noexcept {
    if (!pointer) return;
    auto* allocation = static_cast<Allocation*>(pointer) - 1;
    {
        std::lock_guard lock(allocation->pool->mutex);
        allocation->pool->current -= allocation->size;
    }
    mbedtls_platform_zeroize(pointer, allocation->size);
    std::free(allocation);
}

struct PoolScope {
    Pool* previous;
    bool previousExhausted;
    explicit PoolScope(Pool& pool)
        : previous(std::exchange(currentPool, &pool)), previousExhausted(std::exchange(currentPoolExhausted, false)) {}
    ~PoolScope() {
        currentPool = previous;
        currentPoolExhausted = previousExhausted;
    }
};

struct PoolDeleter {
    void operator()(std::uint8_t* bytes) const { PoolFree(bytes); }
};

using Block = std::unique_ptr<std::uint8_t, PoolDeleter>;

Block Allocate(std::size_t size) {
    Block block(static_cast<std::uint8_t*>(PoolCalloc(1, std::max<std::size_t>(1, size))));
    if (!block) throw std::bad_alloc();
    return block;
}

std::size_t Add(std::size_t left, std::size_t right) {
    if (right > std::numeric_limits<std::size_t>::max() - left) throw std::length_error("SSL allocation size overflow");
    return left + right;
}

void CheckBackend(int error, const char* message) {
    if (error == 0) return;
    if (currentPool && currentPoolExhausted) throw std::bad_alloc();
    throw std::invalid_argument(message);
}

struct CertificateChain;

struct CertificateHandle {
    std::weak_ptr<CertificateChain> owner;
    const mbedtls_x509_crt* certificate;
};

struct CertificateChain {
    mbedtls_x509_crt root;
    std::vector<CertificateHandle*> handles;
    CertificateChain() { mbedtls_x509_crt_init(&root); }
    ~CertificateChain() { mbedtls_x509_crt_free(&root); }
};

struct PrivateKey {
    mbedtls_pk_context key;
    PrivateKey() { mbedtls_pk_init(&key); }
    ~PrivateKey() { mbedtls_pk_free(&key); }
};

struct Random {
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    Random() {
        mbedtls_entropy_init(&entropy);
        mbedtls_ctr_drbg_init(&drbg);
    }
    ~Random() {
        mbedtls_ctr_drbg_free(&drbg);
        mbedtls_entropy_free(&entropy);
    }
    void Seed() {
        CheckBackend(mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy, nullptr, 0), "SSL random generator initialization failed");
    }
};

struct Identity {
    std::shared_ptr<CertificateChain> chain;
    PrivateKey key;
};

struct Snapshot {
    Block data;
    std::vector<std::shared_ptr<CertificateChain>> certificates;
    std::size_t count;
};

struct CertNameEntry {
    std::string oid;
    std::string value;
};

struct CertName {
    std::vector<CertNameEntry> entries;
};

struct Context {
    Pool pool;
    std::vector<std::shared_ptr<CertificateChain>> authorities;
    std::shared_ptr<Identity> identity;
    std::vector<std::unique_ptr<CertificateHandle>> certificateHandles;
    std::unordered_map<void*, Snapshot> caLists;
    std::unordered_map<void*, Snapshot> caCerts;
    std::unordered_map<void*, std::unique_ptr<CertName>> certNames;
    explicit Context(std::size_t size) : pool{size, 0, 0, {}} {}
};

int HostError() {
#ifdef _WIN32
    return WSAGetLastError();
#else
    return errno;
#endif
}

bool HostWouldBlock(int error) {
#ifdef _WIN32
    return error == WSAEWOULDBLOCK;
#else
    return error == EAGAIN || error == EWOULDBLOCK;
#endif
}

bool HostInterrupted(int error) {
#ifdef _WIN32
    return error == WSAEINTR;
#else
    return error == EINTR;
#endif
}

bool HostReset(int error) {
#ifdef _WIN32
    return error == WSAECONNRESET || error == WSAECONNABORTED || error == WSAENETRESET;
#else
    return error == ECONNRESET || error == EPIPE;
#endif
}

bool HostTimedOut(int error) {
#ifdef _WIN32
    return error == WSAETIMEDOUT;
#else
    (void)error;
    return false;
#endif
}

enum class Operation { Connect, Read, Write, Close };

struct Session {
    int contextHandle;
    std::shared_ptr<Context> context;
    std::shared_ptr<Identity> identity;
    std::shared_ptr<CertificateChain> peer;
    std::vector<void*> peerHandles;
    std::shared_ptr<void> socketOwner;
    std::uintptr_t socket;
    std::mutex mutex;
    int hostError = 0;
    std::uint32_t verifyOptions = 0;
    std::vector<std::string> alpnStrings;
    std::vector<const char*> alpnList;
    std::string alpnSelected;
    bool handshaken = false;
    bool verifying = false;
    bool verified = false;
    bool closed = false;
    bool reset = false;
    bool gone = false;
    int verifyResult = 0;
    unsigned int failedOptions = 0;
    Random random;
    mbedtls_x509_crt authorities;
    mbedtls_ssl_config config;
    mbedtls_ssl_context ssl;

    Session(int handle, std::shared_ptr<Context> owner, std::shared_ptr<void> socketHolder, std::uintptr_t native)
        : contextHandle(handle), context(std::move(owner)), identity(context->identity), socketOwner(std::move(socketHolder)), socket(native) {
        mbedtls_x509_crt_init(&authorities);
        mbedtls_ssl_config_init(&config);
        mbedtls_ssl_init(&ssl);
    }

    ~Session() {
        PoolScope scope(context->pool);
        mbedtls_ssl_free(&ssl);
        mbedtls_ssl_config_free(&config);
        mbedtls_x509_crt_free(&authorities);
    }

    void Configure(const std::string& host, const std::string& alpn, std::uint32_t options) {
        verifyOptions = options;
        random.Seed();
        for (const auto& chain : context->authorities)
            for (const auto* entry = &chain->root; entry; entry = entry->next)
                CheckBackend(mbedtls_x509_crt_parse_der(&authorities, entry->raw.p, entry->raw.len), "SSL CA certificate copy failed");
        CheckBackend(mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT),
            "SSL client configuration failed");
        mbedtls_ssl_conf_authmode(&config, MBEDTLS_SSL_VERIFY_OPTIONAL);
        mbedtls_ssl_conf_min_tls_version(&config, MBEDTLS_SSL_VERSION_TLS1_2);
        mbedtls_ssl_conf_ca_chain(&config, &authorities, nullptr);
        mbedtls_ssl_conf_rng(&config, mbedtls_ctr_drbg_random, &random.drbg);
        if (identity)
            CheckBackend(mbedtls_ssl_conf_own_cert(&config, &identity->chain->root, &identity->key.key), "SSL client certificate setup failed");
        for (std::size_t start = 0; start <= alpn.size();) {
            const auto end = alpn.find(',', start);
            const auto protocol = alpn.substr(start, end == std::string::npos ? std::string::npos : end - start);
            if (!protocol.empty()) alpnStrings.push_back(protocol);
            if (end == std::string::npos) break;
            start = end + 1;
        }
        if (!alpnStrings.empty()) {
            for (const auto& protocol : alpnStrings) alpnList.push_back(protocol.c_str());
            alpnList.push_back(nullptr);
            CheckBackend(mbedtls_ssl_conf_alpn_protocols(&config, alpnList.data()), "SSL ALPN list rejected");
        }
        CheckBackend(mbedtls_ssl_setup(&ssl, &config), "SSL connection setup failed");
        CheckBackend(mbedtls_ssl_set_hostname(&ssl, host.c_str()), "SSL host name setup failed");
        mbedtls_ssl_set_bio(&ssl, this, Send, Receive, nullptr);
    }

    static int Send(void* argument, const unsigned char* buffer, std::size_t length) {
        auto& session = *static_cast<Session*>(argument);
        const auto chunk = static_cast<int>(std::min<std::size_t>(length, INT_MAX));
        for (;;) {
#ifdef _WIN32
            auto* owner = static_cast<KernelSocketPoll::NativeOwner*>(session.socketOwner.get());
            const auto sent = owner && owner->transfer
                ? owner->transfer(owner, true, const_cast<unsigned char*>(buffer), chunk)
                : ::send(static_cast<SOCKET>(session.socket), reinterpret_cast<const char*>(buffer), chunk, 0);
#else
            const auto sent = ::send(static_cast<int>(session.socket), buffer, static_cast<std::size_t>(chunk), MSG_NOSIGNAL);
#endif
            if (sent >= 0) return static_cast<int>(sent);
            const int error = HostError();
            if (HostInterrupted(error)) continue;
            if (HostWouldBlock(error) || HostTimedOut(error)) return MBEDTLS_ERR_SSL_WANT_WRITE;
            if (HostReset(error)) return MBEDTLS_ERR_NET_CONN_RESET;
            session.hostError = error;
            return MBEDTLS_ERR_NET_SEND_FAILED;
        }
    }

    static int Receive(void* argument, unsigned char* buffer, std::size_t length) {
        auto& session = *static_cast<Session*>(argument);
        const auto chunk = static_cast<int>(std::min<std::size_t>(length, INT_MAX));
        for (;;) {
#ifdef _WIN32
            auto* owner = static_cast<KernelSocketPoll::NativeOwner*>(session.socketOwner.get());
            const auto received = owner && owner->transfer
                ? owner->transfer(owner, false, buffer, chunk)
                : ::recv(static_cast<SOCKET>(session.socket), reinterpret_cast<char*>(buffer), chunk, 0);
#else
            const auto received = ::recv(static_cast<int>(session.socket), buffer, static_cast<std::size_t>(chunk), 0);
#endif
            if (received >= 0) return static_cast<int>(received);
            const int error = HostError();
            if (HostInterrupted(error)) continue;
            if (HostWouldBlock(error) || HostTimedOut(error)) return MBEDTLS_ERR_SSL_WANT_READ;
            if (HostReset(error)) return MBEDTLS_ERR_NET_CONN_RESET;
            session.hostError = error;
            return MBEDTLS_ERR_NET_RECV_FAILED;
        }
    }

    void Verify() {
        const auto flags = mbedtls_ssl_get_verify_result(&ssl);
        failedOptions = 0;
        verifyResult = 0;
        if (!(verifyOptions & FlagServerVerify)) return;
        if ((verifyOptions & FlagKnownCaCheck) && (flags & MBEDTLS_X509_BADCERT_NOT_TRUSTED)) failedOptions |= FlagKnownCaCheck;
        if ((verifyOptions & FlagCnCheck) && (flags & MBEDTLS_X509_BADCERT_CN_MISMATCH)) failedOptions |= FlagCnCheck;
        if ((verifyOptions & FlagNotAfterCheck) && (flags & MBEDTLS_X509_BADCERT_EXPIRED)) failedOptions |= FlagNotAfterCheck;
        if ((verifyOptions & FlagNotBeforeCheck) && (flags & MBEDTLS_X509_BADCERT_FUTURE)) failedOptions |= FlagNotBeforeCheck;
        constexpr std::uint32_t optional =
            MBEDTLS_X509_BADCERT_NOT_TRUSTED | MBEDTLS_X509_BADCERT_CN_MISMATCH | MBEDTLS_X509_BADCERT_EXPIRED | MBEDTLS_X509_BADCERT_FUTURE;
        if (failedOptions & FlagKnownCaCheck) verifyResult = ErrorUnknownCa;
        else if (failedOptions & FlagCnCheck) verifyResult = ErrorCnCheck;
        else if (failedOptions & FlagNotAfterCheck) verifyResult = ErrorNotAfterCheck;
        else if (failedOptions & FlagNotBeforeCheck) verifyResult = ErrorNotBeforeCheck;
        else if (flags & ~optional) verifyResult = ErrorInvalidCert;
    }

    int Code(int result, Operation operation) {
        switch (result) {
            case MBEDTLS_ERR_SSL_WANT_READ: return ErrorWantPollIn;
            case MBEDTLS_ERR_SSL_WANT_WRITE: return ErrorWantPollOut;
            case MBEDTLS_ERR_NET_CONN_RESET:
                reset = true;
                if (operation == Operation::Write) return ErrorNetPipe;
                if (operation == Operation::Connect) return ErrorSocketClosed;
                return ErrorNetReset;
            case MBEDTLS_ERR_SSL_CONN_EOF: return operation == Operation::Connect ? ErrorSocketClosed : 0;
            case MBEDTLS_ERR_SSL_FATAL_ALERT_MESSAGE: return ErrorFatalAlert;
            case MBEDTLS_ERR_SSL_INVALID_MAC: return operation == Operation::Read ? ErrorBadRecord : 0;
            default: return 0;
        }
    }

    [[noreturn]] void Fail(const char* function, int error) const {
        if (currentPoolExhausted || error == MBEDTLS_ERR_SSL_ALLOC_FAILED) throw std::bad_alloc();
        char text[160];
        mbedtls_strerror(error, text, sizeof(text));
        auto message = std::string(function) + ": " + text;
        if (hostError) message += ", host socket error " + std::to_string(hostError);
        if (error == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED) {
            char detail[512];
            if (mbedtls_x509_crt_verify_info(detail, sizeof(detail), "", mbedtls_ssl_get_verify_result(&ssl)) > 0) message += ", " + std::string(detail);
        }
        throw std::runtime_error(message + "; the console's error code is unknown");
    }
};

using SslVerifyCallback = int (APS5_VABI *)(int, unsigned int, void**, int, void*);

constexpr int SslVersionSsl30 = 2;
constexpr int SslVersionTls12 = 5;

struct SslConnection {
    int context;
    int socket;
    std::string host;
    SslVerifyCallback verifyCallback;
    void* verifyArgument;
    std::uint32_t verifyOptions = InitialVerifyOptions;
    int minimumVersion = SslVersionTls12;
    std::string alpn;
    std::shared_ptr<Session> session;
};

struct Runtime {
    std::mutex mutex;
    std::unordered_map<int, std::shared_ptr<Context>> contexts;
    std::unordered_map<int, SslConnection> connections;
    unsigned nextHandle = 1;
    Runtime() {
        if (mbedtls_platform_set_calloc_free(PoolCalloc, PoolFree) != 0)
            throw std::runtime_error("SSL allocator initialization failed");
    }
};

Runtime& State() {
    static auto* runtime = new Runtime;
    return *runtime;
}

Context& GetContext(int handle) {
    const auto found = State().contexts.find(handle);
    if (found == State().contexts.end()) throw std::invalid_argument("Invalid SSL context");
    return *found->second;
}

SslConnection* FindConnection(int sslConnectionId) {
    const auto connection = State().connections.find(sslConnectionId);
    if (connection == State().connections.end()) return nullptr;
    if (!State().contexts.contains(connection->second.context)) return nullptr;
    return &connection->second;
}

SslConnection& RequireConnection(const char* function, int sslConnectionId) {
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) throw std::invalid_argument(std::string(function) + ": unknown connection");
    return *connection;
}

void RequireUsable(const char* function, const Session& session) {
    if (session.verifyResult != 0 && session.verifyResult != ErrorCallbackCheck)
        throw std::logic_error(std::string(function) + ": the connection failed verification; the console's behaviour is unknown");
}

void RegisterPeer(Session& session) {
    const auto* certificate = mbedtls_ssl_get_peer_cert(&session.ssl);
    if (!certificate || session.peer) return;
    auto chain = std::make_shared<CertificateChain>();
    for (const auto* entry = certificate; entry && entry->raw.p; entry = entry->next)
        CheckBackend(mbedtls_x509_crt_parse_der(&chain->root, entry->raw.p, entry->raw.len), "SSL peer certificate copy failed");
    std::lock_guard lock(State().mutex);
    for (const auto* entry = &chain->root; entry && entry->raw.p; entry = entry->next) {
        auto handle = std::make_unique<CertificateHandle>(CertificateHandle{chain, entry});
        session.peerHandles.push_back(handle.get());
        chain->handles.push_back(handle.get());
        session.context->certificateHandles.push_back(std::move(handle));
    }
    session.peer = std::move(chain);
}

struct Input {
    Block bytes;
    std::size_t size;
};

Input CopyInput(const SceSsl::Data& data) {
    if (!data.ptr || !data.size) throw std::invalid_argument("Empty SSL certificate/key data");
    auto bytes = Allocate(Add(data.size, 1));
    std::memcpy(bytes.get(), data.ptr, data.size);
    auto size = data.size;
    std::size_t first = 0;
    while (first < size && (bytes.get()[first] == ' ' || bytes.get()[first] == '\r' || bytes.get()[first] == '\n' || bytes.get()[first] == '\t')) ++first;
    const bool pem = first < size && bytes.get()[first] == '-';
    if (pem) {
        if (bytes.get()[size - 1] != 0) ++size;
        if (std::memchr(bytes.get(), 0, size - 1)) throw std::invalid_argument("Embedded null in SSL PEM data");
    } else {
        auto* position = bytes.get();
        std::size_t length = 0;
        CheckBackend(mbedtls_asn1_get_tag(&position, bytes.get() + size, &length, MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE),
            "Invalid SSL DER sequence");
        if (length != static_cast<std::size_t>(bytes.get() + size - position)) throw std::invalid_argument("Trailing SSL DER data");
    }
    return {std::move(bytes), size};
}

std::shared_ptr<CertificateChain> ParseCertificate(const SceSsl::Data& data) {
    auto chain = std::make_shared<CertificateChain>();
    const auto input = CopyInput(data);
    CheckBackend(mbedtls_x509_crt_parse(&chain->root, input.bytes.get(), input.size), "Invalid SSL certificate chain");
    return chain;
}

std::size_t CertificateCount(const Context& context) {
    std::size_t count = 0;
    for (const auto& chain : context.authorities) count = Add(count, chain->handles.size());
    return count;
}

const mbedtls_x509_crt* RequireCertificate(const char* function, int sslCtxId, void* cert) {
    if (!cert) throw std::invalid_argument(std::string(function) + ": null certificate");
    auto& context = GetContext(sslCtxId);
    for (const auto& handle : context.certificateHandles) {
        if (handle.get() == cert) {
            if (handle->owner.expired() || !handle->certificate) {
                throw std::invalid_argument(std::string(function) + ": expired certificate");
            }
            return handle->certificate;
        }
    }
    throw std::invalid_argument(std::string(function) + ": unknown certificate");
}

const char* LongAttributeName(const char* shortName) {
    static constexpr std::pair<const char*, const char*> names[] = {
        {"CN", "commonName"}, {"C", "countryName"}, {"L", "localityName"}, {"ST", "stateOrProvinceName"},
        {"O", "organizationName"}, {"OU", "organizationalUnitName"}, {"SN", "surname"}, {"GN", "givenName"},
        {"DC", "domainComponent"}, {"uid", "userId"},
    };
    for (const auto& [name, longName] : names)
        if (std::strcmp(shortName, name) == 0) return longName;
    return shortName;
}

void* ExtractCertName(const char* function, int sslCtxId, void* sslCert, bool subject) {
    std::lock_guard lock(State().mutex);
    auto& context = GetContext(sslCtxId);
    const auto* crt = RequireCertificate(function, sslCtxId, sslCert);
    const auto* name = subject ? &crt->subject : &crt->issuer;
    auto certName = std::make_unique<CertName>();
    for (const auto* node = name; node; node = node->next) {
        if (!node->oid.p || node->oid.len == 0) continue;
        std::string oid;
        const char* shortName = nullptr;
        if (mbedtls_oid_get_attr_short_name(&node->oid, &shortName) == 0 && shortName) {
            oid = LongAttributeName(shortName);
        } else {
            char numeric[64] = {};
            if (mbedtls_oid_get_numeric_string(numeric, sizeof(numeric), &node->oid) > 0) {
                oid = numeric;
            }
        }
        std::string value;
        if (node->val.p && node->val.len > 0) {
            value.assign(reinterpret_cast<const char*>(node->val.p), node->val.len);
        }
        certName->entries.push_back({std::move(oid), std::move(value)});
    }
    auto* handle = certName.get();
    context.certNames.emplace(handle, std::move(certName));
    return handle;
}

}

extern "C" {

int APS5_VABI sceSslInit_nid_postfix(std::uint64_t poolSize) {
    if (poolSize == 0) return ErrorKernelInvalid;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    if (state.nextHandle > static_cast<unsigned>(std::numeric_limits<int>::max())) throw std::overflow_error("SSL context handles exhausted");
    const auto handle = static_cast<int>(state.nextHandle);
    state.contexts.emplace(handle, std::make_shared<Context>(poolSize));
    ++state.nextHandle;
    return handle;
}

int APS5_VABI sceSslTerm_nid_postfix(int sslCtxId) {
    auto& state = State();
    std::lock_guard lock(state.mutex);
    if (!state.contexts.erase(sslCtxId)) return ErrorInvalidId;
    return 0;
}

int APS5_VABI sceSslGetMemoryPoolStats(int sslCtxId, SceSsl::MemoryPoolStats* stats) {
    if (!stats) return ErrorInvalidValue;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    const auto found = state.contexts.find(sslCtxId);
    if (found == state.contexts.end()) {
        std::memset(stats, 0, sizeof(*stats));
        return ErrorInvalidId;
    }
    auto& pool = found->second->pool;
    std::lock_guard poolLock(pool.mutex);
    *stats = {pool.size, pool.peak, pool.current, 0};
    return 0;
}

int APS5_VABI sceSslLoadCert(int sslCtxId, int caCertNum, SceSsl::Data** caList, SceSsl::Data* cert, SceSsl::Data* privateKey) {
    if (caCertNum < 0 || (caCertNum && !caList) || (!!cert != !!privateKey))
        throw std::invalid_argument("Invalid SSL certificate load arguments");
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    PoolScope scope(context.pool);
    std::vector<std::shared_ptr<CertificateChain>> authorities;
    std::vector<std::unique_ptr<CertificateHandle>> handles;
    for (int index = 0; index < caCertNum; ++index) {
        if (!caList[index]) throw std::invalid_argument("Missing SSL certificate descriptor");
        auto chain = ParseCertificate(*caList[index]);
        for (auto* entry = &chain->root; entry; entry = entry->next) {
            auto handle = std::make_unique<CertificateHandle>(CertificateHandle{chain, entry});
            chain->handles.push_back(handle.get());
            handles.push_back(std::move(handle));
        }
        authorities.push_back(std::move(chain));
    }
    std::shared_ptr<Identity> identity;
    if (cert) {
        identity = std::make_shared<Identity>();
        identity->chain = ParseCertificate(*cert);
        const auto key = CopyInput(*privateKey);
        Random random;
        random.Seed();
        CheckBackend(mbedtls_pk_parse_key(&identity->key.key, key.bytes.get(), key.size, nullptr, 0,
            mbedtls_ctr_drbg_random, &random.drbg), "Invalid SSL private key");
        CheckBackend(mbedtls_pk_check_pair(&identity->chain->root.pk, &identity->key.key, mbedtls_ctr_drbg_random, &random.drbg),
            "SSL client certificate and private key do not match");
    }
    context.authorities.reserve(Add(context.authorities.size(), authorities.size()));
    context.certificateHandles.reserve(Add(context.certificateHandles.size(), handles.size()));
    for (auto& chain : authorities) context.authorities.push_back(std::move(chain));
    for (auto& handle : handles) context.certificateHandles.push_back(std::move(handle));
    if (identity) context.identity = std::move(identity);
    return 0;
}

int APS5_VABI sceSslUnloadCert(int sslCtxId) {
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    context.authorities.clear();
    context.identity.reset();
    return 0;
}

int APS5_VABI sceSslGetCaList(int sslCtxId, SceSsl::CaList* output) {
    if (!output) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    PoolScope scope(context.pool);
    const auto count = CertificateCount(context);
    if (!count) {
        *output = {};
        return ErrorNotFound;
    }
    if (count > static_cast<std::size_t>(std::numeric_limits<int>::max())) throw std::length_error("Too many SSL authorities");
    Snapshot snapshot{Allocate(count * sizeof(void*)), context.authorities, count};
    auto** pointers = reinterpret_cast<void**>(snapshot.data.get());
    std::size_t index = 0;
    for (const auto& chain : snapshot.certificates) for (auto* handle : chain->handles) pointers[index++] = handle;
    context.caLists.emplace(pointers, std::move(snapshot));
    *output = {pointers, static_cast<int>(count)};
    return 0;
}

int APS5_VABI sceSslFreeCaList(int sslCtxId, SceSsl::CaList* list) {
    if (!list) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    if (!list->certs && list->num == 0) return 0;
    const auto found = context.caLists.find(list->certs);
    if (found == context.caLists.end() || list->num < 0 || static_cast<std::size_t>(list->num) != found->second.count)
        throw std::invalid_argument("Invalid SSL CA list allocation");
    context.caLists.erase(found);
    *list = {};
    return 0;
}

int APS5_VABI sceSslGetCaCerts(int sslCtxId, SceSsl::CaCerts* output) {
    if (!output) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    const auto found = state.contexts.find(sslCtxId);
    if (found == state.contexts.end()) {
        *output = {};
        return ErrorNotFound;
    }
    auto& context = *found->second;
    PoolScope scope(context.pool);
    const auto count = CertificateCount(context);
    if (!count) {
        *output = {};
        return ErrorNotFound;
    }
    if (count > std::numeric_limits<std::size_t>::max() / sizeof(SceSsl::Data)) throw std::length_error("Too many SSL authorities");
    auto total = count * sizeof(SceSsl::Data);
    for (const auto& chain : context.authorities)
        for (auto* entry = &chain->root; entry; entry = entry->next) total = Add(total, entry->raw.len);
    Snapshot snapshot{Allocate(total), {}, count};
    auto* data = reinterpret_cast<SceSsl::Data*>(snapshot.data.get());
    auto* next = snapshot.data.get() + count * sizeof(SceSsl::Data);
    std::size_t index = 0;
    for (const auto& chain : context.authorities) {
        for (auto* entry = &chain->root; entry; entry = entry->next) {
            data[index++] = {next, entry->raw.len};
            std::memcpy(next, entry->raw.p, entry->raw.len);
            next += entry->raw.len;
        }
    }
    context.caCerts.emplace(data, std::move(snapshot));
    *output = {data, count, data};
    return 0;
}

int APS5_VABI sceSslFreeCaCerts(int sslCtxId, SceSsl::CaCerts* certificates) {
    if (!certificates) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    const auto found = state.contexts.find(sslCtxId);
    if (found != state.contexts.end()) {
        auto& snapshots = found->second->caCerts;
        const auto allocation = snapshots.find(certificates->pool);
        if (allocation != snapshots.end()) {
            if (certificates->certs != certificates->pool || certificates->num != allocation->second.count)
                throw std::invalid_argument("Invalid SSL CA certificate allocation");
            snapshots.erase(allocation);
        }
    }
    *certificates = {};
    return 0;
}

int APS5_VABI sceSslCreateConnection(int sslCtxId, int sockId, const char* host) {
    if (!host) return ErrorInvalidValue;
    std::lock_guard lock(State().mutex);
    if (!State().contexts.contains(sslCtxId)) return ErrorInvalidId;
    auto& state = State();
    if (state.nextHandle > static_cast<unsigned>(std::numeric_limits<int>::max())) throw std::overflow_error("SSL connection handles exhausted");
    const auto id = static_cast<int>(state.nextHandle);
    state.connections.emplace(id, SslConnection{sslCtxId, sockId, host, nullptr, nullptr});
    ++state.nextHandle;
    return id;
}

int APS5_VABI sceSslDeleteConnection(int sslConnectionId) {
    std::shared_ptr<Session> session;
    std::lock_guard lock(State().mutex);
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) return ErrorInvalidId;
    session = std::move(connection->session);
    State().connections.erase(sslConnectionId);
    return 0;
}

int APS5_VABI sceSslSetVerifyCallback(int sslConnectionId, SslVerifyCallback cbfunc, void* userArg) {
    std::lock_guard lock(State().mutex);
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) return ErrorInvalidId;
    connection->verifyCallback = cbfunc;
    connection->verifyArgument = userArg;
    return 0;
}

}

namespace {

int RunCallback(Session& session, std::unique_lock<std::mutex>& sessionLock, SslVerifyCallback callback, void* argument) {
    session.verifying = true;
    sessionLock.unlock();
    const int decision = callback(session.contextHandle, session.failedOptions, session.peerHandles.data(),
        static_cast<int>(session.peerHandles.size()), argument);
    sessionLock.lock();
    session.verifying = false;
    return decision < 0 ? ErrorCallbackCheck : 0;
}

int Establish(const char* function, int sslConnectionId, std::shared_ptr<Session>& session) {
    SslVerifyCallback callback = nullptr;
    void* callbackArgument = nullptr;
    {
        auto& state = State();
        std::lock_guard lock(state.mutex);
        auto* connection = FindConnection(sslConnectionId);
        if (!connection) return ErrorInvalidId;
        if (!connection->session) {
            auto context = state.contexts.at(connection->context);
            std::shared_ptr<void> owner;
            std::uintptr_t native = 0;
            if (!KernelLookupSocketNative_nid_no_patch(connection->socket, &owner, &native)) return ErrorNetBadDescriptor;
            PoolScope scope(context->pool);
            session = std::make_shared<Session>(connection->context, std::move(context), std::move(owner), native);
            session->Configure(connection->host, connection->alpn, connection->verifyOptions);
            connection->session = session;
        } else {
            session = connection->session;
        }
        callback = connection->verifyCallback;
        callbackArgument = connection->verifyArgument;
    }
    std::unique_lock sessionLock(session->mutex);
    if (session->verifying) throw std::logic_error(std::string(function) + ": the verify callback is running");
    if (session->verified) {
        if (session->verifyResult == ErrorCallbackCheck && callback) session->verifyResult = RunCallback(*session, sessionLock, callback, callbackArgument);
        return session->verifyResult;
    }
    if (session->gone) return 0;
    {
        PoolScope scope(session->context->pool);
        if (!session->handshaken) {
            const int result = mbedtls_ssl_handshake(&session->ssl);
            if (result == MBEDTLS_ERR_SSL_WANT_READ || result == MBEDTLS_ERR_SSL_WANT_WRITE) return session->Code(result, Operation::Connect);
            if (result == MBEDTLS_ERR_SSL_FATAL_ALERT_MESSAGE) {
                session->gone = true;
                return ErrorFatalAlert;
            }
            if (result != 0) {
                {
                    std::lock_guard lock(State().mutex);
                    const auto found = State().connections.find(sslConnectionId);
                    if (found != State().connections.end() && found->second.session == session) found->second.session.reset();
                }
                if (const int failure = session->Code(result, Operation::Connect)) return failure;
                session->Fail(function, result);
            }
            session->handshaken = true;
            const char* selected = mbedtls_ssl_get_alpn_protocol(&session->ssl);
            session->alpnSelected = selected ? selected : "";
        }
        session->Verify();
        if (callback && session->verifyResult == ErrorInvalidCert)
            throw std::runtime_error(std::string(function) + ": the chain failed a check no verify option names; what the console passes to the verify callback is unknown");
        if (callback) RegisterPeer(*session);
    }
    if (callback) session->verifyResult = RunCallback(*session, sessionLock, callback, callbackArgument);
    session->verified = true;
    if (session->verifyResult != 0 && session->verifyResult != ErrorCallbackCheck) {
        PoolScope scope(session->context->pool);
        mbedtls_ssl_close_notify(&session->ssl);
        session->closed = true;
    }
    return session->verifyResult;
}

}

extern "C" {

int APS5_VABI sceSslConnect(int sslConnectionId) {
    std::shared_ptr<Session> session;
    return Establish(__func__, sslConnectionId, session);
}

int APS5_VABI sceSslRead(int sslConnectionId, void* buf, size_t len, int flags) {
    if (!buf && len) throw std::invalid_argument("sceSslRead: null buffer");
    std::shared_ptr<Session> session;
    if (const int code = Establish(__func__, sslConnectionId, session)) {
        if (session) {
            std::lock_guard sessionLock(session->mutex);
            RequireUsable(__func__, *session);
        }
        return code;
    }
    std::lock_guard sessionLock(session->mutex);
    if (session->gone || session->closed) return 0;
    if (session->reset) return ErrorNetReset;
    PoolScope scope(session->context->pool);
    auto* bytes = static_cast<unsigned char*>(buf);
    const auto total = std::min<std::size_t>(len, INT_MAX);
    std::size_t received = 0;
    while (received < total) {
        const int result = mbedtls_ssl_read(&session->ssl, bytes + received, total - received);
        if (result > 0) {
            received += static_cast<std::size_t>(result);
            if (flags != 0) break;
            continue;
        }
        if (result == 0 || result == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || result == MBEDTLS_ERR_SSL_CONN_EOF) break;
        const int code = session->Code(result, Operation::Read);
        if (code == 0) session->Fail(__func__, result);
        if (received) break;
        return code;
    }
    return static_cast<int>(received);
}

int APS5_VABI sceSslWrite(int sslConnectionId, void* buf, size_t len, int flags) {
    if (flags != 0) return ErrorInvalidValue;
    if (!buf && len) throw std::invalid_argument("sceSslWrite: null buffer");
    std::shared_ptr<Session> session;
    if (const int code = Establish(__func__, sslConnectionId, session)) {
        if (session) {
            std::lock_guard sessionLock(session->mutex);
            RequireUsable(__func__, *session);
        }
        return code;
    }
    std::lock_guard sessionLock(session->mutex);
    if (session->gone) return ErrorSocketClosed;
    if (session->closed) throw std::logic_error("sceSslWrite: the connection was closed; the console's behaviour is unknown");
    if (session->reset) return ErrorNetPipe;
    PoolScope scope(session->context->pool);
    const auto* bytes = static_cast<const unsigned char*>(buf);
    const auto total = std::min<std::size_t>(len, INT_MAX);
    std::size_t written = 0;
    while (written < total) {
        const int result = mbedtls_ssl_write(&session->ssl, bytes + written, total - written);
        if (result < 0) {
            const int code = session->Code(result, Operation::Write);
            if (code == 0) session->Fail(__func__, result);
            if (written) break;
            return code;
        }
        written += static_cast<std::size_t>(result);
    }
    return static_cast<int>(written);
}

int APS5_VABI sceSslClose(int sslConnectionId) {
    std::shared_ptr<Session> session;
    {
        std::lock_guard lock(State().mutex);
        auto* connection = FindConnection(sslConnectionId);
        if (!connection) return ErrorInvalidId;
        session = connection->session;
    }
    if (!session) return 0;
    std::lock_guard sessionLock(session->mutex);
    if (session->gone || session->closed || !session->handshaken) return 0;
    if (session->reset) return ErrorNetReset;
    PoolScope scope(session->context->pool);
    const int result = mbedtls_ssl_close_notify(&session->ssl);
    if (result == MBEDTLS_ERR_SSL_WANT_WRITE || result == MBEDTLS_ERR_SSL_WANT_READ) return session->Code(result, Operation::Close);
    if (result == MBEDTLS_ERR_NET_CONN_RESET) return session->Code(result, Operation::Close);
    if (result != 0) session->Fail(__func__, result);
    session->closed = true;
    return 0;
}

int APS5_VABI sceSslGetSerialNumber(int sslCtxId, void* sslCert, unsigned char* sboData, std::size_t* sboLen) {
    if (!sboLen) return ErrorInvalidArg;
    std::lock_guard lock(State().mutex);
    const auto* crt = RequireCertificate(__func__, sslCtxId, sslCert);
    const auto reqLen = crt->serial.len;
    if (!sboData || *sboLen == 0) {
        *sboLen = reqLen;
        return 0;
    }
    if (*sboLen < reqLen) {
        *sboLen = reqLen;
        return ErrorInvalidArg;
    }
    std::memcpy(sboData, crt->serial.p, reqLen);
    return 0;
}

int APS5_VABI sceSslFreeSslCertName(int sslCtxId, void* certName) {
    if (!certName) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    const auto found = context.certNames.find(certName);
    if (found == context.certNames.end()) throw std::invalid_argument("sceSslFreeSslCertName: unknown cert name");
    context.certNames.erase(found);
    return 0;
}

int APS5_VABI sceSslEnableVerifyOption(int sslConnectionId, std::uint32_t option) {
    std::lock_guard lock(State().mutex);
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) return ErrorInvalidId;
    if (option & ~VerifyOptionMask) return ErrorInvalidValue;
    connection->verifyOptions |= option;
    return 0;
}

int APS5_VABI sceSslDisableVerifyOption(int sslConnectionId, std::uint32_t option) {
    std::lock_guard lock(State().mutex);
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) return ErrorInvalidId;
    if (option & ~VerifyOptionMask) return ErrorInvalidValue;
    connection->verifyOptions &= ~option;
    return 0;
}

const char* APS5_VABI sceSslGetAlpnSelected(int sslConnectionId) {
    std::shared_ptr<Session> session;
    {
        std::lock_guard lock(State().mutex);
        session = RequireConnection(__func__, sslConnectionId).session;
    }
    if (!session) return nullptr;
    std::lock_guard sessionLock(session->mutex);
    if (!session->handshaken || session->alpnSelected.empty()) return nullptr;
    return session->alpnSelected.c_str();
}

int APS5_VABI sceSslSetAlpn(int sslConnectionId, const char* proto) {
    if (!proto) throw std::invalid_argument("sceSslSetAlpn: null protocol list");
    std::lock_guard lock(State().mutex);
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) return ErrorInvalidId;
    if (!*proto) return ErrorBadLength;
    connection->alpn = proto;
    return 0;
}

int APS5_VABI sceSslSetMinSslVersion(int sslConnectionId, int version) {
    std::lock_guard lock(State().mutex);
    auto* connection = FindConnection(sslConnectionId);
    if (!connection) return ErrorInvalidId;
    if (version < SslVersionSsl30 || version > SslVersionTls12) return ErrorInvalidValue;
    connection->minimumVersion = version;
    return 0;
}

void* APS5_VABI sceSslGetIssuerName(int sslCtxId, void* sslCert) {
    return ExtractCertName(__func__, sslCtxId, sslCert, false);
}

int APS5_VABI sceSslGetNameEntryCount(int sslCtxId, void* certName) {
    if (!certName) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    const auto found = context.certNames.find(certName);
    if (found == context.certNames.end()) throw std::invalid_argument("sceSslGetNameEntryCount: unknown cert name");
    return static_cast<int>(found->second->entries.size());
}

int APS5_VABI sceSslGetNameEntryInfo(int sslCtxId, void* certName, int entryNum, char* oidname, std::size_t maxOidnameLen,
    char* value, std::size_t maxValueLen, std::size_t* valueLen) {
    if (!certName) return ErrorInvalidArg;
    auto& state = State();
    std::lock_guard lock(state.mutex);
    auto& context = GetContext(sslCtxId);
    const auto found = context.certNames.find(certName);
    if (found == context.certNames.end()) throw std::invalid_argument("sceSslGetNameEntryInfo: unknown cert name");
    const auto& entries = found->second->entries;
    if (entryNum < 0 || static_cast<std::size_t>(entryNum) >= entries.size()) return ErrorInvalidArg;
    const auto& entry = entries[static_cast<std::size_t>(entryNum)];
    if (oidname && maxOidnameLen > 0) {
        const auto copyLen = std::min<std::size_t>(entry.oid.size(), maxOidnameLen - 1);
        std::memcpy(oidname, entry.oid.data(), copyLen);
        oidname[copyLen] = '\0';
    }
    if (value && maxValueLen > 0) {
        const auto copyLen = std::min<std::size_t>(entry.value.size(), maxValueLen - 1);
        std::memcpy(value, entry.value.data(), copyLen);
        value[copyLen] = '\0';
    }
    if (valueLen) *valueLen = entry.value.size();
    return 0;
}

int APS5_VABI sceSslGetNotBefore(int sslCtxId, void* sslCert, SceSsl::RtcTick* begin) {
    if (!begin) return ErrorInvalidArg;
    std::lock_guard lock(State().mutex);
    const auto* crt = RequireCertificate(__func__, sslCtxId, sslCert);
    begin->tick = TimeToTick(crt->valid_from);
    return 0;
}

int APS5_VABI sceSslGetNotAfter(int sslCtxId, void* sslCert, SceSsl::RtcTick* limit) {
    if (!limit) return ErrorInvalidArg;
    std::lock_guard lock(State().mutex);
    const auto* crt = RequireCertificate(__func__, sslCtxId, sslCert);
    limit->tick = TimeToTick(crt->valid_to);
    return 0;
}

int APS5_VABI sceSslGetFingerprint(int sslCtxId, void* sslCert, int hashType, unsigned char* fingerprint) {
    if (!fingerprint) return ErrorInvalidArg;
    mbedtls_md_type_t mdType;
    switch (hashType) {
    case 0: mdType = MBEDTLS_MD_MD5; break;
    case 1: mdType = MBEDTLS_MD_SHA1; break;
    case 2: mdType = MBEDTLS_MD_SHA224; break;
    case 3: mdType = MBEDTLS_MD_SHA256; break;
    case 4: mdType = MBEDTLS_MD_SHA384; break;
    case 5: mdType = MBEDTLS_MD_SHA512; break;
    default: return ErrorInvalidArg;
    }
    const auto* info = mbedtls_md_info_from_type(mdType);
    if (!info) return ErrorInvalidArg;
    std::lock_guard lock(State().mutex);
    const auto* crt = RequireCertificate(__func__, sslCtxId, sslCert);
    if (mbedtls_md(info, crt->raw.p, crt->raw.len, fingerprint) != 0) return ErrorInvalidArg;
    return 0;
}

int APS5_VABI sceSslGetPem(int sslCtxId, void* sslCert, char* buf, std::size_t* bufLen) {
    if (!bufLen) return ErrorInvalidArg;
    std::lock_guard lock(State().mutex);
    auto& context = GetContext(sslCtxId);
    const auto* crt = RequireCertificate(__func__, sslCtxId, sslCert);
    PoolScope scope(context.pool);
    std::size_t required = 0;
    const auto encode = [&](unsigned char* output, std::size_t capacity, std::size_t* written) {
        return mbedtls_pem_write_buffer("-----BEGIN CERTIFICATE-----\n", "-----END CERTIFICATE-----\n", crt->raw.p, crt->raw.len, output, capacity, written);
    };
    const int sizing = encode(nullptr, 0, &required);
    if (sizing != MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL) CheckBackend(sizing, "SSL PEM sizing failed");
    if (!buf) {
        *bufLen = required;
        return 0;
    }
    if (*bufLen < required) throw std::length_error("SSL PEM buffer is too small");
    std::size_t written = 0;
    CheckBackend(encode(reinterpret_cast<unsigned char*>(buf), required, &written), "SSL PEM encoding failed");
    *bufLen = written;
    return 0;
}

void* APS5_VABI sceSslGetSubjectName(int sslCtxId, void* sslCert) {
    return ExtractCertName(__func__, sslCtxId, sslCert, true);
}

}
