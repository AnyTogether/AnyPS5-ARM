#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libkernel/File/include/File.hpp"
#include "prx/libkernel/File/include/RandomDevice.hpp"
#include "prx/libkernel/Socket/include/SocketPoll.hpp"
#include "prx/libkernel/Socket/include/SocketSelectDeadline.hpp"
#include "prx/libkernel/Socket/include/SocketRuntime.hpp"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <thread>
#include <vector>

#ifndef _WIN32
#include <poll.h>
#endif

namespace {

constexpr int GuestEbadf = 9;
constexpr int GuestEinval = 22;
constexpr int SelectDescriptorLimit = 1024;
constexpr int SelectPollSliceMilliseconds = 10;

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

// A descriptor that neither libSceNet nor the host can poll is a file which, as on FreeBSD, is always
// ready for reading and writing and never has exceptional conditions; false when it is not open.
bool FileReadiness(KernelSocketPoll::Entry& entry) {
    if (!DescriptorIsOpen_nid_no_patch(entry.descriptor)) return false;
    entry.revents = static_cast<short>(entry.events & (KernelSocketPoll::Readable | KernelSocketPoll::Writable));
    return true;
}

#ifndef _WIN32

short HostEventFlags(short events) {
    short flags = 0;
    if ((events & KernelSocketPoll::Readable) != 0) flags |= POLLIN;
    if ((events & KernelSocketPoll::Writable) != 0) flags |= POLLOUT;
    return flags;
}

short KernelEventFlags(short revents) {
    short flags = 0;
    if ((revents & POLLIN) != 0) flags |= KernelSocketPoll::Readable;
    if ((revents & POLLOUT) != 0) flags |= KernelSocketPoll::Writable;
    if ((revents & POLLERR) != 0) flags |= KernelSocketPoll::Error;
    if ((revents & POLLHUP) != 0) flags |= KernelSocketPoll::HangUp;
    return flags;
}

int HostPoll(KernelSocketPoll::Entry* descriptors, std::size_t count, int timeoutMilliseconds) {
    std::vector<struct pollfd> native(count);
    for (std::size_t index = 0; index < count; ++index) {
        native[index].fd = descriptors[index].descriptor;
        native[index].events = descriptors[index].events;
        native[index].revents = 0;
    }
    const int result = ::poll(native.data(), static_cast<nfds_t>(count), timeoutMilliseconds);
    if (result < 0) return -1;
    for (std::size_t index = 0; index < count; ++index) {
        if ((native[index].revents & POLLNVAL) != 0) {
            errno = EBADF;
            return -1;
        }
        descriptors[index].revents = KernelEventFlags(native[index].revents);
    }
    return result;
}

#ifdef __APPLE__
// macOS poll() does not support devices: each host descriptor it refuses that is open is settled in
// `requested` as a file and dropped from `hosts`; false when one is not open.
bool SettleUnpollable(std::vector<KernelSocketPoll::Entry>& hosts, std::vector<std::size_t>& hostSlots, std::vector<KernelSocketPoll::Entry>& requested, bool& filesReady) {
    std::vector<struct pollfd> native(hosts.size());
    for (std::size_t index = 0; index < hosts.size(); ++index) native[index] = {hosts[index].descriptor, hosts[index].events, 0};
    // A failing probe settles nothing; the polls that follow report the error.
    if (::poll(native.data(), static_cast<nfds_t>(native.size()), 0) < 0) return true;
    for (std::size_t index = native.size(); index-- > 0;) {
        if ((native[index].revents & POLLNVAL) == 0) continue;
        auto& entry = requested[hostSlots[index]];
        if (!FileReadiness(entry)) return false;
        filesReady = filesReady || entry.revents != 0;
        hosts.erase(hosts.begin() + static_cast<std::ptrdiff_t>(index));
        hostSlots.erase(hostSlots.begin() + static_cast<std::ptrdiff_t>(index));
    }
    return true;
}
#endif

#endif

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

// Sockets are polled through libSceNet and other host descriptors through the host's poll. /dev/urandom,
// and any open descriptor the host cannot poll, is a file, which, as on FreeBSD, is always ready for
// reading and writing and never has exceptional conditions; the standard descriptors only accept output.
int APS5_VABI select_nid_postfix(int nfds, void* readfds, void* writefds, void* exceptfds, const void* timeout) {
    const auto* limit = static_cast<const GuestTimeval*>(timeout);
    if (nfds < 0 || nfds > SelectDescriptorLimit || (limit != nullptr && (limit->seconds < 0 || limit->microseconds < 0 || limit->microseconds >= 1000000))) {
        *__error_nid_postfix() = GuestEinval;
        return -1;
    }
    std::vector<KernelSocketPoll::Entry> sockets;
    std::vector<std::size_t> socketSlots;
    std::vector<KernelSocketPoll::Entry> hosts;
    std::vector<std::size_t> hostSlots;
    std::vector<KernelSocketPoll::Entry> devices;
    std::vector<KernelSocketPoll::Entry> requested;
    for (int descriptor = 0; descriptor < nfds; ++descriptor) {
        short events = 0;
        if (DescriptorSet(readfds, descriptor)) events |= KernelSocketPoll::Readable;
        if (DescriptorSet(writefds, descriptor)) events |= KernelSocketPoll::Writable;
        if (DescriptorSet(exceptfds, descriptor)) events |= KernelSocketPoll::Urgent;
        if (events == 0) continue;
        if (File::IsRandomDevice(descriptor)) devices.push_back({descriptor, events, static_cast<short>(events & (KernelSocketPoll::Readable | KernelSocketPoll::Writable))});
        // The standard descriptors have no console behind them: stdin never has input, and output is always accepted.
        else if (descriptor <= 2) devices.push_back({descriptor, events, static_cast<short>(descriptor == 0 ? 0 : events & KernelSocketPoll::Writable)});
        else {
            sockets.push_back({descriptor, events, 0});
            socketSlots.push_back(requested.size());
            requested.push_back({descriptor, events, 0});
        }
    }
    for (const auto& device : devices) requested.push_back(device);
    bool devicesReady = std::any_of(devices.begin(), devices.end(), [](const auto& entry) { return entry.revents != 0; });
    // Moves sockets[index], which is not a libSceNet socket, to the host descriptors, or settles it as a
    // file where the host cannot poll it; false when the descriptor is not open.
    const auto notSocket = [&](std::size_t index) {
        const auto entry = sockets[index];
        const auto slot = socketSlots[index];
        sockets.erase(sockets.begin() + static_cast<std::ptrdiff_t>(index));
        socketSlots.erase(socketSlots.begin() + static_cast<std::ptrdiff_t>(index));
#ifndef _WIN32
        if (entry.descriptor < GuestSockets::FirstDescriptor) {
            hosts.push_back({entry.descriptor, HostEventFlags(entry.events), 0});
            hostSlots.push_back(slot);
            return true;
        }
#endif
        if (!FileReadiness(requested[slot])) return false;
        devicesReady = devicesReady || requested[slot].revents != 0;
        return true;
    };
    const auto poller = g_socketPoller.load();
    if (!sockets.empty()) {
        if (poller == nullptr) {
            while (!sockets.empty()) {
                if (!notSocket(0)) {
                    *__error_nid_postfix() = GuestEbadf;
                    return -1;
                }
            }
        } else {
            for (auto& socket : sockets) socket.revents = 0;
            const int probe = poller(sockets.data(), static_cast<int>(sockets.size()), 0);
            if (probe < 0) {
                *__error_nid_postfix() = -probe;
                return -1;
            }
            for (std::size_t index = 0; index < sockets.size();) {
                if ((sockets[index].revents & KernelSocketPoll::Unknown) == 0) {
                    ++index;
                    continue;
                }
                if (!notSocket(index)) {
                    *__error_nid_postfix() = GuestEbadf;
                    return -1;
                }
            }
        }
    }
#ifdef __APPLE__
    if (!hosts.empty() && !SettleUnpollable(hosts, hostSlots, requested, devicesReady)) {
        *__error_nid_postfix() = GuestEbadf;
        return -1;
    }
#endif
    const auto start = std::chrono::steady_clock::now();
    const auto deadline = limit == nullptr ? std::chrono::steady_clock::time_point::max()
        : KernelSocketSelect::DeadlineAfter(start, limit->seconds, limit->microseconds);
    for (;;) {
        int waitMilliseconds = 100;
        if (limit != nullptr) {
            const auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(deadline - std::chrono::steady_clock::now()).count();
            const auto roundedMilliseconds = remaining > 0 ? remaining / 1000 + (remaining % 1000 != 0) : 0;
            waitMilliseconds = static_cast<int>(std::clamp<std::int64_t>(roundedMilliseconds, 0, 100));
        }
        if (devicesReady) waitMilliseconds = 0;
#ifndef _WIN32
        if (!hosts.empty() && !sockets.empty()) {
            const auto sliceEnd = std::chrono::steady_clock::now() + std::chrono::milliseconds(waitMilliseconds);
            for (;;) {
                for (auto& host : hosts) host.revents = 0;
                const int hostReady = HostPoll(hosts.data(), hosts.size(), SelectPollSliceMilliseconds);
                if (hostReady < 0) {
                    *__error_nid_postfix() = errno;
                    return -1;
                }
                for (std::size_t index = 0; index < hosts.size(); ++index) requested[hostSlots[index]].revents = hosts[index].revents;
                for (auto& socket : sockets) socket.revents = 0;
                const int socketReady = poller(sockets.data(), static_cast<int>(sockets.size()), SelectPollSliceMilliseconds);
                if (socketReady < 0) {
                    *__error_nid_postfix() = -socketReady;
                    return -1;
                }
                for (std::size_t index = 0; index < sockets.size(); ++index) requested[socketSlots[index]].revents = sockets[index].revents;
                if (hostReady > 0 || socketReady > 0) break;
                if (std::chrono::steady_clock::now() >= sliceEnd) break;
            }
        } else if (!hosts.empty()) {
            for (auto& host : hosts) host.revents = 0;
            if (HostPoll(hosts.data(), hosts.size(), waitMilliseconds) < 0) {
                *__error_nid_postfix() = errno;
                return -1;
            }
            for (std::size_t index = 0; index < hosts.size(); ++index) requested[hostSlots[index]].revents = hosts[index].revents;
        } else
#endif
        if (!sockets.empty()) {
            for (auto& socket : sockets) socket.revents = 0;
            const int result = poller(sockets.data(), static_cast<int>(sockets.size()), waitMilliseconds);
            if (result < 0) {
                *__error_nid_postfix() = -result;
                return -1;
            }
            for (std::size_t index = 0; index < sockets.size(); ++index) requested[socketSlots[index]].revents = sockets[index].revents;
        } else if (waitMilliseconds > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(waitMilliseconds));
        }
        int ready = 0;
        for (const auto& entry : requested) {
            // libSceNet no longer knows a socket closed while select waited.
            if ((entry.revents & KernelSocketPoll::Unknown) != 0) {
                *__error_nid_postfix() = GuestEbadf;
                return -1;
            }
            const bool readable = (entry.events & KernelSocketPoll::Readable) != 0 && (entry.revents & (KernelSocketPoll::Readable | KernelSocketPoll::HangUp | KernelSocketPoll::Error)) != 0;
            const bool writable = (entry.events & KernelSocketPoll::Writable) != 0 && (entry.revents & (KernelSocketPoll::Writable | KernelSocketPoll::Error)) != 0;
            const bool urgent = (entry.events & KernelSocketPoll::Urgent) != 0 && (entry.revents & KernelSocketPoll::Urgent) != 0;
            ready += static_cast<int>(readable) + static_cast<int>(writable) + static_cast<int>(urgent);
        }
        if (ready > 0) {
            for (const auto& entry : requested) {
                if ((entry.revents & (KernelSocketPoll::Readable | KernelSocketPoll::HangUp | KernelSocketPoll::Error)) == 0) ClearDescriptor(readfds, entry.descriptor);
                if ((entry.revents & (KernelSocketPoll::Writable | KernelSocketPoll::Error)) == 0) ClearDescriptor(writefds, entry.descriptor);
                if ((entry.revents & KernelSocketPoll::Urgent) == 0) ClearDescriptor(exceptfds, entry.descriptor);
            }
            return ready;
        }
        if (limit != nullptr && std::chrono::steady_clock::now() >= deadline) {
            for (const auto& entry : requested) {
                ClearDescriptor(readfds, entry.descriptor);
                ClearDescriptor(writefds, entry.descriptor);
                ClearDescriptor(exceptfds, entry.descriptor);
            }
            return 0;
        }
    }
}

}
