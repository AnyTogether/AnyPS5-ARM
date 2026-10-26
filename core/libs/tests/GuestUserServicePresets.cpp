#include "SceTypes.hpp"
#include "prx/libSceUserService/UserService.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
#include <string_view>

extern "C" {
int APS5_VABI sceUserServiceGetGamePresets(int user_id, UserServiceGamePresets* presets);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

void SetPresets(const char* value) {
#ifdef _WIN32
    Require(_putenv_s("ANYPS5_GAME_PRESETS", value) == 0);
#else
    Require(::setenv("ANYPS5_GAME_PRESETS", value, 1) == 0);
#endif
}

UserServiceGamePresets Untouched() {
    UserServiceGamePresets presets;
    std::memset(&presets, 0x5a, sizeof(presets));
    presets.this_size = sizeof(presets);
    return presets;
}

}

// The launcher's Settings → Game Presets reach the console call through ANYPS5_GAME_PRESETS.
int main(int argc, char** argv) {
    const std::string_view mode = argc == 2 ? argv[1] : "";
    if (mode == "invalid") {
        SetPresets("difficulty=impossible");
        auto presets = Untouched();
        bool rejected = false;
        try {
            sceUserServiceGetGamePresets(USER_SERVICE_INITIAL_USER_ID, &presets);
        } catch (const std::runtime_error& error) {
            rejected = std::string_view(error.what()).find("ANYPS5_GAME_PRESETS") != std::string_view::npos;
        }
        Require(rejected);
        std::puts("Game presets rejected an unknown value");
        return 0;
    }
    if (mode == "unset") {
        auto presets = Untouched();
        Require(sceUserServiceGetGamePresets(USER_SERVICE_INITIAL_USER_ID, &presets) == USER_SERVICE_OK);
        Require(presets.difficulty == 0 && presets.priority == 0 && presets.display_sub_titles == 0 && presets.audio_language == 0);
        Require(presets.invert_vertical_view_for_1st_person_view == 0 && presets.invert_horizontal_view_for_3rd_person_view == 0);
        Require(presets.this_size == sizeof(presets));
        std::puts("Game presets are unset without the variable");
        return 0;
    }
    if (mode == "others") {
        SetPresets("difficulty=easiest,priority=resolution,subtitles=off,audio_language=default");
        auto presets = Untouched();
        Require(sceUserServiceGetGamePresets(USER_SERVICE_INITIAL_USER_ID, &presets) == USER_SERVICE_OK);
        Require(presets.difficulty == 1 && presets.priority == 2 && presets.display_sub_titles == 2 && presets.audio_language == 0);
        // A key left out is not set.
        Require(presets.invert_vertical_view_for_1st_person_view == 0);
        std::puts("Game presets passed the other values");
        return 0;
    }
    // Unknown keys (from a newer launcher) are passed over; spaces around the parts are allowed.
    SetPresets("difficulty=hard, priority=performance,invert_1st_v=1,invert_1st_h=0,invert_3rd_v=0,invert_3rd_h=1,subtitles=on,audio_language=19,future=1");
    auto presets = Untouched();
    Require(sceUserServiceGetGamePresets(USER_SERVICE_INITIAL_USER_ID, &presets) == USER_SERVICE_OK);
    Require(presets.this_size == sizeof(presets));
    Require(presets.difficulty == 4);
    Require(presets.priority == 1);
    Require(presets.invert_vertical_view_for_1st_person_view == 1);
    Require(presets.invert_horizontal_view_for_1st_person_view == 0);
    Require(presets.invert_vertical_view_for_3rd_person_view == 0);
    Require(presets.invert_horizontal_view_for_3rd_person_view == 1);
    Require(presets.display_sub_titles == 1);
    Require(presets.audio_language == 20);
    // Every signed-in user gets them; a user that is not there gets nothing.
    auto second = Untouched();
    Require(sceUserServiceGetGamePresets(USER_SERVICE_INITIAL_USER_ID + 1, &second) == USER_SERVICE_OK && second.difficulty == 4);
    auto nobody = Untouched();
    Require(sceUserServiceGetGamePresets(0, &nobody) == USER_SERVICE_ERROR_INVALID_ARGUMENT && nobody.difficulty == 0x5a5a5a5au);
    std::puts("Game presets passed");
    return 0;
}
