#include "prx/libc/include/general/VabiMacros.hpp"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>

extern "C" {
float APS5_VABI fminf_nid_postfix(float, float);
}

static void Check(bool condition, int line) {
    if (!condition) {
        std::fprintf(stderr, "fminf check failed at line %d\n", line);
        std::abort();
    }
}
#define Require(value) Check((value), __LINE__)

int main() {
    const auto nan = std::numeric_limits<float>::quiet_NaN();
    const auto infinity = std::numeric_limits<float>::infinity();

    Require(fminf_nid_postfix(3.0f, -2.0f) == -2.0f);
    Require(fminf_nid_postfix(-2.0f, 3.0f) == -2.0f);
    Require(fminf_nid_postfix(1.5f, 2.5f) == 1.5f);

    Require(fminf_nid_postfix(nan, 4.0f) == 4.0f);
    Require(fminf_nid_postfix(4.0f, nan) == 4.0f);
    Require(std::isnan(fminf_nid_postfix(nan, nan)));

    const auto minNegZero = fminf_nid_postfix(-0.0f, +0.0f);
    const auto minPosZero = fminf_nid_postfix(+0.0f, -0.0f);
    Require(minNegZero == 0.0f && std::signbit(minNegZero));
    Require(minPosZero == 0.0f && std::signbit(minPosZero));
    Require(std::signbit(fminf_nid_postfix(-0.0f, -0.0f)));
    Require(!std::signbit(fminf_nid_postfix(+0.0f, +0.0f)));

    Require(fminf_nid_postfix(infinity, -infinity) == -infinity);
    Require(fminf_nid_postfix(-infinity, infinity) == -infinity);
    Require(fminf_nid_postfix(infinity, 5.0f) == 5.0f);
    Require(fminf_nid_postfix(5.0f, infinity) == 5.0f);
    Require(fminf_nid_postfix(-infinity, 5.0f) == -infinity);
    Require(fminf_nid_postfix(5.0f, -infinity) == -infinity);

    return 0;
}
