**English** · [Türkçe](tr/ROADMAP.md)

# Roadmap

Where AnyPS5-ARM is heading on Apple silicon Macs, in order. Today titles run under Rosetta 2 (x86-64 guest and host code) with the PS5 graphics driver on Metal through MoltenVK. Game by game status is in the [game status notebook](games/README.md), the Rosetta port itself in [MACOS_PORT.md](dev/MACOS_PORT.md).

Last updated: 15 October 2026.

✅ done · 🔧 in progress · ⏭️ next · 💤 later

## 1. Frame rate 🔧

Heavy 3D titles are limited by the CPU, not the GPU. Stray at 1080p takes ~100–150 ms per frame, of which the GPU is busy only ~41–45 ms. It waits for the GPU just ~3 ms per frame and never drains the device. The time goes to the driver thread, which turns each PS5 draw packet into Vulkan one by one: ~24,000 draws per 10 s at ~270–415 µs each.

| | Step | Details |
|---|---|---|
| ⏭️ | **Lock waits** | The largest cost per draw (137–247 µs) is waiting for the GPU mutex shared with the other driver threads. Shorter holds or finer locks could halve the time per draw. |
| ⏭️ | **Repeated per-draw work** | Shader memory capture (~40 µs), PM4 decode (~35 µs) and recompile lookups (~40–60 µs) run again on every draw. Cache what does not change between draws. |
| ⏭️ | **Measure against a baseline** | Each step is measured in Stray at 1080p with a warm shader cache, against the build before it. |

Target: Stray in game from ~5 to 20+ FPS at 1080p. This work also carries over to a native arm64 build.

## 2. What Rosetta costs 🔧

The driver code runs translated by Rosetta, like the game. The libraries also build natively for arm64 (`native-arm64` branch), so the same driver tests can run both ways.

| | Step | Details |
|---|---|---|
| ⏭️ | **Same tests, both architectures** | Time the driver and shader recompiler tests in `build-arm64` (native) and `build-mac` (Rosetta). |
| ⏭️ | **Decide** | The difference says how much a Rosetta-free build is worth, and so how soon step 5 starts in earnest. |

## 3. Game compatibility 🔧

| | Game | Next |
|---|---|---|
| 🟢 | **Stray** (`PPSA02100`) | First chapter plays with correct graphics. Next: the chapters after it, and the frame rate (step 1). |
| 🟢 | **Hollow Knight: Silksong**, **Plants vs. Zombies: Replanted** | Playable; the Unity module steps are still manual (step 4). |
| 🟡 | **Quake II / Quake III** | Quake II in game; Quake III needs its data files. |
| 🟡 | **Minecraft** (`PPSA17221`) | Menus at 60 FPS, reaches a world. Next: the open file limit that crashes it ~20 s in, then the frame rate in the world (~7-8). |
| 🔴 | **GTA III – Definitive Edition** (`PPSA03527`) | Retry on current main. |
| ⏭️ | **More titles** | Each new title gets a page in the [notebook](games/README.md). |

## 4. The AnyPS5 app and releases ⏭️

The last release, [v0.1.0-arm](https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.1.0-arm), predates most of the work above.

| | Step | Details |
|---|---|---|
| ⏭️ | **New release** | Current main, with the third upstream merge and the Stray fixes. |
| ⏭️ | **Game patches in the app** | `tools/package_macos_app.py` applies per-title patches (Stray's output resolution); AnyPS5.app does not yet. |
| ⏭️ | **Unity module steps in the app** | Silksong and PvZ Replanted still need the manual module steps described on their pages. |

## 5. Native arm64, without Rosetta 💤

Plan and design: [NATIVE_ARM64.md](https://github.com/AnyTogether/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md) on the `native-arm64` branch. Guest x86-64 code is translated to arm64 ahead of time (Capstone, LLVM), and the host libraries build natively.

| | Milestone | Details |
|---|---|---|
| ✅ | **Libraries build for arm64** | The x86-only parts throw until they are ported. |
| ✅ | **Smallest fixture runs natively** | `import_fixture` (`puts` and `exit` through the GOT) runs as an arm64 process. |
| ⏭️ | **The C and C++ fixtures** | Threads, TLS, exceptions, modules. |
| 💤 | **Breakout, then Dreaming Sarah** | The first real titles without Rosetta. |
| 💤 | **Hard parts** | Non-local control flow (setjmp/longjmp, exception landing pads, fibers), x86 memory ordering on arm64, variadic and `long double` bridges. |

## 6. Metal backend 💤

Replacing Vulkan and MoltenVK with Metal directly means rewriting the whole graphics backend. While the GPU sits idle for most of each frame, it would gain the least, so it comes last.

## Upstream

The fork stays level with [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5) before game tests. Fixes that are not Mac-specific go upstream as pull requests.
