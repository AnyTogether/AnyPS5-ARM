#include <io/NativePath.hpp>

namespace Io {

std::filesystem::path NativePath(const std::string& path) {
    const std::u8string utf8(path.begin(), path.end());
    return std::filesystem::path(utf8);
}

std::string Utf8Path(const std::filesystem::path& path) {
    const auto utf8 = path.u8string();
    return std::string(utf8.begin(), utf8.end());
}

}
