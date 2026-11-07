#include "prx/libc/include/GuestWriteWatch.hpp"
#include "prx/libc/include/FatalLine.hpp"
#include <algorithm>
#include <array>
#include <string>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <map>
#include <mutex>
#include <shared_mutex>
#include <type_traits>
#include <utility>
#include <vector>

#if defined(__linux__)
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <linux/fs.h>
#include <linux/userfaultfd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <atomic>
#include <chrono>
#include <cerrno>
#include <csignal>
#include <cstring>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/semaphore.h>
#include <memory>
#include <pthread.h>
#include <sched.h>
#include <setjmp.h>
#include <sys/mman.h>
#include <sys/ucontext.h>
#include <type_traits>
#include <unistd.h>
#include <unordered_map>
#endif

#if (defined(__linux__) && defined(PAGEMAP_SCAN) && defined(UFFD_FEATURE_WP_ASYNC)) || defined(__APPLE__)
#define APS5_GUEST_WRITE_WATCH 1
#endif

namespace GuestWriteWatch {
namespace {

#if defined(__linux__) && defined(PAGEMAP_SCAN) && defined(UFFD_FEATURE_WP_ASYNC)
constexpr std::uintptr_t PageBytes = 4096;

class Watch {
public:
    static Watch& Get() {
        static auto* watch = new Watch;
        return *watch;
    }

    bool Available() const {
        return _pagemap >= 0;
    }

    void Register(std::uintptr_t begin, std::uintptr_t end) {
        if (!Available() || end <= begin) return;
        std::unique_lock lock(_lock);
        remove(_ranges, begin, end);
        remove(_fresh, begin, end);
        uffdio_register registration{};
        registration.range.start = begin;
        registration.range.len = end - begin;
        registration.mode = UFFDIO_REGISTER_MODE_WP;
        if (ioctl(_uffd, UFFDIO_REGISTER, &registration) != 0) {
            static bool reported = false;
            if (!reported) {
                reported = true;
                std::fprintf(stderr, "[memory] write watch: cannot register 0x%llx+0x%llx (%s); the range stays unwatched\n", static_cast<unsigned long long>(begin), static_cast<unsigned long long>(end - begin), std::strerror(errno));
            }
            return;
        }
        insert(_ranges, begin, end);
        insert(_fresh, begin, end);
    }

    bool Unregister(std::uintptr_t begin, std::uintptr_t end) {
        if (!Available() || end <= begin) return false;
        std::unique_lock lock(_lock);
        const bool watched = remove(_ranges, begin, end);
        remove(_fresh, begin, end);
        return watched;
    }

    bool Covers(std::uintptr_t begin, std::uintptr_t end) {
        if (!Available()) return false;
        std::shared_lock lock(_lock);
        return covers(begin, end);
    }

    bool Overlaps(std::uintptr_t begin, std::uintptr_t end) {
        if (!Available()) return false;
        std::shared_lock lock(_lock);
        const auto next = _ranges.upper_bound(begin);
        return (next != _ranges.begin() && std::prev(next)->second > begin) || (next != _ranges.end() && next->first < end);
    }

    bool Collect(std::uintptr_t begin, std::uintptr_t end, void (*written)(void*, std::uintptr_t, std::uintptr_t), void* context) {
        if (!Available()) return false;
        begin &= ~(PageBytes - 1);
        end = (end + PageBytes - 1) & ~(PageBytes - 1);
        if (end <= begin) return true;
        if (!takeFresh(begin, end, true, written, context)) return false;
        return scanWritten(begin, end, written, context);
    }

    bool CollectFresh(std::uintptr_t begin, std::uintptr_t end, void (*written)(void*, std::uintptr_t, std::uintptr_t), void* context) {
        if (!Available()) return false;
        begin &= ~(PageBytes - 1);
        end = (end + PageBytes - 1) & ~(PageBytes - 1);
        if (end <= begin) return true;
        {
            std::shared_lock lock(_lock);
            auto it = _fresh.upper_bound(begin);
            if (it != _fresh.begin()) --it;
            while (it != _fresh.end() && it->first < end && it->second <= begin) ++it;
            if (it == _fresh.end() || it->first >= end) return true;
        }
        return takeFresh(begin, end, false, written, context);
    }

    bool CollectArmed(std::uintptr_t begin, std::uintptr_t end, void (*written)(void*, std::uintptr_t, std::uintptr_t), void* context) {
        if (!Available()) return false;
        begin &= ~(PageBytes - 1);
        end = (end + PageBytes - 1) & ~(PageBytes - 1);
        if (end <= begin) return true;
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> armed;
        {
            std::shared_lock lock(_lock);
            if (!covers(begin, end)) return false;
            auto cursor = begin;
            auto it = _fresh.upper_bound(begin);
            if (it != _fresh.begin()) --it;
            for (; it != _fresh.end() && it->first < end; ++it) {
                if (it->second <= cursor) continue;
                if (it->first > cursor) armed.emplace_back(cursor, it->first);
                cursor = std::max(cursor, it->second);
            }
            if (cursor < end) armed.emplace_back(cursor, end);
        }
        for (const auto& [from, to] : armed) {
            if (!scanWritten(from, to, written, context)) return false;
        }
        return true;
    }

private:
    bool takeFresh(std::uintptr_t begin, std::uintptr_t end, bool whole, void (*written)(void*, std::uintptr_t, std::uintptr_t), void* context) {
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> fresh;
        {
            std::unique_lock lock(_lock);
            if (whole && !covers(begin, end)) return false;
            auto it = _fresh.upper_bound(begin);
            if (it != _fresh.begin()) --it;
            for (; it != _fresh.end() && it->first < end; ++it) {
                const auto from = std::max(it->first, begin);
                const auto to = std::min(it->second, end);
                if (from < to) fresh.emplace_back(from, to);
            }
            for (const auto& [from, to] : fresh) remove(_fresh, from, to);
        }
        for (const auto& [from, to] : fresh) {
            written(context, from, to);
            if (protect(from, to)) continue;
            std::unique_lock lock(_lock);
            for (const auto& [left, right] : fresh) {
                if (!covers(left, right)) continue;
                remove(_fresh, left, right);
                insert(_fresh, left, right);
            }
            if (whole) written(context, begin, end);
            else for (const auto& [left, right] : fresh) written(context, left, right);
            return false;
        }
        return true;
    }

    bool scanWritten(std::uintptr_t begin, std::uintptr_t end, void (*written)(void*, std::uintptr_t, std::uintptr_t), void* context) const {
        std::array<page_region, 256> regions;
        auto cursor = begin;
        while (cursor < end) {
            pm_scan_arg scan{};
            scan.size = sizeof(scan);
            scan.flags = PM_SCAN_WP_MATCHING | PM_SCAN_CHECK_WPASYNC;
            scan.start = cursor;
            scan.end = end;
            scan.vec = reinterpret_cast<std::uintptr_t>(regions.data());
            scan.vec_len = regions.size();
            scan.category_mask = PAGE_IS_WRITTEN;
            scan.return_mask = PAGE_IS_WRITTEN;
            const auto count = ioctl(_pagemap, PAGEMAP_SCAN, &scan);
            if (count < 0) {
                written(context, cursor, end);
                return false;
            }
            for (long i = 0; i < count; ++i) written(context, regions[i].start, regions[i].end);
            if (scan.walk_end <= cursor || scan.walk_end >= end) break;
            cursor = scan.walk_end;
        }
        return true;
    }

private:
    Watch() {
        if (std::getenv("APS5_NO_WRITE_WATCH") == nullptr) open();
    }

    void open() {
        _uffd = static_cast<int>(syscall(SYS_userfaultfd, O_CLOEXEC | O_NONBLOCK));
        if (_uffd < 0 && errno == EPERM) _uffd = static_cast<int>(syscall(SYS_userfaultfd, O_CLOEXEC | O_NONBLOCK | UFFD_USER_MODE_ONLY));
        if (_uffd < 0) return unavailable("userfaultfd");
        uffdio_api api{};
        api.api = UFFD_API;
        api.features = UFFD_FEATURE_WP_ASYNC | UFFD_FEATURE_WP_UNPOPULATED;
        if (ioctl(_uffd, UFFDIO_API, &api) != 0 || (api.features & UFFD_FEATURE_WP_ASYNC) == 0 || (api.features & UFFD_FEATURE_WP_UNPOPULATED) == 0) return unavailable("asynchronous userfaultfd write protection");
        const int pagemap = ::open("/proc/self/pagemap", O_RDONLY | O_CLOEXEC);
        if (pagemap < 0) return unavailable("/proc/self/pagemap");
        if (!probe(pagemap)) {
            close(pagemap);
            return unavailable("PAGEMAP_SCAN");
        }
        _pagemap = pagemap;
    }

