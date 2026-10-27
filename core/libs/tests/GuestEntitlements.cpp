#include "prx/libSceNpEntitlementAccess/include/Api.hpp"
#include "SceTypes.hpp"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>
#include <stdexcept>
#include <string>
#include <string_view>

static void Require(bool value) { if (!value) std::abort(); }

static void SetEntitlements(const std::filesystem::path& file) {
#ifdef _WIN32
    Require(_wputenv_s(L"ANYPS5_ENTITLEMENTS", file.wstring().c_str()) == 0);
#else
    Require(::setenv("ANYPS5_ENTITLEMENTS", file.c_str(), 1) == 0);
#endif
}

int main(int argc, char** argv) {
    const auto root = std::filesystem::temp_directory_path() / ("anyps5_guest_entitlements-" + std::to_string(std::random_device{}()));
    const auto directory = root / std::filesystem::path(u8"dlc-a\u00e7\u00e3o-\u65e5\u672c");
    const auto file = directory / "anyps5-entitlements.ini";
    if (argc == 2 && std::string_view(argv[1]) == "missing") {
        std::uint32_t skuFlag = 0;
    Require(sceNpEntitlementAccessGetSkuFlag(nullptr) == static_cast<int>(0x80558003));
    Require(sceNpEntitlementAccessGetSkuFlag(&skuFlag) == 0 && skuFlag == 3);
    std::uint32_t pftFlag = 1;
    Require(sceNpEntitlementAccessGetPftFlag(nullptr) == static_cast<int>(0x817D0002));
    Require(sceNpEntitlementAccessGetPftFlag(&pftFlag) == 0 && pftFlag == 0);
    std::uint32_t trialFlag = 1;
    Require(sceNpEntitlementAccessGetGameTrialsFlag(nullptr) == static_cast<int>(0x817D0002));
    Require(sceNpEntitlementAccessGetGameTrialsFlag(&trialFlag) == 0 && trialFlag == 0);
    Require(sceNpEntitlementAccessGenerateTransactionId(nullptr) == static_cast<int>(0x80558003));
    SetEntitlements(file);
        std::uint32_t hits = 0;
        bool rejected = false;
        try {
            sceNpEntitlementAccessGetAddcontEntitlementInfoList(0, nullptr, 0, &hits);

        } catch (const std::runtime_error& error) {
            rejected = std::string_view(error.what()).starts_with("NpEntitlementAccess: cannot read ");
        }
        Require(rejected);
        std::puts("Guest entitlements rejected a missing configured file");
        return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "disk") {
        // No list of owned add-ons: only the add-on folders dumped beside the game count.
        const auto expansion = directory / "EXPANSION0000001";
        const auto license = directory / "SOUNDTRACK000003";
        std::filesystem::create_directories(expansion / "sce_sys");
        std::filesystem::create_directories(license / "sce_sys");
        { std::ofstream data(expansion / "island.pak", std::ios::binary); data << "island"; }
#ifdef _WIN32
        // Wide, as the folder name is not in the ANSI code page.
        const std::wstring folders = expansion.wstring() + L";" + license.wstring() + L";" + (directory / "MISSING000000004").wstring();
        Require(_wputenv_s(L"ANYPS5_ADDCONT_DIRS", folders.c_str()) == 0);
#else
        const std::string folders = expansion.string() + ":" + license.string() + ":" + (directory / "MISSING000000004").string();
        Require(::setenv("ANYPS5_ADDCONT_DIRS", folders.c_str(), 1) == 0);
#endif
        NpEntitlementAccessAddcontEntitlementInfo list[4]{};
        std::uint32_t hits = 0;
        Require(sceNpEntitlementAccessGetAddcontEntitlementInfoList(0, list, 4, &hits) == 0 && hits == 2);
        Require(std::strcmp(list[0].entitlement_label.data, "EXPANSION0000001") == 0 && list[0].download_status == 4);
        Require(std::strcmp(list[1].entitlement_label.data, "SOUNDTRACK000003") == 0 && list[1].download_status == 0);
        NpUnifiedEntitlementLabel missing{};
        std::memcpy(missing.data, "MISSING000000004", 16);
        NpEntitlementAccessAddcontEntitlementInfo info{};
        Require(sceNpEntitlementAccessGetAddcontEntitlementInfo(0, &missing, &info) == static_cast<int>(0x80558007));
        std::filesystem::remove_all(root);
        std::puts("Guest entitlements listed the add-ons on the disk");
        return 0;
    }
    std::filesystem::create_directories(directory);
    {
        std::ofstream ini(file, std::ios::binary);
        ini << "# owned add-ons\nFIRSTADDON0000\n  SECONDADDON ; second\n";
        Require(static_cast<bool>(ini));
    }
    SetEntitlements(file);
    NpEntitlementAccessAddcontEntitlementInfo list[3]{};
    std::uint32_t hits = 0;
    Require(sceNpEntitlementAccessGetAddcontEntitlementInfoList(0, list, 3, &hits) == 0);
    Require(hits == 2);
    Require(std::strcmp(list[0].entitlement_label.data, "FIRSTADDON0000") == 0);
    Require(std::strcmp(list[1].entitlement_label.data, "SECONDADDON") == 0);
    NpUnifiedEntitlementLabel label{};
    std::memcpy(label.data, "SECONDADDON", 11);
    NpEntitlementAccessAddcontEntitlementInfo info{};
    Require(sceNpEntitlementAccessGetAddcontEntitlementInfo(0, &label, &info) == 0);
    Require(std::strcmp(info.entitlement_label.data, "SECONDADDON") == 0 && info.package_type == 3 && info.download_status == 4);
    std::filesystem::remove_all(root);
    std::puts("Guest entitlements passed");
    return 0;
}
