#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_STATSOVERLAY_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_STATSOVERLAY_HPP

struct SDL_Window;

// The minimal performance overlay (ANYPS5_OVERLAY_STYLE=minimal): one line of figures — frames
// per second, frame time, GPU and CPU use, memory — in a small capsule in a corner of the game's
// window, drawn by the window in the system font rather than into the frame, so screenshots leave
// it out. It follows the overlay's toggle and corner. Where there is no such window it draws
// nothing.
namespace StatsOverlay {
// Called on the main thread after every present.
void Present(SDL_Window* window);
}

#endif