    void unavailable(const char* what) {
        const int error = errno;
        if (_uffd >= 0) close(_uffd);
        _uffd = -1;
        std::fprintf(stderr, "[memory] write watch unavailable: %s failed (%s); guest memory is compared instead\n", what, std::strerror(error));
    }

    bool protect(std::uintptr_t begin, std::uintptr_t end) const {
        uffdio_writeprotect protection{};
        protection.range.start = begin;
        protection.range.len = end - begin;
        protection.mode = UFFDIO_WRITEPROTECT_MODE_WP;
        return ioctl(_uffd, UFFDIO_WRITEPROTECT, &protection) == 0;
    }

    bool probe(int pagemap) {
        constexpr std::uintptr_t probeBytes = 4 * PageBytes;
        void* pages = mmap(nullptr, probeBytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (pages == MAP_FAILED) return false;
        const auto address = reinterpret_cast<std::uintptr_t>(pages);
        auto* bytes = static_cast<volatile char*>(pages);
        bytes[0] = 1;
        uffdio_register registration{};
        registration.range.start = address;
        registration.range.len = probeBytes;
        registration.mode = UFFDIO_REGISTER_MODE_WP;
        bool working = ioctl(_uffd, UFFDIO_REGISTER, &registration) == 0 && protect(address, address + probeBytes);
        std::array<page_region, 4> regions{};
        const auto scan = [&]() -> long {
            pm_scan_arg arguments{};
            arguments.size = sizeof(arguments);
            arguments.flags = PM_SCAN_WP_MATCHING | PM_SCAN_CHECK_WPASYNC;
            arguments.start = address;
            arguments.end = address + probeBytes;
            arguments.vec = reinterpret_cast<std::uintptr_t>(regions.data());
            arguments.vec_len = regions.size();
            arguments.category_mask = PAGE_IS_WRITTEN;
            arguments.return_mask = PAGE_IS_WRITTEN;
            const auto count = ioctl(pagemap, PAGEMAP_SCAN, &arguments);
            if (count < 0) return -1;
            long pagesWritten = 0;
            for (long i = 0; i < count; ++i) pagesWritten += static_cast<long>((regions[i].end - regions[i].start) / PageBytes);
            return pagesWritten;
        };
        working = working && scan() == 0;
        if (working) {
            bytes[0] = 2;
            bytes[2 * PageBytes] = 1;
            working = scan() == 2 && scan() == 0;
        }
        munmap(pages, probeBytes);
        return working;
    }

    bool covers(std::uintptr_t begin, std::uintptr_t end) const {
        auto next = _ranges.upper_bound(begin);
        if (next == _ranges.begin()) return false;
        return std::prev(next)->second >= end;
    }

    static void insert(std::map<std::uintptr_t, std::uintptr_t>& ranges, std::uintptr_t begin, std::uintptr_t end) {
        auto next = ranges.upper_bound(begin);
        if (next != ranges.begin() && std::prev(next)->second == begin) {
            begin = std::prev(next)->first;
            ranges.erase(std::prev(next));
        }
        if (next != ranges.end() && next->first == end) {
            end = next->second;
            ranges.erase(next);
        }
        ranges.emplace(begin, end);
    }

    static bool remove(std::map<std::uintptr_t, std::uintptr_t>& ranges, std::uintptr_t begin, std::uintptr_t end) {
        bool removed = false;
        auto it = ranges.upper_bound(begin);
        if (it != ranges.begin()) --it;
        while (it != ranges.end() && it->first < end) {
            const auto rangeBegin = it->first;
            const auto rangeEnd = it->second;
            if (rangeEnd <= begin) {
                ++it;
                continue;
            }
            removed = true;
            it = ranges.erase(it);
            if (rangeBegin < begin) ranges.emplace(rangeBegin, begin);
            if (rangeEnd > end) ranges.emplace(end, rangeEnd);
        }
        return removed;
    }

    int _uffd = -1;
    int _pagemap = -1;
    std::shared_mutex _lock;
    std::map<std::uintptr_t, std::uintptr_t> _ranges;
    std::map<std::uintptr_t, std::uintptr_t> _fresh;
};

const bool g_opened = (Watch::Get(), true);
#elif defined(__APPLE__)
class Watch {
public:
    static Watch& Get() {
        static auto* watch = new Watch;
        return *watch;
    }

    bool Available() const {
        return _available;
    }

