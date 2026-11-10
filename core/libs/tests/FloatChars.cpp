#include "FloatChars.hpp"
#include <cmath>
#include <cstring>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>
#include <system_error>

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

template<typename TFloat>
TFloat parses(const char* text, std::size_t used) {
    TFloat value = TFloat(7);
    const auto result = Aps5::FloatFromChars(text, text + std::strlen(text), value);
    require(result.ec == std::errc{}, std::string("parses ") + text);
    require(result.ptr == text + used, std::string("stops where std::from_chars stops in ") + text);
    return value;
}

template<typename TFloat>
void refuses(const char* text) {
    TFloat value = TFloat(7);
    const auto result = Aps5::FloatFromChars(text, text + std::strlen(text), value);
    require(result.ec == std::errc::invalid_argument, std::string("refuses ") + text);
    require(result.ptr == text, std::string("points at the start of ") + text);
    require(value == TFloat(7), std::string("leaves the value alone for ") + text);
}

template<typename TFloat>
void outOfRange(const char* text) {
    TFloat value = TFloat(7);
    const auto result = Aps5::FloatFromChars(text, text + std::strlen(text), value);
    require(result.ec == std::errc::result_out_of_range, std::string("out of range: ") + text);
    require(result.ptr == text + std::strlen(text), std::string("consumes the number in ") + text);
    require(value == TFloat(7), std::string("leaves the value alone for ") + text);
}

void readsDecimals() {
    require(parses<double>("1.5", 3) == 1.5, "1.5");
    require(parses<double>("-2.25e3", 7) == -2250.0, "-2.25e3");
    require(parses<double>(".5", 2) == 0.5, ".5");
    require(parses<double>("1.5garbage", 3) == 1.5, "stops at the first letter");
    require(parses<double>("1e", 1) == 1.0, "an exponent without digits is not part of the number");
    require(parses<double>("1,5", 1) == 1.0, "the decimal point is always a dot");
    require(parses<double>("0.1", 3) == 0.1, "rounds as the compiler does");
    require(parses<float>("0.1", 3) == 0.1f, "float rounds as the compiler does");
}

void readsSpecialValues() {
    require(std::isinf(parses<double>("inf", 3)), "inf");
    require(std::isinf(parses<double>("-infinity", 9)) && parses<double>("-infinity", 9) < 0, "-infinity");
    require(std::isnan(parses<double>("nan", 3)), "nan");
    require(std::isinf(parses<float>("INF", 3)), "INF");
}

void readsHexPrefixAsZero() {
    require(parses<double>("0x10", 1) == 0.0, "0x10 is 0 then x");
    const double negative = parses<double>("-0x10", 2);
    require(negative == 0.0 && std::signbit(negative), "-0x10 is -0 then x");
}

void refusesWhatStdFromCharsRefuses() {
    refuses<double>("");
    refuses<double>("-");
    refuses<double>("+1");
    refuses<double>(" 1");
    refuses<double>("e5");
    refuses<double>(".");
    refuses<float>("x");
}

void reportsOutOfRange() {
    outOfRange<double>("1e999");
    outOfRange<double>("-1e999");
    outOfRange<float>("3.5e39");
#ifdef APS5_FLOAT_CHARS_STRTOD
    outOfRange<double>("1e-999");
    outOfRange<float>("1e-60");
    require(parses<double>("4.9e-324", 8) > 0.0, "a subnormal is a value");
#endif
}

}  // namespace

int main() {
    try {
        readsDecimals();
        readsSpecialValues();
        readsHexPrefixAsZero();
        refusesWhatStdFromCharsRefuses();
        reportsOutOfRange();
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
    std::cout << "float_chars: all passed\n";
    return 0;
}
