#include "prx/libSceVideoOut/include/HostHdrProbe.hpp"
#include "prx/libSceAgcDriver/Execution/include/HostHdr.hpp"
#include <cstdio>
#include <cstdlib>
#include <string>

#undef main

int main() {
    if (SDL_InitSubSystem(SDL_INIT_VIDEO) != 0) {
        std::printf("skipped, no SDL video driver: %s\n", SDL_GetError());
        return 77;
    }
    SDL_Window* window = SDL_CreateWindow("HDR probe test", 0, 0, 64, 64, SDL_WINDOW_HIDDEN);
    if (window == nullptr) {
        std::printf("skipped, no SDL window: %s\n", SDL_GetError());
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        return 77;
    }
    const std::string driver = SDL_GetCurrentVideoDriver() != nullptr ? SDL_GetCurrentVideoDriver() : "unknown";
    AgcDriverSetSurfaceHdr10_nid_postfix(true);
    int result = 0;
    {
        HostHdrProbe probe;
        probe.Poll(window);
        probe.Poll(window);
        const auto host = AgcDriver::CurrentHostHdr();
        if (host.display.hdr || host.available) {
            std::fprintf(stderr, "FAIL: a window without a Windows HDR monitor report reads as HDR although only the surface offers HDR10 (driver %s)\n", driver.c_str());
            result = 1;
        }
    }
    SDL_DestroyWindow(window);
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
    if (result == 0) std::printf("HDR probe tests passed (driver %s)\n", driver.c_str());
    return result;
}
