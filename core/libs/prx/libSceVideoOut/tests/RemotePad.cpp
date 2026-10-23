#include "prx/libSceVideoOut/include/RemotePad.hpp"
#include <arpa/inet.h>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <iostream>
#include <limits>
#include <netinet/in.h>
#include <optional>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename T>
void put(std::vector<std::uint8_t>& bytes, std::size_t offset, T value) {
    std::memcpy(bytes.data() + offset, &value, sizeof(T));
}

template <typename T>
T get(const std::uint8_t* bytes, std::size_t offset) {
    T value;
    std::memcpy(&value, bytes + offset, sizeof(T));
    return value;
}

std::vector<std::uint8_t> fullPacket(std::uint32_t sequence, std::uint64_t session = 99) {
    std::vector<std::uint8_t> bytes(80, 0);
    put<std::uint32_t>(bytes, 0, RemotePad::InputMagic);
    put<std::uint16_t>(bytes, 4, RemotePad::Version);
    put<std::uint16_t>(bytes, 6, static_cast<std::uint16_t>(RemotePad::InputSize));
    put<std::uint32_t>(bytes, 8, sequence);
    put<std::uint32_t>(bytes, 12, 1);
    put<std::uint64_t>(bytes, 16, 123456);
    put<std::uint64_t>(bytes, 24, session);
    put<std::uint32_t>(bytes, 32, 0x4000u | 0x0010u | 0x40000000u);
    bytes[36] = 255;
    bytes[37] = 0;
    bytes[38] = 128;
    bytes[39] = 64;
    bytes[40] = 200;
    bytes[41] = 0;
    bytes[44] = 1;
    bytes[45] = 3;
    put<std::uint16_t>(bytes, 46, 1919);
    put<std::uint16_t>(bytes, 48, 1079);
    put<float>(bytes, 56, 0.0f);
    put<float>(bytes, 60, 9.8f);
    put<float>(bytes, 64, 0.0f);
    put<float>(bytes, 68, 0.5f);
    return bytes;
}

std::span<const std::uint8_t> view(const std::vector<std::uint8_t>& bytes) {
    return {bytes.data(), bytes.size()};
}

void decodesAFullPacket() {
    const auto input = RemotePad::DecodeInput(view(fullPacket(7)));
    require(input.has_value(), "a full packet decodes");
    require(input->sequence == 7 && input->sentMicros == 123456, "the sequence and the send time are read");
    const auto& state = input->state;
    require(state.buttons == 0x4010u, "unknown button bits are masked off");
    require(state.sticks == std::array<std::uint8_t, 4>{255, 0, 128, 64}, "the sticks are read");
    require(state.analogButtonsL2 == 200 && state.analogButtonsR2 == 0, "the triggers are read");
    require(state.touch[0] == PadTouchPoint{true, 1919, 1079, 3}, "the first touch point is read");
    require(!state.touch[1].active, "the second touch point is inactive");
    require(state.hasMotion && std::fabs(state.accel[1] - 9.8f) < 1e-5f && std::fabs(state.gyro[0] - 0.5f) < 1e-5f, "motion is read");
}

void rejectsBadPackets() {
    auto magic = fullPacket(1);
    put<std::uint32_t>(magic, 0, 0x12345678u);
    require(!RemotePad::DecodeInput(view(magic)), "a wrong magic is dropped");
    auto version = fullPacket(1);
    put<std::uint16_t>(version, 4, 2);
    require(!RemotePad::DecodeInput(view(version)), "another version is dropped");
    auto size = fullPacket(1);
    put<std::uint16_t>(size, 6, 79);
    require(!RemotePad::DecodeInput(view(size)), "a wrong size field is dropped");
    auto shorter = fullPacket(1);
    shorter.resize(79);
    require(!RemotePad::DecodeInput(view(shorter)), "a short datagram is dropped");
    auto touch = fullPacket(1);
    put<std::uint16_t>(touch, 46, 1920);
    require(!RemotePad::DecodeInput(view(touch)), "a touch point outside the touchpad is dropped");
    auto motion = fullPacket(1);
    put<float>(motion, 68, std::numeric_limits<float>::quiet_NaN());
    require(!RemotePad::DecodeInput(view(motion)), "a non-finite motion value is dropped");
}

