#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_FRAMEGENERATIONPACING_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_FRAMEGENERATIONPACING_HPP

#include <chrono>
#include <optional>

namespace AgcDriver {

// When the game's frame follows the generated one before it (FrameGeneration.hpp). Both go to a
// vertical sync swapchain with an image free for each, so the game's frame, presented at once,
// would show one refresh after the generated one and hold the rest of the game's frame interval:
// at 20 fps on a 120 Hz display the generated frame shows for 8 ms of every 50, and the motion
// reads as 20 fps. The game's frame goes half the game's frame interval after the generated one
// instead, so the two share the interval evenly. The interval is measured between generated
// presents, smoothed; one far longer (a load, a stall) is not the game's pace and is left out.
class FrameGenerationPacer {
public:
    using Clock = std::chrono::steady_clock;
    static constexpr Clock::duration Longest = std::chrono::milliseconds(100);
    static constexpr double Weight = 0.25;

    // A generated frame went to the window at `now`: when the game's frame after it should go.
    // At once until an interval was measured.
    Clock::time_point FollowAt(Clock::time_point now) {
        if (previous && now > *previous && now - *previous <= Longest) {
            const double sample = std::chrono::duration<double>(now - *previous).count();
            interval = interval ? *interval + Weight * (sample - *interval) : sample;
        }
        previous = now;
        if (!interval) return now;
        return now + std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(*interval / 2.0));
    }

    // A game frame went without a generated one before it: the next interval is not measured
    // across it.
    void Skip() { previous.reset(); }

    // The game's frame interval measured, in seconds.
    std::optional<double> Interval() const { return interval; }

private:
    std::optional<Clock::time_point> previous;
    std::optional<double> interval;
};

}

#endif
