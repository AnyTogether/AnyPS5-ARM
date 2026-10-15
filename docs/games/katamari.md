[← All games](README.md) · **English**

# Once Upon a KATAMARI

`PPSA21904` · Unity (IL2CPP)

**Status:** 🟡 Work in progress · startup logos render, then the screen stays black · **FPS:** startup ~54–60; gameplay not reached

Tested on an Apple M1 Mac with a 7-core GPU, macOS 27.0.1, at a 1920×1080 Vulkan render extent. The rebuilt app reaches the CRIWARE startup logo at about 60 FPS, then presents a black screen while the frame counter continues advancing at about 54 FPS. Pressing the mapped Cross key (Return) did not change the screen. The game is not playable yet.

The test used a fresh macOS relink of the decrypted game and its Unity modules, packaged with the current `main` build (`0deeb2a99`) and MoltenVK. The upstream rect-list culling fix (`140bdd3d4`) removed the invalid rect-list errors from the latest run, but did not resolve the black screen. That run's log shows the title loading its Unity bundles and scene data without rect-list validation failures.

## Technical details

| | |
|---|---|
| Game ID | `PPSA21904` |
| Engine | `Unity (IL2CPP)` |
| Graphics path | `libSceAgc → Vulkan → MoltenVK → Metal` |
| CPU path | `x86-64 → Rosetta 2` |
| Test hardware | `Apple M1, 7-core GPU; macOS 27.0.1` |
| Tested source | `main at 0deeb2a99` |
| Output | `Black screen after startup logos; ~54 FPS` |

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Startup executable and modules** | Relinked the game executable, its two Unity modules and five Unity plugins from decrypted files. The packaged title starts and loads Unity content. |
| ✅ | **Degenerate rect-list draws** | The log no longer reports the invalid nondegenerate-rectangle validation failure after using the upstream culling fix. |
| 🔧 | **First rendered scene** | The window remains black after the startup logos even though frames continue to present. |
| ⏭️ | **Gameplay and performance** | Not reached; in-game performance has not been measured. |

✅ done · 🔧 in progress · ⏭️ next
