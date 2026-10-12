#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"

#include <array>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

extern "C" {
int APS5_VABI sceSaveDataDirNameSearch(const SaveDataDirNameSearchCond*, SaveDataDirNameSearchResult*);
int APS5_VABI sceSaveDataMount3(const SaveDataMount3*, SaveDataMountResult*);
int APS5_VABI sceSaveDataUmount2(std::uint32_t, const SaveDataMountPoint*);
int APS5_VABI sceSaveDataSetParam(const SaveDataMountPoint*, std::uint32_t, const void*, std::size_t);
}

static constexpr int SaveDataErrorParameter = -2137063424;

static void Require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}

static std::vector<std::string> Search(std::uint32_t key, std::uint32_t order, std::uint32_t capacity, std::uint32_t* hits) {
    SceSaveDataDirName pattern{};
    std::snprintf(pattern.data, sizeof(pattern.data), "SORT_%%");
    SaveDataDirNameSearchCond cond{};
    cond.user_id = 1;
    cond.dir_name = &pattern;
    cond.key = key;
    cond.order = order;
    std::array<SceSaveDataDirName, 3> names{};
    SaveDataDirNameSearchResult result{};
    result.dir_names = names.data();
    result.dir_names_num = capacity;
    Require(sceSaveDataDirNameSearch(&cond, &result) == 0, "sorted search failed");
    *hits = result.hit_num;
    std::vector<std::string> found;
    for (std::uint32_t i = 0; i < result.set_num; ++i) found.emplace_back(names[i].data);
    return found;
}

static void SortByKey() {
    struct Save {
        const char* name;
        std::uint32_t userParam;
        std::int64_t mtime;
    };
    const std::array<Save, 3> saves{{{"SORT_B", 1, 1000}, {"SORT_A", 3, 2000}, {"SORT_C", 2, 3000}}};
    for (const auto& save : saves) {
        std::filesystem::create_directories(std::filesystem::path("_sd") / save.name);
        SceSaveDataDirName dirName{};
        std::snprintf(dirName.data, sizeof(dirName.data), "%s", save.name);
        SaveDataMount3 mount{};
        mount.user_id = 1;
        mount.dir_name = &dirName;
        mount.mount_mode = 2;
        SaveDataMountResult mounted{};
        Require(sceSaveDataMount3(&mount, &mounted) == 0, "mount for parameters failed");
        Require(sceSaveDataSetParam(&mounted.mount_point, 4, &save.userParam, sizeof(save.userParam)) == 0, "user parameter was not set");
        Require(sceSaveDataSetParam(&mounted.mount_point, 5, &save.mtime, sizeof(save.mtime)) == 0, "mtime was not set");
        Require(sceSaveDataUmount2(0, &mounted.mount_point) == 0, "unmount failed");
    }
    using Names = std::vector<std::string>;
    std::uint32_t hits = 0;
    Require(Search(0, 0, 3, &hits) == Names{"SORT_A", "SORT_B", "SORT_C"} && hits == 3, "directory names must sort ascending");
    Require(Search(0, 1, 3, &hits) == Names{"SORT_C", "SORT_B", "SORT_A"}, "directory names must sort descending");
    Require(Search(1, 0, 3, &hits) == Names{"SORT_B", "SORT_C", "SORT_A"}, "user parameters must sort ascending");
    Require(Search(1, 1, 3, &hits) == Names{"SORT_A", "SORT_C", "SORT_B"}, "user parameters must sort descending");
    Require(Search(3, 0, 3, &hits) == Names{"SORT_B", "SORT_A", "SORT_C"}, "modification times must sort ascending");
    Require(Search(3, 1, 1, &hits) == Names{"SORT_C"} && hits == 3, "the newest save must come first in descending modification time");
    SaveDataDirNameSearchCond cond{};
    cond.user_id = 1;
    cond.key = 6;
    SaveDataDirNameSearchResult result{};
    Require(sceSaveDataDirNameSearch(&cond, &result) == SaveDataErrorParameter, "an unknown sort key must be rejected");
    cond.key = 0;
    cond.order = 2;
    Require(sceSaveDataDirNameSearch(&cond, &result) == SaveDataErrorParameter, "an unknown sort order must be rejected");
}

static void SearchAndMount() {
    const std::array names{std::string(31, 'A'), std::string(31, 'B')};
    for (const auto& name : names) std::filesystem::create_directories(std::filesystem::path("_sd") / name);

    alignas(SceSaveDataDirName) std::array<char, 80> buffer;
    buffer.fill('!');
    SaveDataDirNameSearchCond cond{};
    cond.user_id = 1;
    SaveDataDirNameSearchResult result{};
    result.dir_names = reinterpret_cast<SceSaveDataDirName*>(buffer.data());
    result.dir_names_num = 2;
    Require(sceSaveDataDirNameSearch(&cond, &result) == 0, "search failed");
    Require(result.hit_num == 2 && result.set_num == 2, "search must return both saves");
    for (std::size_t i = 64; i < buffer.size(); ++i) {
        Require(buffer[i] == '!', "directory search overran two 32-byte guest records");
    }
    std::array<bool, 2> found{};
    for (int i = 0; i < 2; ++i) {
        const char* record = buffer.data() + i * 32;
        Require(record[31] == '\0', "directory record must terminate within 32 bytes");
        const bool first = std::strcmp(record, names[0].c_str()) == 0;
        Require(first || std::strcmp(record, names[1].c_str()) == 0, "returned directory name is corrupted");
        const int index = first ? 0 : 1;
        Require(!found[index], "search returned a duplicate directory");
        found[index] = true;

        SaveDataMount3 mount{};
        mount.user_id = cond.user_id;
        mount.dir_name = reinterpret_cast<const SceSaveDataDirName*>(record);
        mount.mount_mode = 1;
        SaveDataMountResult mounted{};
        Require(sceSaveDataMount3(&mount, &mounted) == 0, "returned directory must be mountable");
        Require(sceSaveDataUmount2(0, &mounted.mount_point) == 0, "unmount failed");
    }
}

int main() {
    const auto previous = std::filesystem::current_path();
    const auto root = std::filesystem::temp_directory_path() /
        ("anyps5-savedata-search-" + std::to_string(std::random_device{}()));
    std::filesystem::create_directories(root);
    std::filesystem::current_path(root);
    int status = 0;
    try {
        SearchAndMount();
        SortByKey();
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        status = 1;
    }
    std::filesystem::current_path(previous);
    std::filesystem::remove_all(root);
    return status;
}
