#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPAD_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPAD_HPP

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>
#include "prx/libScePad/include/Pad.hpp"
#include "prx/libScePad/include/PadState.hpp"

namespace RemotePad {

constexpr std::uint32_t InputMagic = 0x49525041u;
constexpr std::uint32_t OutputMagic = 0x4F525041u;
constexpr std::uint32_t HelloMagic = 0x48525041u;
constexpr std::uint32_t PressMagic = 0x50525041u;
constexpr std::uint32_t PromptMagic = 0x4B525041u;
constexpr std::uint32_t TextMagic = 0x54525041u;
constexpr std::uint32_t AssistMagic = 0x41525041u;
constexpr std::size_t AssistSize = 16;
// An input whose byte 13 is this helps the first player (assist): the launcher marks a phone,
// a browser pad or a share play guest so; it takes no seat of its own.
constexpr std::uint8_t AssistSeat = 1;
// Bit 0 of an assist datagram's flags: the Mac's game controllers after the first player's help
// the first player instead of becoming players 2 to 4.
constexpr std::uint32_t AssistControllers = 1;
constexpr std::uint16_t Version = 1;
constexpr std::size_t InputSize = 80;
constexpr std::size_t OutputSize = 32;
constexpr std::size_t HelloSize = 16;
constexpr std::size_t PressSize = 24;
constexpr std::size_t PromptHeaderSize = 24;
constexpr std::size_t TextHeaderSize = 20;
// The largest prompt or text datagram: a whole 2048-character text fits in UTF-8 with room.
constexpr std::size_t LargestTextDatagram = 8192;
constexpr std::size_t LargestPromptTitle = 255;
// Bit 0 of the hello's byte 9: this engine takes presses; bit 1: it says when the game asks for
// text (APRK) and takes the text typed for it (APRT).
constexpr std::uint8_t HelloTakesPresses = 1;
constexpr std::uint8_t HelloTakesText = 2;
// Bit 2: it takes assist datagrams (APRA) and inputs that help the first player (byte 13 = 1).
constexpr std::uint8_t HelloTakesAssist = 4;
constexpr auto ShortestHold = std::chrono::milliseconds(50);
constexpr auto LongestHold = std::chrono::milliseconds(2000);
constexpr auto Silence = std::chrono::milliseconds(500);
// A phone silent this long has left: its player is free for another device.
constexpr auto Gone = std::chrono::seconds(5);

struct Input {
    std::uint32_t sequence = 0;
    std::uint64_t sentMicros = 0;
    std::uint32_t waitMicros = 0;
    std::uint64_t session = 0;
    // The player (2 to 4) the launcher holds for a share play guest, from byte 13; 0 for a phone,
    // which may be any player; AssistSeat for a device that helps the first player.
    std::uint8_t seat = 0;
    PadInputState state{};
};

// Buttons held on the first player's pad for a while, whoever drives it, without taking a seat:
// how the launcher's quick menu presses Options to pause a game.
struct Press {
    std::uint32_t id = 0;
    std::uint32_t buttons = 0;
    std::chrono::milliseconds hold{};
};

// The game asks for text (APRK, engine to launcher): sceImeDialogInit's dialog or sceImeOpen's
// keyboard, with the title, the placeholder and the text it starts with, all UTF-8. id 0 says no
// text is asked for any more.
struct Prompt {
    enum class Kind : std::uint8_t { None = 0, Keyboard = 1, Dialog = 2 };
    std::uint32_t id = 0;
    Kind kind = Kind::None;
    // The console's keyboard type (0 default, 1 basic Latin, 2 URL, 3 mail, 4 number) and Enter
    // label (0 default, 1 send, 2 search, 3 go).
    std::uint8_t type = 0;
    std::uint8_t enterLabel = 0;
    bool multiline = false;
    // In UTF-16 units, as the game counts them.
    std::uint16_t maxLength = 0;
    std::string title;
    std::string placeholder;
    std::string text;
};

// What a phone typed for a prompt (APRT, launcher to engine): the whole text, replacing what was
// there, and then Enter, Escape or nothing. id tells copies apart, as a press's does.
struct TypedText {
    enum class Action : std::uint8_t { Update = 0, Submit = 1, Cancel = 2 };
    std::uint32_t prompt = 0;
    std::uint32_t id = 0;
    Action action = Action::Update;
    std::string text;
};

std::vector<std::uint8_t> EncodePrompt(const Prompt& prompt);
std::optional<Prompt> DecodePrompt(std::span<const std::uint8_t> bytes);
std::vector<std::uint8_t> EncodeText(const TypedText& text);
std::optional<TypedText> DecodeText(std::span<const std::uint8_t> bytes);
// The longest start of `text` that is whole UTF-8 and at most `bytes` long; malformed UTF-8 and
// characters that are no text (C0 controls other than a line feed, surrogates) are left out.
std::string ValidUtf8(std::string_view text, std::size_t bytes = LargestTextDatagram);
// `text` (valid UTF-8) cut into pieces of at most `bytes` bytes that end on a character, so each
// fits an ImeHostInput.
std::vector<std::string> TextPieces(std::string_view text, std::size_t bytes);
// UTF-16 as a game keeps it in UTF-8; a lone surrogate is left out.
std::string Utf8(std::u16string_view units);

std::optional<Input> DecodeInput(std::span<const std::uint8_t> bytes);
// The assist datagram (APRA, launcher to engine): its flags (AssistControllers), nil when it is
// not one.
std::optional<std::uint32_t> DecodeAssist(std::span<const std::uint8_t> bytes);
std::array<std::uint8_t, AssistSize> EncodeAssist(std::uint32_t flags);
std::optional<Press> DecodePress(std::span<const std::uint8_t> bytes);
std::array<std::uint8_t, OutputSize> EncodeOutput(const Input& last, const PadOutputState& output);
// player is the channel's player counting from 1, or 0 while its phone is none.
std::array<std::uint8_t, HelloSize> EncodeHello(std::uint8_t player = 0);
bool IsNewer(std::uint32_t sequence, std::uint32_t than);
PadInputState Merge(const PadInputState& controller, const PadInputState& remote);
// The first player's pad with a helper's added (assist): buttons from both, the stick furthest
// from the centre and the stronger trigger win, the helper's touch counts, and the player's own
// motion stays (the helper's is taken only when the player's pad has none).
PadInputState Assisted(const PadInputState& player, const PadInputState& helper);
// Whether a device that asks for a player helps the first player instead: only when controllers
// help (AssistControllers) and another device holds the first player already.
bool Helps(bool controllersHelp, bool playerOneHeld);
PadInputState Current(const std::optional<Input>& last, std::chrono::steady_clock::time_point seen, std::chrono::steady_clock::time_point now);

class Channel {
public:
    explicit Channel(std::uint16_t launcherPort);
    ~Channel();
    Channel(const Channel&) = delete;
    Channel& operator=(const Channel&) = delete;

