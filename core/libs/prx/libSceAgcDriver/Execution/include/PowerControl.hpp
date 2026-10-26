#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_POWERCONTROL_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_POWERCONTROL_HPP

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>

namespace AgcDriver::PowerControl {

// What the launcher's battery and heat profiles ask of the game playing: a frame rate cap (0 for
// none) and frame generation paused. ANYPS5_FPS_CAP gives the cap at start; ANYPS5_POWER_CONTROL
// names a small file of `fps_cap=<n>` and `frame_gen=<0|1>` lines that the launcher rewrites while
// the game runs, read again every PollInterval. Without either nothing changes.
struct Settings {
    unsigned fpsCap = 0;
    bool frameGenerationPaused = false;
    bool operator==(const Settings&) const = default;
};

constexpr unsigned MaxFpsCap = 1000;

// A cap from text: a whole number from 0 to MaxFpsCap, else nothing.
inline std::optional<unsigned> ParseCap(std::string_view text) {
    while (!text.empty() && (text.back() == '\r' || text.back() == ' ')) text.remove_suffix(1);
    unsigned value = 0;
    const auto result = std::from_chars(text.data(), text.data() + text.size(), value);
    if (text.empty() || result.ec != std::errc{} || result.ptr != text.data() + text.size() || value > MaxFpsCap) return std::nullopt;
    return value;
}

// The file's lines over `settings`: a line it does not know, or a value it cannot read, leaves
// that part as it was (the launcher writes the file whole, but a game outlives a launcher).
inline Settings Parse(std::string_view text, Settings settings) {
    while (!text.empty()) {
        const auto end = text.find('\n');
        const auto line = text.substr(0, end);
        text = end == std::string_view::npos ? std::string_view{} : text.substr(end + 1);
        const auto equals = line.find('=');
        if (equals == std::string_view::npos) continue;
        const auto key = line.substr(0, equals);
        const auto value = line.substr(equals + 1);
        if (key == "fps_cap") {
            if (const auto cap = ParseCap(value)) settings.fpsCap = *cap;
        } else if (key == "frame_gen") {
            if (const auto on = ParseCap(value); on && *on <= 1) settings.frameGenerationPaused = *on == 0;
        }
    }
    return settings;
}

// Holds frames at least 1/cap apart: the time the frame ready at `now` may go. A frame later than
// a whole interval (the game slower than the cap), a new cap or the first frame go at once and
// start the count again, so a slow stretch is never made up for with a burst.
class FramePacer {
public:
    using Clock = std::chrono::steady_clock;

    Clock::time_point Due(unsigned fps, Clock::time_point now) {
        if (fps == 0) {
            active = false;
            return now;
        }
        const auto interval = std::chrono::duration_cast<Clock::duration>(std::chrono::nanoseconds(1'000'000'000ull / fps));
        if (!active || fps != rate || now >= next + interval) next = now;
        const auto due = std::max(next, now);
        next = due + interval;
        active = true;
        rate = fps;
        return due;
    }

private:
    bool active = false;
    unsigned rate = 0;
    Clock::time_point next{};
};

// The settings from the environment, the file read again at most every PollInterval.
class ControlFile {
public:
    using Clock = std::chrono::steady_clock;
    static constexpr auto PollInterval = std::chrono::milliseconds(500);

    ControlFile(const char* path, const char* cap) : path(path != nullptr ? path : "") {
        if (cap != nullptr) settings.fpsCap = ParseCap(cap).value_or(0);
    }

    const Settings& Poll(Clock::time_point now) {
        if (path.empty() || (polled && now < nextPoll)) return settings;
        polled = true;
        nextPoll = now + PollInterval;
        std::ifstream file(path, std::ios::binary);
        if (!file) return settings;
        std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        if (text.size() <= 4096) settings = Parse(text, settings);
        return settings;
    }

private:
    std::string path;
    Settings settings;
    bool polled = false;
    Clock::time_point nextPoll{};
};

// This process's settings now.
inline Settings Current(std::chrono::steady_clock::time_point now) {
    static std::mutex mutex;
    static ControlFile file(std::getenv("ANYPS5_POWER_CONTROL"), std::getenv("ANYPS5_FPS_CAP"));
    std::lock_guard lock(mutex);
    return file.Poll(now);
}

}

#endif