    void Register(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available || end <= begin) return;
        begin = pageStart(begin);
        end = pageEnd(end);
        if (end <= begin) return;
        std::vector<std::uint8_t> pages((end - begin) / _page, Written | Fresh);
        std::vector<bool> queried(pages.size(), false);
        const Lock lock(_lock, SiteRegister);
        struct HoldTimer {
            Watch& watch;
            std::uintptr_t bytes;
            std::chrono::steady_clock::time_point start;
            ~HoldTimer() {
                if (!watch._lock.profiled) return;
                const auto us = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - start).count());
                watch._collectStats.registers.fetch_add(1, std::memory_order_relaxed);
                watch._collectStats.registerUs.fetch_add(us, std::memory_order_relaxed);
                for (auto seen = watch._collectStats.registerMaxUs.load(); us > seen && !watch._collectStats.registerMaxUs.compare_exchange_weak(seen, us);) {
                }
                for (auto seen = watch._collectStats.registerMaxBytes.load(); bytes > seen && !watch._collectStats.registerMaxBytes.compare_exchange_weak(seen, bytes);) {
                }
            }
        } holdTimer{*this, end - begin, _lock.profiled ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{}};
        const auto phaseStart = holdTimer.start;
        std::uint64_t regionQueries = 0;
        const auto phaseUs = [&](std::chrono::steady_clock::time_point& from) {
            const auto now = std::chrono::steady_clock::now();
            const auto us = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(now - from).count());
            from = now;
            return us;
        };
        auto phaseAt = phaseStart;
        std::array<std::uint64_t, 4> phases{};
        for (auto cursor = begin; cursor < end;) {
            ++regionQueries;
            mach_vm_address_t address = cursor;
            mach_vm_size_t size = 0;
            vm_region_basic_info_data_64_t info{};
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            mach_port_t object = MACH_PORT_NULL;
            if (mach_vm_region(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, reinterpret_cast<vm_region_info_t>(&info), &count, &object) != KERN_SUCCESS || address >= end) break;
            const auto first = std::max<std::uintptr_t>(cursor, address);
            const auto last = std::min<std::uintptr_t>(end, address + size);
            const std::uint8_t protection = ((info.protection & VM_PROT_READ) ? PROT_READ : 0) | ((info.protection & VM_PROT_WRITE) ? PROT_WRITE : 0) | ((info.protection & VM_PROT_EXECUTE) ? PROT_EXEC : 0);
            for (auto page = first; page < last; page += _page) {
                pages[(page - begin) / _page] = Written | Fresh | protection;
                queried[(page - begin) / _page] = true;
            }
            cursor = last;
        }
        if (_lock.profiled) phases[0] = phaseUs(phaseAt);
        forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state) {
            auto& entry = pages[(page - begin) / _page];
            const std::uint8_t recorded = state & ProtectionMask;
            const bool armed = (state & Protected) != 0 && (entry & ProtectionMask) == (recorded & ~PROT_WRITE);
            if (armed || (state & ReadTrapped) != 0 || !queried[(page - begin) / _page]) entry = static_cast<std::uint8_t>(Written | Fresh | recorded);
            else state = static_cast<std::uint8_t>(state & ~Protected);
        });
        dropTraps(begin, end);
        dropOpened(begin, end);
        if (_lock.profiled) phases[1] = phaseUs(phaseAt);
        // Inside one registered range (the arena's, registered whole): its states are reset in place, as
        // erase and a new range would leave them. Splitting it copied all of its page states, ~128 MB each
        // for the arena's, and held the lock ~20-130 ms per registration.
        // APS5_SPLIT_WATCH_REGISTER=1 splits as before.
        static const bool split = std::getenv("APS5_SPLIT_WATCH_REGISTER") != nullptr;
        if (auto host = _ranges.upper_bound(begin); !split && host != _ranges.begin() && std::prev(host)->second.end >= end) {
            --host;
            auto& range = host->second;
            for (auto page = begin; page < end; page += _page) {
                const auto index = (page - host->first) / _page;
                auto& state = range.pages[index];
                if ((state & (Protected | ReadTrapped)) != 0) ::mprotect(reinterpret_cast<void*>(page), _page, state & ProtectionMask);
                if ((state & Hot) != 0) _snapshots.erase(page);
                state = pages[(page - begin) / _page];
                range.heat[index] = 0;
            }
            if (_lock.profiled) phases[2] = phaseUs(phaseAt);
            return;
        }
        erase(begin, end);
        if (_lock.profiled) phases[2] = phaseUs(phaseAt);
        const auto count = pages.size();
        _ranges.emplace(begin, Range{end, std::move(pages), std::vector<std::uint8_t>(count, 0)});
        publishCoverage();
        if (_lock.profiled) {
            phases[3] = phaseUs(phaseAt);
            const auto total = phases[0] + phases[1] + phases[2] + phases[3];
            if (total > 20000) std::fprintf(stderr, "[watch] register 0x%llx+0x%llx held the lock %.1f ms: %llu region queries %.1f ms, reconcile %.1f ms, erase %.1f ms, publish %.1f ms (%zu ranges)\n", static_cast<unsigned long long>(begin), static_cast<unsigned long long>(end - begin), total / 1000.0, static_cast<unsigned long long>(regionQueries), phases[0] / 1000.0, phases[1] / 1000.0, phases[2] / 1000.0, phases[3] / 1000.0, _ranges.size());
        }
    }

    bool Unregister(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available || end <= begin) return false;
        begin = pageStart(begin);
        end = pageEnd(end);
        if (end <= begin) return false;
        const Lock lock(_lock, SiteUnregister);
        dropTraps(begin, end);
        dropOpened(begin, end);
        const bool removed = erase(begin, end);
        if (removed) publishCoverage();
        return removed;
    }

    // Answered without the lock from a coalesced copy of the ranges, published under the lock by every
    // change: the draw committer asks per storage layer and per clear, and queued behind faults and
    // collections (which hold the lock over page compares and mprotect) it spent ~7% of its time here.
    // APS5_LOCKED_WATCH_COVERS=1 answers under the lock as before.
    bool Covers(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available) return false;
        static const bool locked = std::getenv("APS5_LOCKED_WATCH_COVERS") != nullptr;
        if (locked) {
            const Lock lock(_lock, SiteCovers);
            return covers(begin, end);
        }
        const auto coverage = std::atomic_load_explicit(&_coverage, std::memory_order_acquire);
        if (coverage == nullptr) return false;
        auto it = std::upper_bound(coverage->begin(), coverage->end(), begin, [](std::uintptr_t address, const auto& run) { return address < run.first; });
        if (it == coverage->begin()) return false;
        --it;
        return begin < it->second && end <= it->second;
    }

    // Answered without the lock from the same coalesced copy as Covers (the driver asks per stored block);
    // APS5_LOCKED_WATCH_COVERS=1 answers under the lock as well.
    bool Overlaps(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available) return false;
        static const bool locked = std::getenv("APS5_LOCKED_WATCH_COVERS") != nullptr;
        if (locked) {
            const Lock lock(_lock, SiteOverlaps);
            const auto next = _ranges.upper_bound(begin);
            return (next != _ranges.begin() && std::prev(next)->second.end > begin) || (next != _ranges.end() && next->first < end);
        }
        const auto coverage = std::atomic_load_explicit(&_coverage, std::memory_order_acquire);
        if (coverage == nullptr) return false;
        const auto next = std::upper_bound(coverage->begin(), coverage->end(), begin, [](std::uintptr_t address, const auto& run) { return address < run.first; });
        return (next != coverage->begin() && std::prev(next)->second > begin) || (next != coverage->end() && next->first < end);
    }

    bool HandleFault(std::uintptr_t address) {
        return _available && record(address);
    }

    // Fresh pages were never collected since they were registered: Take::Fresh reports and arms only them,
    // Take::Armed leaves them for the caller that tracks them separately, as the Linux watch does.
    enum class Take { All, Armed, Fresh };

    bool Collect(std::uintptr_t begin, std::uintptr_t end, void (*written)(void*, std::uintptr_t, std::uintptr_t), void* context, Take take = Take::All) {
        if (!_available) return false;
        static const bool profiled = std::getenv("APS5_PROFILE_DRAW") != nullptr;
        if (profiled) countCollect(begin, end);
        begin = pageStart(begin);
        end = pageEnd(end);
        if (end <= begin) return true;
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> runs;
        {
            const Lock lock(_lock, SiteCollect);
            if (take != Take::Fresh && !covers(begin, end)) return false;
            forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state, std::uint8_t& heat) {
                const bool fresh = (state & Fresh) != 0;
                if ((take == Take::Armed && fresh) || (take == Take::Fresh && !fresh)) return;
                // A page that faulted HotFaults times after being re-armed (a ring the guest refills every
                // frame) is left open, as a fault costs ~20 us under Rosetta: a change of its bytes since
                // the last collection is its write. Unchanged for 256 collections, it is re-armed.
                if ((state & (Hot | Written)) == Hot) {
                    if (profiled) _collectStats.hotCompares.fetch_add(1, std::memory_order_relaxed);
                    if (differs(page)) {
                        if (profiled) _collectStats.hotChanged.fetch_add(1, std::memory_order_relaxed);
                        state |= Written;
                    } else {
                        if (++heat != 0) return;
                        if (!cool(page, state, heat)) return;
                    }
                }
                if ((state & Written) == 0) return;
                state &= static_cast<std::uint8_t>(~Fresh);
                if (!runs.empty() && runs.back().second == page) runs.back().second = page + _page;
                else runs.emplace_back(page, page + _page);
                for (const auto& [first, last] : _hostWrites)
                    if (page >= first && page < last) return;
                state &= static_cast<std::uint8_t>(~Written);
                const bool open = (state & (PROT_READ | PROT_WRITE)) == (PROT_READ | PROT_WRITE) && (state & ReadTrapped) == 0;
                if (open && _hotPages && ((state & Hot) != 0 || heat >= HotFaults)) {
                    if ((state & Hot) == 0) _snapshots[page] = std::make_unique<std::uint8_t[]>(_page);
                    if (snapshot(page)) {
                        state |= Hot;
                        heat = HotFaults;
                        return;
                    }
                    _snapshots.erase(page);
                    state = static_cast<std::uint8_t>((state & ~Hot) | Written);
                    heat = 0;
                    return;
                }
                if ((state & Hot) != 0) _snapshots.erase(page);
                state &= static_cast<std::uint8_t>(~Hot);
                if ((state & PROT_WRITE) != 0) state |= Protected;
            });
            for (const auto& [first, last] : runs) protect(first, last);
        }
        for (const auto& [first, last] : runs) written(context, first, last);
        return true;
    }

    // The host is about to store into the range (the GPU into a host import, the driver through a shared
    // alias): a hot page's bytes would change without a guest store, so it goes back to protection first.
    void HostWrites(std::uintptr_t begin, std::uintptr_t end) {
        begin = pageStart(begin);
        end = pageEnd(end);
        if (!_available || end <= begin) return;
        const Lock lock(_lock, SiteHostWrites);
        forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state, std::uint8_t& heat) {
            if ((state & Hot) != 0) cool(page, state, heat);
        });
    }

    // The guest's own SIGSEGV or SIGBUS disposition: faults the watch does not own go to it instead of
    // replacing the watch's handler, which would leave every watched page faulting forever.
    bool ChainSignal(int signal, void (*handler)(int)) {
        if (!_available || (signal != SIGSEGV && signal != SIGBUS)) return false;
        struct sigaction chained {};
        chained.sa_handler = handler;
        sigemptyset(&chained.sa_mask);
        (signal == SIGBUS ? _previousBus : _previousSegv) = chained;
        return true;
    }

    void ProtectionChanged(std::uintptr_t begin, std::uintptr_t end, int protection) {
        if (!_available || end <= begin) return;
        begin = pageStart(begin);
        end = pageEnd(end);
        if (end <= begin) return;
        withoutTraps(begin, end, false, SiteProtectionChanged, [&] {
            forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state) {
                if ((state & Hot) != 0) _snapshots.erase(page);
                state = static_cast<std::uint8_t>(Written | (state & Fresh) | (protection & ProtectionMask));
            });
        });
    }

    int Protect(std::uintptr_t begin, std::uintptr_t end, int protection) {
        if (!_available) return ::mprotect(reinterpret_cast<void*>(begin), end - begin, protection) == 0 ? 0 : errno;
        const auto first = pageStart(begin);
        const auto last = pageEnd(end);
        return withoutTraps(first, last, true, SiteProtectionChanged, [&] {
            if (::mprotect(reinterpret_cast<void*>(begin), end - begin, protection) != 0) return errno;
            if (first < last) {
                forEachPage(first, last, [&](std::uintptr_t page, std::uint8_t& state) {
                    if ((state & Hot) != 0) _snapshots.erase(page);
                    state = static_cast<std::uint8_t>(Written | (state & Fresh) | (protection & ProtectionMask));
                });
            }
            return 0;
        });
    }

    void BeginHostWrite(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available || end <= begin) return;
        begin = pageStart(begin);
        end = pageEnd(end);
        if (end <= begin) return;
        withoutTraps(begin, end, true, SiteBeginHost, [&] {
            _hostWrites.emplace_back(begin, end);
            forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state) {
                if ((state & Protected) != 0) ::mprotect(reinterpret_cast<void*>(page), _page, state & ProtectionMask);
                state = static_cast<std::uint8_t>((state & (ProtectionMask | Fresh)) | Written);
            });
        });
    }

    void EndHostWrite(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available || end <= begin) return;
        begin = pageStart(begin);
        end = pageEnd(end);
        if (end <= begin) return;
        const Lock lock(_lock, SiteEndHost);
        const auto found = std::find(_hostWrites.begin(), _hostWrites.end(), std::pair{begin, end});
        if (found != _hostWrites.end()) _hostWrites.erase(found);
    }

    void OpenImport(std::uintptr_t begin, std::uintptr_t end) {
        begin = pageStart(begin);
        end = pageEnd(end);
        if (!_available || end <= begin) return;
        withoutTraps(begin, end, true, SiteOpenImport, [&] {
            forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state) {
                if ((state & Protected) == 0) return;
                ::mprotect(reinterpret_cast<void*>(page), _page, state & ProtectionMask);
                state = static_cast<std::uint8_t>(state & ~Protected);
                markOpened(page);
            });
        });
    }

    void CloseImport(std::uintptr_t begin, std::uintptr_t end) {
        begin = pageStart(begin);
        end = pageEnd(end);
        if (!_available || end <= begin) return;
        const Lock lock(_lock, SiteCloseImport);
        for (const auto& [first, last] : dropOpened(begin, end)) {
            forEachPage(first, last, [&](std::uintptr_t, std::uint8_t& state) {
                if ((state & (Written | PROT_WRITE)) == PROT_WRITE) state |= Protected;
            });
        }
        protect(begin, end);
    }

    int Protection(std::uintptr_t address, std::uintptr_t limit, std::uintptr_t* runEnd) {
        const auto page = pageStart(address);
        const Lock lock(_lock, SiteProtection);
        auto it = _ranges.upper_bound(page);
        if (_available && it != _ranges.begin() && page < std::prev(it)->second.end) {
            --it;
            const auto& pages = it->second.pages;
            const std::uint8_t protection = pages[(page - it->first) / _page] & ProtectionMask;
            auto end = page + _page;
            while (end < it->second.end && end < limit && (pages[(end - it->first) / _page] & ProtectionMask) == protection) end += _page;
            *runEnd = std::min(end, limit);
            return protection;
        }
        *runEnd = it != _ranges.end() ? std::min(it->first, limit) : limit;
        return -1;
    }

    bool SetReadTrapResolver(void (*resolver)(std::uintptr_t, std::uintptr_t)) {
        if (!_available || resolver == nullptr) return false;
        std::call_once(_resolverStarted, [this] { startResolver(); });
        if (!_resolverRunning.load(std::memory_order_acquire)) return false;
        _resolver.store(resolver, std::memory_order_release);
        return true;
    }

    bool TrapReads(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available || end <= begin || _resolver.load(std::memory_order_acquire) == nullptr) return false;
        const auto first = pageStart(begin);
        const auto last = pageEnd(end);
        const Lock lock(_lock, SiteTraps);
        if (!covers(first, last)) return false;
        const auto [same, other] = _traps.equal_range(begin);
        if (std::any_of(same, other, [&](const auto& trap) { return trap.second == end; })) return true;
        for (const auto& [hostBegin, hostEnd] : _hostWrites)
            if (hostBegin < last && first < hostEnd) return false;
        if (::mprotect(reinterpret_cast<void*>(first), last - first, PROT_NONE) != 0) return false;
        _traps.emplace(begin, end);
        forEachPage(first, last, [](std::uintptr_t, std::uint8_t& state) { state |= ReadTrapped; });
        _trapping.store(true, std::memory_order_release);
        return true;
    }

    void ReleaseReads(std::uintptr_t begin, std::uintptr_t end) {
        if (!_available || end <= begin) return;
        const Lock lock(_lock, SiteTraps);
        const auto [first, last] = _traps.equal_range(begin);
        const auto found = std::find_if(first, last, [&](const auto& trap) { return trap.second == end; });
        if (found == last) return;
        _traps.erase(found);
        untrap(begin, end);
    }

