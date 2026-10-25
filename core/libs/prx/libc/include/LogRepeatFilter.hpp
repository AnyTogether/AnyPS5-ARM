#pragma once

// Keeps one log line from filling the log. A line written more than RepeatLimit times in one window is dropped from
// then on, with one notice when that starts and a count of the dropped copies when the window ends. Human Fall Flat
// (PPSA02429) printed two alternating sceNetEpollControl errors 588,299 times each, 53 MB of log, which plain
// "same as the previous line" coalescing does not catch. Distinct lines always pass, and only whole lines are
// counted: a line split over several writes passes as written.
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <string>
#include <string_view>
#include <unordered_map>

class LogRepeatFilter {
public:
    using Clock = std::chrono::steady_clock;
    static constexpr std::size_t RepeatLimit = 50;
    static constexpr std::chrono::seconds Window{10};
    static constexpr std::size_t LongestCounted = 1024;
    static constexpr std::size_t MostCounted = 4096;

    explicit LogRepeatFilter(Clock::time_point start = Clock::now()) : windowStart(start) {}

    // Calls sink(std::string_view) with what reaches the log, in order.
    template<typename TSink>
    void Write(std::string_view data, Clock::time_point now, TSink&& sink) {
        if (atLineStart && now - windowStart >= Window) Flush(now, sink);
        std::size_t passed = 0;
        std::size_t position = 0;
        while (position < data.size()) {
            const auto newline = data.find('\n', position);
            if (newline == std::string_view::npos) {
                atLineStart = false;
                break;
            }
            const auto line = data.substr(position, newline + 1 - position);
            const bool whole = atLineStart;
            atLineStart = true;
            position = newline + 1;
            if (!whole || line.size() > LongestCounted) continue;
            const Verdict verdict = Count(line);
            if (verdict == Verdict::Pass) continue;
            if (passed < newline + 1 - line.size()) sink(data.substr(passed, newline + 1 - line.size() - passed));
            passed = position;
            if (verdict == Verdict::Notice) {
                std::string notice = "[log] this line repeated " + std::to_string(RepeatLimit) + " times in " +
                    std::to_string(Window.count()) + " s; further copies are dropped and counted: ";
                notice.append(line);
                sink(std::string_view(notice));
            }
        }
        if (passed < data.size()) sink(data.substr(passed));
    }

    // Reports the copies dropped in this window and starts the next one.
    template<typename TSink>
    void Flush(Clock::time_point now, TSink&& sink) {
        const auto seconds = std::chrono::duration_cast<std::chrono::seconds>(now - windowStart).count();
        for (const auto& [line, count] : counts) {
            if (count <= RepeatLimit) continue;
            std::string report = "[log] dropped " + std::to_string(count - RepeatLimit) + " copies of this line in the last " +
                std::to_string(seconds) + " s: ";
            report.append(line);
            sink(std::string_view(report));
        }
        counts.clear();
        windowStart = now;
    }

private:
    enum class Verdict { Pass, Notice, Drop };

    Verdict Count(std::string_view line) {
        auto found = counts.find(std::string(line));
        if (found == counts.end()) {
            if (counts.size() < MostCounted) counts.emplace(line, 1);
            return Verdict::Pass;
        }
        const std::size_t count = ++found->second;
        if (count <= RepeatLimit) return Verdict::Pass;
        return count == RepeatLimit + 1 ? Verdict::Notice : Verdict::Drop;
    }

    std::unordered_map<std::string, std::size_t> counts;
    Clock::time_point windowStart;
    bool atLineStart = true;
};
