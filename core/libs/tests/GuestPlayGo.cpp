#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <random>
#include <string>
#include <string_view>

extern "C" {
int APS5_VABI scePlayGoInitialize(const PlayGoInitParams*);
int APS5_VABI scePlayGoOpen(int*, const void*);
int APS5_VABI scePlayGoClose(int);
int APS5_VABI scePlayGoGetLanguageMask(int, std::uint64_t*);
int APS5_VABI scePlayGoSetToDoList(int, const PlayGoToDo*, std::uint32_t);
int APS5_VABI scePlayGoGetToDoList(int, PlayGoToDo*, std::uint32_t, std::uint32_t*);
int APS5_VABI scePlayGoGetLocus(int, const std::uint16_t*, std::uint32_t, std::int8_t*);
int APS5_VABI scePlayGoGetChunkId(int, std::uint16_t*, std::uint32_t, std::uint32_t*);
}

static void Require(bool value) { if (!value) std::abort(); }

static int CheckPackageChunkTable(const char* root) {
    constexpr int badChunkId = static_cast<int>(0x80B2000C);
    std::filesystem::current_path(root);
    PlayGoInitParams init{};
    int handle = 0;
    Require(scePlayGoInitialize(&init) == 0);
    Require(scePlayGoOpen(&handle, nullptr) == 0);
    const std::uint16_t known[3] = {0, 1, 2};
    std::int8_t loci[3] = {0, 0, 0};
    Require(scePlayGoGetLocus(handle, known, 3, loci) == 0 && loci[0] == 3 && loci[1] == 3 && loci[2] == 3);
    const std::uint16_t outside[2] = {1, 3};
    Require(scePlayGoGetLocus(handle, outside, 2, loci) == badChunkId);
    std::uint32_t chunkCount = 0;
    Require(scePlayGoGetChunkId(handle, nullptr, 0, &chunkCount) == 0 && chunkCount == 3);
    Require(scePlayGoClose(handle) == 0);
    return 0;
}

static void RunWithPackageChunkTable(const char* self) {
    const auto root = std::filesystem::temp_directory_path() / ("guest_playgo_" + std::to_string(std::random_device{}()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root / "app0" / "sce_sys");
    char header[0x100] = {'p', 'l', 'g', 'x'};
    header[0x0A] = 3;
    std::ofstream(root / "app0" / "sce_sys" / "playgo-chunk.dat", std::ios::binary).write(header, sizeof(header));
    const std::string arguments = "\"" + std::string(self) + "\" --package-chunk-table \"" + root.string() + "\"";
#ifdef _WIN32
    const std::string command = "\"" + arguments + "\"";
#else
    const std::string command = arguments;
#endif
    const int status = std::system(command.c_str());
    std::filesystem::remove_all(root);
    Require(status == 0);
}

int main(int argc, char** argv) {
    if (argc == 3 && std::string_view(argv[1]) == "--package-chunk-table") return CheckPackageChunkTable(argv[2]);
    RunWithPackageChunkTable(argv[0]);
    constexpr int badHandle = static_cast<int>(0x80B20009);
    constexpr int badPointer = static_cast<int>(0x80B2000A);
    constexpr int badSize = static_cast<int>(0x80B2000B);
    constexpr int badLocus = static_cast<int>(0x80B20010);

    PlayGoInitParams init{};
    int handle = 0;
    Require(scePlayGoInitialize(nullptr) == badPointer);
    Require(scePlayGoInitialize(&init) == 0);
    Require(scePlayGoOpen(nullptr, nullptr) == badPointer);
    Require(scePlayGoOpen(&handle, nullptr) == 0);

    std::uint64_t mask = 0;
    Require(scePlayGoGetLanguageMask(handle + 1, &mask) == badHandle);
    Require(scePlayGoGetLanguageMask(handle, nullptr) == badPointer);
    Require(scePlayGoGetLanguageMask(handle, &mask) == 0 && mask == ~0ull);

    PlayGoToDo todo[2] = {{0, 3, 0}, {0, 0, 0}};
    Require(scePlayGoSetToDoList(handle + 1, todo, 2) == badHandle);
    Require(scePlayGoSetToDoList(handle, nullptr, 2) == badPointer);
    Require(scePlayGoSetToDoList(handle, todo, 0) == badSize);
    Require(scePlayGoSetToDoList(handle, todo, 2) == 0);
    todo[1].locus = 1;
    Require(scePlayGoSetToDoList(handle, todo, 2) == badLocus);
    todo[1] = {0xFFFF, 3, 0};
    Require(scePlayGoSetToDoList(handle, todo, 2) == 0);

    std::uint32_t entries = 1;
    Require(scePlayGoGetToDoList(handle, todo, 2, &entries) == 0 && entries == 0);
    const std::uint16_t chunk = 0;
    std::int8_t locus = 0;
    Require(scePlayGoGetLocus(handle, &chunk, 0, &locus) == badSize);
    Require(scePlayGoGetLocus(handle, &chunk, 1, &locus) == 0 && locus == 3);
    const std::uint16_t undeclared[2] = {1, 10};
    std::int8_t loci[2] = {0, 0};
    Require(scePlayGoGetLocus(handle, undeclared, 2, loci) == 0 && loci[0] == 3 && loci[1] == 3);
    std::uint32_t chunkCount = 0;
    Require(scePlayGoGetChunkId(handle, nullptr, 0, &chunkCount) == 0 && chunkCount == 1);
    Require(scePlayGoClose(handle + 1) == badHandle);
    Require(scePlayGoClose(handle) == 0);
}
