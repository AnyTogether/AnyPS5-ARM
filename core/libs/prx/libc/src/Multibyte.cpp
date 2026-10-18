#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libc/include/SonyCrt.hpp"
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <climits>
#include <stdexcept>

namespace {

constexpr std::size_t PendingOffset = 0xa;
constexpr std::int8_t LowSurrogatePending = 0x10;

void StorePending(unsigned char* state, std::int8_t pending) {
    const auto stored = static_cast<std::int16_t>(pending);
    std::memcpy(state + PendingOffset, &stored, sizeof(stored));
}

std::size_t EncodeUtf8(char* destination, std::uint64_t value) {
    if (value < 0x80) {
        destination[0] = static_cast<char>(value);
        return 1;
    }
    int extra = 5;
    unsigned lead = 0xfc;
    int shift = 30;
    if (value < 0x800) { extra = 1; lead = 0xc0; shift = 6; }
    else if (value < 0x10000) { extra = 2; lead = 0xe0; shift = 12; }
    else if (value < 0x200000) { extra = 3; lead = 0xf0; shift = 18; }
    else if (value < 0x4000000) { extra = 4; lead = 0xf8; shift = 24; }
    destination[0] = static_cast<char>((value >> shift) | lead);
    for (int index = 1; index <= extra; ++index)
        destination[index] = static_cast<char>(((value >> (shift - 6 * index)) & 0x3f) | 0x80);
    return static_cast<std::size_t>(extra + 1);
}

bool DecodeUtf8Byte(unsigned char byte, std::uint64_t& value, std::int8_t& pending) {
    if (pending > 0) {
        if ((byte & 0xc0) != 0x80) return false;
        value = (value << 6) | (byte & 0x3f);
        --pending;
        return true;
    }
    if (byte < 0x80) value = byte;
    else if ((byte & 0xe0) == 0xc0) { value = byte & 0x1f; pending = 1; }
    else if ((byte & 0xf0) == 0xe0) { value = byte & 0x0f; pending = 2; }
    else if ((byte & 0xf8) == 0xf0) { value = byte & 0x07; pending = 3; }
    else if (byte >= 0xfc) { value = byte & 0x03; pending = 5; }
    else if ((byte & 0xfc) == 0xf8) { value = byte & 0x03; pending = 4; }
    else return false;
    return true;
}

}

