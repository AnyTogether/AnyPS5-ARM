#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINE_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINE_HPP

#include "prx/libSceNetCtl/include/OnlineBridge.hpp"
#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>

extern "C" bool OnlineEnabled_nid_no_patch();
extern "C" bool OnlineAccount_nid_no_patch(Online::AccountState& out);
extern "C" bool OnlineWeb_nid_no_patch(const Online::Wire::WebRequest& request, std::uint32_t timeoutMilliseconds, Online::Wire::WebReply& reply);
extern "C" bool OnlineObserving_nid_no_patch();
extern "C" bool OnlineSendDatagram_nid_no_patch(const Online::Wire::Datagram& datagram);
extern "C" void OnlineSetDatagramReceiver_nid_no_patch(void (*receiver)(const Online::Wire::Datagram& datagram));
// Game streams (libSceNet's stream P2P sockets); see Bridge::SendStream and SetStreamReceiver.
extern "C" bool OnlineSendStream_nid_no_patch(const Online::Wire::Stream& stream);
extern "C" void OnlineSetStreamReceiver_nid_no_patch(void (*receiver)(const Online::Wire::Stream& stream));
// Push events: the receiver runs on the bridge's reader thread; the dispatcher runs on the game's
// thread from sceNpCheckCallback, where callbacks into the game are safe.
extern "C" void OnlineSetPushReceiver_nid_no_patch(void (*receiver)(const Online::Wire::PushEvent& event));
extern "C" void OnlineSetPushDispatcher_nid_no_patch(void (*dispatcher)());
extern "C" void OnlineDispatchPush_nid_no_patch();
extern "C" void OnlineObserve_nid_no_patch(const char* library, const char* function, const std::string& in, const std::string& out, const std::int64_t* result);

namespace Online {

constexpr std::size_t ObservedBytes = 4096;

class Fields {
public:
    Fields& Int(std::string_view name, std::int64_t value) { return raw(name, std::to_string(value)); }
    Fields& Uint(std::string_view name, std::uint64_t value) { return raw(name, std::to_string(value)); }
    Fields& Hex(std::string_view name, std::uint64_t value) {
        char text[24];
        std::snprintf(text, sizeof(text), "\"0x%llx\"", static_cast<unsigned long long>(value));
        return raw(name, text);
    }
    Fields& Bool(std::string_view name, bool value) { return raw(name, value ? "true" : "false"); }
    Fields& Ptr(std::string_view name, const void* value) { return raw(name, value ? "\"set\"" : "null"); }
    Fields& Str(std::string_view name, const char* value, std::size_t limit = ObservedBytes) {
        if (!value) return raw(name, "null");
        std::size_t size = 0;
        while (size < limit && value[size] != '\0') ++size;
        return Text(name, std::string_view(value, size));
    }
    Fields& Text(std::string_view name, std::string_view value) { return raw(name, quote(value)); }
    Fields& Data(std::string_view name, const void* data, std::size_t size, std::size_t limit = ObservedBytes) {
        if (!data) return raw(name, "null");
        const auto* bytes = static_cast<const unsigned char*>(data);
        const auto kept = size < limit ? size : limit;
        bool text = true;
        for (std::size_t index = 0; index < kept && text; ++index) text = bytes[index] >= 0x20 || bytes[index] == '\n' || bytes[index] == '\r' || bytes[index] == '\t';
        std::string value;
        if (text) {
            value = quote(std::string_view(reinterpret_cast<const char*>(bytes), kept));
        } else {
            static constexpr char digits[] = "0123456789abcdef";
            value = "{\"hex\":\"";
            for (std::size_t index = 0; index < kept; ++index) {
                value += digits[bytes[index] >> 4];
                value += digits[bytes[index] & 15];
            }
            value += "\"}";
        }
        raw(name, value);
        if (kept != size) Uint(std::string(name) + "_size", size);
        return *this;
    }
    const std::string& Json() const {
        if (closed.empty()) closed = "{" + body + "}";
        return closed;
    }
    bool Empty() const { return body.empty(); }

    static std::string quote(std::string_view value) {
        std::string out = "\"";
        for (const unsigned char letter : value) {
            switch (letter) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (letter < 0x20) {
                    char escaped[8];
                    std::snprintf(escaped, sizeof(escaped), "\\u%04x", letter);
                    out += escaped;
                } else {
                    out += static_cast<char>(letter);
                }
            }
        }
        out += "\"";
        return out;
    }

private:
    Fields& raw(std::string_view name, std::string_view value) {
        if (!body.empty()) body += ',';
        body += quote(name);
        body += ':';
        body += value;
        closed.clear();
        return *this;
    }

    std::string body;
    mutable std::string closed;
};

inline bool Observing() {
    static const bool observing = OnlineObserving_nid_no_patch();
    return observing;
}

inline bool Enabled() {
    static const bool enabled = OnlineEnabled_nid_no_patch();
    return enabled;
}

inline std::optional<AccountState> CurrentAccount() {
    if (!Enabled()) return std::nullopt;
    AccountState state;
    if (!OnlineAccount_nid_no_patch(state)) return std::nullopt;
    return state;
}

inline bool SignedIn() {
    const auto state = CurrentAccount();
    return state && state->account.signedIn;
}

class Call {
public:
    Call(const char* library, const char* function) : library(library), function(function), observing(Observing()) {}
    ~Call() {
        if (observing && !recorded) OnlineObserve_nid_no_patch(library, function, in.Json(), out.Json(), nullptr);
    }
    Call(const Call&) = delete;
    Call& operator=(const Call&) = delete;

    template <typename TFill>
    Call& Args(TFill fill) {
        if (observing) fill(in);
        return *this;
    }

    template <typename TResult>
    TResult Return(TResult result) {
        return Return(result, [](Fields&) {});
    }

    template <typename TResult, typename TFill>
    TResult Return(TResult result, TFill fill) {
        if (observing) {
            fill(out);
            const auto value = static_cast<std::int64_t>(result);
            OnlineObserve_nid_no_patch(library, function, in.Json(), out.Json(), &value);
            recorded = true;
        }
        return result;
    }

    template <typename TFill>
    void Done(TFill fill) {
        if (observing) {
            fill(out);
            OnlineObserve_nid_no_patch(library, function, in.Json(), out.Json(), nullptr);
            recorded = true;
        }
    }

private:
    const char* library;
    const char* function;
    const bool observing;
    bool recorded = false;
    Fields in;
    Fields out;
};

}

#endif
