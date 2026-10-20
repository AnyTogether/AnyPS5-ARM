#include <cstdint>
#include <cstddef>
#include <cstring>
#include <limits>
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
constexpr int SCE_VOICE_ERROR_LIBVOICEQOS_NOT_INIT = static_cast<int>(0x804E0901);
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
    qos.nextId = qos.nextId == std::numeric_limits<std::int32_t>::max() ? 1 : qos.nextId + 1;
    return id;
}

int CreateEndpoint(std::int32_t* id, std::map<std::int32_t, Endpoint>& endpoints, QoS& qos) {
    if (!id) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    *id = NewId(qos);
    endpoints.emplace(*id, Endpoint{});
    return 0;
}

int DeleteEndpoint(std::int32_t id, std::map<std::int32_t, Endpoint>& endpoints) {
    return endpoints.erase(id) != 0 ? 0 : SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
}

int SetAttribute(std::map<std::int32_t, Endpoint>& endpoints, std::int32_t id, std::int32_t attribute, const void* value, std::int32_t size) {
    const auto endpoint = endpoints.find(id);
    if (endpoint == endpoints.end() || !value) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
    if (size > 0) {
        const auto* bytes = static_cast<const std::uint8_t*>(value);
        endpoint->second[attribute].assign(bytes, bytes + size);
    } else {
        endpoint->second[attribute].clear();
    }
    return 0;
}

template<typename Body>
int Locked(Body&& body) {
    auto& qos = State();
    std::lock_guard lock(qos.mutex);
    if (!qos.initialized) return SCE_VOICE_ERROR_LIBVOICEQOS_NOT_INIT;
    return body(qos);
}

}

extern "C" {

int APS5_VABI sceVoiceQoSInit(void* memBlock, uint32_t memSize, int32_t appType) {
    auto& qos = State();
    std::lock_guard lock(qos.mutex);
    if (qos.initialized) return SCE_VOICE_ERROR_LIBVOICEQOS_INITIALIZED;
    if (!memBlock || memSize != VOICE_QOS_MEMORY_SIZE || (appType != VOICE_QOS_APP_TYPE_GAME && appType != VOICE_QOS_APP_TYPE_10000000)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
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

int APS5_VABI sceVoiceQoSCreateLocalEndpoint(int32_t* localId, int32_t userId, int32_t deviceInId, int32_t deviceOutId) {
    (void)userId;
    (void)deviceInId;
    (void)deviceOutId;
    return Locked([&](QoS& qos) { return CreateEndpoint(localId, qos.locals, qos); });
}

int APS5_VABI sceVoiceQoSDeleteLocalEndpoint(int32_t localId) {
    return Locked([&](QoS& qos) { return DeleteEndpoint(localId, qos.locals); });
}

int APS5_VABI sceVoiceQoSCreateRemoteEndpoint(int32_t* remoteId) {
    return Locked([&](QoS& qos) { return CreateEndpoint(remoteId, qos.remotes, qos); });
}

int APS5_VABI sceVoiceQoSDeleteRemoteEndpoint(int32_t remoteId) {
    return Locked([&](QoS& qos) { return DeleteEndpoint(remoteId, qos.remotes); });
}

int APS5_VABI sceVoiceQoSConnect(int32_t* connectionId, int32_t localId, int32_t remoteId) {
    return Locked([&](QoS& qos) {
        if (!connectionId || !qos.locals.contains(localId) || !qos.remotes.contains(remoteId)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        *connectionId = NewId(qos);
        qos.connections.emplace(*connectionId, Connection{localId, remoteId});
        return 0;
    });
}

int APS5_VABI sceVoiceQoSDisconnect(int32_t connectionId) {
    return Locked([&](QoS& qos) { return qos.connections.erase(connectionId) != 0 ? 0 : SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID; });
}

int APS5_VABI sceVoiceQoSSetConnectionAttribute() {
 NotImplemented_nid_no_patch(__func__);
 return 0;
}

int APS5_VABI sceVoiceQoSSetLocalEndpointAttribute(int32_t localId, int32_t attributeId, const void* value, int32_t size) {
    return Locked([&](QoS& qos) { return SetAttribute(qos.locals, localId, attributeId, value, size); });
}

int APS5_VABI sceVoiceQoSSetRemoteEndpointAttribute(int32_t remoteId, int32_t attributeId, const void* value, int32_t size) {
    return Locked([&](QoS& qos) { return SetAttribute(qos.remotes, remoteId, attributeId, value, size); });
}

int APS5_VABI sceVoiceQoSReadPacket(int32_t connectionId, void* data, uint32_t* size) {
    return Locked([&](QoS& qos) {
        if (!data || !size || !qos.connections.contains(connectionId)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        *size = 0;
        return 0;
    });
}

int APS5_VABI sceVoiceQoSWritePacket(int32_t connectionId, const void* data, uint32_t* size) {
    return Locked([&](QoS& qos) {
        if (!data || !size || !qos.connections.contains(connectionId)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        return 0;
    });
}

// Reports a value the title set; the defaults of attributes never set are unknown, so those fail.
int APS5_VABI sceVoiceQoSGetLocalEndpointAttribute(int32_t localId, int32_t attributeId, void* value, int32_t size) {
    return Locked([&](QoS& qos) {
        const auto endpoint = qos.locals.find(localId);
        if (endpoint == qos.locals.end() || !value || size <= 0) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        const auto attribute = endpoint->second.find(attributeId);
        if (attribute == endpoint->second.end() || attribute->second.size() != static_cast<std::size_t>(size)) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        std::memcpy(value, attribute->second.data(), attribute->second.size());
        return 0;
    });
}

int APS5_VABI sceVoiceQoSGetRemoteEndpointAttribute(int32_t remoteId, int32_t attributeId, const void* value, int32_t size) {
    (void)remoteId;
    (void)attributeId;
    (void)value;
    (void)size;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSGetConnectionAttribute(int32_t connectionId, int32_t attributeId, void* value, int32_t size) {
    (void)connectionId;
    (void)attributeId;
    (void)value;
    (void)size;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSGetLocalEndpoint(int32_t connectionId, int32_t* localId) {
    return Locked([&](QoS& qos) {
        if (!localId) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        const auto it = qos.connections.find(connectionId);
        if (it == qos.connections.end()) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        *localId = it->second.local;
        return 0;
    });
}

int APS5_VABI sceVoiceQoSGetRemoteEndpoint(int32_t connectionId, int32_t* remoteId) {
    return Locked([&](QoS& qos) {
        if (!remoteId) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        const auto it = qos.connections.find(connectionId);
        if (it == qos.connections.end()) return SCE_VOICE_ERROR_LIBVOICEQOS_ARGUMENT_INVALID;
        *remoteId = it->second.remote;
        return 0;
    });
}

int APS5_VABI sceVoiceQoSEnableChat() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSDisableChat() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSGetStatus(int32_t connectionId, int32_t statusId, void* value, int32_t size) {
    (void)connectionId;
    (void)statusId;
    (void)value;
    (void)size;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSDebugGetStatus() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSInitHQ() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSSetMode() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceVoiceQoSTerminate() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
