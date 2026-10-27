#include "prx/libSceNetCtl/include/Online.hpp"
#include "prx/libSceNpGameIntent/include/Api.hpp"
#include <atomic>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <stdexcept>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int NpGameIntentErrorNotInitialized = -2141898750;
constexpr int NpGameIntentErrorInvalidArgument = -2141898748;
constexpr int NpGameIntentErrorIntentNotFound = -2141898746;
constexpr int NpGameIntentErrorValueNotFound = -2141898745;
constexpr int NpGameIntentUserIdInvalid = -1;
constexpr int NpAppLauncherErrorNotInitialized = -2141898238;
constexpr int NpAppLauncherErrorInvalidArgument = -2141898236;

std::atomic_bool& NpGameIntentInitialized() {
    static std::atomic_bool initialized{false};
    return initialized;
}

std::atomic_bool& AppLauncherInitialized() {
    static std::atomic_bool initialized{false};
    return initialized;
}

}

extern "C" {

int APS5_VABI sceNpGameIntentGetPropertyValueString(const NpGameIntentData* intentData, const char* key, char* valueBuf, size_t bufSize) {
    Online::Call call("libSceNpGameIntent", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("intentData", intentData).Str("key", key).Ptr("valueBuf", valueBuf).Uint("bufSize", static_cast<std::uint64_t>(bufSize)); });
	if (!NpGameIntentInitialized()) {
		return call.Return(NpGameIntentErrorNotInitialized);
	}
	if (intentData == nullptr || key == nullptr || key[0] == '\0' || valueBuf == nullptr || bufSize == 0) {
		return call.Return(NpGameIntentErrorInvalidArgument);
	}

 valueBuf[0] = '\0';
 return call.Return(NpGameIntentErrorValueNotFound);
}

int APS5_VABI sceNpGameIntentInitialize(const void* initParam) {
    Online::Call call("libSceNpGameIntent", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("initParam", initParam); });
	(void)initParam;
	NpGameIntentInitialized() = true;
	return call.Return(0);
}

int APS5_VABI sceNpGameIntentReceiveIntent(NpGameIntentInfo* intentInfo) {
    Online::Call call("libSceNpGameIntent", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("intentInfo", intentInfo); });
	if (!NpGameIntentInitialized()) {
		return call.Return(NpGameIntentErrorNotInitialized);
	}
	if (intentInfo == nullptr || intentInfo->size != 0x4140) {
		return call.Return(NpGameIntentErrorInvalidArgument);
	}

	intentInfo->user_id = NpGameIntentUserIdInvalid;
	std::memset(intentInfo->intent_type, 0, sizeof(intentInfo->intent_type));
	std::memset(&intentInfo->intent_data, 0, sizeof(intentInfo->intent_data));

 return call.Return(NpGameIntentErrorIntentNotFound);
}

int APS5_VABI sceNpGameIntentTerminate(void) {
    Online::Call call("libSceNpGameIntent", __func__);
	NpGameIntentInitialized() = false;
	return call.Return(0);
}

int APS5_VABI sceNpGameIntentInitParamInit(NpGameIntentInitParam* param) {
    Online::Call call("libSceNpGameIntent", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("param", param); });
    if (param == nullptr) {
        APS5_INVALID_ARG_EX;
    }
    std::memset(param, 0, sizeof(NpGameIntentInitParam));
    param->size = sizeof(NpGameIntentInitParam);
    return call.Return(0);
}

int APS5_VABI sceNpGameIntentInfoInit(NpGameIntentInfo* info) {
    Online::Call call("libSceNpGameIntent", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("info", info); });
    if (info == nullptr) {
        APS5_INVALID_ARG_EX;
    }
    std::memset(info, 0, sizeof(NpGameIntentInfo));
    info->size = sizeof(NpGameIntentInfo);
    info->user_id = NpGameIntentUserIdInvalid;
    return call.Return(0);
}

int APS5_VABI sceNpGameIntentVshInitialize(void) {
    Online::Call call("libSceNpGameIntent", __func__);
    return call.Return(0);
}

int APS5_VABI sceNpGameIntentVshTerminate(void) {
    Online::Call call("libSceNpGameIntent", __func__);
    return call.Return(0);
}

int APS5_VABI sceNpAppLauncherInitialize(const void* initParam) {
    Online::Call call("libSceNpGameIntent", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("initParam", initParam); });
    (void)initParam;
    AppLauncherInitialized() = true;
    return call.Return(0);
}

int APS5_VABI sceNpAppLauncherLaunchApp(std::int32_t arg0, const char* arg2, const char* arg3) {
    (void)arg0;
    if (!AppLauncherInitialized()) return NpAppLauncherErrorNotInitialized;
    if (arg2 == nullptr || *arg2 == '\0' || (arg3 != nullptr && std::memchr(arg3, '\0', 0x2001) == nullptr)) return NpAppLauncherErrorInvalidArgument;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpAppLauncherTerminate() {
    Online::Call call("libSceNpGameIntent", __func__);
    AppLauncherInitialized() = false;
    return call.Return(0);
}

int APS5_VABI sceNpGameIntentGetUdsNpComId() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpGameIntentLaunchApp() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpGameIntentLaunchApp2() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpGameIntentNotifyAppLaunched() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpSessionServiceGetJoinedPartySession() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpSessionServiceGetRunningGamePlayerSession() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpSessionServiceSendPlayerSessionInvitations() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
