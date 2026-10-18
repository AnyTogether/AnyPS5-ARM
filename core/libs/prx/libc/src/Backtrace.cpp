#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#include "prx/libc/include/General.hpp"

#ifdef __linux__
#include <dlfcn.h>
#include <execinfo.h>

namespace {

constexpr int MaxFrames = 256;
constexpr std::size_t NameOffset = 0x10;
constexpr char GuestSuffix[] = ".guest.prx";

struct Frame {
    std::uint32_t offset;
    std::string module;
};

struct FrameRecord {
    FrameRecord* next;
    std::uint32_t offset;
    std::uint32_t reserved;
};
static_assert(sizeof(FrameRecord) == NameOffset);

[[gnu::noinline]] std::vector<Frame> CaptureFrames(int limit) {
    void* addresses[MaxFrames];
    const int captured = backtrace(addresses, MaxFrames);
    std::vector<Frame> frames;
    for (int index = 2; index < captured && (limit < 0 || static_cast<int>(frames.size()) < limit); ++index) {
        Dl_info info{};
        if (dladdr(addresses[index], &info) == 0 || info.dli_fbase == nullptr || info.dli_fname == nullptr) continue;
        const auto offset = reinterpret_cast<std::uintptr_t>(addresses[index]) - reinterpret_cast<std::uintptr_t>(info.dli_fbase);
        if (offset > UINT32_MAX) continue;
        std::string module = info.dli_fname;
        if (const auto slash = module.find_last_of('/'); slash != std::string::npos) module.erase(0, slash + 1);
        if (module.size() > sizeof(GuestSuffix) - 1 && module.compare(module.size() - (sizeof(GuestSuffix) - 1), std::string::npos, GuestSuffix) == 0)
            module.resize(module.size() - (sizeof(GuestSuffix) - 1));
        frames.push_back({static_cast<std::uint32_t>(offset), std::move(module)});
    }
    return frames;
}

std::size_t RecordSize(const Frame& frame) {
    return (NameOffset + frame.module.size() + 1 + 7) & ~std::size_t{7};
}

}  // namespace

extern "C" {

int APS5_VABI sceLibcBacktraceGetBufferSize_nid_postfix(int limit, int* count, std::size_t* size) {
    if (count == nullptr || size == nullptr) throw std::invalid_argument("sceLibcBacktraceGetBufferSize: null output");
    const auto frames = CaptureFrames(limit);
    std::size_t total = 0;
    for (const auto& frame : frames) total += RecordSize(frame);
    *count = static_cast<int>(frames.size());
    *size = total;
    return 0;
}

int APS5_VABI sceLibcBacktraceSelf_nid_postfix(int limit, void* buffer, std::size_t size, int* count) {
    if (buffer == nullptr || count == nullptr) throw std::invalid_argument("sceLibcBacktraceSelf: null argument");
    const auto frames = CaptureFrames(limit);
    auto* cursor = static_cast<std::byte*>(buffer);
    FrameRecord* previous = nullptr;
    int written = 0;
    for (const auto& frame : frames) {
        const auto bytes = RecordSize(frame);
        if (static_cast<std::size_t>(cursor - static_cast<std::byte*>(buffer)) + bytes > size) break;
        auto* record = reinterpret_cast<FrameRecord*>(cursor);
        record->next = nullptr;
        record->offset = frame.offset;
        record->reserved = 0;
        std::memcpy(cursor + NameOffset, frame.module.c_str(), frame.module.size() + 1);
        if (previous != nullptr) previous->next = record;
        previous = record;
        cursor += bytes;
        ++written;
    }
    *count = written;
    return 0;
}

}

#else

extern "C" {

int APS5_VABI sceLibcBacktraceGetBufferSize_nid_postfix(int limit, int* count, std::size_t* size) {
    (void)limit;
    (void)count;
    (void)size;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceLibcBacktraceSelf_nid_postfix(int limit, void* buffer, std::size_t size, int* count) {
    (void)limit;
    (void)buffer;
    (void)size;
    (void)count;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}

#endif