private:
    static constexpr std::uint8_t ProtectionMask = PROT_READ | PROT_WRITE | PROT_EXEC;
    static constexpr std::uint8_t Written = 0x10;
    static constexpr std::uint8_t Protected = 0x20;
    static constexpr std::uint8_t Fresh = 0x40;
    static constexpr std::uintptr_t FaultAheadBlock = 65536;
    static constexpr std::uint8_t ReadTrapped = 0x80;
    static constexpr std::size_t ResolveSlots = 32;
    static constexpr std::size_t RetrySlots = 64;
    static constexpr unsigned UntrappedRetries = 16;
    static constexpr unsigned GenerationRetries = RetrySlots * UntrappedRetries;

    enum SlotState : unsigned { Free, Claimed, Queued, Running, Done };
    enum class Owner { Any, Self, Others };

    struct Slot {
        std::atomic<unsigned> state{Free};
        std::uintptr_t page = 0;
        semaphore_t done = MACH_PORT_NULL;
    };

    struct Resolving {
        std::uintptr_t begin;
        std::uintptr_t end;
        pthread_t owner;
    };

    struct Retry {
        std::uintptr_t page = 0;
        pthread_t thread = nullptr;
        std::uint64_t generation = 0;
        std::uint64_t used = 0;
        unsigned count = 0;
    };


    static constexpr std::uint8_t Hot = 0x08;
    static constexpr std::uint8_t HotFaults = 4;
    static inline thread_local sigjmp_buf* t_reading = nullptr;

    struct Range {
        std::uintptr_t end;
        std::vector<std::uint8_t> pages;
        std::vector<std::uint8_t> heat;
    };

    // Who holds the lock when another thread has to wait (APS5_PROFILE_DRAW, the [watch] line).
    enum Site : std::uint8_t { SiteRegister, SiteUnregister, SiteCollect, SiteHostWrites, SiteProtectionChanged, SiteBeginHost, SiteEndHost, SiteOpenImport, SiteCloseImport, SiteProtection, SiteFault, SiteCovers, SiteOverlaps, SiteTraps, SiteResolve, SiteCount };
    static constexpr const char* SiteNames[SiteCount] = {"register", "unregister", "collect", "host writes", "protection change", "host write begin", "host write end", "import open", "import close", "protection query", "fault", "covers", "overlaps", "read traps", "read trap resolve"};

    struct Turns {
        std::atomic<std::uint64_t> next{0};
        std::atomic<std::uint64_t> serving{0};
        // Set once by the constructor: the lock is also taken in the fault handler, where a function
        // static's first initialization must not run.
        bool profiled = false;
        std::atomic<std::uint8_t> holder{SiteCount};
        std::array<std::atomic<std::uint64_t>, SiteCount> waitsBehind{};
        std::array<std::atomic<std::uint64_t>, SiteCount> yieldsBehind{};
    };

    struct Lock {
        // The holds are short (a page table lookup), so a waiter spins before it yields: under Rosetta
        // every sched_yield is a system call, and the queued waiters of a hot watch paid one per turn.
        explicit Lock(Turns& turns, Site site) : _turns(turns), _turn(turns.next.fetch_add(1, std::memory_order_relaxed)) {
            const bool profiled = turns.profiled;
            std::uint8_t behind = SiteCount;
            for (unsigned spins = 0; _turns.serving.load(std::memory_order_acquire) != _turn; ++spins) {
                if (profiled && spins == 0) {
                    behind = _turns.holder.load(std::memory_order_relaxed);
                    if (behind < SiteCount) _turns.waitsBehind[behind].fetch_add(1, std::memory_order_relaxed);
                }
                if (spins < 2048) __builtin_ia32_pause();
                else {
                    if (profiled && behind < SiteCount) _turns.yieldsBehind[behind].fetch_add(1, std::memory_order_relaxed);
                    ::sched_yield();
                }
            }
            if (profiled) _turns.holder.store(site, std::memory_order_relaxed);
        }
        ~Lock() {
            _turns.serving.store(_turn + 1, std::memory_order_release);
        }
        Turns& _turns;
        std::uint64_t _turn;
    };

    Watch() {
        _lock.profiled = std::getenv("APS5_PROFILE_DRAW") != nullptr;
        if (const char* ahead = std::getenv("APS5_WRITE_WATCH_FAULT_AHEAD")) _faultAhead = static_cast<std::size_t>(std::strtoul(ahead, nullptr, 0));
        _hotPages = std::getenv("APS5_WRITE_WATCH_NO_HOT") == nullptr;
        if (std::getenv("APS5_NO_WRITE_WATCH") != nullptr) return;
        struct sigaction action {};
        action.sa_sigaction = &Watch::fault;
        action.sa_flags = SA_SIGINFO | SA_RESTART;
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGBUS, &action, &_previousBus) != 0 || sigaction(SIGSEGV, &action, &_previousSegv) != 0) {
            std::fprintf(stderr, "[memory] write watch: cannot install the fault handler (%s); guest buffers are fully re-read every use\n", std::strerror(errno));
            return;
        }
        _available = true;
    }

    static bool isWriteFault(const siginfo_t* info, void* context) {
        if (info->si_code <= 0 || info->si_code >= SI_USER || context == nullptr) return false;
        const auto state = static_cast<ucontext_t*>(context)->uc_mcontext;
        if (state == nullptr) return false;
#if defined(__x86_64__)
        constexpr unsigned PageFault = 14;
        constexpr unsigned WriteAccess = 1u << 1;
        return state->__es.__trapno == PageFault && (state->__es.__err & WriteAccess) != 0;
#elif defined(__aarch64__)
        constexpr unsigned DataAbort = 0x24;
        constexpr unsigned ExceptionClassShift = 26;
        constexpr unsigned WriteAccess = 1u << 6;
        return (state->__es.__esr >> ExceptionClassShift) == DataAbort && (state->__es.__esr & WriteAccess) != 0;
#else
        return false;
#endif
    }

