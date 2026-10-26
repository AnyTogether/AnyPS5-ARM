#pragma once

// Add-on content the player dumped beside the game. The launcher lists each add-on's folder in
// ANYPS5_ADDCONT_DIRS, separated like PATH (';' on Windows, ':' elsewhere). Only folders that are
// there count: nothing is reported as owned beyond what is on the disk.

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

namespace DiskAddons {

// SCE_APP_CONTENT_ADDCONT_DOWNLOAD_STATUS_*: a license-only add-on has no extra data to mount.
constexpr unsigned NoExtraData = 0;
constexpr unsigned Installed = 4;

struct Addon {
    std::string label;
    std::filesystem::path folder;
    bool hasData = false;

    unsigned status() const { return hasData ? Installed : NoExtraData; }
};

// A file name as UTF-8: on Windows path::string() throws for names outside the ANSI code page.
inline std::string NameOf(const std::filesystem::path& path) {
    const auto name = path.filename().u8string();
    return std::string(name.begin(), name.end());
}

inline bool ValidLabel(std::string_view label) {
    return !label.empty() && label.size() <= 16 &&
        std::all_of(label.begin(), label.end(), [](unsigned char c) { return std::isalnum(c) != 0; });
}

// "UP0000-PPSA01234_00-ABCDEFGHIJKLMNOP": the entitlement label is the part after the last dash.
inline std::optional<std::string> LabelOfContentId(std::string_view id) {
    if (id.size() != 36 || id[6] != '-' || id[19] != '-' || id[16] != '_') return std::nullopt;
    const auto label = id.substr(20);
    if (!ValidLabel(label)) return std::nullopt;
    return std::string(label);
}

inline std::optional<std::string> ContentIdOf(const std::filesystem::path& folder) {
    std::ifstream file(folder / "sce_sys" / "param.json", std::ios::binary);
    if (!file) return std::nullopt;
    const std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    const auto key = text.find("\"contentId\"");
    if (key == std::string::npos) return std::nullopt;
    const auto colon = text.find(':', key + 11);
    const auto open = colon == std::string::npos ? colon : text.find('"', colon + 1);
    const auto close = open == std::string::npos ? open : text.find('"', open + 1);
    if (close == std::string::npos) return std::nullopt;
    return text.substr(open + 1, close - open - 1);
}

// The label from the add-on's param.json, else from its folder name: a content ID or a label.
inline std::optional<std::string> LabelOf(const std::filesystem::path& folder) {
    if (const auto id = ContentIdOf(folder)) {
        if (auto label = LabelOfContentId(*id)) return label;
    }
    const auto name = NameOf(folder);
    if (auto label = LabelOfContentId(name)) return label;
    if (ValidLabel(name)) return name;
    return std::nullopt;
}

// Whether the add-on has files besides its sce_sys: a license-only add-on has none.
inline bool HasData(const std::filesystem::path& folder) {
    std::error_code error;
    for (std::filesystem::directory_iterator entry(folder, error), end; !error && entry != end; entry.increment(error)) {
        auto name = NameOf(entry->path());
        std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (name != "sce_sys" && !name.starts_with('.')) return true;
    }
    return false;
}

inline std::vector<std::filesystem::path> ConfiguredFolders() {
    std::vector<std::filesystem::path> folders;
#ifdef _WIN32
    const wchar_t* value = _wgetenv(L"ANYPS5_ADDCONT_DIRS");
    if (value == nullptr) return folders;
    const std::wstring text(value);
    constexpr wchar_t separator = L';';
#else
    const char* value = std::getenv("ANYPS5_ADDCONT_DIRS");
    if (value == nullptr) return folders;
    const std::string text(value);
    constexpr char separator = ':';
#endif
    std::size_t start = 0;
    while (start <= text.size()) {
        const auto end = std::min(text.find(separator, start), text.size());
        if (end > start) folders.emplace_back(text.substr(start, end - start));
        start = end + 1;
    }
    return folders;
}

inline std::vector<Addon> Scan() {
    std::vector<Addon> addons;
    for (const auto& folder : ConfiguredFolders()) {
        std::error_code error;
        if (!std::filesystem::is_directory(folder, error)) continue;
        auto label = LabelOf(folder);
        if (!label) continue;
        if (std::any_of(addons.begin(), addons.end(), [&](const Addon& addon) { return addon.label == *label; })) continue;
        addons.push_back({std::move(*label), folder, HasData(folder)});
    }
    return addons;
}

inline const std::vector<Addon>& InstalledAddons() {
    static const auto addons = Scan();
    return addons;
}

inline const Addon* Find(const char (&label)[17]) {
    const std::string_view wanted(label, static_cast<std::size_t>(std::find(label, label + sizeof(label), '\0') - label));
    for (const auto& addon : InstalledAddons()) {
        if (addon.label == wanted) return &addon;
    }
    return nullptr;
}

}
