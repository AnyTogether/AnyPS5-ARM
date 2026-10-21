# AnyPS5-ARM

**Run PS5 games natively on Apple silicon Macs.**

[Full guide in English and Turkish / Türkçe rehber](docs/user/GUIDE.md)

## The AnyPS5 app

**AnyPS5.app** is a launcher laid out like the PS5 home screen. Point it at the folder with your game dumps and it does the rest: it finds the games, unlocks (converts) them for the Mac, starts them, and keeps your controls, saves and trophies per game. No Terminal, build or Vulkan SDK needed.

![The AnyPS5 launcher in action](docs/videos/launcher-preview.webp)

<p align="center"><a href="https://github.com/utkuhalis/AnyPS5-ARM/raw/main/docs/videos/launcher.mp4"><b>▶ Full video with sound</b></a> (1:39, MP4)</p>

```sh
curl -fsSL https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/install.sh | sh
```

One line installs it into Applications (and Rosetta 2 if it is missing). A download through `curl` carries no quarantine flag, so macOS opens the app without any "cannot be opened" warning. [⬇ Or download the zip](https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/AnyPS5-macOS.zip) · [How to use it](docs/user/GUIDE.md#the-anyps5-app)

### First start

Three steps: the language (Türkçe or English), one of three animated themes (Cosmic, Aurora, Sunset) and the games folder. The folder and its subfolders are scanned, and games you add later show up on their own.

<p align="center"><img src="docs/screenshots/launcher-themes.jpg" alt="Picking a theme on the first start" width="720"></p>

### Home screen

![Home screen with Hollow Knight: Silksong selected](docs/screenshots/launcher-home-trophies.jpg)

Every game sits in a row of tiles with its icon. The selected one grows, its artwork drifts behind the screen, and below it are the facts: status, size on disk, title ID and version. A tile with a lock still has to be unlocked. Under the title:

- **Play**, or **Unlock**, **Retry** and **Cancel** as the state calls for.
- **🏆 8/34**, the trophies earned, when the game has a trophy list.
- **⋯** for the game's settings.

### Unlocking

![A game being unlocked](docs/screenshots/launcher-unlocking.jpg)

**Unlock** turns a PS5 dump into a Mac app in seconds to a few minutes, with a progress bar like the console's:

1. **Unwrap:** `eboot.bin` and every module are opened, even when they are still SELF containers. A dump that is still encrypted is reported, not converted.
2. **Relink:** the relinker writes a Mach-O executable and macOS modules. Unity titles get their `Media/Modules` and `Media/Plugins` folders too.
3. **Copy:** the game files become **APFS clones** of the dump, so an unlocked game takes no extra space.
4. **Bundle:** the libraries, MoltenVK, the per-title patches and a launch script go into the app.

Several games can be queued. When the launcher's toolkit is newer than the one a game was unlocked with, its status reads **Update available**; **⋯ → Unlock Again** brings it up to date and keeps its saves and trophies.

### Starting a game

![The start screen while a game opens](docs/screenshots/launcher-starting.jpg)

**Play** shows a start screen with the game's icon and a timer until the game's first window appears. The first start of a title takes longest, because Rosetta translates it and its shaders compile; later starts use the caches. Esc stops the game before it shows. Once the window is up the launcher hands it the front, and it can hide itself while you play (Settings → Behaviour). If the game closes before its window appears, the launcher says so, and **⋯ → Open Log** shows why.

### Game settings

<img src="docs/screenshots/launcher-game-settings.jpg" alt="Game settings" align="right" width="440">

Each game keeps its own settings, applied at every start:

- **Output resolution**, for titles with a resolution patch (such as Stray).
- **Window or full screen**, and the window size.
- **Vertical sync.**
- **Controls** (below).
- **Trophies** (below).
- **Performance overlay**, off or in any corner of the window.
- **Game language**: the launcher's, or any of the console's languages.
- **Unlock Again**, **Show in Finder**, **Open Log**, **Clear Shader Cache** and **Remove Installation**.

<br clear="right">

### Controls

![Waiting for a key for Square](docs/screenshots/launcher-controls.jpg)

The keyboard and mouse layout of each game. Pick a pad button or stick direction and press the key you want; Esc cancels. A key you give to one button leaves the button that had it, and mouse buttons stay where they were. **Reset to Default Keys** brings back the layout below. A connected game controller keeps its own buttons.

| Pad | Keys |
|-----|------|
| Left stick | W A S D |
| ✕ / □ / ○ / △ | K (also Space, Return) / J (also left click) / L / I |
| L1 / R1 | Q / E |
| L2 / R2 | U (also mouse button 4) / O (also right click) |
| L3 / R3 | Shift / Ctrl |
| D-pad | Arrow keys (also the mouse wheel for up and down) |
| Right stick | T F G H |
| Options / touchpad | Esc / Backspace (left) and Tab (right) |

The launcher writes the layout to `~/Library/Application Support/AnyPS5/Controls/<game>.ini` at each start and passes it to the game ([format](docs/user/INPUT_MAPPING.md)).

### Trophies

![The trophy list of Hollow Knight: Silksong](docs/screenshots/launcher-trophies.jpg)

<sub>The progress in this screenshot is sample data.</sub>

Trophies a game unlocks while you play are kept and listed as on the console:

- The **percentage**, weighted by grade as on the PS5, and the count of **platinum, gold, silver and bronze** trophies earned.
- Every trophy with its **icon, name, description, grade** and the **day and time you earned it**. Trophies you have not earned yet are greyed out.
- **Hidden** trophies stay hidden until you earn them.
- Trophies that count something (*Acquire all Tools*, *Bind all Silk Skills*) show **how far you are**, such as 23/51.

The list, the texts and the icons come from the game's own trophy package (`sce_sys/trophy2`), in the game's language when it has one. The engine records each unlock in the installed game, and the list updates when the game closes. Unlocking a game again keeps them.

### Library and settings

| Game library | Settings |
|---|---|
| ![Game library](docs/screenshots/launcher-library.jpg) | ![Settings](docs/screenshots/launcher-settings.jpg) |

The **library** button shows every game as a grid. **Settings** hold:

- **Appearance:** the theme, the accent color, and the background (the theme animation, your own picture or a looping video). Also the selected game's artwork behind the home screen and animations.
- **Library:** the games folder and scanning it again.
- **Language:** Türkçe or English.
- **Behaviour:** the profile name, interface sounds, hiding the launcher while a game runs, and installing Rosetta if it is missing.
- **About:** the app and toolkit versions.

### Getting around

The launcher works like a console: the arrow keys, Return (✕) and Esc (○), `O` (△) for options, or a game controller (D-pad, ✕, ○, △). The mouse and trackpad work too: click a tile, double-click to play, scroll through the row.

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