public:
    // The faults the watch owns: a host read probe's, a read trap's and a write to a watched page.
    // libkernel's exception delivery (Exception.cpp) offers a fault here before a guest handler.
    static bool claim(siginfo_t* info, void* context) {
        if (t_reading != nullptr) {
            sigset_t faults;
            sigemptyset(&faults);
            sigaddset(&faults, SIGSEGV);
            sigaddset(&faults, SIGBUS);
            pthread_sigmask(SIG_UNBLOCK, &faults, nullptr);
            siglongjmp(*t_reading, 1);
        }
        auto& watch = Get();
        const bool write = isWriteFault(info, context);
        if (info->si_code > 0 && info->si_code < SI_USER && watch.resolveTrap(reinterpret_cast<std::uintptr_t>(info->si_addr), write)) return true;
        return write && watch.record(reinterpret_cast<std::uintptr_t>(info->si_addr));
    }

private:
    static void fault(int signal, siginfo_t* info, void* context) {
        if (claim(info, context)) return;
        auto& watch = Get();
        const auto& previous = signal == SIGBUS ? watch._previousBus : watch._previousSegv;
        if ((previous.sa_flags & SA_SIGINFO) != 0 && previous.sa_sigaction != nullptr) {
            previous.sa_sigaction(signal, info, context);
            return;
        }
        if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN && previous.sa_handler != nullptr) {
            previous.sa_handler(signal);
            return;
        }
        FatalLine::Write(signal, info, context);
        ::signal(signal, SIG_DFL);
        if (previous.sa_handler == SIG_DFL) ::raise(signal);
    }

    bool record(std::uintptr_t address) {
        const auto page = pageStart(address);
        _collectStats.faults.fetch_add(1, std::memory_order_relaxed);
        const Lock lock(_lock, SiteFault);
        auto it = _ranges.upper_bound(page);
        if (it == _ranges.begin()) return false;
        --it;
        if (page >= it->second.end) return false;
        auto& pages = it->second.pages;
        const auto index = static_cast<std::size_t>((page - it->first) / _page);
        auto& state = pages[index];
        if ((state & Protected) != 0) {
            const auto protection = state & ProtectionMask;
            const auto writtenOpen = [&](std::size_t at) { return (pages[at] & (Written | Protected)) == Written && (pages[at] & ProtectionMask) == protection; };
            std::size_t count = 1;
            if (_faultAhead > 1 && index >= 2 && writtenOpen(index - 1) && writtenOpen(index - 2)) {
                const auto blockPages = static_cast<std::size_t>(((page | (FaultAheadBlock - 1)) + 1 - page) / _page);
                const auto limit = std::min({_faultAhead, blockPages, pages.size() - index});
                while (count < limit && (pages[index + count] & (Protected | ReadTrapped)) == Protected && (pages[index + count] & ProtectionMask) == protection) ++count;
            }
            if (::mprotect(reinterpret_cast<void*>(page), count * _page, protection) != 0) return false;
            auto& heat = it->second.heat[index];
            if (heat < HotFaults) ++heat;
            for (std::size_t at = index; at < index + count; ++at) pages[at] = static_cast<std::uint8_t>((pages[at] & (ProtectionMask | Fresh)) | Written);
            return true;
        }
        if ((state & PROT_WRITE) == 0) return false;
        std::uint8_t value = 0;
        mach_vm_size_t copied = 0;
        return mach_vm_read_overwrite(mach_task_self(), address, sizeof(value), reinterpret_cast<mach_vm_address_t>(&value), &copied) == KERN_SUCCESS && copied == sizeof(value);
    }

    bool resolveTrap(std::uintptr_t address, bool write) {
        if (!_trapping.load(std::memory_order_acquire)) return false;
        const auto page = pageStart(address);
        {
            const Lock lock(_lock, SiteFault);
            auto* state = pageState(page);
            if (state == nullptr) return false;
            if ((*state & ReadTrapped) == 0) return retryUntrapped(page, *state, write);
            if (resolvingCovers(page, page + _page, Owner::Self) || pthread_equal(pthread_self(), _resolverThread) || (!trapCovers(page, page + _page) && !resolvingCovers(page, page + _page, Owner::Any))) {
                *state = static_cast<std::uint8_t>(*state & ~ReadTrapped);
                ++_untrapGeneration;
                return ::mprotect(reinterpret_cast<void*>(page), _page, untrappedProtection(*state)) == 0;
            }
        }
        Slot* slot = nullptr;
        while (slot == nullptr) {
            for (auto& candidate : _slots) {
                unsigned expected = Free;
                if (candidate.state.compare_exchange_strong(expected, Claimed, std::memory_order_acq_rel)) {
                    slot = &candidate;
                    break;
                }
            }
            if (slot == nullptr) sched_yield();
        }
        slot->page = page;
        slot->state.store(Queued, std::memory_order_release);
        semaphore_signal(_wake);
        while (semaphore_wait(slot->done) == KERN_ABORTED) {}
        slot->state.store(Free, std::memory_order_release);
        return true;
    }

    void startResolver() {
        if (semaphore_create(mach_task_self(), &_wake, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS) return;
        for (auto& slot : _slots)
            if (semaphore_create(mach_task_self(), &slot.done, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS) return;
        pthread_attr_t attributes;
        pthread_attr_init(&attributes);
        pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
        const bool created = pthread_create(&_resolverThread, &attributes, [](void* watch) -> void* {
            static_cast<Watch*>(watch)->resolveLoop();
            return nullptr;
        }, this) == 0;
        pthread_attr_destroy(&attributes);
        _resolverRunning.store(created, std::memory_order_release);
    }

    void resolveLoop() {
        pthread_setname_np("write watch read traps");
        for (;;) {
            if (semaphore_wait(_wake) != KERN_SUCCESS) continue;
            for (auto& slot : _slots) {
                unsigned expected = Queued;
                if (!slot.state.compare_exchange_strong(expected, Running, std::memory_order_acq_rel)) continue;
                const auto page = slot.page;
                waitForResolving(page, page + _page);
                resolve(page, page + _page);
                {
                    const Lock lock(_lock, SiteResolve);
                    untrap(page, page + _page);
                }
                slot.state.store(Done, std::memory_order_release);
                semaphore_signal(slot.done);
            }
        }
    }

    void resolve(std::uintptr_t begin, std::uintptr_t end) {
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> taken;
        const auto self = pthread_self();
        {
            const Lock lock(_lock, SiteResolve);
            taken = takeTraps(begin, end);
            for (const auto& [first, last] : taken) _resolving.push_back({first, last, self});
        }
        if (taken.empty()) return;
        const auto resolver = _resolver.load(std::memory_order_acquire);
        for (const auto& [first, last] : taken) resolver(first, last);
        const Lock lock(_lock, SiteResolve);
        for (const auto& [first, last] : taken) {
            const auto found = std::find_if(_resolving.begin(), _resolving.end(), [&](const Resolving& entry) { return entry.begin == first && entry.end == last && pthread_equal(entry.owner, self); });
            if (found != _resolving.end()) _resolving.erase(found);
        }
        for (const auto& [first, last] : taken) untrap(first, last);
    }

    void waitForResolving(std::uintptr_t begin, std::uintptr_t end) {
        for (;;) {
            {
                const Lock lock(_lock, SiteResolve);
                if (!resolvingCovers(begin, end, Owner::Others)) return;
            }
            sched_yield();
        }
    }

    bool resolvingCovers(std::uintptr_t begin, std::uintptr_t end, Owner owner) const {
        const auto self = pthread_self();
        return std::any_of(_resolving.begin(), _resolving.end(), [&](const Resolving& entry) {
            if (pageStart(entry.begin) >= end || begin >= pageEnd(entry.end)) return false;
            return owner == Owner::Any || (pthread_equal(entry.owner, self) != 0) == (owner == Owner::Self);
        });
    }

    bool retryUntrapped(std::uintptr_t page, std::uint8_t state, bool write) {
        if ((untrappedProtection(state) & (write ? PROT_WRITE : PROT_READ)) == 0) return false;
        if (_retryGeneration != _untrapGeneration) {
            _retryGeneration = _untrapGeneration;
            _generationRetries = 0;
        }
        if (++_generationRetries > GenerationRetries) return false;
        const auto thread = pthread_self();
        auto found = std::find_if(_retries.begin(), _retries.end(), [&](const Retry& retry) { return retry.used != 0 && retry.page == page && pthread_equal(retry.thread, thread); });
        if (found == _retries.end()) found = std::min_element(_retries.begin(), _retries.end(), [](const Retry& left, const Retry& right) { return left.used < right.used; });
        if (found->used == 0 || found->page != page || !pthread_equal(found->thread, thread) || found->generation != _untrapGeneration) *found = {page, thread, _untrapGeneration, 0, 0};
        found->used = ++_retryUses;
        return ++found->count <= UntrappedRetries;
    }

    template <typename TFunction>
    std::invoke_result_t<TFunction> withoutTraps(std::uintptr_t begin, std::uintptr_t end, bool restore, Site site, TFunction function) {
        for (;;) {
            if (_trapping.load(std::memory_order_acquire)) {
                waitForResolving(begin, end);
                resolve(begin, end);
            }
            const Lock lock(_lock, site);
            if (trapCovers(pageStart(begin), pageEnd(end)) || resolvingCovers(pageStart(begin), pageEnd(end), Owner::Others)) continue;
            if (restore) untrap(begin, end);
            else forEachPage(pageStart(begin), pageEnd(end), [](std::uintptr_t, std::uint8_t& state) { state = static_cast<std::uint8_t>(state & ~ReadTrapped); });
            return function();
        }
    }

    std::vector<std::pair<std::uintptr_t, std::uintptr_t>> takeTraps(std::uintptr_t begin, std::uintptr_t end) {
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> taken;
        auto first = pageStart(begin);
        auto last = pageEnd(end);
        for (bool grew = true; grew;) {
            grew = false;
            for (auto it = _traps.begin(); it != _traps.end();) {
                if (it->first >= last || it->second <= first) {
                    ++it;
                    continue;
                }
                first = std::min(first, pageStart(it->first));
                last = std::max(last, pageEnd(it->second));
                taken.emplace_back(*it);
                it = _traps.erase(it);
                grew = true;
            }
        }
        return taken;
    }

    void dropTraps(std::uintptr_t begin, std::uintptr_t end) {
        for (const auto& [first, last] : takeTraps(begin, end)) untrap(first, last);
        untrap(begin, end);
    }

    bool trapCovers(std::uintptr_t begin, std::uintptr_t end) const {
        return std::any_of(_traps.begin(), _traps.end(), [&](const auto& trap) { return trap.first < end && begin < trap.second; });
    }

    void untrap(std::uintptr_t begin, std::uintptr_t end) {
        const auto first = pageStart(begin);
        const auto last = pageEnd(end);
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> remaining;
        for (const auto& trap : _traps)
            if (trap.first < last && first < trap.second) remaining.push_back(trap);
        forEachPage(first, last, [&](std::uintptr_t page, std::uint8_t& state) {
            if ((state & ReadTrapped) == 0) return;
            if (std::any_of(remaining.begin(), remaining.end(), [&](const auto& trap) { return trap.first < page + _page && page < trap.second; })) return;
            if (resolvingCovers(page, page + _page, Owner::Others)) return;
            state = static_cast<std::uint8_t>(state & ~ReadTrapped);
            ::mprotect(reinterpret_cast<void*>(page), _page, untrappedProtection(state));
            ++_untrapGeneration;
        });
    }

    static int untrappedProtection(std::uint8_t state) {
        return (state & Protected) != 0 ? (state & ProtectionMask & ~PROT_WRITE) : (state & ProtectionMask);
    }

    std::uint8_t* pageState(std::uintptr_t page) {
        auto it = _ranges.upper_bound(page);
        if (it == _ranges.begin()) return nullptr;
        --it;
        if (page >= it->second.end) return nullptr;
        return &it->second.pages[(page - it->first) / _page];
    }


    // The guest may take a hot page's read permission away (mprotect, then ProtectionChanged) while it
    // is compared: the fault returns here and the page reads as written.
    template <typename TFunction>
    bool guarded(TFunction function) {
        sigjmp_buf jump;
        if (sigsetjmp(jump, 0) != 0) {
            t_reading = nullptr;
            return false;
        }
        t_reading = &jump;
        function();
        t_reading = nullptr;
        return true;
    }

    bool differs(std::uintptr_t page) {
        bool same = false;
        return !guarded([&] { same = std::memcmp(reinterpret_cast<const void*>(page), _snapshots.at(page).get(), _page) == 0; }) || !same;
    }

    // Re-arms a hot page: protected first, so a guest store from now on faults and one before it shows in
    // the comparison. Returns whether the page is written (the comparison found a change).
    bool cool(std::uintptr_t page, std::uint8_t& state, std::uint8_t& heat) {
        ::mprotect(reinterpret_cast<void*>(page), _page, (state & ReadTrapped) != 0 ? PROT_NONE : state & ProtectionMask & ~PROT_WRITE);
        const bool changed = differs(page);
        _snapshots.erase(page);
        state = static_cast<std::uint8_t>((state & ~Hot) | Protected | (changed ? Written : 0));
        heat = HotFaults - 1;
        return changed;
    }

    bool snapshot(std::uintptr_t page) {
        return guarded([&] { std::memcpy(_snapshots.at(page).get(), reinterpret_cast<const void*>(page), _page); });
    }

    // APS5_PROFILE_DRAW: what collections walk ([watch] line every 10 s).
    struct CollectStats {
        std::atomic<std::uint64_t> calls{0}, pages{0}, hotCompares{0}, hotChanged{0}, faults{0}, registers{0}, registerUs{0}, registerMaxUs{0}, registerMaxBytes{0};
        std::atomic<std::int64_t> last{0};
    };
    CollectStats _collectStats;

    void countCollect(std::uintptr_t begin, std::uintptr_t end) {
        auto& stats = _collectStats;
        stats.calls.fetch_add(1, std::memory_order_relaxed);
        stats.pages.fetch_add((pageEnd(end) - pageStart(begin)) / _page, std::memory_order_relaxed);
        const auto now = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
        auto last = stats.last.load(std::memory_order_relaxed);
        if (last == 0) stats.last.compare_exchange_strong(last, now);
        else if (now - last >= 10 && stats.last.compare_exchange_strong(last, now)) {
            std::string behind;
            for (std::size_t site = 0; site < SiteCount; ++site) {
                const auto waits = _lock.waitsBehind[site].exchange(0, std::memory_order_relaxed);
                const auto yields = _lock.yieldsBehind[site].exchange(0, std::memory_order_relaxed);
                if (waits == 0) continue;
                char item[64];
                std::snprintf(item, sizeof(item), " %s %llu/%llu", SiteNames[site], static_cast<unsigned long long>(waits), static_cast<unsigned long long>(yields));
                behind += item;
            }
            std::fprintf(stderr, "[watch] collections (10 s): %llu walks over %llu pages, %llu hot pages compared (%llu changed), %llu faults recorded; %llu registers held the lock %.1f ms (longest %.1f ms, largest 0x%llx bytes); lock waits behind (waits/yields):%s\n", static_cast<unsigned long long>(stats.calls.exchange(0)), static_cast<unsigned long long>(stats.pages.exchange(0)), static_cast<unsigned long long>(stats.hotCompares.exchange(0)), static_cast<unsigned long long>(stats.hotChanged.exchange(0)), static_cast<unsigned long long>(stats.faults.exchange(0)), static_cast<unsigned long long>(stats.registers.exchange(0)), static_cast<double>(stats.registerUs.exchange(0)) / 1000.0, static_cast<double>(stats.registerMaxUs.exchange(0)) / 1000.0, static_cast<unsigned long long>(stats.registerMaxBytes.exchange(0)), behind.c_str());
        }
    }

    // Rebuilds Covers' and Overlaps' copy of the ranges (under the lock, after a change to them).
    void publishCoverage() {
        auto built = std::make_shared<std::vector<std::pair<std::uintptr_t, std::uintptr_t>>>();
        built->reserve(_ranges.size());
        for (const auto& [first, range] : _ranges) {
            if (!built->empty() && first <= built->back().second) built->back().second = std::max(built->back().second, range.end);
            else built->emplace_back(first, range.end);
        }
        std::atomic_store_explicit(&_coverage, std::shared_ptr<const std::vector<std::pair<std::uintptr_t, std::uintptr_t>>>(std::move(built)), std::memory_order_release);
    }

    // Pages OpenImport unprotected, as runs: CloseImport protects them again unless written.
    void markOpened(std::uintptr_t page) {
        auto next = _opened.upper_bound(page);
        if (next != _opened.begin() && std::prev(next)->second >= page) {
            auto run = std::prev(next);
            run->second = std::max(run->second, page + _page);
            if (next != _opened.end() && next->first <= run->second) {
                run->second = std::max(run->second, next->second);
                _opened.erase(next);
            }
            return;
        }
        auto run = _opened.emplace_hint(next, page, page + _page);
        if (next != _opened.end() && next->first <= run->second) {
            run->second = std::max(run->second, next->second);
            _opened.erase(next);
        }
    }

    std::vector<std::pair<std::uintptr_t, std::uintptr_t>> dropOpened(std::uintptr_t begin, std::uintptr_t end) {
        std::vector<std::pair<std::uintptr_t, std::uintptr_t>> dropped;
        auto it = _opened.upper_bound(begin);
        if (it != _opened.begin()) --it;
        while (it != _opened.end() && it->first < end) {
            const auto [first, last] = *it;
            if (last <= begin) {
                ++it;
                continue;
            }
            it = _opened.erase(it);
            dropped.emplace_back(std::max(first, begin), std::min(last, end));
            if (first < begin) _opened.emplace(first, begin);
            if (end < last) it = _opened.emplace(end, last).first;
        }
        return dropped;
    }

    std::uintptr_t pageStart(std::uintptr_t address) const {
        return address & ~(_page - 1);
    }

    std::uintptr_t pageEnd(std::uintptr_t address) const {
        return (address + _page - 1) & ~(_page - 1);
    }

    template <typename TFunction>
    void forEachPage(std::uintptr_t begin, std::uintptr_t end, TFunction function) {
        auto it = _ranges.upper_bound(begin);
        if (it != _ranges.begin()) --it;
        for (; it != _ranges.end() && it->first < end; ++it) {
            const auto first = std::max(begin, it->first);
            const auto last = std::min(end, it->second.end);
            for (auto page = first; page < last; page += _page) {
                const auto index = (page - it->first) / _page;
                if constexpr (std::is_invocable_v<TFunction, std::uintptr_t, std::uint8_t&, std::uint8_t&>) function(page, it->second.pages[index], it->second.heat[index]);
                else function(page, it->second.pages[index]);
            }
        }
    }

    void protect(std::uintptr_t begin, std::uintptr_t end) {
        std::uintptr_t runStart = 0;
        std::uintptr_t previous = begin;
        int runProtection = -1;
        const auto flush = [&](std::uintptr_t runEnd) {
            if (runProtection >= 0) ::mprotect(reinterpret_cast<void*>(runStart), runEnd - runStart, runProtection);
            runProtection = -1;
        };
        forEachPage(begin, end, [&](std::uintptr_t page, std::uint8_t& state) {
            const int wanted = (state & ReadTrapped) != 0 ? PROT_NONE : (state & Protected) != 0 ? (state & ProtectionMask & ~PROT_WRITE) : -1;
            if (wanted != runProtection || page != previous) {
                flush(previous);
                runStart = page;
                runProtection = wanted;
            }
            previous = page + _page;
        });
        flush(previous);
    }

    bool covers(std::uintptr_t begin, std::uintptr_t end) const {
        auto it = _ranges.upper_bound(begin);
        if (it == _ranges.begin()) return false;
        --it;
        auto cursor = begin;
        for (; it != _ranges.end() && it->first <= cursor; ++it) {
            if (it->second.end > cursor) cursor = it->second.end;
            if (cursor >= end) return true;
        }
        return false;
    }

    bool erase(std::uintptr_t begin, std::uintptr_t end) {
        bool removed = false;
        auto it = _ranges.upper_bound(begin);
        if (it != _ranges.begin()) --it;
        while (it != _ranges.end() && it->first < end) {
            const auto rangeBegin = it->first;
            const auto rangeEnd = it->second.end;
            if (rangeEnd <= begin) {
                ++it;
                continue;
            }
            removed = true;
            auto pages = std::move(it->second.pages);
            auto heat = std::move(it->second.heat);
            it = _ranges.erase(it);
            const auto cutBegin = std::max(begin, rangeBegin);
            const auto cutEnd = std::min(end, rangeEnd);
            for (auto page = cutBegin; page < cutEnd; page += _page) {
                const auto state = pages[(page - rangeBegin) / _page];
                if ((state & (Protected | ReadTrapped)) != 0) ::mprotect(reinterpret_cast<void*>(page), _page, state & ProtectionMask);
                if ((state & Hot) != 0) _snapshots.erase(page);
            }
            const auto head = static_cast<std::size_t>((cutBegin - rangeBegin) / _page);
            const auto tail = static_cast<std::ptrdiff_t>((cutEnd - rangeBegin) / _page);
            // The tail is copied out and the head keeps the range's own vectors (cut, not copied).
            std::vector<std::uint8_t> tailPages, tailHeat;
            if (cutEnd < rangeEnd) {
                tailPages.assign(pages.begin() + tail, pages.end());
                tailHeat.assign(heat.begin() + tail, heat.end());
            }
            if (rangeBegin < cutBegin) {
                pages.resize(head);
                heat.resize(head);
                if (head * 4 < pages.capacity()) {
                    pages.shrink_to_fit();
                    heat.shrink_to_fit();
                }
                _ranges.emplace(rangeBegin, Range{cutBegin, std::move(pages), std::move(heat)});
            }
            if (cutEnd < rangeEnd) it = _ranges.emplace(cutEnd, Range{rangeEnd, std::move(tailPages), std::move(tailHeat)}).first;
        }
        return removed;
    }

    const std::uintptr_t _page = static_cast<std::uintptr_t>(::getpagesize());
    std::size_t _faultAhead = 32;
    // APS5_WRITE_WATCH_NO_HOT: every written page is protected again at collection, never left open as hot.
    bool _hotPages = true;
    bool _available = false;
    Turns _lock;
    std::map<std::uintptr_t, Range> _ranges;
    // Covers' copy of the ranges, coalesced and sorted.
    std::shared_ptr<const std::vector<std::pair<std::uintptr_t, std::uintptr_t>>> _coverage;
    std::unordered_map<std::uintptr_t, std::unique_ptr<std::uint8_t[]>> _snapshots;
    std::vector<std::pair<std::uintptr_t, std::uintptr_t>> _hostWrites;
    std::map<std::uintptr_t, std::uintptr_t> _opened;
    std::multimap<std::uintptr_t, std::uintptr_t> _traps;
    std::vector<Resolving> _resolving;
    std::array<Retry, RetrySlots> _retries{};
    std::uint64_t _retryUses = 0;
    std::uint64_t _retryGeneration = 0;
    unsigned _generationRetries = 0;
    std::uint64_t _untrapGeneration = 0;
    std::atomic<bool> _trapping{false};
    std::atomic<void (*)(std::uintptr_t, std::uintptr_t)> _resolver{nullptr};
    std::once_flag _resolverStarted;
    std::atomic<bool> _resolverRunning{false};
    pthread_t _resolverThread{};
    semaphore_t _wake = MACH_PORT_NULL;
    std::array<Slot, ResolveSlots> _slots;
    struct sigaction _previousBus {};
    struct sigaction _previousSegv {};
};

const bool g_opened = (Watch::Get(), true);
#endif

}

