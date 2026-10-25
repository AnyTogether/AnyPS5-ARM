#include "prx/libc/include/LogRepeatFilter.hpp"
#include <cstdio>
#include <string>

namespace {

int failures = 0;

void Expect(bool value, const char* what) {
    if (value) return;
    std::fprintf(stderr, "log repeat filter: %s\n", what);
    ++failures;
}

std::size_t Occurrences(const std::string& text, const std::string& piece) {
    std::size_t count = 0;
    for (auto at = text.find(piece); at != std::string::npos; at = text.find(piece, at + piece.size())) ++count;
    return count;
}

}

int main() {
    using Clock = LogRepeatFilter::Clock;
    const auto start = Clock::now();
    LogRepeatFilter filter(start);
    std::string log;
    const auto sink = [&](std::string_view piece) { log.append(piece); };
    const std::string add = "error during sceNetEpollControl 0x80410109\n";
    const std::string del = "error during sceNetEpollControl del 0x80410109\n";

    // Two alternating lines, as PPSA02429 printed them, one write each.
    for (int index = 0; index < 10000; ++index) {
        filter.Write(add, start, sink);
        filter.Write(del, start, sink);
    }
    Expect(Occurrences(log, add) == LogRepeatFilter::RepeatLimit + 1, "a repeated line passed more than the limit, plus its notice");
    Expect(Occurrences(log, del) == LogRepeatFilter::RepeatLimit + 1, "the alternating line was not limited on its own");
    Expect(Occurrences(log, "further copies are dropped") == 2, "each limited line has one notice");

    // Distinct lines and a line split across writes always pass.
    filter.Write("frame 1\nframe 2\n", start, sink);
    filter.Write("error during sceNetEpoll", start, sink);
    filter.Write("Control 0x80410109\n", start, sink);
    Expect(log.find("frame 1\nframe 2\n") != std::string::npos, "distinct lines were dropped");
    Expect(Occurrences(log, add) == LogRepeatFilter::RepeatLimit + 2, "a line split across writes was counted");

    // Several lines in one write keep their order around a dropped copy.
    filter.Write("before\n" + add + "after\n", start, sink);
    Expect(log.find("before\nafter\n") != std::string::npos, "lines around a dropped copy changed");

    // The window end reports the drops and lets the line through again.
    const auto later = start + LogRepeatFilter::Window;
    filter.Write(add, later, sink);
    Expect(log.find("[log] dropped 9951 copies of this line in the last 10 s: " + add) != std::string::npos, "the window end did not count the dropped copies");
    Expect(log.size() > add.size() && log.compare(log.size() - add.size(), add.size(), add) == 0, "the line did not pass in the new window");

    if (failures == 0) std::printf("log repeat filter: 20000 alternating lines kept to %zu bytes\n", log.size());
    return failures == 0 ? 0 : 1;
}
