// The title's writes to descriptor 1 and the host stdout stream both reach the game log through LogRepeatFilter.
#include "prx/libc/include/LogRepeatFilter.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <string>
#include <unistd.h>

extern "C" std::int64_t APS5_VABI write_nid_postfix(int, const char*, std::int64_t);

namespace {

void Require(bool value, const char* message) {
    if (value) return;
    std::fprintf(stderr, "log repeats: %s\n", message);
    std::exit(1);
}

std::size_t Occurrences(const std::string& text, const std::string& piece) {
    std::size_t count = 0;
    for (auto at = text.find(piece); at != std::string::npos; at = text.find(piece, at + piece.size())) ++count;
    return count;
}

}

int main() {
    char path[] = "/tmp/anyps5-log-repeats-XXXXXX";
    const int file = ::mkstemp(path);
    Require(file >= 0, "mkstemp");
    std::fflush(stdout);
    const int saved = ::dup(1);
    Require(saved >= 0 && ::dup2(file, 1) == 1, "redirect the host standard output");
    const std::string guest = "sceNetGetsockopt failed with 0x80410109\n";
    const std::string host = "error during sceNetEpollControl 0x80410109\n";
    const std::string distinct = "a line written once\n";
    for (int index = 0; index < 2000; ++index) {
        Require(write_nid_postfix(1, guest.data(), static_cast<std::int64_t>(guest.size())) == static_cast<std::int64_t>(guest.size()),
            "write() to descriptor 1 must report every byte");
#ifdef __APPLE__
        std::fputs(host.c_str(), stdout);
        std::fflush(stdout);
#endif
    }
    Require(write_nid_postfix(1, distinct.data(), static_cast<std::int64_t>(distinct.size())) == static_cast<std::int64_t>(distinct.size()), "write() a distinct line");
    std::fflush(stdout);
    Require(::dup2(saved, 1) == 1 && ::close(saved) == 0, "restore the host standard output");
    std::string log;
    char buffer[4096];
    ::lseek(file, 0, SEEK_SET);
    for (ssize_t count; (count = ::read(file, buffer, sizeof(buffer))) > 0;) log.append(buffer, static_cast<std::size_t>(count));
    ::close(file);
    ::unlink(path);
    Require(Occurrences(log, guest) == LogRepeatFilter::RepeatLimit + 1, "write() to descriptor 1 was not limited");
#ifdef __APPLE__
    Require(Occurrences(log, host) == LogRepeatFilter::RepeatLimit + 1, "the host stdout stream was not limited");
#endif
    Require(Occurrences(log, distinct) == 1, "a distinct line was dropped");
    std::printf("log repeats: %zu bytes logged for 4000 repeated lines\n", log.size());
    return 0;
}
