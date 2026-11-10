#ifndef CORE_LIBS_FLOATCHARS_HPP
#define CORE_LIBS_FLOATCHARS_HPP

#include <cerrno>
#include <charconv>
#include <cmath>
#include <cstdlib>
#include <string>
#include <system_error>
#include <type_traits>

#if defined(__APPLE__) && defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) && __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 260000
#define APS5_FLOAT_CHARS_STRTOD 1
#include <xlocale.h>
#endif

namespace Aps5 {

template<typename TFloat>
std::from_chars_result FloatFromChars(const char* first, const char* last, TFloat& value) {
    static_assert(std::is_same_v<TFloat, float> || std::is_same_v<TFloat, double>);
#ifdef APS5_FLOAT_CHARS_STRTOD
    const char* cursor = first;
    if (cursor != last && *cursor == '-') ++cursor;
    if (cursor == last) return {first, std::errc::invalid_argument};
    const char lead = *cursor;
    const bool number = (lead >= '0' && lead <= '9') || lead == '.';
    const bool word = lead == 'i' || lead == 'I' || lead == 'n' || lead == 'N';
    if (!number && !word) return {first, std::errc::invalid_argument};
    if (lead == '0' && cursor + 1 != last && (cursor[1] == 'x' || cursor[1] == 'X')) {
        value = cursor != first ? TFloat(-0.0) : TFloat(0.0);
        return {cursor + 1, std::errc{}};
    }
    const std::string text(first, last);
    char* end = nullptr;
    errno = 0;
    TFloat parsed;
    if constexpr (std::is_same_v<TFloat, float>) {
        parsed = strtof_l(text.c_str(), &end, LC_C_LOCALE);
    } else {
        parsed = strtod_l(text.c_str(), &end, LC_C_LOCALE);
    }
    const int error = errno;
    if (end == text.c_str()) return {first, std::errc::invalid_argument};
    const char* stop = first + (end - text.c_str());
    if (error == ERANGE && (std::isinf(parsed) || parsed == TFloat(0))) return {stop, std::errc::result_out_of_range};
    value = parsed;
    return {stop, std::errc{}};
#else
    return std::from_chars(first, last, value);
#endif
}

}  // namespace Aps5

#endif  // CORE_LIBS_FLOATCHARS_HPP
