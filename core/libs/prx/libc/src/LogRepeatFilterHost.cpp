// Puts LogRepeatFilter in front of the host standard output and error, which the launcher sends to the game log.
// Writes reach them through the host FILE streams (printf from the title and the engine) and through libkernel's
// write() to descriptors 1 and 2; both paths share one filter per stream.
#include "prx/libc/include/LogRepeatFilter.hpp"

#ifndef _WIN32
#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <unistd.h>

namespace {

struct FilteredStream {
    std::mutex mutex;
    LogRepeatFilter filter;
};

std::array<FilteredStream, 2>& Streams() {
    static auto* streams = new std::array<FilteredStream, 2>();
    return *streams;
}

bool WriteAll(int descriptor, std::string_view piece) {
    while (!piece.empty()) {
        const auto written = ::write(descriptor, piece.data(), piece.size());
        if (written < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        piece.remove_prefix(static_cast<std::size_t>(written));
    }
    return true;
}

#ifdef __APPLE__
using StreamWrite = int (*)(void*, const char*, int);

struct Hook {
    std::FILE* file = nullptr;
    StreamWrite original = nullptr;
    int standard = 0;
};

std::mutex& HookMutex() {
    static auto* mutex = new std::mutex;
    return *mutex;
}
std::array<Hook, 4> g_hooks{};

Hook FindHook(void* cookie) {
    const std::lock_guard lock(HookMutex());
    for (const auto& hook : g_hooks)
        if (hook.file == cookie) return hook;
    return {};
}

int FilteredStreamWrite(void* cookie, const char* data, int size) {
    const Hook hook = FindHook(cookie);
    if (hook.original == nullptr) return -1;
    if (size <= 0) return hook.original(cookie, data, size);
    auto& stream = Streams()[static_cast<std::size_t>(hook.standard - 1)];
    bool failed = false;
    const std::lock_guard lock(stream.mutex);
    stream.filter.Write(std::string_view(data, static_cast<std::size_t>(size)), LogRepeatFilter::Clock::now(), [&](std::string_view piece) {
        while (!failed && !piece.empty()) {
            const int written = hook.original(cookie, piece.data(), static_cast<int>(piece.size()));
            if (written <= 0) failed = true;
            else piece.remove_prefix(static_cast<std::size_t>(written));
        }
    });
    return failed ? -1 : size;
}
#endif

void FlushAtExit() {
    for (int standard = 1; standard <= 2; ++standard) {
        auto& stream = Streams()[static_cast<std::size_t>(standard - 1)];
        std::FILE* file = standard == 1 ? stdout : stderr;
        std::fflush(file);
        const int descriptor = ::fileno(file);
        const std::lock_guard lock(stream.mutex);
        stream.filter.Flush(LogRepeatFilter::Clock::now(), [&](std::string_view piece) { WriteAll(descriptor, piece); });
    }
}

}

extern "C" {

// Writes data that the title sent to its standard output (1) or error (2), which still reach the host's.
void LogRepeatFilterWrite_nid_no_patch(int standard, int descriptor, const void* data, std::size_t size) {
    auto& stream = Streams()[static_cast<std::size_t>(standard == 2 ? 1 : 0)];
    const std::lock_guard lock(stream.mutex);
    stream.filter.Write(std::string_view(static_cast<const char*>(data), size), LogRepeatFilter::Clock::now(),
        [&](std::string_view piece) { WriteAll(descriptor, piece); });
}

// Filters a host stream that writes to the log. A stream whose descriptor stops being the log is unhooked.
void LogRepeatFilterHookStream_nid_no_patch(std::FILE* file, int standard) {
#ifdef __APPLE__
    if (file == nullptr || file->_cookie != file || file->_write == nullptr || file->_write == FilteredStreamWrite) return;
    const std::lock_guard lock(HookMutex());
    for (auto& hook : g_hooks) {
        if (hook.file != nullptr) continue;
        hook = {file, file->_write, standard};
        file->_write = FilteredStreamWrite;
        return;
    }
#else
    (void)file;
    (void)standard;
#endif
}

void LogRepeatFilterUnhookStream_nid_no_patch(std::FILE* file) {
#ifdef __APPLE__
    const std::lock_guard lock(HookMutex());
    for (auto& hook : g_hooks) {
        if (hook.file != file) continue;
        if (file->_write == FilteredStreamWrite) file->_write = hook.original;
        hook = {};
    }
#else
    (void)file;
#endif
}

}

namespace {
const bool g_logRepeatFilterInstalled = [] {
    LogRepeatFilterHookStream_nid_no_patch(stdout, 1);
    LogRepeatFilterHookStream_nid_no_patch(stderr, 2);
    std::atexit(FlushAtExit);
    return true;
}();
}
#endif
