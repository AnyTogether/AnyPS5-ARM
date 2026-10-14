#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <random>
#include <string>
#include <system_error>

extern "C" {
int APS5_VABI sceSaveDataInitialize3(const void*);
int APS5_VABI sceSaveDataMount3(const SaveDataMount3*, SaveDataMountResult*);
int APS5_VABI sceSaveDataUmount2(std::uint32_t, const SaveDataMountPoint*);
}

namespace {

constexpr std::uint32_t MountReadWrite = 2;
constexpr std::uint32_t MountCreate = 4;
constexpr std::uint32_t MountCreate2 = 32;
constexpr int SaveDataErrorBusy = -2137063421;
constexpr int SaveDataErrorNotFound = -2137063416;

int failures = 0;

void Check(bool condition, const std::string& what) {
    if (condition) return;
    std::fprintf(stderr, "savedata mount status check failed: %s\n", what.c_str());
    ++failures;
}

void MountAndCheck(const char* name, std::uint32_t mode, std::uint32_t expectedStatus, const std::string& what) {
    SceSaveDataDirName dirName{};
    std::memcpy(dirName.data, name, std::strlen(name) + 1);
    SaveDataMount3 mount{};
    mount.dir_name = &dirName;
    mount.mount_mode = mode;
    SaveDataMountResult result{};
    const int code = sceSaveDataMount3(&mount, &result);
    Check(code == 0, what + ": mounts");
    if (code != 0) return;
    Check(result.mount_status == expectedStatus, what + ": status is " + std::to_string(result.mount_status) + ", expected " + std::to_string(expectedStatus));
    Check(sceSaveDataUmount2(0, &result.mount_point) == 0, what + ": unmounts");
}

void CheckFailedMountKeepsResult() {
    SceSaveDataDirName held{};
    std::memcpy(held.data, "held", sizeof("held"));
    SaveDataMount3 mount{};
    mount.dir_name = &held;
    mount.mount_mode = MountReadWrite | MountCreate2;
    SaveDataMountResult result{};
    Check(sceSaveDataMount3(&mount, &result) == 0, "first mount of a save");
    const SaveDataMountResult mounted = result;
    Check(sceSaveDataMount3(&mount, &result) == SaveDataErrorBusy, "second mount of a mounted save is BUSY");
    Check(std::memcmp(&result, &mounted, sizeof(result)) == 0, "a BUSY mount leaves the result as it was");
    SceSaveDataDirName absent{};
    std::memcpy(absent.data, "absent", sizeof("absent"));
    mount.dir_name = &absent;
    mount.mount_mode = MountReadWrite;
    Check(sceSaveDataMount3(&mount, &result) == SaveDataErrorNotFound, "open of a missing save is NOT_FOUND");
    Check(std::memcmp(&result, &mounted, sizeof(result)) == 0, "a NOT_FOUND mount leaves the result as it was");
    Check(sceSaveDataUmount2(0, &result.mount_point) == 0, "the kept mount point unmounts the save");
}

}

int main() {
    const auto root = std::filesystem::temp_directory_path() / ("anyps5-savedata-mount-status-" + std::to_string(std::random_device{}()));
    std::filesystem::create_directories(root);
    const auto previous = std::filesystem::current_path();
    std::filesystem::current_path(root);
    Check(sceSaveDataInitialize3(nullptr) == 0, "SaveData initializes");
    MountAndCheck("fresh", MountReadWrite | MountCreate2, 1u, "CREATE2 of a missing save");
    MountAndCheck("fresh", MountReadWrite | MountCreate2, 0u, "CREATE2 of an existing save");
    MountAndCheck("made", MountReadWrite | MountCreate, 1u, "CREATE of a missing save");
    MountAndCheck("made", MountReadWrite, 0u, "open of an existing save");
    CheckFailedMountKeepsResult();
    std::filesystem::current_path(previous);
    std::error_code error;
    std::filesystem::remove_all(root, error);
    if (failures != 0) return 1;
    std::printf("savedata mount status tests passed\n");
    return 0;
}
