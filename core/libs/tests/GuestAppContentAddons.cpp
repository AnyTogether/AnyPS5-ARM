#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <array>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include "ProcessParametersFixture.hpp"

extern "C" {
int APS5_VABI sceAppContentInitialize(const AppContentInitParam*, AppContentBootParam*);
int APS5_VABI sceAppContentAddcontMount(uint32_t, const NpUnifiedEntitlementLabel*, AppContentMountPoint*);
int APS5_VABI sceAppContentAddcontUnmount(const AppContentMountPoint*);
int APS5_VABI sceAppContentGetAddcontInfo(uint32_t, const NpUnifiedEntitlementLabel*, void*);
int APS5_VABI sceAppContentGetAddcontInfoList(uint32_t, void*, uint32_t, uint32_t*);
int APS5_VABI access_nid_postfix(const char*, int);
}

namespace {

constexpr int ErrorNotFound = static_cast<int>(0x80D90005);
constexpr int ErrorDrmNoEntitlement = static_cast<int>(0x80D90007);
constexpr std::uint32_t StatusNoExtraData = 0;
constexpr std::uint32_t StatusInstalled = 4;

struct AddcontInfo {
    NpUnifiedEntitlementLabel label;
    std::uint32_t status;
};

void Require(bool value) { if (!value) std::abort(); }

void Write(const std::filesystem::path& file, const std::string& text) {
    std::filesystem::create_directories(file.parent_path());
    std::ofstream out(file, std::ios::binary);
    out << text;
    Require(static_cast<bool>(out));
}

NpUnifiedEntitlementLabel MakeLabel(const char* text) {
    NpUnifiedEntitlementLabel label{};
    std::memcpy(label.data, text, std::strlen(text));
    return label;
}

void SetFolders(const std::string& value) {
#ifdef _WIN32
    Require(_putenv_s("ANYPS5_ADDCONT_DIRS", value.c_str()) == 0);
#else
    Require(::setenv("ANYPS5_ADDCONT_DIRS", value.c_str(), 1) == 0);
#endif
}

}