bool GuestWriteWatchAvailable_nid_postfix() {
#ifdef APS5_GUEST_WRITE_WATCH
    return Watch::Get().Available();
#else
    return false;
#endif
}

void GuestWriteWatchRegister_nid_postfix(const void* pointer, std::size_t bytes) {
#ifdef APS5_GUEST_WRITE_WATCH
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().Register(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
#endif
}

bool GuestWriteWatchUnregister_nid_postfix(const void* pointer, std::size_t bytes) {
#ifdef APS5_GUEST_WRITE_WATCH
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    return Watch::Get().Unregister(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
    return false;
#endif
}

bool GuestWriteWatchCovers_nid_postfix(std::uintptr_t address, std::size_t bytes) {
#ifdef APS5_GUEST_WRITE_WATCH
    return bytes != 0 && address + bytes > address && Watch::Get().Covers(address, address + bytes);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
    return false;
#endif
}

bool GuestWriteWatchOverlaps_nid_postfix(std::uintptr_t address, std::size_t bytes) {
#ifdef APS5_GUEST_WRITE_WATCH
    return bytes != 0 && address + bytes > address && Watch::Get().Overlaps(address, address + bytes);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
    return false;
#endif
}

bool GuestWriteWatchHandleFault_nid_postfix(std::uintptr_t address) {
#if defined(__APPLE__)
    return Watch::Get().HandleFault(address);
#else
    static_cast<void>(address);
    return false;
#endif
}

bool GuestWriteWatchClaimFault_nid_postfix(void* info, void* context) {
#if defined(__APPLE__)
    return Watch::Get().Available() && Watch::claim(static_cast<siginfo_t*>(info), context);
#else
    static_cast<void>(info);
    static_cast<void>(context);
    return false;
#endif
}

bool GuestWriteWatchCollect_nid_postfix(std::uintptr_t address, std::size_t bytes, void (*written)(void* context, std::uintptr_t begin, std::uintptr_t end), void* context) {
#ifdef APS5_GUEST_WRITE_WATCH
    if (bytes == 0 || address + bytes < address) return false;
    return Watch::Get().Collect(address, address + bytes, written, context);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
    static_cast<void>(written);
    static_cast<void>(context);
    return false;
#endif
}

void GuestWriteWatchBeginHostWrite_nid_postfix(const void* pointer, std::size_t bytes) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().BeginHostWrite(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
#endif
}

void GuestWriteWatchOpenImport_nid_postfix(const void* pointer, std::size_t bytes) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().OpenImport(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
#endif
}

void GuestWriteWatchCloseImport_nid_postfix(const void* pointer, std::size_t bytes) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().CloseImport(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
#endif
}

void GuestWriteWatchEndHostWrite_nid_postfix(const void* pointer, std::size_t bytes) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().EndHostWrite(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
#endif
}

void GuestWriteWatchHostWrites_nid_postfix(const void* pointer, std::size_t bytes) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().HostWrites(begin, begin + bytes);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
#endif
}

bool GuestWriteWatchChainSignal_nid_postfix(int signal, void (*handler)(int)) {
#if defined(__APPLE__)
    return Watch::Get().ChainSignal(signal, handler);
#else
    static_cast<void>(signal);
    static_cast<void>(handler);
    return false;
#endif
}

void GuestWriteWatchProtectionChanged_nid_postfix(const void* pointer, std::size_t bytes, int protection) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    Watch::Get().ProtectionChanged(begin, begin + bytes, protection);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
    static_cast<void>(protection);
#endif
}

