#include "SceTypes.hpp"
#include "prx/libScePad/include/PadState.hpp"
#include "prx/libSceUserService/UserService.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI sceUserServiceInitialize(const UserServiceInitParam* params);
int APS5_VABI sceUserServiceTerminate(void);
int APS5_VABI sceUserServiceGetLoginUserIdList(UserServiceLoginUserIdList* user_id_list);
int APS5_VABI sceUserServiceGetEvent(SceUserServiceEvent* event);
int APS5_VABI sceUserServiceGetUserName(int user_id, char* name, size_t size);
int APS5_VABI sceUserServiceGetUserNumber(int user_id, int32_t* number);
int APS5_VABI sceUserServiceGetUserColor(int user_id, int* color);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

constexpr int first = USER_SERVICE_INITIAL_USER_ID;
constexpr int second = USER_SERVICE_INITIAL_USER_ID + 1;

int NextLogin() {
    SceUserServiceEvent event{};
    const int result = sceUserServiceGetEvent(&event);
    if (result == USER_SERVICE_ERROR_NO_EVENT) return USER_SERVICE_USER_ID_INVALID;
    Require(result == USER_SERVICE_OK && event.event_type == 0);
    return event.user_id;
}

}

// A second user logs in when the second player's pad first connects, and stays logged in.
int main() {
    Require(sceUserServiceInitialize(nullptr) == USER_SERVICE_OK);
    Require(NextLogin() == first);
    Require(NextLogin() == USER_SERVICE_USER_ID_INVALID);
    UserServiceLoginUserIdList list{};
    Require(sceUserServiceGetLoginUserIdList(&list) == USER_SERVICE_OK);
    Require(list.user_id[0] == first && list.user_id[1] == USER_SERVICE_USER_ID_INVALID);
    char name[USER_SERVICE_MAX_USER_NAME_LENGTH + 1]{};
    Require(sceUserServiceGetUserName(second, name, sizeof(name)) == USER_SERVICE_ERROR_UNKNOWN_USER);

    PadPublishPlayerInput_nid_postfix(1, PadInputState{});
    Require(NextLogin() == second);
    Require(NextLogin() == USER_SERVICE_USER_ID_INVALID);
    Require(sceUserServiceGetLoginUserIdList(&list) == USER_SERVICE_OK);
    Require(list.user_id[0] == first && list.user_id[1] == second && list.user_id[2] == USER_SERVICE_USER_ID_INVALID);
    Require(sceUserServiceGetUserName(second, name, sizeof(name)) == USER_SERVICE_OK);
    Require(std::strcmp(name, "Player 2") == 0);
    std::int32_t number = 0;
    Require(sceUserServiceGetUserNumber(second, &number) == USER_SERVICE_OK && number == 2);
    int color = -1;
    Require(sceUserServiceGetUserColor(second, &color) == USER_SERVICE_OK && color == 1);

    PadDisconnectPlayer_nid_postfix(1);
    Require(sceUserServiceGetLoginUserIdList(&list) == USER_SERVICE_OK && list.user_id[1] == second);

    Require(sceUserServiceTerminate() == USER_SERVICE_OK);
    Require(sceUserServiceInitialize(nullptr) == USER_SERVICE_OK);
    Require(NextLogin() == first);
    Require(NextLogin() == second);
    Require(NextLogin() == USER_SERVICE_USER_ID_INVALID);
    Require(sceUserServiceTerminate() == USER_SERVICE_OK);
}
