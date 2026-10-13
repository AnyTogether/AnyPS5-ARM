#include "prx/libSceLibcInternal/include/Spawn.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI posix_spawnattr_init_nid_postfix(PosixSpawnAttributes**);
int APS5_VABI posix_spawnattr_destroy_nid_postfix(PosixSpawnAttributes**);
int APS5_VABI posix_spawnattr_setflags_nid_postfix(PosixSpawnAttributes**, std::int16_t);
int APS5_VABI posix_spawnattr_setsigdefault_nid_postfix(PosixSpawnAttributes**, const GuestSignalSet*);
int APS5_VABI posix_spawn_file_actions_init_nid_postfix(PosixSpawnFileActions**);
int APS5_VABI posix_spawn_file_actions_destroy_nid_postfix(PosixSpawnFileActions**);
int APS5_VABI posix_spawn_file_actions_addopen_nid_postfix(PosixSpawnFileActions**, int, const char*, int, std::uint16_t);
int APS5_VABI posix_spawn_file_actions_adddup2_nid_postfix(PosixSpawnFileActions**, int, int);
int APS5_VABI posix_spawn_file_actions_addclose_nid_postfix(PosixSpawnFileActions**, int);
int APS5_VABI posix_spawn_nid_postfix(std::int32_t*, const char*, PosixSpawnFileActions* const*, PosixSpawnAttributes* const*, char* const*, char* const*);
int APS5_VABI posix_spawnp_nid_postfix(std::int32_t*, const char*, PosixSpawnFileActions* const*, PosixSpawnAttributes* const*, char* const*, char* const*);
}

static void Require(bool condition, int line) {
    if (!condition) {
        std::fprintf(stderr, "Posix spawn check failed at line %d\n", line);
        std::abort();
    }
}
#define Check(value) Require((value), __LINE__)

constexpr int BadDescriptor = 9;

