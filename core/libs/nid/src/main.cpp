#include <nid/BinaryPatcherFactory.hpp>
#include <nid/ExportExclusions.hpp>
#include <nid/NativePath.hpp>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::vector<std::uint8_t> _readFile(const std::string& path) {
    std::ifstream f(Nid::Internal::NativePath(path), std::ios::binary);
    if (!f) throw std::runtime_error("cannot open: " + path);
    return {std::istreambuf_iterator<char>(f), {}};
}

void _writeFile(const std::string& path, const std::vector<std::uint8_t>& data) {
    std::ofstream f(Nid::Internal::NativePath(path), std::ios::binary);
    if (!f) throw std::runtime_error("cannot write: " + path);
    f.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
}

}

int Run(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: nid_patcher <library_name> [--preserve-exports <unpatched-library>] <file> [file2 ...]\n";
        return 1;
    }

    const std::string libraryName = argv[1];
    std::unordered_set<std::string> excludedExports;
    std::vector<std::string> paths;
    try {
        bool hasReference = false;
        for (int i = 2; i < argc; ++i) {
            const std::string argument = argv[i];
            if (argument == "--preserve-exports") {
                if (hasReference || i + 1 == argc) throw std::runtime_error("--preserve-exports requires exactly one reference library");
                hasReference = true;
                excludedExports = Nid::ReadExportExclusions(argv[++i]);
            } else {
                if (argument.starts_with("--")) throw std::runtime_error("unknown option: " + argument);
                paths.push_back(argument);
            }
        }
        if (paths.empty()) throw std::runtime_error("no files to patch");
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n';
        return 2;
    }

    for (const std::string& path : paths) {
        try {
            auto binary = _readFile(path);
            const auto patcher = Nid::MakePatcher(binary);
            patcher->PatchNids(binary, libraryName, excludedExports);
            _writeFile(path, binary);
            std::cout << "OK: " << path << "\n";
        } catch (const std::exception& e) {
            std::cerr << "FAIL: " << path << ": " << e.what() << "\n";
            return 2;
        }
    }

    return 0;
}

#ifdef _WIN32
int wmain(int argc, wchar_t* argv[]) {
    try {
        std::vector<std::string> values;
        values.reserve(static_cast<std::size_t>(argc));
        for (int index = 0; index < argc; ++index) {
            const auto utf8 = std::filesystem::path(argv[index]).u8string();
            values.emplace_back(utf8.begin(), utf8.end());
        }
        std::vector<char*> arguments;
        arguments.reserve(values.size());
        for (auto& value : values) arguments.push_back(value.data());
        return Run(argc, arguments.data());
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 2;
    }
}
#else
int main(int argc, char* argv[]) {
    return Run(argc, argv);
}
#endif
