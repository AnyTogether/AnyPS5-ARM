#include <NativeModules.hpp>
#include <io/FileReader.hpp>
#include <io/NativePath.hpp>
#include <algorithm>
#include <fstream>

namespace Cli {

NativeModules ReadModules(const std::filesystem::path& inputPath, const std::filesystem::path& sceModulePath, const std::set<std::string>& excludedModules, const std::vector<std::string>& moduleDirectories) {
    using namespace Relinker;
    const auto root = std::filesystem::absolute(sceModulePath).lexically_normal();
    if (!std::filesystem::exists(root)) throw Domain::RelinkerException("Guest module parent directory does not exist: " + Io::Utf8Path(root));
    if (!std::filesystem::is_directory(root)) throw Domain::RelinkerException("Guest module parent path is not a directory: " + Io::Utf8Path(root));
    const auto missingModuleMessage = std::string(GuestModulePattern) + " was not found in: " + Io::Utf8Path(root) + ". Use --skip-sce-module to disable guest module processing.";
    const auto singular = root / "sce_module";
    const auto plural = root / "sce_modules";
    const auto prx = root / "prx";
    const bool hasSingular = std::filesystem::exists(singular);
    const bool hasPlural = std::filesystem::exists(plural);
    const bool hasPrx = std::filesystem::exists(prx);
    if (hasSingular && hasPlural) throw Domain::RelinkerException("Both sce_module and sce_modules exist in the guest module parent directory");
    if (!hasSingular && !hasPlural && !hasPrx) throw Domain::RelinkerException(missingModuleMessage);
    std::vector<std::filesystem::path> directories;
    if (hasSingular || hasPlural) directories.push_back(hasSingular ? singular : plural);
    if (hasPrx) directories.push_back(prx);
    std::vector<std::filesystem::path> runtimeDirectories;
    for (const auto& name : moduleDirectories) {
        const auto relative = Io::NativePath(name).lexically_normal();
        if (relative.empty() || relative.has_root_path() || *relative.begin() == "..")
            throw Domain::RelinkerException("--module-dir must be a directory inside the guest module parent directory: " + name);
        auto directory = (root / relative).lexically_normal();
        if (!directory.has_filename()) directory = directory.parent_path();
        if (!std::filesystem::is_directory(directory)) throw Domain::RelinkerException("Guest module path is not a directory: " + Io::Utf8Path(directory));
        if (std::find(directories.begin(), directories.end(), directory) != directories.end()) throw Domain::RelinkerException("Duplicate guest module directory: " + Io::Utf8Path(directory));
        directories.push_back(directory);
        runtimeDirectories.push_back(directory);
    }
    std::vector<std::filesystem::path> paths;
    std::set<std::string> unmatchedExclusions = excludedModules;
    const auto isElf = [](const std::filesystem::path& path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream) throw Domain::RelinkerException("Cannot read guest candidate: " + Io::Utf8Path(path));
        char magic[4]{};
        stream.read(magic, 4);
        if (stream.bad()) throw Domain::RelinkerException("Cannot read guest candidate magic: " + Io::Utf8Path(path));
        if (stream.gcount() != 4) return false;
        const auto byte = [&](const std::size_t index) { return static_cast<unsigned char>(magic[index]); };
        return byte(0) == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
    };
    for (const auto& directory : directories) {
        if (!std::filesystem::is_directory(directory)) throw Domain::RelinkerException("Guest module path is not a directory: " + Io::Utf8Path(directory));
        for (const auto& entry : std::filesystem::directory_iterator(directory)) {
            if (Io::Utf8Path(entry.path().filename()).ends_with(GuestModuleSuffix)) continue;
            if (excludedModules.contains(Io::Utf8Path(entry.path().filename()))) {
                unmatchedExclusions.erase(Io::Utf8Path(entry.path().filename()));
                continue;
            }
            if (!entry.is_regular_file()) continue;
            if (std::filesystem::equivalent(entry.path(), inputPath)) continue;
            if (isElf(entry.path())) paths.push_back(entry.path());
        }
    }
    if (!unmatchedExclusions.empty()) throw Domain::RelinkerException("Excluded guest module file not found: " + *unmatchedExclusions.begin());
    std::sort(paths.begin(), paths.end());
    NativeModules result;
    result.Root = root;
    result.RuntimeDirectories = std::move(runtimeDirectories);
    for (const auto& path : paths) result.Modules.push_back({path, Io::FileReader().Read(Io::Utf8Path(path))});
    return result;
}

}