void mergeTakesTheStrongerInput() {
    PadInputState controller;
    controller.buttons = 0x4000;
    controller.analogButtonsL2 = 10;
    PadInputState remote;
    remote.buttons = 0x2000;
    remote.sticks[0] = 250;
    remote.analogButtonsL2 = 200;
    const auto merged = RemotePad::Merge(controller, remote);
    require(merged.buttons == 0x6000u, "buttons from both are held");
    require(merged.sticks[0] == 250 && merged.analogButtonsL2 == 200, "the stronger stick and trigger win");
    controller.sticks[0] = 0;
    remote.sticks[0] = 140;
    require(RemotePad::Merge(controller, remote).sticks[0] == 0, "the stick furthest from the centre wins");
    controller.hasMotion = true;
    controller.gyro = {1.0f, 2.0f, 3.0f};
    remote.gyro = {9.0f, 9.0f, 9.0f};
    require(RemotePad::Merge(controller, remote).gyro[0] == 1.0f, "the controller's motion stays without remote motion");
    remote.hasMotion = true;
    require(RemotePad::Merge(controller, remote).gyro[0] == 9.0f, "remote motion replaces the controller's");
}

void encodesOutput() {
    RemotePad::Input last{9, 555, {}};
    PadOutputState output;
    output.vibrationLarge = 10;
    output.audioVibrationLarge = 40;
    output.vibrationSmall = 3;
    output.lightBarValid = true;
    output.lightBar[0] = 1;
    output.lightBar[1] = 2;
    output.lightBar[2] = 3;
    output.trigger[0].fallback = 7;
    output.trigger[1].fallback = 8;
    const auto bytes = RemotePad::EncodeOutput(last, output);
    require(get<std::uint32_t>(bytes.data(), 0) == RemotePad::OutputMagic, "output magic");
    require(get<std::uint16_t>(bytes.data(), 4) == 1 && get<std::uint16_t>(bytes.data(), 6) == 32, "output version and size");
    require(get<std::uint32_t>(bytes.data(), 8) == 9 && get<std::uint64_t>(bytes.data(), 16) == 555, "the input is echoed");
    require(bytes[24] == 40 && bytes[25] == 3, "vibration takes the stronger source");
    require(bytes[26] == 1 && bytes[27] == 1 && bytes[28] == 2 && bytes[29] == 3, "the light bar is sent");
    require(bytes[30] == 7 && bytes[31] == 8, "the trigger fallbacks are sent");
}

struct Peer {
    int socket = -1;
    std::uint16_t port = 0;

    Peer() {
        socket = ::socket(AF_INET, SOCK_DGRAM, 0);
        require(socket >= 0, "open the test socket");
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        require(::bind(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0, "bind the test socket");
        socklen_t length = sizeof(address);
        require(::getsockname(socket, reinterpret_cast<sockaddr*>(&address), &length) == 0, "read the test port");
        port = ntohs(address.sin_port);
        timeval timeout{0, 200000};
        ::setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    }

    ~Peer() { ::close(socket); }

    std::optional<std::vector<std::uint8_t>> receive() const {
        std::vector<std::uint8_t> bytes(256);
        const auto got = ::recv(socket, bytes.data(), bytes.size(), 0);
        if (got < 0) return std::nullopt;
        bytes.resize(static_cast<std::size_t>(got));
        return bytes;
    }

    void send(const std::vector<std::uint8_t>& bytes, std::uint16_t to) const {
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons(to);
        require(::sendto(socket, bytes.data(), bytes.size(), 0, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == static_cast<ssize_t>(bytes.size()), "send from the test socket");
    }
};

std::optional<RemotePad::Input> pollFor(RemotePad::Channel& channel, std::chrono::steady_clock::time_point now) {
    for (int attempt = 0; attempt < 50; ++attempt) {
        if (auto input = channel.Poll(now)) return input;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    return std::nullopt;
}

void loopbackChannel() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto start = std::chrono::steady_clock::now();
    channel.Greet(start);
    const auto hello = launcher.receive();
    require(hello && hello->size() == RemotePad::HelloSize && get<std::uint32_t>(hello->data(), 0) == RemotePad::HelloMagic, "the channel greets the launcher");
    launcher.send(fullPacket(5), channel.Port());
    const auto input = pollFor(channel, start);
    require(input && input->sequence == 5, "an input reaches the channel");
    channel.Answer(*input, PadOutputState{});
    const auto output = launcher.receive();
    require(output && output->size() == RemotePad::OutputSize && get<std::uint32_t>(output->data(), 8) == 5, "the answer reaches the launcher");
    channel.Greet(start + std::chrono::milliseconds(200));
    require(!launcher.receive(), "no hello within a second of the last");
    channel.Greet(start + std::chrono::milliseconds(1100));
    require(launcher.receive().has_value(), "the hello goes on after an input, so a restarted launcher finds the game again");
}

void newSessionStartsANewSequence() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto now = std::chrono::steady_clock::now();
    launcher.send(fullPacket(50000, 1), channel.Port());
    require(pollFor(channel, now)->sequence == 50000, "the first session's input arrives");
    launcher.send(fullPacket(1, 2), channel.Port());
    const auto restarted = pollFor(channel, now);
    require(restarted && restarted->sequence == 1, "a phone that starts again under a new session is not ignored");
    launcher.send(fullPacket(0, 2), channel.Port());
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    require(!channel.Poll(now), "older inputs of the new session are still ignored");
}

void greetsEverySecond() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto start = std::chrono::steady_clock::now();
    channel.Greet(start);
    require(launcher.receive().has_value(), "the first hello is sent");
    channel.Greet(start + std::chrono::milliseconds(200));
    require(!launcher.receive(), "the next hello waits a second");
    channel.Greet(start + std::chrono::milliseconds(1100));
    require(launcher.receive().has_value(), "a hello follows a second later");
}

