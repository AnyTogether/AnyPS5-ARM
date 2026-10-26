#include "prx/libSceVideoOut/include/RemotePad.hpp"
#include "prx/libSceVideoOut/src/RemotePadSocket.hpp"
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <iostream>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void setVariable(const char* name, const char* value) {
#ifdef _WIN32
    ::_putenv_s(name, value);
#else
    ::setenv(name, value, 1);
#endif
}

void unsetVariable(const char* name) {
#ifdef _WIN32
    ::_putenv_s(name, "");
#else
    ::unsetenv(name);
#endif
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
    RemotePad::Net::Handle socket = RemotePad::Net::None;
    std::uint16_t port = 0;

    Peer() {
        socket = RemotePad::Net::OpenUdp();
        require(socket != RemotePad::Net::None, "open the test socket");
        const auto bound = RemotePad::Net::BindLoopback(socket);
        require(bound.has_value(), "bind the test socket and read its port");
        port = *bound;
        RemotePad::Net::SetReceiveTimeout(socket, std::chrono::milliseconds(200));
    }

    ~Peer() { RemotePad::Net::Close(socket); }

    std::optional<std::vector<std::uint8_t>> receive() const {
        std::vector<std::uint8_t> bytes(256);
        std::optional<std::int64_t> arrived;
        const auto got = RemotePad::Net::Receive(socket, bytes.data(), bytes.size(), arrived);
        if (!got) return std::nullopt;
        bytes.resize(*got);
        return bytes;
    }

    void send(const std::vector<std::uint8_t>& bytes, std::uint16_t to) const {
        require(RemotePad::Net::SendTo(socket, bytes.data(), bytes.size(), to), "send from the test socket");
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

void helloToNoLauncherHoldsNothingBack() {
    std::uint16_t absent = 0;
    {
        Peer gone;
        absent = gone.port;
    }
    RemotePad::Channel channel(absent);
    channel.Greet(std::chrono::steady_clock::now());
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    Peer phone;
    phone.send(fullPacket(6), channel.Port());
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const auto input = channel.Poll(std::chrono::steady_clock::now());
    require(input && input->sequence == 6, "an input after a hello nobody heard is read at once");
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
    if (RemotePad::Net::StampsArrivals) {
        require(input && input->waitMicros >= 25000 && input->waitMicros < 1000000, "the time the input waited in the socket is measured");
    } else {
        require(input && input->waitMicros == 0, "without arrival stamps the wait is said as 0");
    }
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
    unsetVariable("ANYPS5_REMOTE_PAD");
    require(RemotePad::OpenFromEnvironment() == nullptr, "no channel without ANYPS5_REMOTE_PAD");
    setVariable("ANYPS5_REMOTE_PAD", "");
    require(RemotePad::OpenFromEnvironment() == nullptr, "no channel for an empty ANYPS5_REMOTE_PAD");
    for (const char* value : {"127.0.0.1:0", "10.0.0.1:5000", "127.0.0.1:x", "127.0.0.1:70000"}) {
        setVariable("ANYPS5_REMOTE_PAD", value);
        bool threw = false;
        try {
            RemotePad::OpenFromEnvironment();
        } catch (const std::runtime_error& error) {
            threw = std::string(error.what()).find("ANYPS5_REMOTE_PAD") != std::string::npos;
        }
        require(threw, "a malformed ANYPS5_REMOTE_PAD stops with an error naming it");
    }
    setVariable("ANYPS5_REMOTE_PAD", "127.0.0.1:5000");
    require(RemotePad::OpenFromEnvironment() != nullptr, "a loopback address opens a channel");
    unsetVariable("ANYPS5_REMOTE_PAD");
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

// A share play guest's packets carry the player the launcher holds for it (byte 13, 2 to 4): it
// takes that player, or the lowest free one after the first, never the host's first player.
void guestsNeverTakeTheFirstPlayer() {
    auto packet = fullPacket(1);
    require(RemotePad::DecodeInput(view(packet))->seat == 0, "a phone's packet holds no seat");
    packet[13] = 2;
    const auto guest = RemotePad::DecodeInput(view(packet));
    require(guest.has_value() && guest->seat == 2 && guest->state.hasMotion, "a guest's packet names its player and keeps its motion flag");
    packet[13] = 1;
    require(RemotePad::DecodeInput(view(packet))->seat == RemotePad::AssistSeat, "the first player is no seat to hold: 1 marks a helper of it (assist)");
    packet[13] = 5;
    require(RemotePad::DecodeInput(view(packet))->seat == 0, "nor is a fifth");

    RemotePad::Seats seats;
    require(seats.Seat(RemotePad::RemoteDevice(3), true, 2) == 1, "a guest asking first takes its own player, not the first");
    require(!seats.Held(0), "the first player stays free for the host");
    require(seats.Seat(RemotePad::RemoteDevice(2), true, 2) == 2, "a guest whose player is taken gets the lowest free one after the first");
    require(seats.Seat(RemotePad::RemoteDevice(1), true, 4) == 3, "and one holding the fourth gets it");
    require(seats.Seat(RemotePad::RemoteDevice(0), true, 3) == -1, "with players 2 to 4 taken a guest waits");
    require(seats.Seat(7, true) == 0, "while a controller still takes the first player");
}

std::vector<std::uint8_t> pressPacket(std::uint32_t id, std::uint32_t buttons, std::uint16_t holdMillis) {
    std::vector<std::uint8_t> bytes(RemotePad::PressSize, 0);
    put<std::uint32_t>(bytes, 0, RemotePad::PressMagic);
    put<std::uint16_t>(bytes, 4, RemotePad::Version);
    put<std::uint16_t>(bytes, 6, static_cast<std::uint16_t>(RemotePad::PressSize));
    put<std::uint32_t>(bytes, 8, id);
    put<std::uint32_t>(bytes, 12, buttons);
    put<std::uint16_t>(bytes, 16, holdMillis);
    return bytes;
}

// A press (APRP, 24 bytes) holds buttons on the first player's pad for a while without being a
// pad of its own: the launcher's quick menu pauses a game this way whoever holds player 1.
void decodesAPress() {
    const auto press = RemotePad::DecodePress(view(pressPacket(7, 0x0008u | 0x40000000u, 120)));
    require(press.has_value(), "a press decodes");
    require(press->id == 7 && press->buttons == 0x0008u, "its id and buttons are read, unknown bits masked off");
    require(press->hold == std::chrono::milliseconds(120), "its hold is read");
    require(RemotePad::DecodePress(view(pressPacket(1, 0x0008u, 0)))->hold == RemotePad::ShortestHold, "a hold too short for a frame is lengthened");
    require(RemotePad::DecodePress(view(pressPacket(1, 0x0008u, 60000)))->hold == RemotePad::LongestHold, "a long hold is cut");
    require(!RemotePad::DecodeInput(view(pressPacket(1, 0x0008u, 120))), "a press is no input");
    require(!RemotePad::DecodePress(view(fullPacket(1))), "an input is no press");
}

void rejectsBadPresses() {
    auto magic = pressPacket(1, 0x0008u, 120);
    put<std::uint32_t>(magic, 0, RemotePad::InputMagic);
    require(!RemotePad::DecodePress(view(magic)), "a wrong magic is dropped");
    auto version = pressPacket(1, 0x0008u, 120);
    put<std::uint16_t>(version, 4, 2);
    require(!RemotePad::DecodePress(view(version)), "another version is dropped");
    auto size = pressPacket(1, 0x0008u, 120);
    put<std::uint16_t>(size, 6, 23);
    require(!RemotePad::DecodePress(view(size)), "a wrong size field is dropped");
    auto shorter = pressPacket(1, 0x0008u, 120);
    shorter.resize(23);
    require(!RemotePad::DecodePress(view(shorter)), "a short datagram is dropped");
    require(!RemotePad::DecodePress(view(pressPacket(1, 0x40000000u, 120))), "a press of no known button is dropped");
}

void pressesHoldForTheirTime() {
    RemotePad::Presses presses;
    const auto start = std::chrono::steady_clock::now();
    require(presses.Buttons(start) == 0, "nothing is pressed at first");
    presses.Add({1, 0x0008u, std::chrono::milliseconds(120)}, start);
    require(presses.Buttons(start) == 0x0008u, "a press holds its buttons at once");
    require(presses.Buttons(start + std::chrono::milliseconds(119)) == 0x0008u, "and through its hold");
    require(presses.Buttons(start + std::chrono::milliseconds(120)) == 0, "then lets go");
    presses.Add({2, 0x4000u, std::chrono::milliseconds(200)}, start + std::chrono::milliseconds(50));
    require(presses.Buttons(start + std::chrono::milliseconds(100)) == 0x4008u, "presses that overlap are held together");
    require(presses.Buttons(start + std::chrono::milliseconds(200)) == 0x4000u, "each lets go at its own time");
    require(presses.Buttons(start + std::chrono::milliseconds(250)) == 0, "and the last one too");
}

// A press reaches the channel beside the inputs and leaves the phone's order and player alone:
// it is sent a few times in case one is lost, and only its first copy counts.
void channelTakesPresses() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto now = std::chrono::steady_clock::now();
    launcher.send(pressPacket(40, 0x0008u, 120), channel.Port());
    std::vector<RemotePad::Press> taken;
    for (int attempt = 0; attempt < 50 && taken.empty(); ++attempt) {
        require(!channel.Poll(now), "a press is not an input");
        taken = channel.TakePresses();
        if (taken.empty()) std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    require(taken.size() == 1 && taken[0].id == 40 && taken[0].buttons == 0x0008u, "the press is taken from the channel");
    require(channel.TakePresses().empty(), "and taken once");
    launcher.send(pressPacket(40, 0x0008u, 120), channel.Port());
    launcher.send(fullPacket(5), channel.Port());
    const auto input = pollFor(channel, now);
    require(input && input->sequence == 5, "an input after a press arrives in its order");
    require(channel.TakePresses().empty(), "a copy of the last press is dropped");
    launcher.send(pressPacket(41, 0x0008u, 120), channel.Port());
    launcher.send(fullPacket(6), channel.Port());
    require(pollFor(channel, now)->sequence == 6, "the next input follows");
    require(channel.TakePresses().size() == 1, "a new press is taken again");
}

// The hello says the engine takes presses (bit 0 of byte 9), so a launcher knows it may send them.
void helloSaysItTakesPresses() {
    const auto hello = RemotePad::EncodeHello(2);
    require(hello[8] == 2 && (hello[9] & RemotePad::HelloTakesPresses) != 0, "the hello names the player and says presses are taken");
}

// A prompt (APRK) says what text the game asks for: a header, then the title, the placeholder
// and the starting text in UTF-8, each with its length in the header.
void promptRoundTrip() {
    RemotePad::Prompt prompt;
    prompt.id = 12;
    prompt.kind = RemotePad::Prompt::Kind::Dialog;
    prompt.type = 4;
    prompt.enterLabel = 2;
    prompt.multiline = true;
    prompt.maxLength = 16;
    prompt.title = "Name your save";
    prompt.placeholder = "Save 1";
    prompt.text = "Kral \xc3\xbc";
    const auto bytes = RemotePad::EncodePrompt(prompt);
    require(get<std::uint32_t>(bytes.data(), 0) == RemotePad::PromptMagic, "prompt magic");
    require(get<std::uint16_t>(bytes.data(), 4) == 1 && get<std::uint16_t>(bytes.data(), 6) == bytes.size(), "prompt version and size");
    require(bytes.size() == RemotePad::PromptHeaderSize + prompt.title.size() + prompt.placeholder.size() + prompt.text.size(), "header and three strings");
    require(get<std::uint32_t>(bytes.data(), 8) == 12 && bytes[12] == 2 && bytes[13] == 1 && bytes[14] == 4 && bytes[15] == 2, "id, kind, flags, type and Enter label");
    require(get<std::uint16_t>(bytes.data(), 16) == 16, "the most characters");
    const auto decoded = RemotePad::DecodePrompt(view(bytes));
    require(decoded && decoded->id == 12 && decoded->kind == RemotePad::Prompt::Kind::Dialog && decoded->multiline, "the prompt decodes");
    require(decoded->title == prompt.title && decoded->placeholder == prompt.placeholder && decoded->text == prompt.text, "its strings come back");
    require(decoded->type == 4 && decoded->enterLabel == 2 && decoded->maxLength == 16, "with its type, label and length");
    const auto none = RemotePad::DecodePrompt(view(RemotePad::EncodePrompt(RemotePad::Prompt{})));
    require(none && none->id == 0 && none->kind == RemotePad::Prompt::Kind::None, "no prompt is said with id 0");
}

void promptKeepsToItsLimits() {
    RemotePad::Prompt prompt;
    prompt.id = 1;
    prompt.kind = RemotePad::Prompt::Kind::Keyboard;
    prompt.title = std::string(400, 'a');
    prompt.text = std::string(9000, 'b');
    const auto bytes = RemotePad::EncodePrompt(prompt);
    require(bytes.size() <= RemotePad::LargestTextDatagram, "a prompt stays one datagram");
    const auto decoded = RemotePad::DecodePrompt(view(bytes));
    require(decoded && decoded->title.size() == RemotePad::LargestPromptTitle, "a long title is cut");
    require(!decoded->text.empty() && decoded->text.size() + decoded->title.size() + RemotePad::PromptHeaderSize <= RemotePad::LargestTextDatagram, "the text is cut to fit");
    prompt.title = "\xc3\xbc\xc3\xbc";
    prompt.text = {};
    auto cut = RemotePad::EncodePrompt(prompt);
    cut.resize(cut.size() - 1);
    put<std::uint16_t>(cut, 6, static_cast<std::uint16_t>(cut.size()));
    require(!RemotePad::DecodePrompt(view(cut)), "string lengths that do not add up are dropped");
    auto magic = RemotePad::EncodePrompt(prompt);
    put<std::uint32_t>(magic, 0, RemotePad::TextMagic);
    require(!RemotePad::DecodePrompt(view(magic)), "a wrong magic is dropped");
    auto kind = RemotePad::EncodePrompt(prompt);
    kind[12] = 9;
    require(!RemotePad::DecodePrompt(view(kind)), "an unknown kind is dropped");
}

// A text (APRT) carries the whole text typed for a prompt and what to do after.
void textRoundTrip() {
    RemotePad::TypedText text;
    text.prompt = 12;
    text.id = 3;
    text.action = RemotePad::TypedText::Action::Submit;
    text.text = "Ay\xc5\x9f" "e \xf0\x9f\x98\x80";
    const auto bytes = RemotePad::EncodeText(text);
    require(get<std::uint32_t>(bytes.data(), 0) == RemotePad::TextMagic && get<std::uint16_t>(bytes.data(), 6) == bytes.size(), "text magic and size");
    require(get<std::uint32_t>(bytes.data(), 8) == 12 && get<std::uint32_t>(bytes.data(), 12) == 3 && bytes[16] == 1, "prompt, id and action");
    const auto decoded = RemotePad::DecodeText(view(bytes));
    require(decoded && decoded->prompt == 12 && decoded->id == 3 && decoded->action == RemotePad::TypedText::Action::Submit && decoded->text == text.text, "the text decodes");
    auto action = bytes;
    action[16] = 7;
    require(!RemotePad::DecodeText(view(action)), "an unknown action is dropped");
    auto broken = bytes;
    broken[RemotePad::TextHeaderSize] = static_cast<std::uint8_t>(0xff);
    const auto cleaned = RemotePad::DecodeText(view(broken));
    require(cleaned && cleaned->text.find('\xff') == std::string::npos, "malformed UTF-8 is left out of the text");
    auto shorter = bytes;
    shorter.pop_back();
    require(!RemotePad::DecodeText(view(shorter)), "a text whose length does not add up is dropped");
    require(!RemotePad::DecodeInput(view(bytes)) && !RemotePad::DecodePress(view(bytes)), "a text is no input and no press");
}

void validUtf8AndPieces() {
    require(RemotePad::ValidUtf8("ab\xc3\xbc") == "ab\xc3\xbc", "valid UTF-8 stays");
    require(RemotePad::ValidUtf8("a\xc3") == "a", "a cut character is left out");
    require(RemotePad::ValidUtf8("a\x01" "b\nc") == "ab\nc", "control characters other than a line feed go");
    require(RemotePad::ValidUtf8("a\xed\xa0\x80" "b") == "ab", "an encoded surrogate goes");
    require(RemotePad::ValidUtf8("ab\xc3\xbc", 3) == "ab", "a limit never cuts a character");
    const std::string text = "\xf0\x9f\x98\x80\xf0\x9f\x98\x80" + std::string(30, 'x') + "\xc3\xbc";
    const auto pieces = RemotePad::TextPieces(text, 31);
    std::string joined;
    for (const auto& piece : pieces) {
        require(!piece.empty() && piece.size() <= 31, "each piece fits");
        require(RemotePad::ValidUtf8(piece) == piece, "and ends on a character");
        joined += piece;
    }
    require(joined == text, "the pieces make the text");
    require(RemotePad::TextPieces("", 31).empty(), "no text, no piece");
    require(RemotePad::Utf8(u"Ay\u015fe \U0001F600") == "Ay\xc5\x9f" "e \xf0\x9f\x98\x80", "a game's UTF-16 becomes UTF-8");
    const char16_t lone[] = {u'a', 0xd800, u'b', 0xdc00, 0};
    require(RemotePad::Utf8(lone) == "ab", "lone surrogates are left out");
}

// The engine says on its channel what text the game asks for, and takes the typed text the
// launcher sends back, a copy counting once.
void channelCarriesPromptsAndTexts() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    RemotePad::Prompt prompt;
    prompt.id = 5;
    prompt.kind = RemotePad::Prompt::Kind::Dialog;
    prompt.title = "Code";
    channel.SendPrompt(prompt);
    std::vector<std::uint8_t> bytes(RemotePad::LargestTextDatagram);
    std::optional<std::int64_t> arrived;
    const auto got = RemotePad::Net::Receive(launcher.socket, bytes.data(), bytes.size(), arrived);
    require(got.has_value(), "the prompt reaches the launcher");
    bytes.resize(*got);
    const auto heard = RemotePad::DecodePrompt(view(bytes));
    require(heard && heard->id == 5 && heard->title == "Code", "as it was sent");
    RemotePad::TypedText text{5, 1, RemotePad::TypedText::Action::Submit, std::string(3000, 'k')};
    launcher.send(RemotePad::EncodeText(text), channel.Port());
    launcher.send(RemotePad::EncodeText(text), channel.Port());
    const auto now = std::chrono::steady_clock::now();
    std::vector<RemotePad::TypedText> taken;
    for (int attempt = 0; attempt < 50 && taken.empty(); ++attempt) {
        require(!channel.Poll(now), "a text is not an input");
        taken = channel.TakeTexts();
        if (taken.empty()) std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    channel.Poll(now);
    const auto more = channel.TakeTexts();
    require(taken.size() + more.size() == 1, "a copy of the last text is dropped");
    require(taken[0].text.size() == 3000 && taken[0].prompt == 5, "a long text arrives whole");
}

void helloSaysItTakesText() {
    require((RemotePad::EncodeHello(1)[9] & RemotePad::HelloTakesText) != 0, "the hello says the engine takes text");
}

// Assist: a device marked in byte 13 helps the first player, and the assist datagram (APRA)
// says whether the Mac's other controllers do.
void anInputCanHelpTheFirstPlayer() {
    auto bytes = fullPacket(1);
    bytes[13] = RemotePad::AssistSeat;
    const auto input = RemotePad::DecodeInput(view(bytes));
    require(input && input->seat == RemotePad::AssistSeat, "byte 13 = 1 marks a helper of the first player");
    bytes[13] = 5;
    require(RemotePad::DecodeInput(view(bytes))->seat == 0, "a seat past the fourth player is none");
}

void assistDatagram() {
    const auto bytes = RemotePad::EncodeAssist(RemotePad::AssistControllers);
    require(bytes.size() == 16 && get<std::uint32_t>(bytes.data(), 0) == RemotePad::AssistMagic, "assist magic and size");
    require(get<std::uint16_t>(bytes.data(), 4) == 1 && get<std::uint16_t>(bytes.data(), 6) == 16, "assist version and size field");
    require(RemotePad::DecodeAssist(std::span<const std::uint8_t>(bytes.data(), bytes.size())) == RemotePad::AssistControllers, "the flags come back");
    auto unknown = std::vector<std::uint8_t>(bytes.begin(), bytes.end());
    put<std::uint32_t>(unknown, 8, 0xF0u);
    require(RemotePad::DecodeAssist(view(unknown)) == 0u, "unknown flags are dropped");
    auto wrong = std::vector<std::uint8_t>(bytes.begin(), bytes.end());
    put<std::uint16_t>(wrong, 6, 15);
    require(!RemotePad::DecodeAssist(view(wrong)), "a wrong size field is dropped");
    require(!RemotePad::DecodeInput(view(unknown)) && !RemotePad::DecodePress(view(unknown)), "an assist datagram is no input and no press");
    require((RemotePad::EncodeHello(1)[9] & RemotePad::HelloTakesAssist) != 0, "the hello says the engine takes assist");
}

void assistedKeepsThePlayersMotion() {
    PadInputState player;
    player.buttons = 0x4000;
    player.sticks = {128, 128, 40, 128};
    player.analogButtonsR2 = 30;
    player.hasMotion = true;
    player.gyro = {1.0f, 2.0f, 3.0f};
    PadInputState helper;
    helper.buttons = 0x0010;
    helper.sticks = {250, 128, 120, 128};
    helper.analogButtonsR2 = 200;
    helper.hasMotion = true;
    helper.gyro = {9.0f, 9.0f, 9.0f};
    helper.touch[0] = {true, 100, 200, 7};
    const auto both = RemotePad::Assisted(player, helper);
    require(both.buttons == 0x4010u, "both press");
    require(both.sticks[0] == 250 && both.sticks[2] == 40, "each stick from whoever pushes it further");
    require(both.analogButtonsR2 == 200, "the stronger trigger");
    require(both.touch[0].active && both.touch[0].x == 100, "the helper's touch counts");
    require(both.gyro[0] == 1.0f, "the player's own motion stays");
    player.hasMotion = false;
    require(RemotePad::Assisted(player, helper).gyro[0] == 9.0f, "the helper's motion only when the player has none");
    require(RemotePad::Assisted(PadInputState{}, PadInputState{}).buttons == 0, "nothing pressed, nothing held");
}

void controllersHelpOnlyWhenAskedAndPlayerOneIsTaken() {
    require(!RemotePad::Helps(false, true), "controllers are players unless the launcher says they help");
    require(!RemotePad::Helps(true, false), "with no one on player 1, a controller takes it");
    require(RemotePad::Helps(true, true), "with player 1 taken, the next controller helps it");
}

void channelTakesTheNewestAssist() {
    Peer launcher;
    RemotePad::Channel channel(launcher.port);
    const auto now = std::chrono::steady_clock::now();
    const auto on = RemotePad::EncodeAssist(RemotePad::AssistControllers);
    const auto off = RemotePad::EncodeAssist(0);
    launcher.send(std::vector<std::uint8_t>(on.begin(), on.end()), channel.Port());
    launcher.send(std::vector<std::uint8_t>(off.begin(), off.end()), channel.Port());
    launcher.send(std::vector<std::uint8_t>(on.begin(), on.end()), channel.Port());
    std::optional<std::uint32_t> flags;
    for (int attempt = 0; attempt < 50; ++attempt) {
        channel.Poll(now);
        if (const auto taken = channel.TakeAssist()) flags = taken;
        if (flags == RemotePad::AssistControllers) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    require(flags == RemotePad::AssistControllers, "the newest assist flags are taken");
    require(!channel.TakeAssist(), "and taken once");
}

void environmentForMorePlayers() {
    unsetVariable("ANYPS5_REMOTE_PAD");
    setVariable("ANYPS5_REMOTE_PAD_2", "127.0.0.1:5002");
    require(RemotePad::OpenAllFromEnvironment().empty(), "no channel for later players without the first");
    setVariable("ANYPS5_REMOTE_PAD", "127.0.0.1:5001");
    setVariable("ANYPS5_REMOTE_PAD_4", "127.0.0.1:5004");
    const auto channels = RemotePad::OpenAllFromEnvironment();
    require(channels.size() == 2, "a channel for ANYPS5_REMOTE_PAD and each numbered one, stopping at a gap");
    setVariable("ANYPS5_REMOTE_PAD_2", "10.0.0.1:5002");
    bool threw = false;
    try {
        RemotePad::OpenAllFromEnvironment();
    } catch (const std::runtime_error& error) {
        threw = std::string(error.what()).find("ANYPS5_REMOTE_PAD_2") != std::string::npos;
    }
    require(threw, "a malformed numbered address stops with an error naming it");
    unsetVariable("ANYPS5_REMOTE_PAD");
    unsetVariable("ANYPS5_REMOTE_PAD_2");
    unsetVariable("ANYPS5_REMOTE_PAD_4");
}

}

int main() try {
    decodesAFullPacket();
    rejectsBadPackets();
    mergeTakesTheStrongerInput();
    encodesOutput();
    loopbackChannel();
    greetsEverySecond();
    helloToNoLauncherHoldsNothingBack();
    helloNamesThePlayer();
    olderSequenceIsIgnored();
    newSessionStartsANewSequence();
    answerTellsHowLongTheInputWaited();
    remoteReleasedAfterSilence();
    environment();
    onlyRealInputWantsAPlayer();
    seatsGoInOrderAndComeBack();
    guestsNeverTakeTheFirstPlayer();
    environmentForMorePlayers();
    decodesAPress();
    rejectsBadPresses();
    pressesHoldForTheirTime();
    channelTakesPresses();
    helloSaysItTakesPresses();
    promptRoundTrip();
    promptKeepsToItsLimits();
    textRoundTrip();
    validUtf8AndPieces();
    channelCarriesPromptsAndTexts();
    helloSaysItTakesText();
    anInputCanHelpTheFirstPlayer();
    assistDatagram();
    assistedKeepsThePlayersMotion();
    controllersHelpOnlyWhenAskedAndPlayerOneIsTaken();
    channelTakesTheNewestAssist();
    std::cout << "remote pad tests passed\n";
    return 0;
} catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
