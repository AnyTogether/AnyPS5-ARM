#include "SceTypes.hpp"
#include "prx/libSceSystemService/SystemService.hpp"
#include <cstdlib>
#include <stdexcept>
#include <string>

extern "C" int APS5_VABI sceSystemServiceParamGetInt(int paramId, int* value);

namespace {

void Require(bool value) { if (!value) std::abort(); }

void SetLanguage(const char* value) {
#ifdef _WIN32
    Require(_putenv_s("ANYPS5_LANGUAGE", value != nullptr ? value : "") == 0);
#else
    Require((value != nullptr ? ::setenv("ANYPS5_LANGUAGE", value, 1) : ::unsetenv("ANYPS5_LANGUAGE")) == 0);
#endif
}

int Language() {
    int value = -1;
    Require(sceSystemServiceParamGetInt(SYSTEM_SERVICE_PARAM_ID_LANG, &value) == SYSTEM_SERVICE_OK);
    int sameValue = -1;
    Require(sceSystemServiceParamGetInt(SYSTEM_SERVICE_PARAM_ID_400, &sameValue) == SYSTEM_SERVICE_OK);
    Require(sameValue == value);
    return value;
}

bool ParameterRejected(int paramId) {
    int language = -1;
    try {
        static_cast<void>(sceSystemServiceParamGetInt(paramId, &language));
    } catch (const std::runtime_error& error) {
        return language == -1 && std::string(error.what()).find("ANYPS5_LANGUAGE") != std::string::npos;
    }
    return false;
}

bool Rejected(const char* value) {
    SetLanguage(value);
    return ParameterRejected(SYSTEM_SERVICE_PARAM_ID_LANG) && ParameterRejected(SYSTEM_SERVICE_PARAM_ID_400);
}

}

int main() {
    SetLanguage(nullptr);
    Require(Language() == SYSTEM_SERVICE_PARAM_LANG_ENGLISH_US);
    SetLanguage("");
    Require(Language() == SYSTEM_SERVICE_PARAM_LANG_ENGLISH_US);
    SetLanguage("21");
    Require(Language() == SYSTEM_SERVICE_PARAM_LANG_ARABIC);
    SetLanguage("0");
    Require(Language() == SYSTEM_SERVICE_PARAM_LANG_JAPANESE);
    SetLanguage("30");
    Require(Language() == SYSTEM_SERVICE_PARAM_LANG_UKRAINIAN);
    for (const char* value : {"31", "-1", "+21", " 21", "21 ", "21a", "0x15", "arabic", "4294967317"}) {
        Require(Rejected(value));
    }

    SetLanguage("arabic");
    Require(sceSystemServiceParamGetInt(SYSTEM_SERVICE_PARAM_ID_LANG, nullptr) == SYSTEM_SERVICE_ERROR_PARAMETER);
    Require(sceSystemServiceParamGetInt(SYSTEM_SERVICE_PARAM_ID_400, nullptr) == SYSTEM_SERVICE_ERROR_PARAMETER);
    int enterButton = -1;
    Require(sceSystemServiceParamGetInt(SYSTEM_SERVICE_PARAM_ID_ENTER_BUTTON_ASSIGN, &enterButton) == SYSTEM_SERVICE_OK);
    Require(enterButton == SYSTEM_SERVICE_PARAM_ENTER_BUTTON_CROSS);
}
