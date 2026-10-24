#include "prx/libSceNetCtl/include/OnlineEnvironment.hpp"
#include <charconv>
#include <cstdlib>
#include <stdexcept>

namespace Online {

std::optional<Endpoint> ParseEndpoint(const char* address, const char* secret) {
    const bool hasAddress = address != nullptr && *address != '\0';
    const bool hasSecret = secret != nullptr && *secret != '\0';
    if (!hasAddress && !hasSecret) return std::nullopt;
    if (!hasAddress) throw std::runtime_error(std::string(SecretVariable) + " is set without " + EndpointVariable);
    const std::string_view value(address);
    constexpr std::string_view host = "127.0.0.1:";
    const auto bad = std::runtime_error(std::string(EndpointVariable) + " must be 127.0.0.1:<port from 1 to 65535>, not \"" + std::string(value) + "\"");
    if (!value.starts_with(host)) throw bad;
    const auto digits = value.substr(host.size());
    unsigned port = 0;
    const auto [end, error] = std::from_chars(digits.data(), digits.data() + digits.size(), port);
    if (digits.empty() || error != std::errc{} || end != digits.data() + digits.size() || port == 0 || port > 65535) throw bad;
    if (!hasSecret) throw std::runtime_error(std::string(EndpointVariable) + " is set without " + SecretVariable);
    const auto parsed = Wire::ParseSecret(secret);
    if (!parsed) throw std::runtime_error(std::string(SecretVariable) + " must be 64 hexadecimal digits (32 bytes)");
    return Endpoint{static_cast<std::uint16_t>(port), *parsed};
}

std::optional<Endpoint> BridgeEndpoint() {
    return ParseEndpoint(std::getenv(EndpointVariable), std::getenv(SecretVariable));
}

std::optional<std::string> ObservationPath() {
    const char* value = std::getenv(ObservationVariable);
    if (value == nullptr || *value == '\0') return std::nullopt;
    return std::string(value);
}

}
