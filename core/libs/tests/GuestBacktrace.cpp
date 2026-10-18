#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <vector>

extern "C" {
int APS5_VABI sceLibcBacktraceGetBufferSize_nid_postfix(int, int*, std::size_t*);
int APS5_VABI sceLibcBacktraceSelf_nid_postfix(int, void*, std::size_t, int*);
}

namespace {

constexpr std::size_t NameOffset = 0x10;
constexpr unsigned char Fill = 0xcc;

struct Record {
    const std::byte* next;
    std::uint32_t offset;
    std::uint32_t reserved;
    std::string module;
    std::size_t bytes;
};

void Require(bool condition, const char* message) {
    if (condition) return;
    std::fprintf(stderr, "guest backtrace: %s\n", message);
    std::abort();
}

std::vector<Record> Parse(const std::vector<unsigned char>& buffer, std::size_t used, int count) {
    std::vector<Record> records;
    const auto* base = reinterpret_cast<const std::byte*>(buffer.data());
    const auto* cursor = count == 0 ? nullptr : base;
    while (cursor != nullptr) {
        Require(cursor >= base && static_cast<std::size_t>(cursor - base) + NameOffset < used, "record outside the written bytes");
        Require(reinterpret_cast<std::uintptr_t>(cursor) % 8 == 0, "record is not 8-byte aligned");
        Record record{};
        std::memcpy(&record.next, cursor, sizeof(record.next));
        std::memcpy(&record.offset, cursor + 8, sizeof(record.offset));
        std::memcpy(&record.reserved, cursor + 12, sizeof(record.reserved));
        const auto* name = reinterpret_cast<const char*>(cursor + NameOffset);
        const auto limit = used - static_cast<std::size_t>(cursor - base) - NameOffset;
        const auto length = strnlen(name, limit);
        Require(length < limit, "module name is not terminated inside the record");
        record.module.assign(name, length);
        record.bytes = (NameOffset + length + 1 + 7) & ~std::size_t{7};
        Require(record.next == nullptr || record.next == cursor + record.bytes, "next does not point to the following record");
        records.push_back(record);
        cursor = record.next;
    }
    Require(static_cast<int>(records.size()) == count, "record list length differs from the reported count");
    return records;
}

std::size_t Used(const std::vector<Record>& records) {
    std::size_t total = 0;
    for (const auto& record : records) total += record.bytes;
    return total;
}

}

[[gnu::noinline]] void CheckBacktrace() {
    Dl_info self{};
    Require(dladdr(reinterpret_cast<void*>(&CheckBacktrace), &self) != 0 && self.dli_fname != nullptr && self.dli_saddr != nullptr, "dladdr of the test failed");
    std::string executable = self.dli_fname;
    executable.erase(0, executable.find_last_of('/') + 1);

    int count = -1;
    std::size_t size = 0;
    Require(sceLibcBacktraceGetBufferSize_nid_postfix(-1, &count, &size) == 0, "GetBufferSize failed");
    Require(count > 1 && size >= static_cast<std::size_t>(count) * NameOffset, "GetBufferSize reported too little");

    std::vector<unsigned char> buffer(size + 64, Fill);
    int written = -1;
    Require(sceLibcBacktraceSelf_nid_postfix(-1, buffer.data(), size, &written) == 0, "Self failed");
    Require(written == count, "Self wrote a different count than GetBufferSize reported");
    const auto records = Parse(buffer, size, written);
    Require(Used(records) == size, "Self used a different size than GetBufferSize reported");
    for (std::size_t index = size; index < buffer.size(); ++index) Require(buffer[index] == Fill, "Self wrote past the buffer size");
    for (const auto& record : records) Require(record.reserved == 0 && !record.module.empty(), "record has a nonzero reserved word or no module");
    Require(records.front().module == executable, "first frame is not in the calling module");
    Dl_info caller{};
    const auto address = reinterpret_cast<std::uintptr_t>(self.dli_fbase) + records.front().offset;
    Require(dladdr(reinterpret_cast<void*>(address), &caller) != 0 && caller.dli_saddr == self.dli_saddr, "first frame is not the caller");

    for (const int limit : {0, 1, 2}) {
        Require(sceLibcBacktraceGetBufferSize_nid_postfix(limit, &count, &size) == 0 && count == limit, "GetBufferSize ignored the frame limit");
        std::vector<unsigned char> limited(size + 64, Fill);
        Require(sceLibcBacktraceSelf_nid_postfix(limit, limited.data(), limited.size(), &written) == 0 && written == limit, "Self ignored the frame limit");
        const auto limitedRecords = Parse(limited, limited.size(), written);
        Require(Used(limitedRecords) == size, "limited Self used a different size than GetBufferSize reported");
        for (int index = 0; index < limit; ++index) Require(limitedRecords[index].module == records[index].module, "limited frames differ from the full trace");
    }

    const auto first = records.front().bytes;
    for (const std::size_t available : {std::size_t{0}, first - 1, first, first + records[1].bytes - 1, first + records[1].bytes}) {
        std::vector<unsigned char> small(available + 64, Fill);
        written = -1;
        Require(sceLibcBacktraceSelf_nid_postfix(-1, small.data(), available, &written) == 0, "Self with a small buffer failed");
        const int expected = available < first ? 0 : available < first + records[1].bytes ? 1 : 2;
        Require(written == expected, "Self with a small buffer wrote the wrong number of records");
        const auto smallRecords = Parse(small, available, written);
        Require(written == 0 || smallRecords.back().next == nullptr, "last record is not terminated");
        for (std::size_t index = Used(smallRecords); index < small.size(); ++index) Require(small[index] == Fill, "Self wrote past the last record that fits");
    }
}

int main() {
    CheckBacktrace();
}
