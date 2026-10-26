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
    PushEvent = 0x0204,
    Datagram = 0x0310,
    StreamOpen = 0x0311,
    StreamData = 0x0312,
    StreamClose = 0x0313,
    StreamAccept = 0x0314,
};

constexpr bool IsStream(std::uint16_t type) {
    return type >= static_cast<std::uint16_t>(Type::StreamOpen) && type <= static_cast<std::uint16_t>(Type::StreamAccept);
}

// Why a stream ended: the other end closed it (its reads end once everything sent has arrived),
// nobody listens on the port and virtual port it named, or it broke (no route to the player, the
// player left, a connection on the way dropped).
enum class StreamCloseReason : std::uint8_t {
    Closed = 0,
    Refused = 1,
    Reset = 2,
};

// Stream numbers name a stream on one engine-launcher connection; 0 is never one. The side that
// opens a stream picks its number: the engine's have the top bit clear, the launcher's set.
constexpr std::uint32_t LauncherStream = 0x80000000u;
// The most bytes one StreamData frame carries.
constexpr std::size_t MaxStreamData = 65536;

enum class DatagramKind : std::uint8_t {
    Udp = 1,
    P2p = 2,
};

constexpr std::uint32_t VirtualNetwork = 0xC6120000u;
constexpr std::uint32_t VirtualMask = 0xFFFE0000u;
constexpr bool IsVirtual(std::uint32_t address) { return (address & VirtualMask) == VirtualNetwork; }
// A datagram to the limited broadcast, the virtual network's broadcast or a multicast group goes to
// every other player of the session, and arrives from the sender's virtual address.
constexpr std::uint32_t VirtualBroadcast = VirtualNetwork | ~VirtualMask;
constexpr bool IsGroup(std::uint32_t address) {
    return address == 0xFFFFFFFFu || address == VirtualBroadcast || (address & 0xF0000000u) == 0xE0000000u;
}
constexpr std::size_t MaxDatagram = 65535;
// A push event's data type and extended data keys, as the platform's structures hold them
// (64 and 32 letters plus the terminator).
constexpr std::size_t MaxPushDataType = 64;
constexpr std::size_t MaxPushExtendedKey = 32;
constexpr std::size_t MaxPushContextId = 36;
// The largest game datagram online play carries: the largest UDP payload over IPv4 (65507 bytes)
// less the 12-byte header the receiving engine puts in front of it on its loopback hop to the
// game's socket. A bigger one fails with EMSGSIZE in the sending game, as on a network.
constexpr std::size_t MaxGameDatagram = 65507 - 12;

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

struct Datagram {
    std::uint32_t peer = 0;
    std::uint16_t peerPort = 0;
    std::uint16_t peerVport = 0;
    std::uint16_t localPort = 0;
    std::uint16_t localVport = 0;
    DatagramKind kind = DatagramKind::Udp;
    std::vector<std::uint8_t> data;
};

// A game stream between two players (stream P2P sockets), both directions, events:
// StreamOpen  u32 stream, u32 peer, u16 peer port, u16 peer virtual port, u16 local port, u16 local virtual port
// StreamAccept u32 stream
// StreamData  u32 stream, bytes data (at most MaxStreamData)
// StreamClose u32 stream, u8 reason
// The engine opens toward the peer's address, port and virtual port from its own port and virtual
// port; the launcher opens toward the engine's port and virtual port from the peer's.
struct Stream {
    Type type = Type::StreamData;
    std::uint32_t stream = 0;
    std::uint32_t peer = 0;
    std::uint16_t peerPort = 0;
    std::uint16_t peerVport = 0;
    std::uint16_t localPort = 0;
    std::uint16_t localVport = 0;
    StreamCloseReason reason = StreamCloseReason::Closed;
    std::vector<std::uint8_t> data;
};

// Session and invitation news from the launcher (launcher -> engine, event): what the platform's
// push events carry. An empty push context goes to the plain callbacks and every push context.
struct PushEvent {
    std::string service;
    std::uint32_t label = 0;
    std::string pushContextId;
    std::string dataType;
    std::vector<std::uint8_t> data;
    Pairs extended;
    std::uint64_t to = 0;
    std::uint64_t from = 0;
    std::string fromOnlineId;
};

std::vector<std::uint8_t> Encode(const Hello& message);
std::vector<std::uint8_t> Encode(const Welcome& message);
std::vector<std::uint8_t> Encode(const ProofBytes& proof);
std::vector<std::uint8_t> Encode(const Refuse& message);
std::vector<std::uint8_t> Encode(const Account& message);
std::vector<std::uint8_t> Encode(const WebRequest& message);
std::vector<std::uint8_t> Encode(const WebReply& message);
std::vector<std::uint8_t> Encode(const Datagram& message);
std::vector<std::uint8_t> Encode(const PushEvent& message);
std::vector<std::uint8_t> Encode(const Stream& message);

std::optional<Hello> DecodeHello(std::span<const std::uint8_t> payload);
std::optional<Welcome> DecodeWelcome(std::span<const std::uint8_t> payload);
std::optional<ProofBytes> DecodeProof(std::span<const std::uint8_t> payload);
std::optional<Refuse> DecodeRefuse(std::span<const std::uint8_t> payload);
std::optional<Account> DecodeAccount(std::span<const std::uint8_t> payload);
std::optional<WebRequest> DecodeWebRequest(std::span<const std::uint8_t> payload);
std::optional<WebReply> DecodeWebReply(std::span<const std::uint8_t> payload);
std::optional<Datagram> DecodeDatagram(std::span<const std::uint8_t> payload);
std::optional<PushEvent> DecodePushEvent(std::span<const std::uint8_t> payload);
std::optional<Stream> DecodeStream(Type type, std::span<const std::uint8_t> payload);

enum class Side : std::uint8_t { Launcher, Engine };
ProofBytes MakeProof(const Secret& secret, Side side, const Nonce& engine, const Nonce& launcher);
bool SameProof(const ProofBytes& left, const ProofBytes& right);
std::optional<Secret> ParseSecret(std::string_view hex);
Nonce RandomNonce();

}

#endif
