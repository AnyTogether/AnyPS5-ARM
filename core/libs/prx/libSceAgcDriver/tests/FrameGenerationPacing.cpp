#include "prx/libSceAgcDriver/Execution/include/FrameGenerationPacing.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace {

using namespace std::chrono_literals;
using AgcDriver::FrameGenerationPacer;
using Clock = FrameGenerationPacer::Clock;

void Require(bool condition, const char* message) {
    if (condition) return;
    std::fprintf(stderr, "frame_generation_pacing: %s\n", message);
    std::exit(1);
}

double Milliseconds(Clock::duration duration) {
    return std::chrono::duration<double, std::milli>(duration).count();
}

// The game's frame goes half its frame interval after the generated one, so at 20 fps the two
// presents are 25 ms apart, not one refresh.
void HalvesTheGamesInterval() {
    FrameGenerationPacer pacer;
    const auto start = Clock::now();
    Require(pacer.FollowAt(start) == start, "the first generated frame, with nothing measured, is followed at once");
    for (int frame = 1; frame <= 20; ++frame) {
        const auto now = start + frame * 50ms;
        const double after = Milliseconds(pacer.FollowAt(now) - now);
        Require(std::abs(after - 25.0) < 0.01, "at 20 fps the game's frame goes 25 ms after the generated one");
    }
    Require(pacer.Interval() && std::abs(*pacer.Interval() - 0.050) < 1e-6, "the interval measured is the game's 50 ms");
}

// A changed frame rate moves the delay over a few frames; one frame does not swing it.
void FollowsAChangedRate() {
    FrameGenerationPacer pacer;
    auto now = Clock::now();
    pacer.FollowAt(now);
    for (int frame = 0; frame < 30; ++frame) pacer.FollowAt(now += 50ms);
    const double once = Milliseconds(pacer.FollowAt(now += 25ms) - now);
    Require(once > 20.0 && once < 25.0, "one shorter frame moves the delay a quarter of the way");
    for (int frame = 0; frame < 30; ++frame) pacer.FollowAt(now += 25ms);
    const double settled = Milliseconds(pacer.FollowAt(now += 25ms) - now);
    Require(std::abs(settled - 12.5) < 0.1, "at 40 fps the delay settles at 12.5 ms");
}

// A stall (a load, a hitch) longer than Longest is not the game's pace, and a frame presented
// without a generated one before it breaks the measurement.
void LeavesOutStallsAndGaps() {
    FrameGenerationPacer pacer;
    auto now = Clock::now();
    pacer.FollowAt(now);
    for (int frame = 0; frame < 10; ++frame) pacer.FollowAt(now += 40ms);
    const double stalled = Milliseconds(pacer.FollowAt(now += 2s) - now);
    Require(std::abs(stalled - 20.0) < 0.01, "a two second stall leaves the delay at half of 40 ms");
    pacer.Skip();
    const double skipped = Milliseconds(pacer.FollowAt(now += 90ms) - now);
    Require(std::abs(skipped - 20.0) < 0.01, "an interval across a frame without generation is not measured");
    const double measured = Milliseconds(pacer.FollowAt(now += 40ms) - now);
    Require(std::abs(measured - 20.0) < 0.01, "after the gap the next interval is measured again");
    Require(pacer.FollowAt(now) == now + 20ms, "a second present at the same moment measures nothing");
}

// The delay never exceeds half of Longest, so a slow game's next flip is not held long.
void BoundsTheDelay() {
    FrameGenerationPacer pacer;
    auto now = Clock::now();
    pacer.FollowAt(now);
    for (int frame = 0; frame < 50; ++frame) pacer.FollowAt(now += FrameGenerationPacer::Longest);
    const auto after = pacer.FollowAt(now += FrameGenerationPacer::Longest) - now;
    Require(after <= FrameGenerationPacer::Longest / 2 + 1us, "the game's frame waits at most half of Longest");
}

}

int main() {
    HalvesTheGamesInterval();
    FollowsAChangedRate();
    LeavesOutStallsAndGaps();
    BoundsTheDelay();
    std::puts("frame_generation_pacing: ok");
    return 0;
}
