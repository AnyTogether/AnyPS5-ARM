[← All games](README.md) · **English** · [Türkçe](tr/katamari.md)

# Once Upon a KATAMARI

`PPSA21904` · Unity (IL2CPP)

**Status:** 🟡 Work in progress · reaches gameplay; shader warm-up is still in progress · **FPS:** user reports ~3 in game during warm-up; settled FPS not measured

Tested on an Apple M1 Mac with a 7-core GPU, macOS 27.0.1, at a 1920×1080 Vulkan render extent. In a follow-up run, the user reports reaching gameplay at about 3 FPS while the game's displayed shader counter continued increasing past 30,000. This is a cold-cache observation; shader/pipeline warm-up was not completed, and performance after a warmed repeat run has not been measured. Treat the 3 FPS figure as provisional rather than settled gameplay performance.

The user also reports that relaunching starts the game from the beginning. Save-data files exist in the app's `_sd` directory, but their presence does not confirm that game progress was committed or successfully loaded. The in-game save flow and resume behavior still need verification; don't treat this as a confirmed save-data implementation bug yet.

The test used a fresh macOS relink of the decrypted game and its Unity modules, packaged with the current `main` build (`0deeb2a99`) and MoltenVK. The upstream rect-list culling fix (`140bdd3d4`) removed the invalid rect-list errors from the tested run. An earlier run stopped at a black screen after the startup logo; the follow-up gameplay report supersedes that result.

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Startup executable and modules** | Relinked the game executable, its two Unity modules and five Unity plugins from decrypted files. The packaged title starts and loads Unity content. |
| ✅ | **Degenerate rect-list draws** | The log no longer reports the invalid nondegenerate-rectangle validation failure after using the upstream culling fix. |
| ✅ | **First rendered scene** | Gameplay is reached in the user's follow-up run. |
| 🔧 | **Shader warm-up and performance** | The shader counter continues past 30,000; the user reports about 3 FPS during this cold-cache run. Repeat after the counter settles and compare the same scene before assessing steady-state performance. |
| 🔧 | **Save and resume** | The user reports the next launch starts from the beginning despite save files being present. Verify the in-game save action and whether a saved run resumes. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Game ID | `PPSA21904` |
| Engine | `Unity (IL2CPP)` |
| Graphics path | `libSceAgc → Vulkan → MoltenVK → Metal` |
| CPU path | `x86-64 → Rosetta 2` |
| Test hardware | `Apple M1, 7-core GPU; macOS 27.0.1` |
| Tested source | `main at 0deeb2a99` |
| Output | `Gameplay reached; user reports ~3 FPS during shader warm-up and restart from beginning; save/resume and warm-cache FPS unverified` |

First reported by Eyad Al-Daoud in [PR #8](https://github.com/utkuhalis/AnyPS5-ARM/pull/8).