int main() {
    static std::array<std::byte, 64> process{};
    Require(ProcessParametersFixture::Install(process.data(), process.size()));
    std::uint32_t sdkVersion = 0x01500000;
    std::memcpy(process.data() + 16, &sdkVersion, sizeof(sdkVersion));

    const auto original = std::filesystem::current_path();
    const auto directory = original / ("appcontent-addons-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(directory / "app0" / "sce_sys");
    Write(directory / "app0" / "sce_sys" / "param.json", R"({"titleId":"PPSA01234"})");

    // A dump beside the game the way the launcher finds it: PPSA01234-DLC/<label> folders (one
    // named by its label, one by its content ID with a param.json saying so), a license-only
    // add-on with nothing but sce_sys, and a folder that is not there at all.
    const auto dlc = directory / "PPSA01234-DLC";
    const auto expansion = dlc / "EXPANSION0000001";
    Write(expansion / "sce_sys" / "param.json", R"({"titleId":"PPSA01234"})");
    Write(expansion / "maps" / "island.pak", "island");
    const auto costumes = dlc / "UP0000-PPSA01234_00-COSTUMEPACK00002";
    Write(costumes / "sce_sys" / "param.json", R"({"contentId" : "UP0000-PPSA01234_00-COSTUMEPACK00002"})");
    Write(costumes / "costume.bin", "costume");
    const auto license = dlc / "SOUNDTRACK000003";
    Write(license / "sce_sys" / "param.json", "{}");
    const auto missing = dlc / "NOTDUMPED0000004";
    const auto unlabelled = dlc / "not a label folder";
    Write(unlabelled / "file.bin", "x");
#ifdef _WIN32
    const char separator = ';';
#else
    const char separator = ':';
#endif
    SetFolders(expansion.string() + separator + costumes.string() + separator + license.string() + separator + missing.string() + separator +
               unlabelled.string() + separator + expansion.string());
    std::filesystem::current_path(directory);

    AppContentInitParam init{};
    AppContentBootParam boot{};
    Require(sceAppContentInitialize(&init, &boot) == 0);

    // The list holds what is on the disk, once each, and nothing else.
    std::uint32_t hits = 0;
    Require(sceAppContentGetAddcontInfoList(0, nullptr, 0, &hits) == 0 && hits == 3);
    std::array<AddcontInfo, 4> list{};
    std::memset(list.data(), 0x5a, sizeof(list));
    Require(sceAppContentGetAddcontInfoList(0, list.data(), 2, &hits) == 0 && hits == 2);
    Require(std::strcmp(list[0].label.data, "EXPANSION0000001") == 0 && list[0].status == StatusInstalled);
    Require(std::strcmp(list[1].label.data, "COSTUMEPACK00002") == 0 && list[1].status == StatusInstalled);
    Require(list[2].status == 0x5a5a5a5au);
    Require(sceAppContentGetAddcontInfoList(0, list.data(), 4, &hits) == 0 && hits == 3);
    Require(std::strcmp(list[2].label.data, "SOUNDTRACK000003") == 0 && list[2].status == StatusNoExtraData);
    Require(list[2].label.padding[0] == 0 && list[2].label.padding[1] == 0 && list[2].label.padding[2] == 0);

    AddcontInfo info{};
    auto label = MakeLabel("COSTUMEPACK00002");
    Require(sceAppContentGetAddcontInfo(0, &label, &info) == 0);
    Require(std::strcmp(info.label.data, "COSTUMEPACK00002") == 0 && info.status == StatusInstalled);
    auto absent = MakeLabel("NOTDUMPED0000004");
    std::memset(&info, 0x5a, sizeof(info));
    Require(sceAppContentGetAddcontInfo(0, &absent, &info) == ErrorDrmNoEntitlement);
    Require(info.status == 0x5a5a5a5au);

    // Mounting maps /addcontN onto the add-on's folder; the game reads its files through it.
    AppContentMountPoint first{};
    auto expansionLabel = MakeLabel("EXPANSION0000001");
    Require(sceAppContentAddcontMount(0, &expansionLabel, &first) == 0);
    Require(std::strcmp(first.data, "/addcont0") == 0);
    Require(access_nid_postfix("/addcont0/maps/island.pak", 0) == 0);
    Require(std::filesystem::equivalent(ResolvePath_nid_no_patch("/addcont0/maps/island.pak"), expansion / "maps" / "island.pak"));
    AppContentMountPoint again{};
    Require(sceAppContentAddcontMount(0, &expansionLabel, &again) == 0 && std::strcmp(again.data, "/addcont0") == 0);
    AppContentMountPoint second{};
    Require(sceAppContentAddcontMount(0, &label, &second) == 0);
    Require(std::strcmp(second.data, "/addcont1") == 0);
    Require(access_nid_postfix("/addcont1/costume.bin", 0) == 0);

    // Nothing to mount for an add-on that is not there or has no data.
    AppContentMountPoint untouched{};
    std::memset(&untouched, 0x5a, sizeof(untouched));
    AppContentMountPoint refused = untouched;
    Require(sceAppContentAddcontMount(0, &absent, &refused) == ErrorNotFound);
    auto licenseLabel = MakeLabel("SOUNDTRACK000003");
    Require(sceAppContentAddcontMount(0, &licenseLabel, &refused) == ErrorNotFound);
    Require(std::memcmp(&refused, &untouched, sizeof(refused)) == 0);

    // Unmounting closes the path; the freed slot is used again.
    Require(sceAppContentAddcontUnmount(&first) == 0);
    Require(access_nid_postfix("/addcont0/maps/island.pak", 0) == -1);
    Require(sceAppContentAddcontUnmount(&first) == ErrorNotFound);
    Require(access_nid_postfix("/addcont1/costume.bin", 0) == 0);
    Require(sceAppContentAddcontMount(0, &expansionLabel, &first) == 0 && std::strcmp(first.data, "/addcont0") == 0);
    Require(access_nid_postfix("/addcont0/maps/island.pak", 0) == 0);
    Require(sceAppContentAddcontUnmount(&first) == 0);
    Require(sceAppContentAddcontUnmount(&second) == 0);

    std::filesystem::current_path(original);
    std::filesystem::remove_all(directory);
    return 0;
}
