[← All games](README.md) · **English** · [Türkçe](tr/breakout.md)

# AnyPS5 Breakout

`APS5TEST1` · The project's test game

**Status:** 🟢 Playable · **FPS:** 60

The project's own test game. It exercises the basic system (memory, display, sound, controller) and runs without problems.

![Breakout, 60 FPS](img/breakout.jpg)
*Breakout, 60 FPS*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Build** | core/relinker/relinker/tests/macos/breakout.cpp, built as a PS5 ELF. |
| ✅ | **Playable** | CPU rendering, VideoOut flip, AudioOut, Pad. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Source | `core/relinker/relinker/tests/macos/breakout.cpp` |
| GPU | `Not used (CPU rendering)` |
| FPS | `60` |
