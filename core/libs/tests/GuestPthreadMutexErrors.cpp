#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <initializer_list>

extern "C" {
int APS5_VABI scePthreadMutexattrInit(PthreadMutexattr* attr);
int APS5_VABI scePthreadMutexattrDestroy(PthreadMutexattr* attr);
int APS5_VABI scePthreadMutexattrSettype(PthreadMutexattr* attr, int type);
int APS5_VABI scePthreadMutexattrSetprotocol(PthreadMutexattr* attr, int protocol);
int APS5_VABI scePthreadMutexInit(PthreadMutex* mutex, const PthreadMutexattr* attr, const char* name);
int APS5_VABI scePthreadMutexDestroy(PthreadMutex* mutex);
int APS5_VABI scePthreadMutexLock(PthreadMutex* mutex);
int APS5_VABI scePthreadMutexUnlock(PthreadMutex* mutex);
}

static constexpr int SCE_OK = 0;
static constexpr int SCE_KERNEL_ERROR_EINVAL = static_cast<int>(0x80020016u);
static constexpr int SCE_KERNEL_ERROR_EBUSY = static_cast<int>(0x80020010u);

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    PthreadMutexattr attr = nullptr;
    Require(scePthreadMutexattrInit(&attr) == SCE_OK);
    for (int type : {-1, 0, 5}) Require(scePthreadMutexattrSettype(&attr, type) == SCE_KERNEL_ERROR_EINVAL);
    for (int type : {1, 2, 3, 4}) Require(scePthreadMutexattrSettype(&attr, type) == SCE_OK);
    for (int protocol : {-1, 3}) Require(scePthreadMutexattrSetprotocol(&attr, protocol) == SCE_KERNEL_ERROR_EINVAL);
    for (int protocol : {0, 1, 2}) Require(scePthreadMutexattrSetprotocol(&attr, protocol) == SCE_OK);

    PthreadMutexattr unset = nullptr;
    Require(scePthreadMutexattrSettype(&unset, 1) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadMutexattrSetprotocol(&unset, 0) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadMutexattrDestroy(&unset) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadMutexattrSettype(nullptr, 1) == SCE_KERNEL_ERROR_EINVAL);
    Require(scePthreadMutexattrDestroy(nullptr) == SCE_KERNEL_ERROR_EINVAL);

    PthreadMutex mutex = nullptr;
    Require(scePthreadMutexInit(&mutex, &unset, "unset") == SCE_OK);
    Require(scePthreadMutexLock(&mutex) == SCE_OK);
    Require(scePthreadMutexDestroy(&mutex) == SCE_KERNEL_ERROR_EBUSY);
    Require(scePthreadMutexUnlock(&mutex) == SCE_OK);
    Require(scePthreadMutexDestroy(&mutex) == SCE_OK);
    Require(mutex == reinterpret_cast<PthreadMutex>(std::uintptr_t{2}));
    Require(scePthreadMutexDestroy(&mutex) == SCE_KERNEL_ERROR_EINVAL);

    Require(scePthreadMutexInit(&mutex, &attr, "attr") == SCE_OK);
    Require(scePthreadMutexDestroy(&mutex) == SCE_OK);
    Require(scePthreadMutexattrDestroy(&attr) == SCE_OK);
}
