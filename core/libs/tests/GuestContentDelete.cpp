#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>

extern "C" int APS5_VABI sceContentDeleteInitialize(const ContentDeleteInitParam* init_param);
extern "C" int APS5_VABI sceContentDeleteTerminate(void);
extern "C" int APS5_VABI sceContentDeleteById(std::int64_t contentId);
extern "C" int APS5_VABI sceContentDeleteByPath(const char* contentPath);

namespace {

void Require(bool value) { if (!value) std::abort(); }

template <typename TAction>
std::string LogicErrorMessage(TAction action) {
    try {
        action();
    } catch (const std::invalid_argument&) {
        return "invalid argument";
    } catch (const std::logic_error& error) {
        return error.what();
    }
    return "returned";
}

bool Contains(const std::string& text, const std::string& part) { return text.find(part) != std::string::npos; }

}

int main() {
    Require(LogicErrorMessage([] { sceContentDeleteById(1); }) == "sceContentDeleteById: not initialized");
    Require(LogicErrorMessage([] { sceContentDeleteByPath("/user/av_contents/photo/a.png"); }) == "sceContentDeleteByPath: not initialized");
    Require(LogicErrorMessage([] { sceContentDeleteByPath(nullptr); }) == "invalid argument");

    ContentDeleteInitParam param{};
    param.heap_size = 0x10000;
    Require(sceContentDeleteInitialize(&param) == 0);

    Require(LogicErrorMessage([] { sceContentDeleteByPath(nullptr); }) == "invalid argument");
    Require(Contains(LogicErrorMessage([] { sceContentDeleteByPath("/user/av_contents/photo/a.png"); }), "sceContentDeleteByPath: /user/av_contents/photo/a.png is not in the host content library"));
    Require(Contains(LogicErrorMessage([] { sceContentDeleteById(0x123456789); }), "sceContentDeleteById: content id 4886718345 is not in the host content library"));
    Require(Contains(LogicErrorMessage([] { sceContentDeleteById(-1); }), "sceContentDeleteById: content id -1 is not in the host content library"));

    Require(sceContentDeleteTerminate() == 0);
    Require(LogicErrorMessage([] { sceContentDeleteById(1); }) == "sceContentDeleteById: not initialized");
    return 0;
}
