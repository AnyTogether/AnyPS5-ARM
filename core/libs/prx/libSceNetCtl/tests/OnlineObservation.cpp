#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

extern "C" {
int APS5_VABI sceNpGetState(int userId, std::uint32_t* state);
int APS5_VABI sceNpSetNpTitleId(const NpTitleId* titleId, const NpTitleSecret* titleSecret);
int APS5_VABI sceNpWebApi2SendRequest(std::int64_t requestId, const void* data, std::size_t size, NpWebApi2ResponseInformationOption* option);
int APS5_VABI sceNpMatching2JoinRoom();
}

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

std::vector<std::string> lines(const char* path) {
    std::ifstream file(path);
    std::vector<std::string> out;
    for (std::string line; std::getline(file, line);) out.push_back(line);
    return out;
}

bool any(const std::vector<std::string>& all, std::initializer_list<const char*> parts) {
    for (const auto& line : all) {
        bool found = true;
        for (const char* part : parts) found = found && line.find(part) != std::string::npos;
        if (found) return true;
    }
    return false;
}

}

int main() {
    try {
        const char* path = std::getenv("ANYPS5_ONLINE_LOG");
        require(path && *path, "the test runs with ANYPS5_ONLINE_LOG set");
        std::remove(path);
        std::uint32_t state = 0;
        for (int index = 0; index < 3; ++index) require(sceNpGetState(1, &state) == 0, "sceNpGetState answers");
        NpTitleId titleId{};
        std::strcpy(titleId.data, "PPSA00000_00");
        NpTitleSecret secret{};
        std::memset(secret.data, 0xAB, sizeof(secret.data));
        sceNpSetNpTitleId(&titleId, &secret);
        const char body[] = "{\"hello\":1}";
        sceNpWebApi2SendRequest(5, body, std::strlen(body), nullptr);
        bool threw = false;
        try {
            sceNpMatching2JoinRoom();
        } catch (const std::runtime_error&) {
            threw = true;
        }
        require(threw, "an unimplemented export still stops");
        const auto all = lines(path);
        require(any(all, {"\"start\"", "\"pid\""}), "the log starts with the process");
        require(any(all, {"\"lib\":\"libSceNpManager\"", "\"fn\":\"sceNpGetState\"", "\"in\":{\"user_id\":1,\"state\":\"set\"}", "\"out\":{\"state\":1}", "\"ret\":0"}),
            "a call is written with its arguments, outputs and result");
        int states = 0;
        for (const auto& line : all) states += line.find("sceNpGetState") != std::string::npos;
        require(states == 1, "identical calls inside the interval are folded");
        require(any(all, {"sceNpSetNpTitleId", "\"title_id\":\"PPSA00000_00\""}), "the title ID is written");
        for (const auto& line : all) require(line.find("abab") == std::string::npos && line.find("\xAB") == std::string::npos, "the title secret is never written");
        require(any(all, {"sceNpWebApi2SendRequest", "\"data\":\"{\\\"hello\\\":1}\""}), "a request body is written as text");
        require(any(all, {"\"fn\":\"sceNpMatching2JoinRoom\"", "\"not_implemented\":true"}), "an unimplemented export is written before it stops");
        std::remove(path);
    } catch (const std::exception& error) {
        std::cerr << "online observation: " << error.what() << '\n';
        return 1;
    }
    std::cout << "online observation: ok\n";
    return 0;
}