// The hello says which player the channel's phone is, so the launcher can show it.
void helloNamesThePlayer() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto start = std::chrono::steady_clock::now();
    channel.Greet(start);
    auto hello = launcher.receive();
    require(hello && hello->size() == RemotePad::HelloSize && (*hello)[8] == 0, "a phone that is no player yet says 0");
    channel.SetPlayer(2);
    channel.Greet(start + std::chrono::milliseconds(10));
    hello = launcher.receive();
    require(hello && (*hello)[8] == 2, "a new player is said at once, counting from 1");
    channel.Greet(start + std::chrono::milliseconds(20));
    require(!launcher.receive(), "and then once a second again");
}

void olderSequenceIsIgnored() {
    require(RemotePad::IsNewer(8, 7) && RemotePad::IsNewer(0, 0xFFFFFFFFu), "later sequences are newer, also across the wrap");
    require(!RemotePad::IsNewer(7, 8) && !RemotePad::IsNewer(7, 7), "earlier and equal sequences are not newer");
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto now = std::chrono::steady_clock::now();
    launcher.send(fullPacket(5), channel.Port());
    require(pollFor(channel, now)->sequence == 5, "the first input arrives");
    launcher.send(fullPacket(4), channel.Port());
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    require(!channel.Poll(now), "an older input is ignored");
}

void answerTellsHowLongTheInputWaited() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    launcher.send(fullPacket(3), channel.Port());
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    const auto input = channel.Poll(std::chrono::steady_clock::now());
    require(input && input->waitMicros >= 25000 && input->waitMicros < 1000000, "the time the input waited in the socket is measured");
    channel.Answer(*input, PadOutputState{});
    const auto output = launcher.receive();
    require(output && get<std::uint32_t>(output->data(), 12) == input->waitMicros, "the answer carries the wait");
}

void remoteReleasedAfterSilence() {
    const auto seen = std::chrono::steady_clock::now();
    RemotePad::Input input;
    input.state.buttons = 0x4000;
    input.state.sticks[0] = 255;
    require(RemotePad::Current(input, seen, seen + std::chrono::milliseconds(499)).buttons == 0x4000u, "a recent input holds");
    const auto released = RemotePad::Current(input, seen, seen + std::chrono::milliseconds(500));
    require(released.buttons == 0 && released.sticks == PadInputState{}.sticks, "half a second of silence releases everything");
    const auto none = RemotePad::Current(std::nullopt, seen, seen);
    require(none.buttons == 0 && none.sticks == PadInputState{}.sticks, "no input is released");
}

void environment() {
    ::unsetenv("ANYPS5_REMOTE_PAD");
    require(RemotePad::OpenFromEnvironment() == nullptr, "no channel without ANYPS5_REMOTE_PAD");
    ::setenv("ANYPS5_REMOTE_PAD", "", 1);
    require(RemotePad::OpenFromEnvironment() == nullptr, "no channel for an empty ANYPS5_REMOTE_PAD");
    for (const char* value : {"127.0.0.1:0", "10.0.0.1:5000", "127.0.0.1:x", "127.0.0.1:70000"}) {
        ::setenv("ANYPS5_REMOTE_PAD", value, 1);
        bool threw = false;
        try {
            RemotePad::OpenFromEnvironment();
        } catch (const std::runtime_error& error) {
            threw = std::string(error.what()).find("ANYPS5_REMOTE_PAD") != std::string::npos;
        }
        require(threw, "a malformed ANYPS5_REMOTE_PAD stops with an error naming it");
    }
    ::setenv("ANYPS5_REMOTE_PAD", "127.0.0.1:5000", 1);
    require(RemotePad::OpenFromEnvironment() != nullptr, "a loopback address opens a channel");
    ::unsetenv("ANYPS5_REMOTE_PAD");
}


