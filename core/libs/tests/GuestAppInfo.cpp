#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>

extern "C" {
int APS5_VABI sceKernelGetAppInfo(int pid, void* info);
int APS5_VABI getpid_nid_postfix(void);
}

static constexpr int SCE_KERNEL_ERROR_EPERM = static_cast<int>(0x80020001);

static void Require(bool value) { if (!value) std::abort(); }

struct AppInfo {
    std::uint32_t appId;
    std::uint64_t unknown1;
    char titleId[14];
    char unknown2[0x3c];
};

static std::filesystem::path EnterTemporaryRoot(std::string_view name) {
    const auto root = std::filesystem::temp_directory_path() / (std::string(name) + std::to_string(getpid_nid_postfix()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);
    std::filesystem::current_path(root);
    return root;
}

int main(int argc, char** argv) {
    if (argc == 3 && std::string_view(argv[1]) == "--without-param-json") {
        std::filesystem::current_path(argv[2]);
        AppInfo info{};
        sceKernelGetAppInfo(getpid_nid_postfix(), &info);
        return 0;
    }
    const auto previous = std::filesystem::current_path();
    const auto root = EnterTemporaryRoot("guest_app_info_");
    std::filesystem::create_directories(root / "app0" / "sce_sys");
    std::ofstream(root / "app0" / "sce_sys" / "param.json") << "{\n  \"contentId\": \"IV0000-PPSA97358_00-XPSEMU0000000000\",\n  \"localizedParameters\": {\"defaultLanguage\": \"en-US\", \"en-US\": {\"titleName\": \"XPSemu\"}},\n  \"titleId\": \"PPSA97358\"\n}\n";
    AppInfo info;
    std::memset(&info, 0x5a, sizeof(info));
    const int self = getpid_nid_postfix();
    Require(sceKernelGetAppInfo(self, &info) == 0);
    Require(info.appId == 1);
    Require(std::strcmp(info.titleId, "PPSA97358") == 0);
    Require(info.unknown1 == 0x5a5a5a5a5a5a5a5aull);
    Require(info.unknown2[0] == 0x5a);
    Require(sceKernelGetAppInfo(self + 1, &info) == SCE_KERNEL_ERROR_EPERM);
    Require(sceKernelGetAppInfo(self, nullptr) == 0);
    std::filesystem::current_path(previous);
    std::filesystem::remove_all(root);
    const auto empty = std::filesystem::temp_directory_path() / ("guest_app_info_empty_" + std::to_string(self));
    std::filesystem::remove_all(empty);
    std::filesystem::create_directories(empty);
    const std::string arguments = "\"" + std::string(argv[0]) + "\" --without-param-json \"" + empty.string() + "\"";
#ifdef _WIN32
    const std::string command = "\"" + arguments + "\"";
#else
    const std::string command = arguments;
#endif
    Require(std::system(command.c_str()) != 0);
    std::filesystem::remove_all(empty);
}