int GuestWriteWatchProtect_nid_postfix(void* pointer, std::size_t bytes, int protection) {
#if defined(__APPLE__)
    const auto begin = reinterpret_cast<std::uintptr_t>(pointer);
    return Watch::Get().Protect(begin, begin + bytes, protection);
#else
    static_cast<void>(pointer);
    static_cast<void>(bytes);
    static_cast<void>(protection);
    return ENOSYS;
#endif
}

int GuestWriteWatchProtection_nid_postfix(std::uintptr_t address, std::uintptr_t limit, std::uintptr_t* runEnd) {
#if defined(__APPLE__)
    return Watch::Get().Protection(address, limit, runEnd);
#else
    static_cast<void>(address);
    *runEnd = limit;
    return -1;
#endif
}

bool GuestWriteWatchCollectFresh_nid_postfix(std::uintptr_t address, std::size_t bytes, void (*written)(void* context, std::uintptr_t begin, std::uintptr_t end), void* context) {
#if defined(__linux__) && defined(PAGEMAP_SCAN) && defined(UFFD_FEATURE_WP_ASYNC)
    if (bytes == 0 || address + bytes < address) return false;
    return Watch::Get().CollectFresh(address, address + bytes, written, context);
#elif defined(__APPLE__)
    if (bytes == 0 || address + bytes < address) return false;
    return Watch::Get().Collect(address, address + bytes, written, context, Watch::Take::Fresh);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
    static_cast<void>(written);
    static_cast<void>(context);
    return false;
#endif
}