extern "C" {

int __mb_cur_max_nid_postfix = 1;

int APS5_VABI ___mb_cur_max_nid_postfix() {
    return 1;
}

int APS5_VABI _Getmbcurmax_nid_postfix() { return ___mb_cur_max_nid_postfix(); }

int APS5_VABI mbsinit_nid_postfix(const void*) {
    return 1;
}

std::size_t APS5_VABI mbrtowc_nid_postfix(std::uint16_t* destination, const char* source, std::size_t count, void*) {
    if (!source) return 0;
    if (!count) return static_cast<std::size_t>(-2);
    const auto value = static_cast<unsigned char>(*source);
    if (destination) *destination = value;
    return value != 0;
}

std::size_t APS5_VABI mbrlen_nid_postfix(const char* source, std::size_t count, void* state) {
    return mbrtowc_nid_postfix(nullptr, source, count, state);
}

int APS5_VABI mbtowc_nid_postfix(std::uint16_t* destination, const char* source, std::size_t count) {
    const auto result = mbrtowc_nid_postfix(destination, source, count, nullptr);
    if (result == static_cast<std::size_t>(-2)) {
        errno = 86;
        return -1;
    }
    return static_cast<int>(result);
}

std::size_t APS5_VABI wcrtomb_nid_postfix(char* destination, std::uint16_t value, void*) {
    if (!destination) return 1;
    if (value > 255) {
        errno = 86;
        return static_cast<std::size_t>(-1);
    }
    *destination = static_cast<char>(value);
    return 1;
}

int APS5_VABI mblen_nid_postfix(const char* source, std::size_t count) {
    return mbtowc_nid_postfix(nullptr, source, count);
}

int APS5_VABI wctomb_nid_postfix(char* destination, std::uint16_t value) {
    if (!destination) return 0;
    const auto result = wcrtomb_nid_postfix(destination, value, nullptr);
    return result == static_cast<std::size_t>(-1) ? -1 : static_cast<int>(result);
}

std::size_t APS5_VABI c32rtomb_nid_postfix(char* destination, std::uint32_t value, void*) {
    char scratch[8];
    if (!destination) {
        destination = scratch;
        value = 0;
    }
    return EncodeUtf8(destination, value);
}

std::size_t APS5_VABI c16rtomb_nid_postfix(char* destination, std::uint16_t unit, void* state) {
    if (!state) throw std::invalid_argument("c16rtomb: null conversion state");
    char scratch[8];
    if (!destination) {
        destination = scratch;
        unit = 0;
    }
    auto* const bytes = static_cast<unsigned char*>(state);
    std::uint64_t value = unit;
    if (bytes[PendingOffset] != 0) {
        if (static_cast<std::uint16_t>(unit + 0x2000) < 0xfc00) return static_cast<std::size_t>(-1);
        std::uint64_t high = 0;
        std::memcpy(&high, bytes, sizeof(high));
        value = high | (unit & 0x3ffu);
        StorePending(bytes, 0);
    } else if (static_cast<std::uint16_t>(unit + 0x2400) >= 0xfc00) {
        const std::uint64_t high = ((static_cast<std::uint64_t>(unit) << 10) + 0x10000) & 0x1ffc00;
        std::memcpy(bytes, &high, sizeof(high));
        StorePending(bytes, 1);
        return 0;
    }
    return EncodeUtf8(destination, value);
}

std::size_t APS5_VABI mbrtoc32_nid_postfix(std::uint32_t* destination, const char* source, std::size_t count, void* state) {
    if (!state) throw std::invalid_argument("mbrtoc32: null conversion state");
    auto* const bytes = static_cast<unsigned char*>(state);
    if (!source) {
        destination = nullptr;
        source = "";
        count = 1;
    }
    std::uint64_t value = 0;
    std::memcpy(&value, bytes, sizeof(value));
    auto pending = static_cast<std::int8_t>(bytes[PendingOffset]);
    for (std::size_t consumed = 0; consumed < count;) {
        const auto byte = static_cast<unsigned char>(source[consumed++]);
        if (!DecodeUtf8Byte(byte, value, pending)) {
            errno = 86;
            return static_cast<std::size_t>(-1);
        }
        if (pending == 0) {
            if (destination) *destination = static_cast<std::uint32_t>(value);
            StorePending(bytes, 0);
            return value == 0 ? 0 : consumed;
        }
    }
    std::memcpy(bytes, &value, sizeof(value));
    StorePending(bytes, pending);
    return static_cast<std::size_t>(-2);
}

std::size_t APS5_VABI mbrtoc16_nid_postfix(std::uint16_t* destination, const char* source, std::size_t count, void* state) {
    if (!state) throw std::invalid_argument("mbrtoc16: null conversion state");
    auto* const bytes = static_cast<unsigned char*>(state);
    if (!source) {
        destination = nullptr;
        source = "";
        count = 1;
    }
    std::uint64_t value = 0;
    std::memcpy(&value, bytes, sizeof(value));
    auto pending = static_cast<std::int8_t>(bytes[PendingOffset]);
    if (pending == LowSurrogatePending) {
        if (destination) *destination = static_cast<std::uint16_t>((value & 0x3ff) | 0xdc00);
        StorePending(bytes, 0);
        return static_cast<std::size_t>(-3);
    }
    for (std::size_t consumed = 0; consumed < count;) {
        const auto byte = static_cast<unsigned char>(source[consumed++]);
        if (!DecodeUtf8Byte(byte, value, pending)) {
            errno = 86;
            return static_cast<std::size_t>(-1);
        }
        if (pending != 0) continue;
        if (value >= 0x110000) {
            errno = 86;
            return static_cast<std::size_t>(-1);
        }
        if (value >= 0x10000) {
            if (destination) *destination = static_cast<std::uint16_t>(((value >> 10) + 0x3fc0) | 0xd800);
            StorePending(bytes, LowSurrogatePending);
            return consumed;
        }
        if (destination) *destination = static_cast<std::uint16_t>(value);
        StorePending(bytes, 0);
        return value == 0 ? 0 : consumed;
    }
    std::memcpy(bytes, &value, sizeof(value));
    StorePending(bytes, pending);
    return static_cast<std::size_t>(-2);
}

std::size_t APS5_VABI wcsrtombs_nid_postfix(char* destination, const std::uint16_t** source, std::size_t capacity, void* state) {
    const auto* wide = *source;
    std::size_t converted = 0;
    while (!destination || converted < capacity) {
        char byte;
        if (wcrtomb_nid_postfix(&byte, wide[converted], state) == static_cast<std::size_t>(-1)) {
            if (destination) *source = wide + converted;
            return static_cast<std::size_t>(-1);
        }
        if (destination) destination[converted] = byte;
        if (byte == '\0') {
            if (destination) *source = nullptr;
            return converted;
        }
        ++converted;
    }
    *source = wide + converted;
    return converted;
}

int APS5_VABI wcsrtombs_s_nid_postfix(
    std::size_t* result, char* destination, std::size_t capacity, const std::uint16_t** source, std::size_t limit,
    void* state
) {
    constexpr int GuestEinval = 22;
    constexpr int GuestErange = 34;
    constexpr int GuestEilseq = 86;
    constexpr auto Failed = static_cast<std::size_t>(-1);
    if (!result || !source || !state || !*source || (destination && (static_cast<std::int64_t>(capacity) <= 0
            || static_cast<std::int64_t>(limit) < 0))) {
        if (destination && static_cast<std::int64_t>(capacity) > 0) destination[0] = '\0';
        if (result) *result = Failed;
        return GuestEinval;
    }
    if (!destination && capacity) {
        *result = Failed;
        return GuestEinval;
    }
    const auto* wide = *source;
    char bytes[MB_LEN_MAX];
    if (!destination) {
        std::size_t total = 0;
        for (;; ++wide) {
            const auto length = wcrtomb_nid_postfix(bytes, *wide, state);
            if (length == Failed) {
                *result = Failed;
                return GuestEilseq;
            }
            if (length && bytes[length - 1] == '\0') {
                *result = total + length - 1;
                return 0;
            }
            total += length;
        }
    }
    std::size_t written = 0;
    while (limit) {
        const auto length = wcrtomb_nid_postfix(bytes, *wide, state);
        if (length == Failed) {
            destination[written] = '\0';
            *result = Failed;
            return GuestEilseq;
        }
        if (length > limit || length > capacity) {
            *source = wide;
            destination[0] = '\0';
            *result = Failed;
            return GuestErange;
        }
        std::memcpy(destination + written, bytes, length);
        written += length;
        if (length && destination[written - 1] == '\0') {
            *source = nullptr;
            *result = written - 1;
            return 0;
        }
        ++wide;
        capacity -= length;
        if (!capacity) {
            *source = wide;
            destination[0] = '\0';
            *result = Failed;
            return GuestErange;
        }
        limit -= length;
    }
    *source = wide;
    destination[written] = '\0';
    *result = written;
    return 0;
}

std::size_t APS5_VABI mbsrtowcs_nid_postfix(std::uint16_t* destination, const char** source, std::size_t capacity, void*) {
    if (!destination) return std::strlen(*source);
    std::size_t converted = 0;
    while (converted < capacity) {
        const auto value = static_cast<unsigned char>((*source)[converted]);
        destination[converted] = value;
        if (value == 0) {
            *source = nullptr;
            return converted;
        }
        ++converted;
    }
    *source += converted;
    return converted;
}

std::size_t APS5_VABI mbstowcs_nid_postfix(std::uint16_t* dest, const char* src, std::size_t size) {
    return SonyMbstowcs(dest, src, size);
}

}
