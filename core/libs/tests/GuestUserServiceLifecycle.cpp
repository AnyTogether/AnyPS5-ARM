#include "SceTypes.hpp"
#include "prx/libSceUserService/UserService.hpp"
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI sceUserServiceInitialize(const void* params);
int APS5_VABI sceUserServiceTerminate(void);
int APS5_VABI sceUserServiceGetLoginUserIdList(UserServiceLoginUserIdList* user_id_list);
int APS5_VABI sceUserServiceGetEvent(SceUserServiceEvent* event);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

void RequireNotInitialized() {
    UserServiceLoginUserIdList list{};
    Require(sceUserServiceGetLoginUserIdList(&list) == USER_SERVICE_ERROR_NOT_INITIALIZED);
    SceUserServiceEvent event{};
    std::memset(&event, 0xAA, sizeof(event));
    Require(sceUserServiceGetEvent(&event) == USER_SERVICE_ERROR_NOT_INITIALIZED);
    Require(event.user_id == static_cast<int>(0xAAAAAAAAu));
    Require(sceUserServiceGetEvent(nullptr) == USER_SERVICE_ERROR_NOT_INITIALIZED);
}

void RequireLoginOnce() {
    SceUserServiceEvent event{};
    Require(sceUserServiceGetEvent(&event) == USER_SERVICE_OK);
    Require(event.event_type == 0 && event.user_id == USER_SERVICE_INITIAL_USER_ID);
    Require(sceUserServiceGetEvent(&event) == USER_SERVICE_ERROR_NO_EVENT);
}

}

int main() {
    RequireNotInitialized();
    Require(sceUserServiceTerminate() == USER_SERVICE_ERROR_NOT_INITIALIZED);

    Require(sceUserServiceInitialize(nullptr) == USER_SERVICE_OK);
    Require(sceUserServiceInitialize(nullptr) == USER_SERVICE_ERROR_ALREADY_INITIALIZED);
    UserServiceLoginUserIdList list{};
    Require(sceUserServiceGetLoginUserIdList(&list) == USER_SERVICE_OK);
    Require(list.user_id[0] == USER_SERVICE_INITIAL_USER_ID);
    RequireLoginOnce();

    Require(sceUserServiceTerminate() == USER_SERVICE_OK);
    Require(sceUserServiceTerminate() == USER_SERVICE_ERROR_NOT_INITIALIZED);
    RequireNotInitialized();

    Require(sceUserServiceInitialize(nullptr) == USER_SERVICE_OK);
    RequireLoginOnce();
    Require(sceUserServiceTerminate() == USER_SERVICE_OK);
}