void onlyRealInputWantsAPlayer() {
    PadInputState state;
    require(!RemotePad::Wants(state), "a pad at rest does not ask for a player");
    state.hasMotion = true;
    state.gyro = {1.0f, 0.0f, 0.0f};
    require(!RemotePad::Wants(state), "moving the device is not asking for a player");
    state.sticks[0] = 150;
    require(!RemotePad::Wants(state), "a stick near the centre is not asking");
    state.sticks[0] = 230;
    require(RemotePad::Wants(state), "a stick pushed asks for a player");
    state = PadInputState{};
    state.buttons = 0x4000u;
    require(RemotePad::Wants(state), "a button asks for a player");
    state = PadInputState{};
    state.analogButtonsR2 = 40;
    require(RemotePad::Wants(state), "a trigger asks for a player");
    state = PadInputState{};
    state.touch[0].active = true;
    require(RemotePad::Wants(state), "a touch asks for a player");
}

void seatsGoInOrderAndComeBack() {
    RemotePad::Seats seats;
    require(seats.Seat(7, false) == -1, "a device that does not ask gets no player");
    require(seats.Seat(7, true) == 0, "the first device to ask is the first player");
    require(seats.Seat(7, false) == 0, "a device keeps its player while it rests");
    require(seats.Seat(RemotePad::RemoteDevice(0), true) == 1, "the next device is the second player");
    require(seats.Seat(9, true) == 2, "then the third");
    require(seats.Held(1) && seats.Of(RemotePad::RemoteDevice(0)) == 1, "the seat is held");
    require(seats.Leave(7) == 0, "leaving frees the player it held");
    require(seats.Leave(7) == -1, "leaving twice frees nothing");
    require(!seats.Held(0), "the first player is free again");
    require(seats.Seat(11, true) == 0, "a new device takes the lowest free player");
    require(seats.Seat(12, true) == 3, "and the last");
    require(seats.Seat(13, true) == -1, "a fifth device gets no player");
    require(RemotePad::RemoteDevice(0) != RemotePad::RemoteDevice(1), "phones are told apart");
}

void environmentForMorePlayers() {
    ::unsetenv("ANYPS5_REMOTE_PAD");
    ::setenv("ANYPS5_REMOTE_PAD_2", "127.0.0.1:5002", 1);
    require(RemotePad::OpenAllFromEnvironment().empty(), "no channel for later players without the first");
    ::setenv("ANYPS5_REMOTE_PAD", "127.0.0.1:5001", 1);
    ::setenv("ANYPS5_REMOTE_PAD_4", "127.0.0.1:5004", 1);
    const auto channels = RemotePad::OpenAllFromEnvironment();
    require(channels.size() == 2, "a channel for ANYPS5_REMOTE_PAD and each numbered one, stopping at a gap");
    ::setenv("ANYPS5_REMOTE_PAD_2", "10.0.0.1:5002", 1);
    bool threw = false;
    try {
        RemotePad::OpenAllFromEnvironment();
    } catch (const std::runtime_error& error) {
        threw = std::string(error.what()).find("ANYPS5_REMOTE_PAD_2") != std::string::npos;
    }
    require(threw, "a malformed numbered address stops with an error naming it");
    ::unsetenv("ANYPS5_REMOTE_PAD");
    ::unsetenv("ANYPS5_REMOTE_PAD_2");
    ::unsetenv("ANYPS5_REMOTE_PAD_4");
}

}

int main() try {
    decodesAFullPacket();
    rejectsBadPackets();
    mergeTakesTheStrongerInput();
    encodesOutput();
    loopbackChannel();
    greetsEverySecond();
    helloNamesThePlayer();
    olderSequenceIsIgnored();
    newSessionStartsANewSequence();
    answerTellsHowLongTheInputWaited();
    remoteReleasedAfterSilence();
    environment();
    onlyRealInputWantsAPlayer();
    seatsGoInOrderAndComeBack();
    environmentForMorePlayers();
    std::cout << "remote pad tests passed\n";
    return 0;
} catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
