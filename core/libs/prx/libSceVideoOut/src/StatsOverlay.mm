#include "prx/libSceVideoOut/include/StatsOverlay.hpp"

#import <AppKit/AppKit.h>
#include <IOKit/IOKitLib.h>
#include "SDL.h"
#include "SDL_syswm.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <sys/resource.h>
#include <unistd.h>

extern "C" std::uint64_t AgcDriverGeneratedFrames_nid_postfix();
extern "C" std::uint64_t AgcDriverUpscaledSource_nid_postfix();
extern "C" bool AgcDriverMinimalOverlayShown_nid_postfix();
extern "C" int AgcDriverOverlayCorner_nid_postfix();
extern "C" std::uint64_t AgcDriverProcessFootprint_nid_postfix();

namespace {

using Clock = std::chrono::steady_clock;
constexpr auto Interval = std::chrono::milliseconds(500);
constexpr CGFloat Margin = 12;

NSColor* Green() { return [NSColor colorWithSRGBRed:0.3 green:0.85 blue:0.45 alpha:1]; }
NSColor* Amber() { return [NSColor colorWithSRGBRed:1 green:0.75 blue:0.3 alpha:1]; }
NSColor* Red() { return [NSColor colorWithSRGBRed:1 green:0.42 blue:0.4 alpha:1]; }

// The busiest GPU's utilization, as the GPU driver reports it in the I/O Registry.
std::optional<double> GpuPercent() {
    io_iterator_t found = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &found) != KERN_SUCCESS) return std::nullopt;
    std::optional<double> busiest;
    for (io_object_t service = IOIteratorNext(found); service != IO_OBJECT_NULL; service = IOIteratorNext(found)) {
        const auto statistics = static_cast<CFDictionaryRef>(IORegistryEntryCreateCFProperty(service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0));
        if (statistics != nullptr) {
            if (CFGetTypeID(statistics) == CFDictionaryGetTypeID()) {
                const auto value = static_cast<CFNumberRef>(CFDictionaryGetValue(statistics, CFSTR("Device Utilization %")));
                long long percent = 0;
                if (value != nullptr && CFGetTypeID(value) == CFNumberGetTypeID() && CFNumberGetValue(value, kCFNumberLongLongType, &percent)) {
                    busiest = std::max(busiest.value_or(0), static_cast<double>(percent));
                }
            }
            CFRelease(statistics);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(found);
    return busiest;
}

double CpuSeconds() {
    rusage usage{};
    getrusage(RUSAGE_SELF, &usage);
    const auto seconds = [](timeval time) { return static_cast<double>(time.tv_sec) + static_cast<double>(time.tv_usec) * 1e-6; };
    return seconds(usage.ru_utime) + seconds(usage.ru_stime);
}

struct Figures {
    double fps = 0;
    // Frames generated between the game's, per second (frame generation); fps counts them too.
    double generated = 0;
    std::uint64_t upscaled = 0;
    double frameMs = 0;
    std::optional<double> gpu;
    double cpu = 0;
    std::optional<std::uint64_t> memory;
};

struct Sampler {
    Clock::time_point since = Clock::now();
    std::uint64_t frames = 0;
    double cpuSince = CpuSeconds();
    std::uint64_t generatedSince = AgcDriverGeneratedFrames_nid_postfix();

    // Counts a present; every Interval, the figures since the last ones.
    std::optional<Figures> Present() {
        ++frames;
        const auto now = Clock::now();
        if (now - since < Interval) return std::nullopt;
        const double seconds = std::chrono::duration<double>(now - since).count();
        const double cpu = CpuSeconds();
        static const double cores = static_cast<double>(std::max(1L, sysconf(_SC_NPROCESSORS_ONLN)));
        Figures figures;
        const auto generated = AgcDriverGeneratedFrames_nid_postfix();
        figures.generated = static_cast<double>(generated - generatedSince) / seconds;
        figures.upscaled = AgcDriverUpscaledSource_nid_postfix();
        figures.fps = static_cast<double>(frames) / seconds + figures.generated;
        figures.frameMs = frames > 0 ? seconds * 1000.0 / static_cast<double>(frames) : 0;
        generatedSince = generated;
        figures.gpu = GpuPercent();
        figures.cpu = std::clamp((cpu - cpuSince) / seconds / cores * 100.0, 0.0, 100.0);
        if (const auto footprint = AgcDriverProcessFootprint_nid_postfix(); footprint != 0) figures.memory = footprint;
        since = now;
        frames = 0;
        cpuSince = cpu;
        return figures;
    }

    void Reset() {
        since = Clock::now();
        frames = 0;
        cpuSince = CpuSeconds();
        generatedSince = AgcDriverGeneratedFrames_nid_postfix();
    }
};

NSAttributedString* Line(const Figures& figures) {
    NSMutableAttributedString* line = [[NSMutableAttributedString alloc] init];
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.5];
    shadow.shadowBlurRadius = 2;
    shadow.shadowOffset = NSMakeSize(0, -0.5);
    NSDictionary* label = @{NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
                            NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.55],
                            NSKernAttributeName: @0.6,
                            NSShadowAttributeName: shadow};
    NSDictionary* unit = @{NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                           NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.55],
                           NSShadowAttributeName: shadow};
    NSDictionary* divider = @{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightLight],
                              NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.22]};
    const auto value = [&](NSColor* color) {
        return @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold],
                 NSForegroundColorAttributeName: color,
                 NSShadowAttributeName: shadow};
    };
    NSColor* white = [NSColor colorWithWhite:1 alpha:0.95];
    bool first = true;
    const auto item = [&](NSString* name, NSString* figure, NSString* suffix, NSColor* color) {
        if (!first) [line appendAttributedString:[[NSAttributedString alloc] initWithString:@"   |   " attributes:divider]];
        first = false;
        if (name != nil) [line appendAttributedString:[[NSAttributedString alloc] initWithString:[name stringByAppendingString:@" "] attributes:label]];
        [line appendAttributedString:[[NSAttributedString alloc] initWithString:figure attributes:value(color)]];
        if (suffix != nil) [line appendAttributedString:[[NSAttributedString alloc] initWithString:suffix attributes:unit]];
    };
    NSColor* health = figures.fps >= 55 ? Green() : figures.fps >= 28 ? Amber() : Red();
    item(@"FPS", [NSString stringWithFormat:@"%.0f", figures.fps], nil, health);
    if (figures.generated >= 0.5) item(@"FG", [NSString stringWithFormat:@"+%.0f", figures.generated], nil, white);
    if (figures.upscaled != 0) item(@"FSR", [NSString stringWithFormat:@"%llu\u00d7%llu", static_cast<unsigned long long>(figures.upscaled >> 32), static_cast<unsigned long long>(figures.upscaled & 0xffffffffu)], nil, white);
    item(nil, [NSString stringWithFormat:@"%.1f", figures.frameMs], @" ms", white);
    if (figures.gpu) item(@"GPU", [NSString stringWithFormat:@"%.0f", *figures.gpu], @" %", white);
    item(@"CPU", [NSString stringWithFormat:@"%.0f", figures.cpu], @" %", white);
    if (figures.memory) item(@"MEM", [NSString stringWithFormat:@"%.1f", static_cast<double>(*figures.memory) / (1024.0 * 1024.0 * 1024.0)], @" GB", white);
    return line;
}

