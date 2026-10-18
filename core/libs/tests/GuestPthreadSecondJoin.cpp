#include "SceTypes.hpp"
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <thread>

extern "C" {
int APS5_VABI scePthreadCreate(Pthread* thread, const PthreadAttr* attr, PthreadEntry entry, void* arg, const char* name);
int APS5_VABI scePthreadJoin(Pthread thread, void** retval);
int APS5_VABI scePthreadDetach(Pthread thread);
int APS5_VABI pthread_join_nid_postfix(Pthread thread, void** retval);
}

static constexpr int SCE_OK = 0;
static constexpr int SCE_KERNEL_ERROR_ESRCH = static_cast<int>(0x80020003u);
static constexpr int SCE_KERNEL_ERROR_EINVAL = static_cast<int>(0x80020016u);
static constexpr int GUEST_ESRCH = 3;
static constexpr std::size_t REUSED_SLOT_ROUNDS = 64;

static void Require(bool value) { if (!value) std::abort(); }

static void* APS5_VABI Finish(void*) {
    return reinterpret_cast<void*>(std::uintptr_t{0x1234});
}

static void* APS5_VABI WaitForRelease(void* arg) {
    auto* release = static_cast<std::atomic<bool>*>(arg);
    while (!release->load()) std::this_thread::yield();
    return nullptr;
}

int main() {
    Pthread thread = nullptr;
    void* result = nullptr;
    Require(scePthreadCreate(&thread, nullptr, Finish, nullptr, "second-join") == SCE_OK);
    Require(scePthreadJoin(thread, &result) == SCE_OK);
    Require(result == reinterpret_cast<void*>(std::uintptr_t{0x1234}));

    result = reinterpret_cast<void*>(std::uintptr_t{0x55});
    Require(scePthreadJoin(thread, &result) == SCE_KERNEL_ERROR_ESRCH);
    Require(result == reinterpret_cast<void*>(std::uintptr_t{0x55}));
    Require(scePthreadDetach(thread) == SCE_KERNEL_ERROR_EINVAL);
    Require(pthread_join_nid_postfix(thread, &result) == GUEST_ESRCH);
    Require(result == reinterpret_cast<void*>(std::uintptr_t{0x55}));

    for (std::size_t round = 0; round < REUSED_SLOT_ROUNDS; ++round) {
        thread = nullptr;
        result = nullptr;
        Require(scePthreadCreate(&thread, nullptr, Finish, nullptr, "reused-slot") == SCE_OK);
        Require(scePthreadJoin(thread, &result) == SCE_OK);
        Require(result == reinterpret_cast<void*>(std::uintptr_t{0x1234}));
        Require(scePthreadJoin(thread, nullptr) == SCE_KERNEL_ERROR_ESRCH);
    }

    static std::atomic<bool> release{false};
    Pthread detached = nullptr;
    Require(scePthreadCreate(&detached, nullptr, WaitForRelease, &release, "detached") == SCE_OK);
    Require(scePthreadDetach(detached) == SCE_OK);
    result = reinterpret_cast<void*>(std::uintptr_t{0x55});
    Require(scePthreadJoin(detached, &result) == SCE_KERNEL_ERROR_EINVAL);
    Require(result == reinterpret_cast<void*>(std::uintptr_t{0x55}));
    Require(scePthreadDetach(detached) == SCE_KERNEL_ERROR_EINVAL);
    release = true;
}
