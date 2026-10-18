#include <cstdio>

extern "C" int shared() {
    std::fputs("Windows DLL stdout probe\n", stdout);
    std::fputs("Windows DLL stderr probe\n", stderr);
    return 11;
}
