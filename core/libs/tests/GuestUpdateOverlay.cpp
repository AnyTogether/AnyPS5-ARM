#include "prx/libc/include/General.hpp"
#include "prx/libkernel/File/include/FileFlags.hpp"
#include "SceTypes.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

extern "C" {
int APS5_VABI sceKernelOpen(const char*, int, std::uint16_t);
int APS5_VABI sceKernelClose(int);
std::int64_t APS5_VABI sceKernelRead(int, void*, std::size_t);
int APS5_VABI access_nid_postfix(const char*, int);
}

static void Require(bool value) { if (!value) std::abort(); }

static void Write(const std::filesystem::path& file, const std::string& text) {
    std::filesystem::create_directories(file.parent_path());
    std::ofstream out(file, std::ios::binary);
    out << text;
    Require(static_cast<bool>(out));
}

static std::string Read(const char* path) {
    const int fd = sceKernelOpen(path, SCE_KERNEL_O_RDONLY, 0);
    Require(fd >= 0);
    char buffer[64]{};
    const auto count = sceKernelRead(fd, buffer, sizeof(buffer));
    Require(count >= 0 && sceKernelClose(fd) == 0);
    return std::string(buffer, static_cast<std::size_t>(count));
}

int main() {
    const auto original = std::filesystem::current_path();
    const auto directory = std::filesystem::canonical(original) / ("update-overlay-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    // The game (app0 under the working directory) and its update dumped beside it.
    Write(directory / "game" / "app0" / "sce_sys" / "param.json", R"({"contentVersion":"01.000.000"})");
    Write(directory / "game" / "app0" / "data" / "level1.pak", "base level 1");
    Write(directory / "game" / "app0" / "data" / "level2.pak", "base level 2");
    Write(directory / "game" / "app0" / "sce_module" / "libgame.prx.guest.prx", "relinked");
    const auto update = directory / "PPSA01234-UPDATE";
    Write(update / "sce_sys" / "param.json", R"({"contentVersion":"01.004.000"})");
    Write(update / "data" / "level2.pak", "patched level 2");
    Write(update / "data" / "new" / "level3.pak", "new level 3");
    Write(update / "sce_module" / "libgame.prx", "raw update module");
#ifdef _WIN32
    Require(_putenv_s("ANYPS5_UPDATE_DIR", update.string().c_str()) == 0);
#else
    Require(::setenv("ANYPS5_UPDATE_DIR", update.c_str(), 1) == 0);
#endif
    std::filesystem::current_path(directory / "game");

    // The update's files take the place of the game's; the rest still comes from the game.
    Require(Read("/app0/sce_sys/param.json") == R"({"contentVersion":"01.004.000"})");
    Require(Read("/app0/data/level2.pak") == "patched level 2");
    Require(Read("/app0/data/level1.pak") == "base level 1");
    Require(Read("/app0/data/new/level3.pak") == "new level 3");
    Require(Read("/APP0/Data/Level2.pak") == "patched level 2");
    Require(access_nid_postfix("/app0/data/missing.pak", 0) == -1);
    // A folder both have stays the game's, so a listing of it shows the game's files.
    Require(std::filesystem::equivalent(ResolvePath_nid_no_patch("/app0/data"), directory / "game" / "app0" / "data"));
    Require(std::filesystem::equivalent(ResolvePath_nid_no_patch("/app0/data/new"), update / "data" / "new"));
    Require(std::filesystem::equivalent(ResolvePath_nid_no_patch("/app0"), directory / "game" / "app0"));
    // Modules are the relinked ones in app0, never the update's raw files.
    Require(std::filesystem::equivalent(ResolvePathOrRelinkedModule_nid_no_patch("/app0/sce_module/libgame.prx"),
                                        directory / "game" / "app0" / "sce_module" / "libgame.prx.guest.prx"));
    // A module opened for reading is the game's relinked one too, never the update's raw file.
    Require(Read("/app0/sce_module/libgame.prx") == "relinked");
    // Paths outside app0 are untouched.
    Write(directory / "game" / "data" / "level2.pak", "outside");
    Require(Read("/data/level2.pak") == "outside");

    std::filesystem::current_path(original);
    std::filesystem::remove_all(directory);
    return 0;
}