    std::optional<Input> Poll(std::chrono::steady_clock::time_point now);
    // The presses Poll read since the last call; a copy of the last one (the same id) is dropped.
    std::vector<Press> TakePresses();
    // The texts Poll read since the last call; a copy of the last one (the same id) is dropped.
    std::vector<TypedText> TakeTexts();
    // The newest assist flags Poll read since the last call, if any came.
    std::optional<std::uint32_t> TakeAssist();
    // Tells the launcher what text the game asks for (id 0: none).
    void SendPrompt(const Prompt& prompt);
    void Answer(const Input& last, const PadOutputState& output);
    void Greet(std::chrono::steady_clock::time_point now);
    // Which player the phone is, from 1, or 0; a change is said in the next hello at once.
    void SetPlayer(std::uint8_t number);
    std::uint16_t Port() const { return port; }

private:
    void send(const std::uint8_t* bytes, std::size_t size);

    std::intptr_t socket = -1;
    std::uint16_t port = 0;
    std::uint16_t launcherPort = 0;
    std::optional<std::uint32_t> newest;
    std::optional<std::uint64_t> session;
    std::optional<std::uint32_t> lastPress;
    std::vector<Press> presses;
    std::optional<std::uint32_t> lastText;
    std::vector<TypedText> texts;
    std::optional<std::uint32_t> assist;
    std::optional<std::chrono::steady_clock::time_point> greeted;
    std::uint8_t player = 0;
};

std::unique_ptr<Channel> OpenFromEnvironment();
// The channel of ANYPS5_REMOTE_PAD, then one for each of ANYPS5_REMOTE_PAD_2 to _4 up to the
// first that is unset: one per phone the launcher can bring.
std::vector<std::unique_ptr<Channel>> OpenAllFromEnvironment();

// Whether a device's input asks for a player: a button, a trigger, a touch or a stick pushed
// well off centre. Moving the device does not, so a controller lying on the desk takes no one's
// place.
bool Wants(const PadInputState& state);

// The players' seats: each device that asks takes the lowest free player and keeps it until it
// leaves. Devices are named by number: a controller by its SDL instance id, a phone by
// RemoteDevice(its channel).
class Seats {
public:
    // guest is the player (2 to 4) held for a share play guest: it takes that one, or the lowest
    // free one after the first, never the first (the host's); 0 takes the lowest free one.
    int Seat(std::uint32_t device, bool wants, std::uint8_t guest = 0);
    int Leave(std::uint32_t device);
    int Of(std::uint32_t device) const;
    bool Held(int player) const;

private:
    std::array<std::optional<std::uint32_t>, PAD_MAX_CONTROLLERS> holders;
};

constexpr std::uint32_t RemoteDevice(std::size_t channel) { return 0x80000000u | static_cast<std::uint32_t>(channel); }

// The presses being held on the first player's pad.
class Presses {
public:
    void Add(const Press& press, std::chrono::steady_clock::time_point now);
    std::uint32_t Buttons(std::chrono::steady_clock::time_point now) const;

private:
    struct Held {
        std::uint32_t buttons;
        std::chrono::steady_clock::time_point until;
    };
    std::vector<Held> held;
};

// The light a player's pad shows when the game sets none, as on the console: blue, red, green, pink.
std::array<std::uint8_t, 3> PlayerColor(int player);

}

#endif
