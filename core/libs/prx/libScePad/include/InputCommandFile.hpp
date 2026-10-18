#ifndef CORE_LIBS_PRX_LIBSCEPAD_INPUTCOMMANDFILE_HPP
#define CORE_LIBS_PRX_LIBSCEPAD_INPUTCOMMANDFILE_HPP

#include <array>
#include <charconv>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <string>

namespace Pad {
class InputCommandFile {
public:
    struct Input {
        std::uint32_t buttons = 0;
        bool hasSticks = false;
        std::array<std::uint8_t, 4> sticks{};
        bool touchLeft = false;
        bool touchRight = false;

        bool operator==(const Input&) const = default;
    };

    explicit InputCommandFile(const std::filesystem::path& path) : path(path) {
        if (!this->path.empty()) lastSequence = read().sequence;
    }

    Input Poll(std::uint64_t now) {
        if (path.empty()) return {};
        if (now >= nextPoll) {
            nextPoll = now + 100000;
            const auto command = read();
            if (command.sequence > lastSequence) {
                lastSequence = command.sequence;
                input = command.input;
                until = now + command.durationMs * 1000ull;
            }
        }
        return now < until ? input : Input{};
    }

    std::uint32_t Buttons(std::uint64_t now) { return Poll(now).buttons; }

private:
    struct Command {
        std::uint64_t sequence = 0;
        Input input;
        std::uint32_t durationMs = 0;
    };

    Command read() const {
        std::ifstream file(path);
        char line[128]{};
        if (!file.getline(line, sizeof(line))) return {};
        const std::string text(line);
        if (text.find('-') != std::string::npos) return {};
        std::istringstream fields(text);
        std::string tokens[8];
        int count = 0;
        while (count < 8 && fields >> tokens[count]) ++count;
        if (count != 3 && count != 7) return {};
        std::uint64_t values[7]{};
        for (int i = 0; i < count; ++i) {
            const char* first = tokens[i].data() + (tokens[i].front() == '+' ? 1 : 0);
            const char* last = tokens[i].data() + tokens[i].size();
            const auto parsed = std::from_chars(first, last, values[i]);
            if (first == last || parsed.ec != std::errc{} || parsed.ptr != last) return {};
        }
        if (values[0] == 0 || (values[1] & ~(0x10fffeull | TouchLeftBit | TouchRightBit)) != 0 || values[2] == 0 || values[2] > 5000) return {};
        Command command;
        command.sequence = values[0];
        command.input.buttons = static_cast<std::uint32_t>(values[1] & 0x10fffeull);
        command.input.touchLeft = (values[1] & TouchLeftBit) != 0;
        command.input.touchRight = (values[1] & TouchRightBit) != 0;
        command.durationMs = static_cast<std::uint32_t>(values[2]);
        for (int i = 3; i < count; ++i) {
            if (values[i] > 255) return {};
            command.input.sticks[i - 3] = static_cast<std::uint8_t>(values[i]);
        }
        command.input.hasSticks = count == 7;
        return command;
    }

    static constexpr std::uint64_t TouchLeftBit = 0x200000;
    static constexpr std::uint64_t TouchRightBit = 0x400000;

    std::filesystem::path path;
    std::uint64_t lastSequence = 0;
    std::uint64_t nextPoll = 0;
    std::uint64_t until = 0;
    Input input;
};
}

#endif