template<typename TCall>
static bool ThrowsInvalidArgument(TCall call) {
    try {
        call();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

template<typename TCall>
static bool ReportsNotImplemented(TCall call, const std::string& message) {
    try {
        call();
    } catch (const std::runtime_error& error) {
        return std::string(error.what()) == message;
    }
    return false;
}

static void CheckAttributes() {
    PosixSpawnAttributes* attributes = nullptr;
    Check(posix_spawnattr_init_nid_postfix(&attributes) == 0 && attributes != nullptr);
    Check(attributes->flags == 0 && attributes->processGroup == 0 && attributes->schedulingPriority == 0 && attributes->schedulingPolicy == 0);
    const GuestSignalSet empty{};
    Check(std::memcmp(&attributes->signalDefault, &empty, sizeof(empty)) == 0 && std::memcmp(&attributes->signalMask, &empty, sizeof(empty)) == 0);

    Check(posix_spawnattr_setflags_nid_postfix(&attributes, 0x30) == 0 && attributes->flags == 0x30);
    Check(posix_spawnattr_setflags_nid_postfix(&attributes, -1) == 0 && attributes->flags == -1);
    Check(posix_spawnattr_setflags_nid_postfix(&attributes, 0) == 0 && attributes->flags == 0);

    const GuestSignalSet defaults{{0x00004002u, 0x80000000u, 1u, 0xffffffffu}};
    Check(posix_spawnattr_setsigdefault_nid_postfix(&attributes, &defaults) == 0);
    Check(std::memcmp(&attributes->signalDefault, &defaults, sizeof(defaults)) == 0);
    Check(std::memcmp(&attributes->signalMask, &empty, sizeof(empty)) == 0);

    PosixSpawnAttributes* uninitialized = nullptr;
    Check(ThrowsInvalidArgument([&] { posix_spawnattr_setflags_nid_postfix(&uninitialized, 1); }));
    Check(ThrowsInvalidArgument([&] { posix_spawnattr_setsigdefault_nid_postfix(&uninitialized, &defaults); }));
    Check(ThrowsInvalidArgument([&] { posix_spawnattr_setsigdefault_nid_postfix(&attributes, nullptr); }));
    Check(ThrowsInvalidArgument([] { posix_spawnattr_init_nid_postfix(nullptr); }));

    Check(posix_spawnattr_destroy_nid_postfix(&attributes) == 0);
    Check(posix_spawnattr_destroy_nid_postfix(&uninitialized) == 0);
}

static void CheckFileActions() {
    PosixSpawnFileActions* actions = nullptr;
    Check(posix_spawn_file_actions_init_nid_postfix(&actions) == 0 && actions != nullptr && actions->actions.empty());

    char path[] = "/app0/log.txt";
    Check(posix_spawn_file_actions_addopen_nid_postfix(&actions, 3, path, 0x601, 0644) == 0);
    std::strcpy(path, "/changed");
    Check(posix_spawn_file_actions_adddup2_nid_postfix(&actions, 3, 1) == 0);
    Check(posix_spawn_file_actions_addclose_nid_postfix(&actions, 3) == 0);
    Check(posix_spawn_file_actions_adddup2_nid_postfix(&actions, 0, 0) == 0);

    Check(posix_spawn_file_actions_addopen_nid_postfix(&actions, -1, "/app0/other", 0, 0) == BadDescriptor);
    Check(posix_spawn_file_actions_adddup2_nid_postfix(&actions, -1, 1) == BadDescriptor);
    Check(posix_spawn_file_actions_adddup2_nid_postfix(&actions, 1, -1) == BadDescriptor);
    Check(posix_spawn_file_actions_addclose_nid_postfix(&actions, -2) == BadDescriptor);

    const auto& recorded = actions->actions;
    Check(recorded.size() == 4);
    Check(recorded[0].kind == PosixSpawnFileActionKind::Open && recorded[0].descriptor == 3);
    Check(recorded[0].path == "/app0/log.txt" && recorded[0].openFlags == 0x601 && recorded[0].mode == 0644);
    Check(recorded[1].kind == PosixSpawnFileActionKind::Duplicate && recorded[1].descriptor == 3 && recorded[1].newDescriptor == 1);
    Check(recorded[2].kind == PosixSpawnFileActionKind::Close && recorded[2].descriptor == 3);
    Check(recorded[3].kind == PosixSpawnFileActionKind::Duplicate && recorded[3].descriptor == 0 && recorded[3].newDescriptor == 0);

    PosixSpawnFileActions* uninitialized = nullptr;
    Check(posix_spawn_file_actions_addclose_nid_postfix(&uninitialized, -1) == BadDescriptor);
    Check(ThrowsInvalidArgument([&] { posix_spawn_file_actions_addclose_nid_postfix(&uninitialized, 1); }));
    Check(ThrowsInvalidArgument([&] { posix_spawn_file_actions_adddup2_nid_postfix(&uninitialized, 1, 2); }));
    Check(ThrowsInvalidArgument([&] { posix_spawn_file_actions_addopen_nid_postfix(&uninitialized, 1, "/app0/a", 0, 0); }));
    Check(ThrowsInvalidArgument([&] { posix_spawn_file_actions_addopen_nid_postfix(&actions, 1, nullptr, 0, 0); }));
    Check(ThrowsInvalidArgument([&] { posix_spawn_file_actions_destroy_nid_postfix(&uninitialized); }));
    Check(ThrowsInvalidArgument([] { posix_spawn_file_actions_init_nid_postfix(nullptr); }));
    Check(actions->actions.size() == 4);

    Check(posix_spawn_file_actions_destroy_nid_postfix(&actions) == 0);
}

static void CheckSpawn() {
    PosixSpawnAttributes* attributes = nullptr;
    PosixSpawnFileActions* actions = nullptr;
    Check(posix_spawnattr_init_nid_postfix(&attributes) == 0 && posix_spawn_file_actions_init_nid_postfix(&actions) == 0);
    char program[] = "/app0/tool.elf";
    char* arguments[] = {program, nullptr};
    char* environment[] = {nullptr};
    std::int32_t processId = 77;
    Check(ReportsNotImplemented([&] { posix_spawn_nid_postfix(&processId, program, &actions, &attributes, arguments, environment); },
        "posix_spawn: process creation not implemented"));
    Check(ReportsNotImplemented([&] { posix_spawnp_nid_postfix(&processId, "tool.elf", nullptr, nullptr, arguments, nullptr); },
        "posix_spawnp: process creation not implemented"));
    Check(processId == 77);
    Check(posix_spawn_file_actions_destroy_nid_postfix(&actions) == 0 && posix_spawnattr_destroy_nid_postfix(&attributes) == 0);
}

int main() {
    CheckAttributes();
    CheckFileActions();
    CheckSpawn();
}
