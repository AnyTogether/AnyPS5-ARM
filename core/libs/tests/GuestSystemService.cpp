#include "SceTypes.hpp"
#include "prx/libSceSystemService/SystemService.hpp"
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <stdexcept>

extern "C" int APS5_VABI sceSystemServiceGetHdrToneMapLuminance(SystemServiceHdrToneMapLuminance* luminance);
extern "C" int APS5_VABI sceSystemServiceParamGetString(int paramId, char* buf, std::size_t bufSize);
extern "C" int APS5_VABI sceSystemServiceLaunchApp(const char* titleId, const char* const* arguments, const void* param);

namespace {

constexpr int browserUnavailable = static_cast<int>(0x8002002Du);

void Require(bool value) { if (!value) std::abort(); }

bool LaunchAppThrows(const char* titleId, const char* const* arguments, const void* param) {
    try {
        static_cast<void>(sceSystemServiceLaunchApp(titleId, arguments, param));
    } catch (const std::runtime_error&) {
        return true;
    }
    return false;
}

}

extern "C" int APS5_VABI sceSystemServicePowerTick(void);
extern "C" int APS5_VABI sceSystemServiceReportAbnormalTermination(const void* info);
extern "C" int APS5_VABI sceSystemServiceDisableMusicPlayer(void);
extern "C" int APS5_VABI sceSystemServiceReenableMusicPlayer(void);
extern "C" int APS5_VABI sceSystemServiceDisableMediaPlay(void);
extern "C" int APS5_VABI sceSystemServiceReenableMediaPlay(void);
extern "C" int APS5_VABI sceSystemServiceLaunchWebBrowser(const char* uri, void* param);
extern "C" int APS5_VABI sceSystemServiceOpenChallengeActivity(void);
extern "C" int APS5_VABI sceSystemServiceOpenTournamentOccurrence(void);
extern "C" int APS5_VABI sceSystemServiceShowControllerSettings(void);

int main() {
    Require(sceSystemServicePowerTick() == SYSTEM_SERVICE_OK);
    Require(sceSystemServicePowerTick() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceReportAbnormalTermination(nullptr) == SYSTEM_SERVICE_OK);
    int info = 0;
    Require(sceSystemServiceReportAbnormalTermination(&info) == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceDisableMusicPlayer() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceDisableMusicPlayer() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceReenableMusicPlayer() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceReenableMusicPlayer() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceDisableMediaPlay() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceDisableMediaPlay() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceReenableMediaPlay() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceReenableMediaPlay() == SYSTEM_SERVICE_OK);
    Require(sceSystemServiceLaunchWebBrowser("http://127.0.0.1:8780/video?v=0", nullptr) == browserUnavailable);
    unsigned char browserParam[64];
    std::memset(browserParam, 0x5a, sizeof(browserParam));
    Require(sceSystemServiceLaunchWebBrowser("https://example.com/", browserParam) == browserUnavailable);
    for (unsigned char byte : browserParam) Require(byte == 0x5a);
    Require(sceSystemServiceLaunchWebBrowser("", nullptr) == browserUnavailable);
    Require(sceSystemServiceLaunchWebBrowser(nullptr, nullptr) == browserUnavailable);
    Require(sceSystemServiceOpenChallengeActivity() == browserUnavailable);
    Require(sceSystemServiceOpenTournamentOccurrence() == browserUnavailable);
    Require(sceSystemServiceShowControllerSettings() == browserUnavailable);
    Require(LaunchAppThrows("PPSA99109", nullptr, nullptr));
    Require(LaunchAppThrows(nullptr, nullptr, nullptr));
    const char* launchArguments[] = {"--backup", nullptr};
    unsigned char launchParam[0x20];
    std::memset(launchParam, 0x5a, sizeof(launchParam));
    Require(LaunchAppThrows("PPSA99110", launchArguments, launchParam));
    for (unsigned char byte : launchParam) Require(byte == 0x5a);
    Require(std::strcmp(launchArguments[0], "--backup") == 0 && launchArguments[1] == nullptr);
    Require(sceSystemServiceGetHdrToneMapLuminance(nullptr) == SYSTEM_SERVICE_ERROR_PARAMETER);
    SystemServiceHdrToneMapLuminance luminance{-1.0f, -1.0f, -1.0f};
    Require(sceSystemServiceGetHdrToneMapLuminance(&luminance) == SYSTEM_SERVICE_OK);
    Require(luminance.max_full_frame_tone_map_luminance == 100.0f);
    Require(luminance.max_tone_map_luminance == 100.0f);
    Require(luminance.min_tone_map_luminance == 0.0f);

    char name[SYSTEM_SERVICE_MAX_SYSTEM_NAME_LENGTH];
    std::memset(name, 'x', sizeof(name));
    Require(sceSystemServiceParamGetString(SYSTEM_SERVICE_PARAM_ID_SYSTEM_NAME, nullptr, sizeof(name)) == SYSTEM_SERVICE_ERROR_PARAMETER);
    Require(sceSystemServiceParamGetString(SYSTEM_SERVICE_PARAM_ID_SYSTEM_NAME, name, 0) == SYSTEM_SERVICE_ERROR_PARAMETER);
    Require(sceSystemServiceParamGetString(SYSTEM_SERVICE_PARAM_ID_LANG, nullptr, sizeof(name)) == SYSTEM_SERVICE_ERROR_PARAMETER);
    for (int paramId : {SYSTEM_SERVICE_PARAM_ID_LANG, SYSTEM_SERVICE_PARAM_ID_DATE_FORMAT, SYSTEM_SERVICE_PARAM_ID_TIME_FORMAT,
                        SYSTEM_SERVICE_PARAM_ID_TIME_ZONE, SYSTEM_SERVICE_PARAM_ID_SUMMERTIME, SYSTEM_SERVICE_PARAM_ID_GAME_PARENTAL_LEVEL,
                        SYSTEM_SERVICE_PARAM_ID_ENTER_BUTTON_ASSIGN, 0, 8, -1}) {
        Require(sceSystemServiceParamGetString(paramId, name, sizeof(name)) == SYSTEM_SERVICE_ERROR_PARAMETER);
        Require(sceSystemServiceParamGetString(paramId, name, 4) == SYSTEM_SERVICE_ERROR_PARAMETER);
    }
    for (std::size_t bufSize = 1; bufSize < 4; ++bufSize) {
        Require(sceSystemServiceParamGetString(SYSTEM_SERVICE_PARAM_ID_SYSTEM_NAME, name, bufSize) == SYSTEM_SERVICE_ERROR_PARAMETER);
    }
    for (char byte : name) Require(byte == 'x');
    for (std::size_t bufSize : {std::size_t{4}, std::size_t{64}, sizeof(name)}) {
        std::memset(name, 'x', sizeof(name));
        Require(sceSystemServiceParamGetString(SYSTEM_SERVICE_PARAM_ID_SYSTEM_NAME, name, bufSize) == SYSTEM_SERVICE_OK);
        Require(std::strcmp(name, "PS5") == 0);
        for (std::size_t index = 4; index < sizeof(name); ++index) Require(name[index] == 'x');
    }
}
