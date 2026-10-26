#include "prx/libSceAgcDriver/Execution/include/PowerControl.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace {

using namespace std::chrono_literals;
using AgcDriver::PowerControl::ControlFile;
using AgcDriver::PowerControl::FramePacer;
using AgcDriver::PowerControl::Settings;

void Require(bool condition, const char* message) {
    if (condition) return;
    std::fprintf(stderr, "power_control: %s\n", message);
    std::exit(1);
}

void ParsesTheLaunchersFile() {
    using AgcDriver::PowerControl::Parse;
    const auto settings = Parse("fps_cap=40\nframe_gen=0\n", {});
    Require(settings.fpsCap == 40 && settings.frameGenerationPaused, "the launcher's two lines are read");
    Require(Parse("fps_cap=0\r\nframe_gen=1\r\n", {40, true}) == Settings{0, false}, "0 lifts the cap and 1 resumes, CRLF too");
    Require(Parse("fps_cap=fast\nframe_gen=2\nnoise\nother=1\n", {30, true}) == Settings{30, true}, "what cannot be read leaves the settings as they were");
    Require(Parse("fps_cap=5000\n", {45, false}).fpsCap == 45, "a cap past the limit is refused");
    Require(Parse("", {45, true}) == Settings{45, true}, "an empty file changes nothing");
}

void PacesFramesToTheCap() {
    FramePacer pacer;
    const auto start = FramePacer::Clock::time_point{} + 10s;
    Require(pacer.Due(40, start) == start, "the first frame goes at once");
    const auto interval = std::chrono::duration_cast<FramePacer::Clock::duration>(25ms);
    Require(pacer.Due(40, start + 5ms) == start + interval, "a frame ready early waits for its turn");
    Require(pacer.Due(40, start + interval + 1ms) == start + 2 * interval, "the count goes on from the last turn, not from when the frame came");
    // Frames slower than the cap go at once and never make up for it with a burst.
    const auto late = start + 1s;
    Require(pacer.Due(40, late) == late, "a frame later than the cap goes at once");
    Require(pacer.Due(40, late + 1ms) == late + interval, "and the next one waits a whole interval from it");
}

void ACapChangeOrNoneTakesEffectAtOnce() {
    FramePacer pacer;
    const auto start = FramePacer::Clock::time_point{} + 10s;
    pacer.Due(30, start);
    Require(pacer.Due(0, start + 1ms) == start + 1ms, "no cap: at once");
    Require(pacer.Due(45, start + 2ms) == start + 2ms, "a new cap starts from now");
    Require(pacer.Due(45, start + 3ms) > start + 3ms, "then paces");
}

void ReadsTheFileAgainWhileTheGameRuns() {
    const auto file = std::filesystem::temp_directory_path() / ("anyps5-power-control-" + std::to_string(std::rand()) + ".txt");
    {
        ControlFile none(nullptr, "30");
        Require(none.Poll(FramePacer::Clock::now()).fpsCap == 30, "ANYPS5_FPS_CAP alone gives the cap");
    }
    ControlFile control(file.string().c_str(), "30");
    const auto start = ControlFile::Clock::time_point{} + 10s;
    Require(control.Poll(start).fpsCap == 30, "before the file is there the start cap holds");
    std::ofstream(file) << "fps_cap=45\nframe_gen=0\n";
    Require(control.Poll(start + 1ms).fpsCap == 30, "the file is not read again before the interval");
    const auto read = control.Poll(start + ControlFile::PollInterval);
    Require(read.fpsCap == 45 && read.frameGenerationPaused, "then the change is read");
    std::ofstream(file) << "fps_cap=0\nframe_gen=1\n";
    Require(control.Poll(start + 2 * ControlFile::PollInterval) == Settings{0, false}, "and lifted again");
    std::filesystem::remove(file);
    Require(control.Poll(start + 3 * ControlFile::PollInterval) == Settings{0, false}, "a file gone keeps the last settings");
}

}

int main() {
    ParsesTheLaunchersFile();
    PacesFramesToTheCap();
    ACapChangeOrNoneTakesEffectAtOnce();
    ReadsTheFileAgainWhileTheGameRuns();
    std::puts("power_control: ok");
    return 0;
}
