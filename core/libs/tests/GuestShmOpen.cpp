#include "prx/libkernel/include/Api.hpp"
#include "prx/libc/include/Api.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI shm_unlink_nid_postfix(const char*);
}
static void Require(bool value) { if (!value) std::abort(); }
static const char* const anonymous = reinterpret_cast<const char*>(1);
static void RequireInvalid(const char* path, int flags) {
    *__error_nid_postfix() = 0;
    Require(shm_open_nid_postfix(path, flags, 0600) == -1);
    Require(*__error_nid_postfix() == 22);
}
static void RequireError(const char* path, int flags, int error) {
    *__error_nid_postfix() = 0;
    Require(shm_open_nid_postfix(path, flags, 0600) == -1);
    Require(*__error_nid_postfix() == error);
}
#ifdef __APPLE__
// On macOS a named object lives in the process until shm_unlink.
static void CheckNamed() {
    const char* const name = "/anyps5-shm";
    RequireError(name, 0x2, 2);
    RequireError(name, 0x0, 2);
    RequireError(nullptr, 0x202, 14);
    std::string longName(1024, 'n');
    RequireError(longName.c_str(), 0x202, 63);
    const int creator = shm_open_nid_postfix(name, 0x100a02, 0600);
    Require(creator >= 0);
    RequireError(name, 0xa02, 17);
    Require(ftruncate_nid_postfix(creator, 0x2000) == 0);
    const char text[] = "named";
    Require(pwrite_nid_disambig1_nid_postfix(creator, text, sizeof(text), 0x100) == static_cast<std::int64_t>(sizeof(text)));
    const int reader = shm_open_nid_postfix(name, 0x0, 0);
    Require(reader >= 0 && reader != creator);
    char back[sizeof(text)] = {};
    Require(pread_nid_postfix(reader, back, sizeof(back), 0x100) == static_cast<std::int64_t>(sizeof(back)));
    Require(std::memcmp(back, text, sizeof(text)) == 0);
    *__error_nid_postfix() = 0;
    Require(pwrite_nid_disambig1_nid_postfix(reader, text, sizeof(text), 0) == -1);
    Require(*__error_nid_postfix() == 9);
    // Read-only O_TRUNC leaves the object alone; a read-write O_TRUNC empties it for every opener.
    const int readOnlyTruncate = shm_open_nid_postfix(name, 0x400, 0);
    Require(readOnlyTruncate >= 0);
    Require(pread_nid_postfix(reader, back, 1, 0x1fff) == 1);
    const int truncating = shm_open_nid_postfix(name, 0x602, 0600);
    Require(truncating >= 0);
    Require(pread_nid_postfix(reader, back, 1, 0) == 0);
    const int other = shm_open_nid_postfix("/anyps5-shm-other", 0x202, 0600);
    Require(other >= 0);
    Require(pread_nid_postfix(other, back, 1, 0) == 0);
    for (const int descriptor : {creator, reader, readOnlyTruncate, truncating, other})
        Require(close_nid_postfix(descriptor) == 0);
    const int reopened = shm_open_nid_postfix(name, 0x2, 0);
    Require(reopened >= 0);
    // shm_unlink frees the name at once; an open descriptor stays usable.
    Require(shm_unlink_nid_postfix(name) == 0);
    RequireError(name, 0x2, 2);
    Require(pread_nid_postfix(reopened, back, 1, 0) == 0);
    Require(close_nid_postfix(reopened) == 0);
    *__error_nid_postfix() = 0;
    Require(shm_unlink_nid_postfix(name) == -1 && *__error_nid_postfix() == 2);
    *__error_nid_postfix() = 0;
    Require(shm_unlink_nid_postfix("") == -1 && *__error_nid_postfix() == 22);
    Require(shm_unlink_nid_postfix("/anyps5-shm-other") == 0);
    const int recreated = shm_open_nid_postfix(name, 0xa02, 0600);
    Require(recreated >= 0 && close_nid_postfix(recreated) == 0);
    Require(shm_unlink_nid_postfix(name) == 0);
}
#endif
int main() {
    *__error_nid_postfix() = 13;
    const int first = shm_open_nid_postfix(anonymous, 0x100202, 0600);
    const int second = shm_open_nid_postfix(anonymous, 0x2, 0);
    const int third = shm_open_nid_postfix(anonymous, 0x100e02, 0400);
    Require(first >= 0 && second >= 0 && third >= 0);
    Require(first != second && second != third && first != third);
    Require(*__error_nid_postfix() == 13);
    Require(ftruncate_nid_postfix(first, 0x4000) == 0);
    const char text[] = "anonymous";
    Require(pwrite_nid_disambig1_nid_postfix(first, text, sizeof(text), 0x1000) == static_cast<std::int64_t>(sizeof(text)));
    char back[sizeof(text)] = {};
    Require(pread_nid_postfix(first, back, sizeof(back), 0x1000) == static_cast<std::int64_t>(sizeof(back)));
    Require(std::memcmp(back, text, sizeof(text)) == 0);
    char last = 1;
    Require(pread_nid_postfix(first, &last, 1, 0x3fff) == 1 && last == 0);
    Require(pread_nid_postfix(first, &last, 1, 0x4000) == 0);
    Require(pread_nid_postfix(second, back, sizeof(back), 0) == 0);
#ifndef __APPLE__
    // macOS maps no shared guest file views (file-backed guest mmap is Linux and Windows only).
    auto* view = static_cast<volatile char*>(mmap_nid_postfix(nullptr, 0x4000, 3, 0x1, first, 0));
    Require(view != reinterpret_cast<void*>(static_cast<std::uintptr_t>(-1)));
    Require(view[0x1000] == 'a' && view[0x3fff] == 0);
    view[0x2000] = 'm';
    Require(pread_nid_postfix(first, &last, 1, 0x2000) == 1 && last == 'm');
    Require(munmap_nid_postfix(const_cast<char*>(view), 0x4000) == 0);
#ifndef _WIN32
    const unsigned char code[] = {0xb8, 0x2a, 0, 0, 0, 0xc3};
    Require(pwrite_nid_disambig1_nid_postfix(first, code, sizeof(code), 0) == static_cast<std::int64_t>(sizeof(code)));
    void* executable = mmap_nid_postfix(nullptr, 0x4000, 5, 0x1, first, 0);
    Require(executable != reinterpret_cast<void*>(static_cast<std::uintptr_t>(-1)));
    int (*function)();
    std::memcpy(&function, &executable, sizeof(function));
    Require(function() == 42);
    Require(munmap_nid_postfix(executable, 0x4000) == 0);
#endif
#endif
#ifdef __linux__
    // A shared-memory write does not grow the object; macOS and Windows back it with a temporary file.
    Require(pwrite_nid_disambig1_nid_postfix(third, text, sizeof(text), 0) == 0);
#endif
    Require(ftruncate_nid_postfix(third, 0x4000) == 0);
    Require(pwrite_nid_disambig1_nid_postfix(third, text, sizeof(text), 0) == static_cast<std::int64_t>(sizeof(text)));
    Require(close_nid_postfix(first) == 0 && close_nid_postfix(second) == 0 && close_nid_postfix(third) == 0);
    RequireInvalid(anonymous, 0x0);
    RequireInvalid(anonymous, 0x200);
    RequireInvalid(anonymous, 0x1);
    RequireInvalid(anonymous, 0x3);
    RequireInvalid(anonymous, 0x2 | 0x8);
    RequireInvalid(anonymous, 0x2 | 0x4);
    RequireInvalid("/anyps5-shm", 0x1);
    RequireInvalid("/anyps5-shm", 0x202 | 0x8);
    RequireInvalid("", 0x202);
#ifdef __APPLE__
    CheckNamed();
#endif
}
