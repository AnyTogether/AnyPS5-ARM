# AnyPS5-ARM engine (Rosetta)

**The AnyPS5 engine for Apple silicon Macs, on its own:** the relinker and the system libraries that turn a PS5 game into a Mac app, with the game's x86-64 code running under Rosetta 2.

This branch holds the engine alone, for those who want it without the apps. The whole project, with the launcher (AnyPS5.app) and the phone app, is on [`main`](https://github.com/utkuhalis/AnyPS5-ARM/tree/main); releases are made from there. The engine running games as native arm64 code, without Rosetta, is on [`native-arm64`](https://github.com/utkuhalis/AnyPS5-ARM/tree/native-arm64).

## How it works

AnyPS5-ARM is the macOS port of [AnyPS5](https://github.com/boykopovar/AnyPS5). AnyPS5 is not an emulator: its relinker turns a PS5 executable into a native program, and its system libraries are reimplemented as ordinary shared libraries the program links against. On Apple silicon:

- **CPU:** the game's x86-64 code runs under **Rosetta 2**.
- **Executable:** the relinker writes a **Mach-O** executable.
- **Graphics:** the PS5 graphics driver runs on **Vulkan through MoltenVK**, which runs on Metal.
- **Distribution:** the result is a normal **`.app`** you open from Finder.

## Requirements

- A Mac with Apple silicon (M1 or newer)
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`
- Xcode command-line tools: `xcode-select --install`
- CMake and Ninja: `brew install cmake ninja`
- The [Vulkan SDK for macOS](https://vulkan.lunarg.com/sdk/home#mac), which provides the Vulkan loader and MoltenVK
- A **decrypted dump of a game you own**. It needs a plain ELF executable; a signed SELF does not work.

## 1. Build

```sh
git clone --recursive -b rosetta https://github.com/utkuhalis/AnyPS5-ARM.git
cd AnyPS5-ARM
cmake -S . -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
ninja -C build-mac all libs
```

`CMAKE_OSX_ARCHITECTURES=x86_64` is required, because the system libraries have to match the game's x86-64 code. The build produces the relinker at `build-mac/core/relinker/relinker` and the system libraries in `build-mac/core/libs/libs/`. `ctest --test-dir build-mac` runs the tests.

## 2. Convert a game

The dump folder holds the executable, its bundled modules and the game's data:

```text
MyGame/
    eboot.bin        decrypted ELF executable
    sce_module/      the game's bundled modules (libc.prx, ...)
    sce_sys/         param.json, icon0.png, ...
    ...              the game's data files
```

```sh
build-mac/core/relinker/relinker --macos --to-rosetta MyGame/eboot.bin out/eboot
```

- `--macos` writes a Mach-O executable.
- `--to-rosetta` rewrites the AMD-only instructions and the ones Rosetta lacks (RDSEED, RDPID, CLWB).
- The converted modules are written to `out/app0/sce_module/`.

## 3. Package it as an app

```sh
python3 tools/package_macos_app.py \
    --relinked out \
    --game MyGame \
    --libs build-mac/core/libs/libs \
    --vulkan ~/VulkanSDK/<version>/macOS \
    "My Game.app"
```

The bundle contains everything it needs: the game, the system libraries, the Vulkan loader and MoltenVK. Its name and icon come from `sce_sys/param.json` and `icon0.png`. The app is not signed: if macOS refuses to open it, right-click it and choose **Open** once.

## 4. Play

The keyboard and mouse stand in for the pad (WASD for the left stick, Return for ✕, the arrow keys for the D-pad, and so on: [the full table](docs/user/INPUT_MAPPING.md)), and controllers SDL recognizes, such as DualSense, DualShock and Xbox pads, work by themselves.

- **Log:** `~/Library/Logs/AnyPS5/<TITLE ID>.log`. When a game stops, the reason is at the end of this file. Unsupported states always end the program with an error message rather than continuing silently.
- **Shader cache:** `~/Library/Caches/org.anyps5.<title id>/shader_cache`.

## Status

Unsupported or unexpected states strictly throw `std::runtime_error`; `what()` is printed to stderr and the process terminates. Games may stop at a function or GPU feature that is not implemented yet: see the [compatibility list](docs/user/COMPATIBILITY.md) and the [game notebook](docs/games/README.md). MoltenVK has no geometry shaders, mesh shaders, 64-bit atomics or 64-bit floats; the [technical debt](docs/dev/TechnicalDebt.md) lists the known costs of the macOS port.

[macOS port changes](docs/dev/MACOS_PORT.md) · [Architecture](docs/dev/ARCHITECTURE.md) · [Build details](docs/dev/BUILD.md) · [Conventions](docs/dev/CONVENTIONS.md)

Built on [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5) and the community macOS port [mugurc/AnyPS5 `macos-port`](https://github.com/mugurc/AnyPS5/tree/macos-port).

## Disclaimer

This project is intended for interoperability, research, preservation and compatibility purposes. It does not include, distribute or require copyrighted software, firmware, cryptographic keys or proprietary libraries. Users are responsible for obtaining and using any binaries with this project in accordance with applicable laws and their license terms.

## License

GNU General Public License version 2 only.
