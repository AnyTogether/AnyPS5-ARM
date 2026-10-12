#include "prx/libc/include/general/LogMacros.hpp"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#else
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace {

void Require(bool value, const char* what) {
    if (value) return;
    std::fprintf(stderr, "log macros test failed: %s\n", what);
    std::exit(1);
}

template<typename TAction>
std::vector<std::string> CaptureWrites(TAction action) {
    std::vector<std::string> messages;
#ifdef _WIN32
    const std::string name = R"(\\.\pipe\anyps5-log-macros-)" + std::to_string(GetCurrentProcessId());
    HANDLE server = CreateNamedPipeA(name.c_str(), PIPE_ACCESS_INBOUND, PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 0, 1 << 20, 0, nullptr);
    Require(server != INVALID_HANDLE_VALUE, "message pipe");
    HANDLE client = CreateFileA(name.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
    Require(client != INVALID_HANDLE_VALUE, "message pipe client");
    std::FILE* stream = _fdopen(_open_osfhandle(reinterpret_cast<intptr_t>(client), _O_WRONLY | _O_BINARY), "wb");
    std::thread reader([&] {
        std::string buffer(1 << 20, '\0');
        DWORD read = 0;
        while (ReadFile(server, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) messages.emplace_back(buffer.data(), read);
    });
#else
    int sockets[2];
    Require(socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sockets) == 0, "message socket pair");
    std::FILE* stream = fdopen(sockets[0], "w");
    std::thread reader([&] {
        std::string buffer(1 << 20, '\0');
        ssize_t read = 0;
        while ((read = recv(sockets[1], buffer.data(), buffer.size(), 0)) > 0) messages.emplace_back(buffer.data(), static_cast<std::size_t>(read));
    });
#endif
    Require(stream != nullptr, "message stream");
    Require(std::setvbuf(stream, nullptr, _IONBF, 0) == 0, "unbuffered message stream");
    action(stream);
    std::fclose(stream);
    reader.join();
#ifdef _WIN32
    CloseHandle(server);
#else
    close(sockets[1]);
#endif
    return messages;
}

std::string Join(const std::vector<std::string>& messages) {
    std::string text;
    for (const auto& message : messages) text += message;
    return text;
}

bool HasLine(const std::string& text, const std::string& tail) {
    const std::string head = "[tests/LogMacros.cpp:";
    return text.size() > head.size() + tail.size() && text.compare(0, head.size(), head) == 0 && text.compare(text.size() - tail.size(), tail.size(), tail) == 0 && text.find('\n') == text.size() - 1;
}

}

int main() {
    const auto shortLine = CaptureWrites([](std::FILE* stream) { Require(_APS5_LOG_IMPL(stream, "value %d of %s", 7, "seven") == 0, "a short line was not flushed"); });
    Require(HasLine(Join(shortLine), "] value 7 of seven\n"), "a short line differs");
    Require(shortLine.size() <= 2, "a short line took more than two writes");

    const std::string text(20000, 'r');
    const auto longLine = CaptureWrites([&](std::FILE* stream) { Require(_APS5_LOG_IMPL(stream, "%s", text.c_str()) == 0, "a long line was not flushed"); });
    Require(HasLine(Join(longLine), "] " + text + "\n"), "a long line differs");
    Require(longLine.size() <= 2, "a 20000-character line took more than two writes");

    const auto plainLine = CaptureWrites([](std::FILE* stream) { Require(_APS5_LOG_IMPL_NF(stream, "plain") == 0, "a line without arguments was not flushed"); });
    Require(HasLine(Join(plainLine), "] plain\n"), "a line without arguments differs");
    Require(plainLine.size() <= 2, "a line without arguments took more than two writes");
    return 0;
}
