#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include <algorithm>
#include <mbedtls/md.h>
#include <random>
#include <stdexcept>

namespace Online::Wire {

namespace {

template <typename T>
void putLittle(std::vector<std::uint8_t>& data, T value) {
    for (std::size_t index = 0; index < sizeof(T); ++index) data.push_back(static_cast<std::uint8_t>(value >> (8 * index)));
}

template <typename T>
T getLittle(const std::uint8_t* bytes) {
    T value = 0;
    for (std::size_t index = 0; index < sizeof(T); ++index) value |= static_cast<T>(static_cast<T>(bytes[index]) << (8 * index));
    return value;
}

constexpr std::size_t MaxOnlineId = 16;
constexpr std::size_t MaxCountry = 2;
constexpr std::size_t MaxLanguage = 35;

template <typename TMessage, typename TRead>
std::optional<TMessage> decode(std::span<const std::uint8_t> payload, TRead read) {
    Reader reader(payload);
    TMessage message = read(reader);
    if (!reader.Ok()) return std::nullopt;
    return message;
}

int hexDigit(char letter) {
    if (letter >= '0' && letter <= '9') return letter - '0';
    if (letter >= 'a' && letter <= 'f') return letter - 'a' + 10;
    if (letter >= 'A' && letter <= 'F') return letter - 'A' + 10;
    return -1;
}

}

Writer& Writer::U8(std::uint8_t value) {
    data.push_back(value);
    return *this;
}

Writer& Writer::U16(std::uint16_t value) {
    putLittle(data, value);
    return *this;
}

Writer& Writer::U32(std::uint32_t value) {
    putLittle(data, value);
    return *this;
}

Writer& Writer::U64(std::uint64_t value) {
    putLittle(data, value);
    return *this;
}

Writer& Writer::Raw(std::span<const std::uint8_t> bytes) {
    data.insert(data.end(), bytes.begin(), bytes.end());
    return *this;
}

Writer& Writer::Str(std::string_view text) {
    if (text.size() > 0xffff) throw std::length_error("online bridge: a string is longer than 65535 bytes");
    U16(static_cast<std::uint16_t>(text.size()));
    data.insert(data.end(), text.begin(), text.end());
    return *this;
}

Writer& Writer::Bytes(std::span<const std::uint8_t> bytes) {
    if (bytes.size() > MaxPayload) throw std::length_error("online bridge: a body is larger than a frame");
    U32(static_cast<std::uint32_t>(bytes.size()));
    return Raw(bytes);
}

Writer& Writer::PairList(const Pairs& pairs) {
    if (pairs.size() > 0xffff) throw std::length_error("online bridge: more than 65535 pairs");
    U16(static_cast<std::uint16_t>(pairs.size()));
    for (const auto& [name, value] : pairs) Str(name).Str(value);
    return *this;
}

bool Reader::take(std::size_t size) {
    if (!ok || bytes.size() - offset < size) {
        ok = false;
        return false;
    }
    return true;
}

std::uint8_t Reader::U8() {
    if (!take(1)) return 0;
    return bytes[offset++];
}

std::uint16_t Reader::U16() {
    if (!take(2)) return 0;
    const auto value = getLittle<std::uint16_t>(bytes.data() + offset);
    offset += 2;
    return value;
}

std::uint32_t Reader::U32() {
    if (!take(4)) return 0;
    const auto value = getLittle<std::uint32_t>(bytes.data() + offset);
    offset += 4;
    return value;
}

std::uint64_t Reader::U64() {
    if (!take(8)) return 0;
    const auto value = getLittle<std::uint64_t>(bytes.data() + offset);
    offset += 8;
    return value;
}

void Reader::Raw(std::span<std::uint8_t> out) {
    if (!take(out.size())) return;
    std::copy_n(bytes.begin() + static_cast<std::ptrdiff_t>(offset), out.size(), out.begin());
    offset += out.size();
}

std::string Reader::Str() {
    const auto size = U16();
    if (!take(size)) return {};
    std::string text(reinterpret_cast<const char*>(bytes.data() + offset), size);
    offset += size;
    return text;
}

std::vector<std::uint8_t> Reader::Bytes() {
    const auto size = U32();
    if (!take(size)) return {};
    std::vector<std::uint8_t> out(bytes.begin() + static_cast<std::ptrdiff_t>(offset), bytes.begin() + static_cast<std::ptrdiff_t>(offset + size));
    offset += size;
    return out;
}

Pairs Reader::PairList() {
    const auto count = U16();
    Pairs pairs;
    for (std::uint16_t index = 0; index < count && ok; ++index) {
        auto name = Str();
        auto value = Str();
        if (ok) pairs.emplace_back(std::move(name), std::move(value));
    }
    return pairs;
}

std::array<std::uint8_t, HeaderSize> EncodeHeader(const Header& header) {
    Writer writer;
    writer.U32(header.length).U16(header.type).U16(header.flags).U32(header.call);
    std::array<std::uint8_t, HeaderSize> out{};
    std::copy(writer.Data().begin(), writer.Data().end(), out.begin());
    return out;
}

std::optional<Header> DecodeHeader(std::span<const std::uint8_t> bytes) {
    if (bytes.size() < HeaderSize) return std::nullopt;
    Reader reader(bytes.first(HeaderSize));
    Header header;
    header.length = reader.U32();
    header.type = reader.U16();
    header.flags = reader.U16();
    header.call = reader.U32();
    if (header.length > MaxPayload) return std::nullopt;
    return header;
}

std::vector<std::uint8_t> Frame(Type type, std::uint16_t flags, std::uint32_t call, std::span<const std::uint8_t> payload) {
    if (payload.size() > MaxPayload) throw std::length_error("online bridge: a frame is larger than 16 MiB");
    const auto header = EncodeHeader({static_cast<std::uint32_t>(payload.size()), static_cast<std::uint16_t>(type), flags, call});
    std::vector<std::uint8_t> frame(header.begin(), header.end());
    frame.insert(frame.end(), payload.begin(), payload.end());
    return frame;
}

std::vector<std::uint8_t> Encode(const Hello& message) {
    Writer writer;
    writer.U16(message.protocol).Raw(message.nonce).Str(message.build).U32(message.pid);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const Welcome& message) {
    Writer writer;
    writer.U16(message.protocol).Raw(message.nonce).Raw(message.proof);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const ProofBytes& proof) {
    Writer writer;
    writer.Raw(proof);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const Refuse& message) {
    Writer writer;
    writer.U16(static_cast<std::uint16_t>(message.reason)).Str(message.text);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const Account& message) {
    Writer writer;
    writer.U8(message.signedIn ? 1 : 0).U64(message.accountId).Str(message.onlineId).Str(message.country).Str(message.language)
        .U8(message.age).U32(message.address).U8(message.nat);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const WebRequest& message) {
    Writer writer;
    writer.I32(message.userId).Str(message.apiGroup).Str(message.path).Str(message.method).PairList(message.headers).Bytes(message.body);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const WebReply& message) {
    Writer writer;
    writer.U16(message.status).PairList(message.headers).Bytes(message.body);
    return writer.Take();
}

std::vector<std::uint8_t> Encode(const Datagram& message) {
    if (message.data.size() > MaxDatagram) throw std::length_error("online bridge: a datagram is larger than 65535 bytes");
    Writer writer;
    writer.U32(message.peer).U16(message.peerPort).U16(message.peerVport).U16(message.localPort).U16(message.localVport)
        .U8(static_cast<std::uint8_t>(message.kind)).Bytes(message.data);
    return writer.Take();
}

std::optional<Datagram> DecodeDatagram(std::span<const std::uint8_t> payload) {
    auto datagram = decode<Datagram>(payload, [](Reader& reader) {
        Datagram message;
        message.peer = reader.U32();
        message.peerPort = reader.U16();
        message.peerVport = reader.U16();
        message.localPort = reader.U16();
        message.localVport = reader.U16();
        message.kind = static_cast<DatagramKind>(reader.U8());
        message.data = reader.Bytes();
        return message;
    });
    if (!datagram || !IsVirtual(datagram->peer) || datagram->data.size() > MaxDatagram) return std::nullopt;
    if (datagram->kind != DatagramKind::Udp && datagram->kind != DatagramKind::P2p) return std::nullopt;
    return datagram;
}

std::vector<std::uint8_t> Encode(const PushEvent& message) {
    Writer writer;
    writer.Str(message.service).U32(message.label).Str(message.pushContextId).Str(message.dataType).Bytes(message.data).PairList(message.extended)
        .U64(message.to).U64(message.from).Str(message.fromOnlineId);
    return writer.Take();
}

std::optional<PushEvent> DecodePushEvent(std::span<const std::uint8_t> payload) {
    auto event = decode<PushEvent>(payload, [](Reader& reader) {
        PushEvent message;
        message.service = reader.Str();
        message.label = reader.U32();
        message.pushContextId = reader.Str();
        message.dataType = reader.Str();
        message.data = reader.Bytes();
        message.extended = reader.PairList();
        message.to = reader.U64();
        message.from = reader.U64();
        message.fromOnlineId = reader.Str();
        return message;
    });
    if (!event || event->dataType.empty() || event->dataType.size() > MaxPushDataType || event->pushContextId.size() > MaxPushContextId ||
        event->fromOnlineId.size() > MaxOnlineId)
        return std::nullopt;
    for (const auto& [key, value] : event->extended) {
        if (key.empty() || key.size() > MaxPushExtendedKey) return std::nullopt;
    }
    return event;
}

std::optional<Hello> DecodeHello(std::span<const std::uint8_t> payload) {
    return decode<Hello>(payload, [](Reader& reader) {
        Hello message;
        message.protocol = reader.U16();
        reader.Raw(message.nonce);
        message.build = reader.Str();
        message.pid = reader.U32();
        return message;
    });
}

std::optional<Welcome> DecodeWelcome(std::span<const std::uint8_t> payload) {
    return decode<Welcome>(payload, [](Reader& reader) {
        Welcome message;
        message.protocol = reader.U16();
        reader.Raw(message.nonce);
        reader.Raw(message.proof);
        return message;
    });
}

std::optional<ProofBytes> DecodeProof(std::span<const std::uint8_t> payload) {
    return decode<ProofBytes>(payload, [](Reader& reader) {
        ProofBytes proof{};
        reader.Raw(proof);
        return proof;
    });
}

std::optional<Refuse> DecodeRefuse(std::span<const std::uint8_t> payload) {
    return decode<Refuse>(payload, [](Reader& reader) {
        Refuse message;
        message.reason = static_cast<RefuseReason>(reader.U16());
        message.text = reader.Str();
        return message;
    });
}

std::optional<Account> DecodeAccount(std::span<const std::uint8_t> payload) {
    auto account = decode<Account>(payload, [](Reader& reader) {
        Account message;
        message.signedIn = reader.U8() != 0;
        message.accountId = reader.U64();
        message.onlineId = reader.Str();
        message.country = reader.Str();
        message.language = reader.Str();
        message.age = reader.U8();
        message.address = reader.U32();
        message.nat = reader.U8();
        return message;
    });
    if (!account) return std::nullopt;
    if (account->onlineId.size() > MaxOnlineId || account->country.size() > MaxCountry || account->language.size() > MaxLanguage) return std::nullopt;
    if (account->signedIn && (account->onlineId.empty() || account->accountId == 0)) return std::nullopt;
    return account;
}

std::optional<WebRequest> DecodeWebRequest(std::span<const std::uint8_t> payload) {
    return decode<WebRequest>(payload, [](Reader& reader) {
        WebRequest message;
        message.userId = reader.I32();
        message.apiGroup = reader.Str();
        message.path = reader.Str();
        message.method = reader.Str();
        message.headers = reader.PairList();
        message.body = reader.Bytes();
        return message;
    });
}

std::optional<WebReply> DecodeWebReply(std::span<const std::uint8_t> payload) {
    return decode<WebReply>(payload, [](Reader& reader) {
        WebReply message;
        message.status = reader.U16();
        message.headers = reader.PairList();
        message.body = reader.Bytes();
        return message;
    });
}

ProofBytes MakeProof(const Secret& secret, Side side, const Nonce& engine, const Nonce& launcher) {
    constexpr std::string_view launcherLabel = "anyps5-online/1 launcher";
    constexpr std::string_view engineLabel = "anyps5-online/1 engine";
    const auto label = side == Side::Launcher ? launcherLabel : engineLabel;
    std::vector<std::uint8_t> input(label.begin(), label.end());
    input.insert(input.end(), engine.begin(), engine.end());
    input.insert(input.end(), launcher.begin(), launcher.end());
    ProofBytes proof{};
    const auto* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!info || mbedtls_md_hmac(info, secret.data(), secret.size(), input.data(), input.size(), proof.data()) != 0)
        throw std::runtime_error("online bridge: HMAC-SHA-256 is not available");
    return proof;
}

bool SameProof(const ProofBytes& left, const ProofBytes& right) {
    std::uint8_t difference = 0;
    for (std::size_t index = 0; index < left.size(); ++index) difference |= static_cast<std::uint8_t>(left[index] ^ right[index]);
    return difference == 0;
}

std::optional<Secret> ParseSecret(std::string_view hex) {
    if (hex.size() != SecretSize * 2) return std::nullopt;
    Secret secret{};
    for (std::size_t index = 0; index < SecretSize; ++index) {
        const int high = hexDigit(hex[index * 2]);
        const int low = hexDigit(hex[index * 2 + 1]);
        if (high < 0 || low < 0) return std::nullopt;
        secret[index] = static_cast<std::uint8_t>(high << 4 | low);
    }
    return secret;
}

Nonce RandomNonce() {
    std::random_device device;
    Nonce nonce{};
    for (std::size_t index = 0; index < nonce.size(); index += 4) {
        const auto word = device();
        for (std::size_t byte = 0; byte < 4; ++byte) nonce[index + byte] = static_cast<std::uint8_t>(word >> (8 * byte));
    }
    return nonce;
}

}
