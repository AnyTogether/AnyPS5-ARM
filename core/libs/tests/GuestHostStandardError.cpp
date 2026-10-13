#include "prx/libc/include/FileStream.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <sys/wait.h>
#include <unistd.h>

extern "C" {
FileStream* APS5_VABI freopen_nid_postfix(const char*, const char*, FileStream*);
int APS5_VABI setvbuf_nid_postfix(FileStream*, char*, int, std::size_t);
std::size_t APS5_VABI fwrite_nid_postfix(const void*, std::size_t, std::size_t, FileStream*);
int APS5_VABI fflush_nid_postfix(FileStream*);
int APS5_VABI pipe_nid_postfix(int*);
int APS5_VABI dup2_nid_postfix(int, int);
std::int64_t APS5_VABI write_nid_postfix(int, const void*, std::size_t);
extern FileStream* __stderrp_nid_postfix;
}

static void Require(bool value) { if (!value) std::abort(); }

// The host C++ runtime's report of the uncaught host exception the child throws.
#ifdef __APPLE__
static constexpr const char* HostTerminateReport = "libc++abi: terminating due to uncaught exception of type std::runtime_error: report kept\n";
#else
static constexpr const char* HostTerminateReport = "  what():  report kept\n";
#endif

enum class Redirect { Duplicate, Reopen };

struct Outcome {
    std::string host;
    int status = 0;
};

static void RedirectGuest(Redirect redirect, const std::filesystem::path& probe) {
    if (redirect == Redirect::Duplicate) {
        int guest[2] = {-1, -1};
        Require(pipe_nid_postfix(guest) == 0);
        Require(dup2_nid_postfix(guest[1], 2) == 2);
        Require(write_nid_postfix(2, "guest", 5) == 5);
        return;
    }
    Require(freopen_nid_postfix(probe.c_str(), "w", __stderrp_nid_postfix) == __stderrp_nid_postfix);
    Require(setvbuf_nid_postfix(__stderrp_nid_postfix, nullptr, 0, 0) == 0);
    Require(fwrite_nid_postfix("guest", 1, 5, __stderrp_nid_postfix) == 5);
}

static Outcome Run(Redirect redirect, const std::filesystem::path& probe, bool terminate) {
    int host[2] = {-1, -1};
    Require(::pipe(host) == 0);
    const pid_t child = ::fork();
    Require(child >= 0);
    if (child == 0) {
        ::close(host[0]);
        if (::dup2(host[1], 2) != 2) ::_exit(70);
        ::close(host[1]);
        RedirectGuest(redirect, probe);
        std::fputs("host\n", stderr);
        if (terminate) throw std::runtime_error("report kept");
        if (redirect == Redirect::Reopen && fflush_nid_postfix(__stderrp_nid_postfix) != 0) ::_exit(71);
        ::_exit(0);
    }
    ::close(host[1]);
    Outcome outcome;
    char buffer[4096];
    for (ssize_t count; (count = ::read(host[0], buffer, sizeof(buffer))) > 0;) outcome.host.append(buffer, static_cast<std::size_t>(count));
    ::close(host[0]);
    Require(::waitpid(child, &outcome.status, 0) == child);
    return outcome;
}

static std::string Contents(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

int main() {
    const std::filesystem::path probe = "host_stderr_probe_" + std::to_string(::getpid()) + ".txt";
    for (const auto redirect : {Redirect::Duplicate, Redirect::Reopen}) {
        const auto written = Run(redirect, probe, false);
        Require(WIFEXITED(written.status) && WEXITSTATUS(written.status) == 0);
        Require(written.host == "host\n");
        if (redirect == Redirect::Reopen) Require(Contents(probe) == "guest");

        const auto terminated = Run(redirect, probe, true);
        Require(WIFSIGNALED(terminated.status) && WTERMSIG(terminated.status) == SIGABRT);
        Require(terminated.host.rfind("host\n", 0) == 0);
        Require(terminated.host.find(HostTerminateReport) != std::string::npos);
        if (redirect == Redirect::Reopen) Require(Contents(probe).find("report kept") == std::string::npos);
    }
    std::filesystem::remove(probe);
    return 0;
}
