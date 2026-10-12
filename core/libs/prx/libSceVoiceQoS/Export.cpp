#include <cstdint>
#include <cstddef>
#include <climits>
#include <cstring>
#include <map>
#include <mutex>
#include <utility>
#include <vector>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr std::int32_t VOICE_QOS_APP_TYPE_GAME = 0x20000000;
constexpr std::int32_t VOICE_QOS_APP_TYPE_10000000 = 0x10000000;
constexpr std::uint32_t VOICE_QOS_MEMORY_SIZE = 0x40000;
constexpr int SCE_VOICE_ERROR_LIBVOICEQOS_NOT_INITIALIZED = static_cast<int>(0x804E0901);
constexpr int SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID = static_cast<int>(0x804E0902);
constexpr int SCE_VOICE_ERROR_LIBVOICEQOS_INITIALIZED = static_cast<int>(0x804E0905);

// An endpoint keeps the attribute values the title sets, by attribute id, to report them back.
using Endpoint = std::map<std::int32_t, std::vector<std::uint8_t>>;

struct Connection {
    std::int32_t local;
    std::int32_t remote;
};

// Endpoints and connections are bookkeeping only: there is no microphone to encode from and no voice
// output for received packets, so a connection never has a packet to send and drops what it receives.
struct QoS {
    std::mutex mutex;
    bool initialized = false;
    std::int32_t nextId = 1;
    std::map<std::int32_t, Endpoint> locals;
    std::map<std::int32_t, Endpoint> remotes;
    std::map<std::int32_t, Connection> connections;
};

QoS& State() {
    static QoS qos;
    return qos;
}

std::int32_t NewId(QoS& qos) {
    const std::int32_t id = qos.nextId;
    qos.nextId = qos.nextId == INT_MAX ? 1 : qos.nextId + 1;
    return id;
}

int CreateEndpoint(std::int32_t* id, std::map<std::int32_t, Endpoint>& endpoints, QoS& qos) {
    if (!id) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    *id = NewId(qos);
    endpoints.emplace(*id, Endpoint{});
    return 0;
}

// An endpoint still used by a connection cannot be deleted.
int DeleteEndpoint(std::int32_t id, std::map<std::int32_t, Endpoint>& endpoints, std::int32_t Connection::*side, const QoS& qos) {
    if (!endpoints.contains(id)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    for (const auto& entry : qos.connections) {
        if (entry.second.*side == id) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    }
    endpoints.erase(id);
    return 0;
}

int SetAttribute(std::map<std::int32_t, Endpoint>& endpoints, std::int32_t id, std::int32_t attribute, const void* value, std::int32_t size) {
    const auto endpoint = endpoints.find(id);
    if (endpoint == endpoints.end() || !value || size <= 0) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    const auto* bytes = static_cast<const std::uint8_t*>(value);
    endpoint->second[attribute].assign(bytes, bytes + size);
    return 0;
}

template<typename Body>
int Locked(Body&& body) {
    auto& qos = State();
    std::lock_guard lock(qos.mutex);
    if (!qos.initialized) return SCE_VOICE_ERROR_LIBVOICEQOS_NOT_INITIALIZED;
    return body(qos);
}

}

extern "C" {

int APS5_VABI sceVoiceQoSInit(void* mem_block, uint32_t mem_size, int32_t app_type) {
    auto& qos = State();
    std::lock_guard lock(qos.mutex);
    if (qos.initialized) return SCE_VOICE_ERROR_LIBVOICEQOS_INITIALIZED;
    if (!mem_block || mem_size != VOICE_QOS_MEMORY_SIZE || (app_type != VOICE_QOS_APP_TYPE_GAME && app_type != VOICE_QOS_APP_TYPE_10000000)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    qos.initialized = true;
    return 0;
}

int APS5_VABI sceVoiceQoSEnd() {
    return Locked([](QoS& qos) {
        qos.connections.clear();
        qos.locals.clear();
        qos.remotes.clear();
        qos.initialized = false;
        return 0;
    });
}

int APS5_VABI sceVoiceQoSCreateLocalEndpoint(int32_t* local_id, int32_t user_id, int32_t device) {
    (void)user_id;
    (void)device;
    return Locked([&](QoS& qos) { return CreateEndpoint(local_id, qos.locals, qos); });
}

int APS5_VABI sceVoiceQoSDeleteLocalEndpoint(int32_t local_id) {
    return Locked([&](QoS& qos) { return DeleteEndpoint(local_id, qos.locals, &Connection::local, qos); });
}

int APS5_VABI sceVoiceQoSCreateRemoteEndpoint(int32_t* remote_id) {
    return Locked([&](QoS& qos) { return CreateEndpoint(remote_id, qos.remotes, qos); });
}

int APS5_VABI sceVoiceQoSDeleteRemoteEndpoint(int32_t remote_id) {
    return Locked([&](QoS& qos) { return DeleteEndpoint(remote_id, qos.remotes, &Connection::remote, qos); });
}

int APS5_VABI sceVoiceQoSConnect(int32_t* connection_id, int32_t local_id, int32_t remote_id) {
    return Locked([&](QoS& qos) {
        if (!connection_id || !qos.locals.contains(local_id) || !qos.remotes.contains(remote_id)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        for (const auto& entry : qos.connections) {
            if (entry.second.local == local_id && entry.second.remote == remote_id) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        }
        *connection_id = NewId(qos);
        qos.connections.emplace(*connection_id, Connection{local_id, remote_id});
        return 0;
    });
}

int APS5_VABI sceVoiceQoSDisconnect(int32_t connection_id) {
    return Locked([&](QoS& qos) { return qos.connections.erase(connection_id) != 0 ? 0 : SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID; });
}

int APS5_VABI sceVoiceQoSSetConnectionAttribute() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSSetLocalEndpointAttribute(int32_t local_id, int32_t attribute_id, const void* value, int32_t size) {
    return Locked([&](QoS& qos) { return SetAttribute(qos.locals, local_id, attribute_id, value, size); });
}

// Reports a value the title set; the defaults of attributes never set are unknown, so those fail.
int APS5_VABI sceVoiceQoSGetLocalEndpointAttribute(int32_t local_id, int32_t attribute_id, void* value, int32_t size) {
    return Locked([&](QoS& qos) {
        const auto endpoint = qos.locals.find(local_id);
        if (endpoint == qos.locals.end() || !value || size <= 0) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        const auto attribute = endpoint->second.find(attribute_id);
        if (attribute == endpoint->second.end() || attribute->second.size() != static_cast<std::size_t>(size)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        std::memcpy(value, attribute->second.data(), attribute->second.size());
        return 0;
    });
}

int APS5_VABI sceVoiceQoSSetRemoteEndpointAttribute(int32_t remote_id, int32_t attribute_id, const void* value, int32_t size) {
    return Locked([&](QoS& qos) { return SetAttribute(qos.remotes, remote_id, attribute_id, value, size); });
}

int APS5_VABI sceVoiceQoSReadPacket(int32_t connection_id, void* data, uint32_t* size) {
    return Locked([&](QoS& qos) {
        if (!data || !size || !qos.connections.contains(connection_id)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        *size = 0;
        return 0;
    });
}

int APS5_VABI sceVoiceQoSWritePacket(int32_t connection_id, const void* data, uint32_t* size) {
    return Locked([&](QoS& qos) {
        if (!data || !size || !qos.connections.contains(connection_id)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        return 0;
    });
}

}
