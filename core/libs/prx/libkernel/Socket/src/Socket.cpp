#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libkernel/File/include/File.hpp"
#include "prx/libkernel/File/include/RandomDevice.hpp"
#include "prx/libkernel/Socket/include/SocketPoll.hpp"
#include "prx/libkernel/Socket/include/SocketSelectDeadline.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

namespace {

constexpr int GuestEbadf = 9;
constexpr int GuestEinval = 22;
constexpr int SelectDescriptorLimit = 1024;

struct GuestTimeval {
    std::int64_t seconds;
    std::int64_t microseconds;
};

std::atomic<KernelSocketPoll::Poller> g_socketPoller{nullptr};

bool DescriptorSet(const void* set, int descriptor) {
    return set != nullptr && ((static_cast<const std::uint64_t*>(set)[descriptor / 64] >> (descriptor % 64)) & 1u) != 0;
}

void ClearDescriptor(void* set, int descriptor) {
    if (set != nullptr) static_cast<std::uint64_t*>(set)[descriptor / 64] &= ~(std::uint64_t{1} << (descriptor % 64));
}

}

extern "C" {

const char* APS5_VABI __inet_ntop_nid_postfix(int family, const void* source, char* destination, std::uint32_t capacity);
int APS5_VABI __inet_pton_nid_postfix(int family, const char* text, void* destination);

const char* APS5_VABI inet_ntop_nid_postfix(int af, const void* src, char* dst, uint32_t size) {
    return __inet_ntop_nid_postfix(af, src, dst, size);
}

int APS5_VABI inet_pton_nid_postfix(int af, const char* src, void* dst) {
    return __inet_pton_nid_postfix(af, src, dst);
}

int* APS5_VABI __error_nid_postfix();

void KernelSetSocketPoller_nid_no_patch(KernelSocketPoll::Poller poller) {
    g_socketPoller.store(poller);
}

// Sockets are polled through libSceNet. /dev/urandom and any other open descriptor is a file, which,
// as on FreeBSD, is always ready for reading and writing and never has exceptional conditions; the
// standard descriptors only accept output.
int APS5_VABI select_nid_postfix(int nfds, void* readfds, void* writefds, void* exceptfds, const void* timeout) {
    const auto* limit = static_cast<const GuestTimeval*>(timeout);
    if (nfds < 0 || nfds > SelectDescriptorLimit || (limit != nullptr && (limit->seconds < 0 || limit->microseconds < 0 || limit->microseconds >= 1000000))) {
        *__error_nid_postfix() = GuestEinval;
        return -1;
    }
    std::vector<KernelSocketPoll::Entry> entries;
    for (int descriptor = 0; descriptor < nfds; ++descriptor) {
        short events = 0;
        if (DescriptorSet(readfds, descriptor)) events |= KernelSocketPoll::Readable;
        if (DescriptorSet(writefds, descriptor)) events |= KernelSocketPoll::Writable;
        if (DescriptorSet(exceptfds, descriptor)) events |= KernelSocketPoll::Urgent;
        if (events != 0) entries.push_back({descriptor, events, 0});
    }
    const auto poller = g_socketPoller.load();
    std::vector<KernelSocketPoll::Entry> sockets;
    std::vector<KernelSocketPoll::Entry> files;
    if (poller != nullptr && !entries.empty()) {
        const int result = poller(entries.data(), static_cast<int>(entries.size()), 0);
        if (result < 0) {
            *__error_nid_postfix() = -result;
            return -1;
        }
    }
    for (auto& entry : entries) {
        if (poller != nullptr && (entry.revents & KernelSocketPoll::Unknown) == 0) {
            sockets.push_back(entry);
            continue;
        }
        if (File::IsRandomDevice(entry.descriptor)) {
            entry.revents = static_cast<short>(entry.events & (KernelSocketPoll::Readable | KernelSocketPoll::Writable));
        } else if (entry.descriptor <= 2) {
            // The standard descriptors have no console behind them: stdin never has input, and output is always accepted.
            entry.revents = static_cast<short>(entry.descriptor == 0 ? 0 : entry.events & KernelSocketPoll::Writable);
        } else {
            if (!DescriptorIsOpen_nid_no_patch(entry.descriptor)) {
                *__error_nid_postfix() = GuestEbadf;
                return -1;
            }
            entry.revents = static_cast<short>(entry.events & (KernelSocketPoll::Readable | KernelSocketPoll::Writable));
        }
        files.push_back(entry);
    }
    const auto finish = [&] {
        int ready = 0;
        for (const auto* group : {&sockets, &files}) {
            for (const auto& entry : *group) {
                const bool readable = (entry.events & KernelSocketPoll::Readable) != 0 && (entry.revents & (KernelSocketPoll::Readable | KernelSocketPoll::HangUp | KernelSocketPoll::Error)) != 0;
                const bool writable = (entry.events & KernelSocketPoll::Writable) != 0 && (entry.revents & (KernelSocketPoll::Writable | KernelSocketPoll::Error)) != 0;
                const bool urgent = (entry.events & KernelSocketPoll::Urgent) != 0 && (entry.revents & KernelSocketPoll::Urgent) != 0;
                if (!readable) ClearDescriptor(readfds, entry.descriptor);
                if (!writable) ClearDescriptor(writefds, entry.descriptor);
                if (!urgent) ClearDescriptor(exceptfds, entry.descriptor);
                ready += static_cast<int>(readable) + static_cast<int>(writable) + static_cast<int>(urgent);
            }
        }
        return ready;
    };
    const auto anyReady = [](const std::vector<KernelSocketPoll::Entry>& group) {
        return std::any_of(group.begin(), group.end(), [](const auto& entry) {
            return (entry.events & KernelSocketPoll::Readable && entry.revents & (KernelSocketPoll::Readable | KernelSocketPoll::HangUp | KernelSocketPoll::Error)) ||
                (entry.events & KernelSocketPoll::Writable && entry.revents & (KernelSocketPoll::Writable | KernelSocketPoll::Error)) ||
                (entry.events & KernelSocketPoll::Urgent && entry.revents & KernelSocketPoll::Urgent);
        });
    };
    if (anyReady(sockets) || anyReady(files)) return finish();
    const auto start = std::chrono::steady_clock::now();
    const auto deadline = limit == nullptr ? std::chrono::steady_clock::time_point::max()
        : KernelSocketSelect::DeadlineAfter(start, limit->seconds, limit->microseconds);
    for (;;) {
        if (limit != nullptr && std::chrono::steady_clock::now() >= deadline) {
            for (auto* group : {&sockets, &files}) {
                for (auto& entry : *group) entry.revents = 0;
            }
            return finish();
        }
        int waitMilliseconds = 100;
        if (limit != nullptr) {
            const auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(deadline - std::chrono::steady_clock::now()).count();
            waitMilliseconds = static_cast<int>(std::clamp<std::int64_t>((remaining + 999) / 1000, 0, 100));
        }
        if (!sockets.empty()) {
            for (auto& entry : sockets) entry.revents = 0;
            const int result = poller(sockets.data(), static_cast<int>(sockets.size()), waitMilliseconds);
            if (result < 0) {
                *__error_nid_postfix() = -result;
                return -1;
            }
            const bool closed = std::any_of(sockets.begin(), sockets.end(), [](const auto& entry) { return (entry.revents & KernelSocketPoll::Unknown) != 0; });
            if (closed) {
                *__error_nid_postfix() = GuestEbadf;
                return -1;
            }
            if (anyReady(sockets)) return finish();
        } else if (waitMilliseconds > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(waitMilliseconds));
        }
    }
}

}
