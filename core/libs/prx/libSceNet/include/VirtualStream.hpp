#ifndef CORE_LIBS_PRX_LIBSCENET_VIRTUALSTREAM_HPP
#define CORE_LIBS_PRX_LIBSCENET_VIRTUALSTREAM_HPP

#include "prx/libSceNet/include/VirtualNet.hpp"
#include <chrono>
#include <cstdint>
#include <optional>

// Stream P2P sockets (type 10) over the online bridge. The game's socket stays a host TCP socket
// on 127.0.0.1, so poll, epoll, non-blocking mode, timeouts and shutdown keep working; the engine
// holds the other end of each connection and carries its bytes as Stream frames:
//
// - A listener listens on a loopback port of its own and is registered under its port and virtual
//   port. A stream the launcher opens to them is connected into that listener from an engine
//   socket, whose port tells accept which player it came from.
// - A connecting socket is bound to a loopback port, the stream is opened toward the peer, and the
//   socket connects to the engine's relay listener, which pairs it with the stream by that port.
//
// Each paired connection has a reader (game -> launcher) and a writer (launcher -> game) thread.
namespace VirtualStream {

// Registers a listener; false when another socket listens on the same port and virtual port.
bool Listen(std::uint16_t port, std::uint16_t vport, std::uint16_t nativePort, int descriptor);
// Drops the listener of a socket that closes.
void Forget(int descriptor);

struct Opening {
    std::uint32_t id = 0;
    // The engine's relay listener, which the game's socket connects to next.
    std::uint16_t relayPort = 0;
};

// Opens a stream from the game's (port, virtual port) to the peer's; `guestPort` is the
// loopback port the game's socket is bound to. Nothing when the bridge is down.
std::optional<Opening> Open(std::uint32_t peer, std::uint16_t peerPort, std::uint16_t peerVport, std::uint16_t localPort, std::uint16_t localVport,
                            std::uint16_t guestPort);

enum class Answer { Accepted, Refused, TimedOut, Broken };
// Waits for the peer to accept or refuse a stream opened with Open.
Answer Wait(std::uint32_t id, std::chrono::milliseconds timeout);
// Gives up a stream whose socket never connected.
void Abandon(std::uint32_t id);

// The player behind a connection accepted from a listener, by the port it came from; nothing for
// a connection that is not one of the engine's (another program on the machine).
std::optional<VirtualNet::Source> Accepted(std::uint16_t enginePort);

}

#endif
