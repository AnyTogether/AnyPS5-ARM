#include <elfpatcher/windows/WindowsIconResourceBuilder.hpp>
#include <elfpatcher/windows/WindowsPeFormat.hpp>
#include <domain/Types.hpp>
#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

const std::vector<std::uint8_t> Png{
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
    0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4e, 0x44, 0xae, 0x42, 0x60, 0x82};

void require(const bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

std::uint32_t readU32(const std::vector<std::uint8_t>& data, const std::size_t offset) {
    return static_cast<std::uint32_t>(data[offset]) | static_cast<std::uint32_t>(data[offset + 1]) << 8 |
           static_cast<std::uint32_t>(data[offset + 2]) << 16 | static_cast<std::uint32_t>(data[offset + 3]) << 24;
}

std::vector<std::uint8_t> chunk(const std::string& type, const std::vector<std::uint8_t>& payload) {
    std::vector<std::uint8_t> result;
    const auto append = [&result](std::uint32_t value) {
        for (const auto shift : {24, 16, 8, 0}) result.push_back(static_cast<std::uint8_t>(value >> shift));
    };
    append(static_cast<std::uint32_t>(payload.size()));
    result.insert(result.end(), type.begin(), type.end());
    result.insert(result.end(), payload.begin(), payload.end());
    std::uint32_t crc = 0xffffffffu;
    for (std::size_t index = 4; index < result.size(); ++index) {
        crc ^= result[index];
        for (int bit = 0; bit < 8; ++bit) crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320u : 0u);
    }
    append(crc ^ 0xffffffffu);
    return result;
}

void checkChunks() {
    const Elfpatcher::Windows::WindowsIconResourceBuilder builder;
    const auto check = [&](const std::string& name, const std::vector<std::vector<std::uint8_t>>& chunks, bool valid, const std::vector<std::uint8_t>& header = {}) {
        std::vector<std::uint8_t> image(Png.begin(), Png.begin() + (header.empty() ? 33 : 8));
        if (!header.empty()) {
            const auto ihdr = chunk("IHDR", header);
            image.insert(image.end(), ihdr.begin(), ihdr.end());
        }
        for (const auto& value : chunks) image.insert(image.end(), value.begin(), value.end());
        image.insert(image.end(), Png.end() - 12, Png.end());
        const std::filesystem::path path = std::filesystem::path(name) / "icon.png";
        std::vector<Elfpatcher::Windows::PeSection> sections;
        bool rejected = false;
        try { builder.Build(image, path, sections, 0x10000); }
        catch (const Domain::RelinkerException& error) {
            rejected = true;
            require(std::string(error.what()).find(path.string()) != std::string::npos, "Icon failure omitted the path");
        }
        require(rejected != valid, "Unexpected validation result for " + name);
        require(sections.size() == (valid ? 1u : 0u), "Unexpected section mutation for " + name);
    };
    const std::vector<std::uint8_t> data(Png.begin() + 41, Png.begin() + 54);
    const auto idat = chunk("IDAT", data);
    const auto note = chunk("tEXt", {'n', 0, 'v'});
    check("unknown-critical", {chunk("ABCD", {}), idat}, false);
    check("ancillary", {note, idat}, true);
    const auto first = chunk("IDAT", {data.begin(), data.begin() + 6});
    const auto last = chunk("IDAT", {data.begin() + 6, data.end()});
    check("consecutive", {first, last}, true);
    check("nonconsecutive", {first, note, last}, false);
    const auto palette = chunk("PLTE", {255, 0, 0});
    check("late-palette", {idat, palette}, false);
    check("duplicate-palette", {palette, palette, idat}, false);
    check("palette", {palette, idat}, true);
    check("empty-palette", {chunk("PLTE", {}), idat}, false);
    check("partial-palette", {chunk("PLTE", {0, 1, 2, 3}), idat}, false);
    check("large-palette", {chunk("PLTE", std::vector<std::uint8_t>(771)), idat}, false);
    std::vector<std::uint8_t> header(Png.begin() + 16, Png.begin() + 29);
    header[8] = 1;
    header[9] = 3;
    const auto indexed = chunk("IDAT", {0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01});
    check("indexed", {palette, indexed}, true, header);
    check("indexed-missing-palette", {indexed}, false, header);
    check("indexed-large-palette", {chunk("PLTE", std::vector<std::uint8_t>(9)), indexed}, false, header);
    header[9] = 0;
    check("grayscale-palette", {palette, indexed}, false, header);
}

void run() {
    const Elfpatcher::Windows::WindowsIconResourceBuilder builder;

    checkChunks();

    const std::filesystem::path iconPath = "valid/icon0.png";
    const std::uint32_t nextRva = 0x50000;
    std::vector<Elfpatcher::Windows::PeSection> sections;
    const auto directory = builder.Build(Png, iconPath, sections, nextRva);
    require(sections.size() == 1, "Expected one section");
    require(sections[0].Name == ".rsrc", "Unexpected section name: " + sections[0].Name);
    require(sections[0].Rva == nextRva, "Unexpected section RVA");
    require(sections[0].Characteristics == (Elfpatcher::Windows::SectionRead | 0x40u), "Unexpected section characteristics");
    const auto& data = sections[0].Data;
    require(data.size() == 184 + Png.size(), "Unexpected section size");
    require(directory.Rva == nextRva && directory.Size == data.size(), "Unexpected resource directory");
    require(readU32(data, 16) == 3 && readU32(data, 24) == 14, "Unexpected resource types");
    require(readU32(data, 128) == nextRva + 184 && readU32(data, 132) == Png.size(), "Unexpected RT_ICON data entry");
    require(readU32(data, 144) == nextRva + 160 && readU32(data, 148) == 20, "Unexpected RT_GROUP_ICON data entry");
    require(data[166] == 1 && data[167] == 1, "Unexpected icon dimensions");
    require(readU32(data, 174) == Png.size(), "Unexpected icon size in group entry");
    require(std::equal(Png.begin(), Png.end(), data.begin() + 184), "Icon bytes changed");

    const auto badPath = std::filesystem::path("bad/icon0.png");
    auto truncated = Png;
    truncated.resize(40);
    std::vector<Elfpatcher::Windows::PeSection> badSections;
    try {
        builder.Build(truncated, badPath, badSections, nextRva);
    } catch (const Domain::RelinkerException& e) {
        require(std::string(e.what()).find(badPath.string()) != std::string::npos, std::string("Failure does not name the icon: ") + e.what());
        require(badSections.empty(), "Section added despite the failure");
        return;
    }
    throw std::runtime_error("Build succeeded for a malformed icon");
}

}

int main() {
    try {
        run();
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
    return 0;
}