bool GuestWriteWatchCollectArmed_nid_postfix(std::uintptr_t address, std::size_t bytes, void (*written)(void* context, std::uintptr_t begin, std::uintptr_t end), void* context) {
#if defined(__linux__) && defined(PAGEMAP_SCAN) && defined(UFFD_FEATURE_WP_ASYNC)
    if (bytes == 0 || address + bytes < address) return false;
    return Watch::Get().CollectArmed(address, address + bytes, written, context);
#elif defined(__APPLE__)
    if (bytes == 0 || address + bytes < address) return false;
    return Watch::Get().Collect(address, address + bytes, written, context, Watch::Take::Armed);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
    static_cast<void>(written);
    static_cast<void>(context);
    return false;
#endif
}

bool GuestWriteWatchSetReadTrapResolver_nid_postfix(void (*resolve)(std::uintptr_t begin, std::uintptr_t end)) {
#if defined(__APPLE__)
    return Watch::Get().SetReadTrapResolver(resolve);
#else
    static_cast<void>(resolve);
    return false;
#endif
}

bool GuestWriteWatchTrapReads_nid_postfix(std::uintptr_t address, std::size_t bytes) {
#if defined(__APPLE__)
    return bytes != 0 && address + bytes > address && Watch::Get().TrapReads(address, address + bytes);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
    return false;
#endif
}

void GuestWriteWatchReleaseReads_nid_postfix(std::uintptr_t address, std::size_t bytes) {
#if defined(__APPLE__)
    if (bytes != 0 && address + bytes > address) Watch::Get().ReleaseReads(address, address + bytes);
#else
    static_cast<void>(address);
    static_cast<void>(bytes);
#endif
}

}
