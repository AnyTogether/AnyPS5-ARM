#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINEENVIRONMENT_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINEENVIRONMENT_HPP

#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace Online {

constexpr const char* EndpointVariable = "ANYPS5_ONLINE";
constexpr const char* SecretVariable = "ANYPS5_ONLINE_SECRET";
constexpr const char* ObservationVariable = "ANYPS5_ONLINE_LOG";

struct Endpoint {
    std::uint16_t port = 0;
    Wire::Secret secret{};
};

std::optional<Endpoint> ParseEndpoint(const char* address, const char* secret);
std::optional<Endpoint> BridgeEndpoint();
std::optional<std::string> ObservationPath();

}

#endif
