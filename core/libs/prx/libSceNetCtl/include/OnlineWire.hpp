#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINEWIRE_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINEWIRE_HPP

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace Online::Wire {

constexpr std::uint16_t Protocol = 1;
constexpr std::size_t HeaderSize = 12;
constexpr std::uint32_t MaxPayload = 16u * 1024u * 1024u;
constexpr std::size_t NonceSize = 16;
constexpr std::size_t ProofSize = 32;
constexpr std::size_t SecretSize = 32;

enum class Type : std::uint16_t {
    Hello = 0x0001,
    Welcome = 0x0002,
    Proof = 0x0003,
    Refuse = 0x0004,
    Account = 0x0101,
    Observation = 0x0102,
    WebRequest = 0x0201,
};

enum Flags : std::uint16_t {
    FlagReply = 0x0001,
    FlagUnsupported = 0x0002,
};

enum class RefuseReason : std::uint16_t {
    BadProof = 1,
    Protocol = 2,
    NoGame = 3,
    Busy = 4,
};

struct Header {
    std::uint32_t length = 0;
    std::uint16_t type = 0;
    std::uint16_t flags = 0;
    std::uint32_t call = 0;
};

using Nonce = std::array<std::uint8_t, NonceSize>;
using ProofBytes = std::array<std::uint8_t, ProofSize>;
using Secret = std::array<std::uint8_t, SecretSize>;
using Pairs = std::vector<std::pair<std::string, std::string>>;

class Writer {
public:
    Writer& U8(std::uint8_t value);
    Writer& U16(std::uint16_t value);
    Writer& U32(std::uint32_t value);
    Writer& U64(std::uint64_t value);
    Writer& I32(std::int32_t value) { return U32(static_cast<std::uint32_t>(value)); }
    Writer& Raw(std::span<const std::uint8_t> bytes);
    Writer& Str(std::string_view text);
    Writer& Bytes(std::span<const std::uint8_t> bytes);
    Writer& PairList(const Pairs& pairs);
    const std::vector<std::uint8_t>& Data() const { return data; }
    std::vector<std::uint8_t> Take() { return std::move(data); }

private:
    std::vector<std::uint8_t> data;
};

class Reader {
public:
    explicit Reader(std::span<const std::uint8_t> bytes) : bytes(bytes) {}
    std::uint8_t U8();
    std::uint16_t U16();
    std::uint32_t U32();
    std::uint64_t U64();
    std::int32_t I32() { return static_cast<std::int32_t>(U32()); }
    void Raw(std::span<std::uint8_t> out);
    std::string Str();
    std::vector<std::uint8_t> Bytes();
    Pairs PairList();
    bool Ok() const { return ok; }
    std::size_t Remaining() const { return ok ? bytes.size() - offset : 0; }

private:
    bool take(std::size_t size);

    std::span<const std::uint8_t> bytes;
    std::size_t offset = 0;
    bool ok = true;
};

std::array<std::uint8_t, HeaderSize> EncodeHeader(const Header& header);
std::optional<Header> DecodeHeader(std::span<const std::uint8_t> bytes);
std::vector<std::uint8_t> Frame(Type type, std::uint16_t flags, std::uint32_t call, std::span<const std::uint8_t> payload);

struct Hello {
    std::uint16_t protocol = Protocol;
    Nonce nonce{};
    std::string build;
    std::uint32_t pid = 0;
};

struct Welcome {
    std::uint16_t protocol = Protocol;
    Nonce nonce{};
    ProofBytes proof{};
};

struct Refuse {
    RefuseReason reason = RefuseReason::BadProof;
    std::string text;
};

struct Account {
    bool signedIn = false;
    std::uint64_t accountId = 0;
    std::string onlineId;
    std::string country;
    std::string language;
    std::uint8_t age = 0;
    std::uint32_t address = 0;
    std::uint8_t nat = 0;
};

struct WebRequest {
    std::int32_t userId = 0;
    std::string apiGroup;
    std::string path;
    std::string method;
    Pairs headers;
    std::vector<std::uint8_t> body;
};

struct WebReply {
    std::uint16_t status = 0;
    Pairs headers;
    std::vector<std::uint8_t> body;
};

std::vector<std::uint8_t> Encode(const Hello& message);
std::vector<std::uint8_t> Encode(const Welcome& message);
std::vector<std::uint8_t> Encode(const ProofBytes& proof);
std::vector<std::uint8_t> Encode(const Refuse& message);
std::vector<std::uint8_t> Encode(const Account& message);
std::vector<std::uint8_t> Encode(const WebRequest& message);
std::vector<std::uint8_t> Encode(const WebReply& message);

std::optional<Hello> DecodeHello(std::span<const std::uint8_t> payload);
std::optional<Welcome> DecodeWelcome(std::span<const std::uint8_t> payload);
std::optional<ProofBytes> DecodeProof(std::span<const std::uint8_t> payload);
std::optional<Refuse> DecodeRefuse(std::span<const std::uint8_t> payload);
std::optional<Account> DecodeAccount(std::span<const std::uint8_t> payload);
std::optional<WebRequest> DecodeWebRequest(std::span<const std::uint8_t> payload);
std::optional<WebReply> DecodeWebReply(std::span<const std::uint8_t> payload);

enum class Side : std::uint8_t { Launcher, Engine };
ProofBytes MakeProof(const Secret& secret, Side side, const Nonce& engine, const Nonce& launcher);
bool SameProof(const ProofBytes& left, const ProofBytes& right);
std::optional<Secret> ParseSecret(std::string_view hex);
Nonce RandomNonce();

}

#endif