// AgcDriver's OverlayCorner, in its order.
enum class Corner { TopLeft, TopRight, BottomLeft, BottomRight };

// The capsule and its line, over the game's content view.
struct Badge {
    NSView* capsule = nil;
    NSTextField* text = nil;

    void Show(NSView* content, NSAttributedString* line, Corner corner) {
        if (capsule == nil) {
            capsule = [[NSView alloc] initWithFrame:NSZeroRect];
            capsule.wantsLayer = YES;
            capsule.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:0.38].CGColor;
            capsule.layer.borderColor = [NSColor colorWithWhite:1 alpha:0.08].CGColor;
            capsule.layer.borderWidth = 1;
            text = [NSTextField labelWithString:@""];
            text.drawsBackground = NO;
            text.bezeled = NO;
            text.editable = NO;
            text.selectable = NO;
            [capsule addSubview:text];
        }
        if (capsule.superview != content) {
            [capsule removeFromSuperview];
            [content addSubview:capsule positioned:NSWindowAbove relativeTo:nil];
        }
        capsule.hidden = NO;
        text.attributedStringValue = line;
        [text sizeToFit];
        const NSSize size = text.frame.size;
        const CGFloat width = std::ceil(size.width) + 24;
        const CGFloat height = std::ceil(size.height) + 8;
        text.frame = NSMakeRect(12, std::round((height - size.height) / 2), std::ceil(size.width), size.height);
        capsule.layer.cornerRadius = height / 2;
        const NSRect bounds = content.bounds;
        const bool top = corner == Corner::TopLeft || corner == Corner::TopRight;
        const bool right = corner == Corner::TopRight || corner == Corner::BottomRight;
        const CGFloat x = right ? NSMaxX(bounds) - width - Margin : NSMinX(bounds) + Margin;
        const bool high = top != content.isFlipped;
        const CGFloat y = high ? NSMaxY(bounds) - height - Margin : NSMinY(bounds) + Margin;
        capsule.frame = NSMakeRect(x, y, width, height);
        capsule.autoresizingMask = (right ? NSViewMinXMargin : NSViewMaxXMargin) | (high ? NSViewMinYMargin : NSViewMaxYMargin);
    }

    void Hide() {
        if (capsule != nil) capsule.hidden = YES;
    }
};

}

void StatsOverlay::Present(SDL_Window* window) {
    static Sampler sampler;
    static Badge badge;
    static bool shown = false;
    const bool wanted = AgcDriverMinimalOverlayShown_nid_postfix();
    if (!wanted) {
        if (shown) badge.Hide();
        shown = false;
        return;
    }
    if (!shown) sampler.Reset();
    const auto figures = sampler.Present();
    // ANYPS5_OVERLAY_LOG=1 also writes the figures to the game's log every five seconds, for
    // measuring without looking at the window.
    static const bool logged = std::getenv("ANYPS5_OVERLAY_LOG") != nullptr;
    static int samples = 0;
    if (logged && figures && ++samples % 10 == 0) {
        std::fprintf(stderr, "[overlay] fps %.1f (game %.1f, generated %.1f) frame %.1f ms gpu %.0f%% cpu %.0f%%\n", figures->fps, figures->fps - figures->generated,
                     figures->generated, figures->frameMs, figures->gpu.value_or(-1), figures->cpu);
    }
    if (shown && !figures) return;
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (window == nullptr || SDL_GetWindowWMInfo(window, &info) != SDL_TRUE || info.subsystem != SDL_SYSWM_COCOA || info.info.cocoa.window == nullptr) return;
    NSView* content = info.info.cocoa.window.contentView;
    if (content == nil) return;
    @autoreleasepool {
        badge.Show(content, Line(figures.value_or(Figures{})), static_cast<Corner>(AgcDriverOverlayCorner_nid_postfix()));
    }
    shown = true;
}
