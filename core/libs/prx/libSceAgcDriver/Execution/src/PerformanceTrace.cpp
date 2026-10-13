#include "prx/libSceAgcDriver/Execution/include/PerformanceTrace.hpp"
#include "prx/libSceAgcDriver/Execution/include/ProfileOutput.hpp"
#include "prx/libSceAgcDriver/Execution/include/TraceFile.hpp"
#include "prx/libSceAgcDriver/Execution/include/VulkanDevice.hpp"
#include "prx/libSceAgcDriver/TraceRevision.hpp"
#include <cstdlib>
#include <filesystem>
#include <limits>
#include <mutex>
#include <system_error>
#ifdef _WIN32
#include <windows.h>
#else
#include <cerrno>
#include <sys/utsname.h>
#include <unistd.h>
#endif

#ifndef _WIN32
extern char** environ;
#endif

namespace AgcDriver {

namespace {

using Clock = std::chrono::steady_clock;
constexpr std::size_t GpuRangeCapacity = TraceThread::DefaultCapacity;

struct Session {
    std::mutex mutex;
    std::vector<std::unique_ptr<TraceThread>> threads;
    std::optional<TraceWindow> window;
    Clock::time_point first{};
    std::uint64_t present = 0;
    std::uint64_t firstPresent = 0;
    double gpuBusyAtOpen = 0;
    std::optional<TraceClockSample> gpuClock;
    std::vector<Clock::time_point> presents;
};

Session& session() {
    static auto& state = *new Session();
    return state;
}

std::unique_ptr<ProfileOutput>& writer() {
    static std::unique_ptr<ProfileOutput> output;
    return output;
}

std::uint64_t processId() {
#ifdef _WIN32
    return GetCurrentProcessId();
#else
    return static_cast<std::uint64_t>(::getpid());
#endif
}

std::string operatingSystem() {
#ifdef _WIN32
    using QueryVersion = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    static const auto query = reinterpret_cast<QueryVersion>(reinterpret_cast<void*>(::GetProcAddress(::GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion")));
    RTL_OSVERSIONINFOW version{};
    version.dwOSVersionInfoSize = sizeof(version);
    if (query == nullptr || query(&version) != 0) throw std::runtime_error("RtlGetVersion failed");
    return "Windows " + std::to_string(version.dwMajorVersion) + "." + std::to_string(version.dwMinorVersion) + "." + std::to_string(version.dwBuildNumber);
#else
    utsname name{};
    if (::uname(&name) != 0) throw std::system_error(errno, std::generic_category(), "uname");
    return std::string(name.sysname) + " " + name.release;
#endif
}

std::vector<std::pair<std::string, std::string>> environment() {
#ifdef _WIN32
    char** entries = _environ;
#else
    char** entries = environ;
#endif
    std::vector<std::pair<std::string, std::string>> result;
    for (; entries != nullptr && *entries != nullptr; ++entries) {
        const std::string_view entry = *entries;
        const auto equals = entry.find('=');
        if (!entry.starts_with("APS5_") || equals == std::string_view::npos) continue;
        std::string value(entry.substr(equals + 1));
        if (value.find_first_of("/\\") != std::string::npos) value = "<path>";
        result.emplace_back(std::string(entry.substr(0, equals)), std::move(value));
    }
    std::sort(result.begin(), result.end());
    return result;
}

}

void PerformanceTrace::BindThread(const char* name, std::size_t capacity) {
    if (!Configured() || local != nullptr) return;
    auto bound = std::make_unique<TraceThread>(name, presentCount, capacity);
    auto& state = session();
    std::lock_guard lock(state.mutex);
    local = bound.get();
    state.threads.push_back(std::move(bound));
}

void PerformanceTrace::Present(std::uint32_t width, std::uint32_t height, const VulkanDevice* device) {
    const auto now = Clock::now();
    BindThread("presenter");
    auto& state = session();
    std::lock_guard lock(state.mutex);
    if (!state.window) {
        state.window.emplace(TraceWindow::Parse(std::getenv("APS5_TRACE_FRAMES"), std::getenv("APS5_TRACE_SECONDS")).value());
        state.first = now;
    }
    const auto present = state.present++;
    const auto edge = state.window->Present(present, now - state.first);
    if (edge == TraceWindow::Edge::Open) {
        state.firstPresent = present;
        state.gpuBusyAtOpen = VulkanDevice::PresentCounts().gpuBusyMs;
        TraceClockSample clock;
        if (device != nullptr && device->CalibrateClock(clock.gpuNs, clock.cpu)) state.gpuClock = clock;
        {
            std::lock_guard gpu(gpuMutex);
            gpuRanges.clear();
            gpuRanges.reserve(GpuRangeCapacity);
        }
        state.presents.push_back(now);
        presentCount.fetch_add(1, std::memory_order_relaxed);
        recording.store(true, std::memory_order_relaxed);
        ProfilePrint_nid_no_patch("[trace] recording %s from present %llu%s\n", state.window->Describe().c_str(), static_cast<unsigned long long>(present), state.gpuClock ? "" : "; no GPU track: the device has no calibrated timestamps");
        return;
    }
    if (!recording.load(std::memory_order_relaxed)) return;
    state.presents.push_back(now);
    presentCount.fetch_add(1, std::memory_order_relaxed);
    if (edge != TraceWindow::Edge::Close) return;
    recording.store(false, std::memory_order_relaxed);

    std::vector<TraceThread::Snapshot> snapshots;
    std::size_t presenter = 0;
    for (std::size_t index = 0; index < state.threads.size(); ++index) {
        if (state.threads[index].get() == local) presenter = index;
        snapshots.push_back(state.threads[index]->Collect());
    }
    std::vector<TraceThread::Slice> gpuSlices;
    TraceClockSample clock;
    if (state.gpuClock && device != nullptr && device->CalibrateClock(clock.gpuNs, clock.cpu)) {
        std::lock_guard gpu(gpuMutex);
        gpuSlices = TraceFormat::GpuSlices(gpuRanges, *state.gpuClock, clock, state.presents.front());
        snapshots.push_back({"gpu", gpuSlices, {}, gpuDropped});
    }
    const auto process = processId();
    TraceSummary summary;
    summary.commit = APS5_TRACE_COMMIT;
    if (APS5_TRACE_DIRTY >= 0) summary.dirty = APS5_TRACE_DIRTY != 0;
    summary.environment = environment();
    summary.gpu = device != nullptr ? device->DeviceName() : std::string();
    summary.driver = device != nullptr ? device->DriverInfo() : std::string();
    summary.os = operatingSystem();
    summary.width = width;
    summary.height = height;
    summary.window = state.window->Describe();
    summary.firstPresent = state.firstPresent;
    summary.gpuBusyMs = VulkanDevice::PresentCounts().gpuBusyMs - state.gpuBusyAtOpen;
    summary.trace = "aps5-trace-" + summary.commit + "-" + std::to_string(process) + ".json.gz";
    auto events = TraceFormat::Events(process, state.presents.front(), snapshots, presenter, state.presents, state.firstPresent);
    const char* traceDirectory = std::getenv("APS5_TRACE_DIR");
    auto& output = writer();
    output = std::make_unique<ProfileOutput>([directory = std::filesystem::path(traceDirectory != nullptr ? traceDirectory : "."), name = summary.trace, line = TraceFormat::Summary(summary, snapshots, state.presents)](std::string_view text) {
        try {
            std::filesystem::create_directories(directory);
            TraceFile::WriteGzip(directory / name, text);
            TraceFile::AppendLine(directory / "aps5-summary.jsonl", line);
            std::fprintf(stderr, "[trace] wrote %s and its line in aps5-summary.jsonl\n", name.c_str());
            std::fflush(stderr);
        } catch (const std::exception& error) {
            std::fprintf(stderr, "[trace] writing %s failed: %s\n", name.c_str(), error.what());
            std::fflush(stderr);
            throw;
        }
    }, std::numeric_limits<std::size_t>::max());
    ProfilePrint_nid_no_patch("[trace] closed at present %llu, writing %s (%zu bytes of JSON)\n", static_cast<unsigned long long>(present), summary.trace.c_str(), events.size());
    output->Write(std::move(events));
}

void PerformanceTrace::StopOutput() {
    if (writer()) writer()->Stop();
}

}
