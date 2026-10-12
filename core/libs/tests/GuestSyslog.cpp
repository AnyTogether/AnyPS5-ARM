#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

extern "C" {
void APS5_VABI syslog_nid_postfix(int, const char*, ...);
int APS5_VABI setlogmask_nid_postfix(int);
int* APS5_VABI __error_nid_postfix();
}
static void Require(bool value) { if (!value) std::abort(); }
int main() {
    auto* captured = std::tmpfile();
    Require(captured != nullptr);
    std::fflush(stderr);
#ifdef _WIN32
    const int saved = ::_dup(::_fileno(stderr));
    Require(saved >= 0 && ::_dup2(::_fileno(captured), ::_fileno(stderr)) == 0);
#else
    const int saved = ::dup(::fileno(stderr));
    Require(saved >= 0 && ::dup2(::fileno(captured), ::fileno(stderr)) == ::fileno(stderr));
#endif
    *__error_nid_postfix() = 2;
    Require(setlogmask_nid_postfix(0) == 0xff);
    syslog_nid_postfix(6, "station %s at %d kbps", "radio", 128);
    const int afterFirst = *__error_nid_postfix();
    syslog_nid_postfix(16 | 3, "open: %m, %%m kept, %d%%\n", 50);
    syslog_nid_postfix(0x10000 | 4, "masked");
    syslog_nid_postfix(7, "");
    Require(setlogmask_nid_postfix(1 << 3) == 0xff);
    Require(setlogmask_nid_postfix(0) == (1 << 3));
    int count = -1;
    syslog_nid_postfix(7, "suppressed %m%n", &count);
    Require(count == -1 && *__error_nid_postfix() == 2);
    syslog_nid_postfix(16 | 3, "allowed: %m");
    Require(*__error_nid_postfix() == 2);
    syslog_nid_postfix(0x10000 | 7, "suppressed %n", &count);
    Require(count == -1 && *__error_nid_postfix() == 2);
    Require(setlogmask_nid_postfix(1 << 4) == (1 << 3));
    syslog_nid_postfix(0x10000 | 4, "warning without diagnostic");
    syslog_nid_postfix(0x10000 | 7, "both suppressed %n", &count);
    Require(count == -1 && *__error_nid_postfix() == 2);
    Require(setlogmask_nid_postfix(0x100) == (1 << 4));
    Require(setlogmask_nid_postfix(0) == 0x100);
    syslog_nid_postfix(0x10000 | 3, "no priorities enabled %n", &count);
    Require(count == -1 && *__error_nid_postfix() == 2);
    Require(setlogmask_nid_postfix(-1) == 0x100);
    Require(setlogmask_nid_postfix(0) == -1);
    syslog_nid_postfix(7, "negative mask");
    Require(setlogmask_nid_postfix(0x55) == -1);
    for (int priority = 0; priority < 8; ++priority)
        syslog_nid_postfix(16 | priority, "level %d", priority);
    std::thread([] { Require(setlogmask_nid_postfix(0xff) == 0x55); }).join();
    Require(setlogmask_nid_postfix(0) == 0xff);
    syslog_nid_postfix(7, "mask shared across threads");
    std::fflush(stderr);
#ifdef _WIN32
    Require(::_dup2(saved, ::_fileno(stderr)) == 0 && ::_close(saved) == 0);
#else
    Require(::dup2(saved, ::fileno(stderr)) == ::fileno(stderr) && ::close(saved) == 0);
#endif
    Require(afterFirst == 2 && *__error_nid_postfix() == 2);
    std::rewind(captured);
    char text[1024]{};
    const auto length = std::fread(text, 1, sizeof(text) - 1, captured);
    const char* expected =
        "[syslog:14] station radio at 128 kbps\n"
        "[syslog:19] open: No such file or directory, %m kept, 50%\n"
        "[syslog:35] syslog: unknown facility/priority: 10004\n"
        "[syslog:12] masked\n"
        "[syslog:15] \n"
        "[syslog:19] allowed: No such file or directory\n"
        "[syslog:35] syslog: unknown facility/priority: 10007\n"
        "[syslog:12] warning without diagnostic\n"
        "[syslog:15] negative mask\n"
        "[syslog:16] level 0\n"
        "[syslog:18] level 2\n"
        "[syslog:20] level 4\n"
        "[syslog:22] level 6\n"
        "[syslog:15] mask shared across threads\n";
    Require(length == std::strlen(expected) && std::strcmp(text, expected) == 0);
    Require(std::fclose(captured) == 0);
}
