# AnyPS5-ARM

**Run PS5 games natively on Apple silicon Macs.**

[Full guide in English and Turkish / Türkçe rehber](docs/user/GUIDE.md)

## The AnyPS5 app

**AnyPS5.app** is a launcher laid out like the PS5 home screen. Point it at the folder with your game dumps and it does the rest: it finds the games, unlocks (converts) them for the Mac and starts them.

![The AnyPS5 launcher in action](docs/videos/launcher-preview.webp)

<p align="center"><a href="https://github.com/utkuhalis/AnyPS5-ARM/raw/main/docs/videos/launcher.mp4"><b>▶ Full video with sound</b></a> (1:39, MP4)</p>

```sh
curl -fsSL https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/install.sh | sh
```

One line installs it into Applications (and Rosetta 2 if it is missing). A download through `curl` carries no quarantine flag, so macOS opens the app without any "cannot be opened" warning. [⬇ Or download the zip](https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/AnyPS5-macOS.zip) · [How to use it](docs/user/GUIDE.md#the-anyps5-app)

- **First start in three steps:** language (Türkçe or English), one of three animated themes (Cosmic, Aurora, Sunset) and the games folder.
- **Finds your games:** the folder and its subfolders are scanned, and games added later show up on their own, with their icon, artwork, size, title ID and version.
- **One-click unlock:** a game that is not converted yet shows a lock.
  - **Unlock** opens `eboot.bin` and the modules even when they are still SELF containers, and relinks them for macOS.
  - The game app is ready in seconds to a few minutes, with a PS5-style progress bar.
  - The game files are APFS clones of the dump, so an unlocked game takes no extra space.
- **Per-game settings:**
  - output resolution (for titles with a resolution patch, such as Stray);
  - window or full screen, and the window size;
  - vertical sync, the performance overlay and the game's language;
  - **controls:** keyboard and mouse keys for every pad button and stick, set by pressing the key. The default is WASD for the left stick and J/K/L/I for □/✕/○/△;
  - Show in Finder, the log, clearing the shader cache, unlocking again, removing the installation.
- **Trophies:** every game's trophy list from its own package, with icons, grades, progress and the day each one was earned, as on the console. Unlocking a game again keeps its saves and trophies.
- **Personal:**
  - the theme, the accent color, and the background (the theme animation, your own picture or a looping video);
  - the selected game's artwork drifting behind the home screen;
  - animations, interface sounds, the profile name.
- **Console-style controls:** arrow keys, Return and Esc; a game controller (D-pad, ✕, ○, △); or the mouse and trackpad. A game library grid shows everything at once.

| First start | Unlocking | Game settings | Game library |
|---|---|---|---|
| ![Picking a theme](docs/screenshots/launcher-themes.jpg) | ![Unlocking a game](docs/screenshots/launcher-unlocking.jpg) | ![Game settings](docs/screenshots/launcher-game-settings.jpg) | ![Game library](docs/screenshots/launcher-library.jpg) |

## Games on a Mac

| Hollow Knight: Silksong | Plants vs. Zombies: Replanted | Dreaming Sarah | AnyPS5 Breakout |
|---|---|---|---|
| ![Silksong](docs/games/img/silksong-120-moss.jpg) | ![PvZ Replanted](docs/games/img/pvz-ingame.jpg) | ![Dreaming Sarah](docs/games/img/dreaming-sarah.jpg) | ![AnyPS5 Breakout](docs/games/img/breakout.jpg) |
| **120 fps, playable** | opening screens at 60 fps, work in progress | 60 fps, playable | 60 fps, test title |

**[Game status notebook →](docs/games/README.md)** ([Türkçe](docs/games/tr/README.md)) one page per game with screenshots, the steps behind it and technical details: DOOM (homebrew) plays too, Stray plays its first chapter, at a low frame rate (~12 FPS) for now, and Minecraft gets into a world.

<sub>MacBook Pro M3 Pro, macOS 26.6.2. Silksong is unlocked and started from AnyPS5.app; PvZ was converted by hand and has not been tried in it yet.</sub>

## Status

[![libraries](https://boykopovar.github.io/AnyPS5/badge-libraries.svg)](https://boykopovar.github.io/AnyPS5/progress.html) [![shaders](https://boykopovar.github.io/AnyPS5/badge-shaders.svg)](https://boykopovar.github.io/AnyPS5/progress.html)

[![progress map](https://boykopovar.github.io/AnyPS5/progress.svg)](https://boykopovar.github.io/AnyPS5/progress.html)

[Progress history](https://boykopovar.github.io/AnyPS5/history.html)

Unsupported or unexpected states strictly throw `std::runtime_error`. `what()` is printed to stderr and the process terminates.

The [shader recompiler](core/shader/recompiler/Recompiler.cpp) successfully produces SPIR-V (validated via [Spirv-Tools](3rdparty/SPIRV-Tools) when built with `ANYPS5_ENABLE_SPIRV_TOOLS`).

## Compatibility

[Tested games and their frame rates](docs/user/COMPATIBILITY.md)

Per-game progress (stage reached, open blockers, libraries and GPU coverage) is tracked on the [blocker map](https://alxcbtw.github.io/anyps5-roadmap/), a community project built from public GitHub data ([source](https://github.com/AlxcBTW/anyps5-roadmap)). Test reports go in the [Game bring-up](https://github.com/boykopovar/AnyPS5/discussions/categories/game-bring-up) discussions, one thread per title.

## About

AnyPS5-ARM is the macOS port of [AnyPS5](https://github.com/boykopovar/AnyPS5). AnyPS5 is not an emulator: its relinker turns a PS5 executable into a native program, and its system libraries are reimplemented as ordinary shared libraries the program links against. On Apple silicon:

- **CPU:** the game's x86-64 code runs under **Rosetta 2**. A [native arm64 mode](https://github.com/utkuhalis/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md) without Rosetta is in development on the `native-arm64` branch.
- **Executable:** the relinker writes a **Mach-O** executable.
- **Graphics:** the PS5 graphics driver runs on **Vulkan through MoltenVK**, which runs on Metal.
- **Distribution:** the result is a normal **`.app`** you open from Finder.

[Building from source](docs/user/GUIDE.md#building-from-source) · [macOS port changes](docs/dev/MACOS_PORT.md) · [Input mapping](docs/user/INPUT_MAPPING.md) · [Technical debt](docs/dev/TechnicalDebt.md)

Built on [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5) and the community macOS port [mugurc/AnyPS5 `macos-port`](https://github.com/mugurc/AnyPS5/tree/macos-port).

## Disclaimer

This project is intended for interoperability, research, preservation and compatibility purposes. It does not include, distribute or require copyrighted software, firmware, cryptographic keys or proprietary libraries. Users are responsible for obtaining and using any binaries with this project in accordance with applicable laws and their license terms.

## License

GNU General Public License version 2 only.
