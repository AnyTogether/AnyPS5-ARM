#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <random>
#include <string>
#include <system_error>
#include <vector>

extern "C" {
int APS5_VABI sceSaveDataConvert(const SaveDataConvert*);
int APS5_VABI sceSaveDataInitialize3(const void*);
}

namespace {

constexpr int SaveDataErrorParameter = -2137063424;
constexpr int SaveDataErrorNotFound = -2137063416;

int failures = 0;

void Check(bool condition, const std::string& what) {
    if (condition) return;
    std::fprintf(stderr, "savedata convert check failed: %s\n", what.c_str());
    ++failures;
}

int Convert(const char* data, std::size_t size) {
    SceSaveDataDirName name{};
    std::memcpy(name.data, data, size);
    SaveDataConvert convert{};
    convert.user_id = 0x10000000;
    convert.dir_name = &name;
    return sceSaveDataConvert(&convert);
}

std::vector<char> Read(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

}

int main() {
    const auto root = std::filesystem::temp_directory_path() / ("anyps5-savedata-convert-" + std::to_string(std::random_device{}()));
    const auto work = root / "work";
    const auto kept = work / "_sd" / "kept" / "data.bin";
    std::filesystem::create_directories(kept.parent_path());
    std::ofstream(kept) << "data";
    const auto previous = std::filesystem::current_path();
    std::filesystem::current_path(work);

    Check(sceSaveDataInitialize3(nullptr) == 0, "SaveData initializes");
    Check(Convert("kept", sizeof("kept")) == 0, "an existing save converts");
    Check(Read(kept) == std::vector<char>{'d', 'a', 't', 'a'}, "the converted save keeps its files");
    Check(Convert("missing", sizeof("missing")) == SaveDataErrorNotFound, "a missing save is not found");
    for (const char* invalid : {"../kept", "", ".", "..", "a\\b", "c:d"}) {
        Check(Convert(invalid, std::strlen(invalid) + 1) == SaveDataErrorParameter, std::string("\"") + invalid + "\" is rejected");
    }
    char unterminated[sizeof(SceSaveDataDirName::data)];
    std::memset(unterminated, 'a', sizeof(unterminated));
    Check(Convert(unterminated, sizeof(unterminated)) == SaveDataErrorParameter, "an unterminated name is rejected");

    std::filesystem::current_path(previous);
    std::error_code error;
    std::filesystem::remove_all(root, error);
    if (failures != 0) return 1;
    std::printf("savedata convert tests passed\n");
    return 0;
}
