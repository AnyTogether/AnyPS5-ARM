[← All games](README.md) · **English** · [Türkçe](tr/pvz.md)

# Plants vs. Zombies: Replanted

`PPSA29802` · Unity (IL2CPP)

**Status:** 🟢 Playable · Levels 1-1 to 1-3 played through · **FPS:** menu ~120 · in game 60–120 (120 Hz display)

Plays from the main menu through the first levels, unlocks and huge waves included, and draws correctly. Six minutes of continuous play showed no glitch and no crash.

![In game: the first level, planting the first seed, 117 FPS](img/pvz-ingame.jpg)
*In game: the first level, planting the first seed, 117 FPS*

| | |
|---|---|
| <img src="img/pvz-newplant.jpg" width="420"><br>*Level 1-1 finished: the Sunflower unlocked* | <img src="img/pvz-garden.jpg" width="420"><br>*Level 1-2: sunflowers and peashooters* |
| <img src="img/pvz-wave.jpg" width="420"><br>*Level 1-3: "A huge wave of zombies is approaching!", 88 FPS* | <img src="img/pvz-zombies.jpg" width="420"><br>*Level 1-3: the wave reaches the garden* |

![EA user agreement screen](img/pvz-agreement.jpg)
*EA user agreement screen*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Same Unity preparation as Silksong** | SELF → ELF, modules with the executable, plugins separately. |
| ✅ | **C# exceptions are caught** | An ArgumentOutOfRangeException in a date/time calculation could not be caught by the game's own code. Fixed by reporting unwind tables on macOS (PR #4, kabonKoda). |
| ✅ | **MSAA sample locations** | The game uses nonstandard sample positions with 4x MSAA. They are applied through VK_EXT_sample_locations; main now uses upstream's implementation. |
| ✅ | **MSAA memory size** | The size of the 4x MSAA target was computed 2 MB too large and overlapped a small image; fixed with AddrLib's GFX10 rule. |
| ✅ | **Rosetta + AVX crash** | Fixed by upstream #4194; 53,718 stores were split in the executable. |
| ✅ | **Main menu and game** | Played by hand through levels 1-1, 1-2 and 1-3: main menu at ~120 FPS, in game 60–120 FPS on a 120 Hz display. |
| ✅ | **Startup abort fixed** | One of two launches used to end during startup with a Rosetta `EmulateForward` abort: a masked `vmaskmovps` store crossed into a write-watched page. The relinker stored masked stores element by element (b8dce7fb9; 63 sites in this game); five launches in a row then: no abort. Since the upstream merge of 2026-10-25 it probes every active element before the store instead (upstream 3cae921a6), not yet measured on this game. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| ID | `PPSA29802 · content 01.001.001` |
| Engine | `Unity, IL2CPP` |
| MSAA | `4x, custom sample positions` |
| Split 256-bit stores | `53,718 (executable)` |
| 5-minute run | `17,933 frames, no crash` |

## Converting it today (Unity, by hand)

AnyPS5.app does not do these steps yet, so for now they are manual:

1. Convert `eboot.bin`, `sce_module/*.prx`, `Media/Modules/*.prx` and `Media/Plugins/*.prx` from SELF to ELF.
2. Put the `Media/Modules` modules (`Il2cppUserAssemblies.prx`, `PS5Util.prx`) next to `sce_module` and relink the executable with `relinker --macos --to-rosetta`.
3. Relink the `Media/Plugins` plugins separately, without linking them into the executable, as `.guest.prx` files next to the originals. Unity loads them at run time with their start arguments.
4. After packaging:
   - symlink `Media/Modules/*.guest.prx` to the `sce_module` copies (the game also opens the same module as `Il2CppUserAssemblies`);
   - add symlinks under `Media/Plugins` for the plugins' `libc` and `libSceNpCppWebApi` dependencies;
   - link `app0/libs` → `../../../MacOS/libs`.

## Links

- [PR #4: macOS unwind tables](https://github.com/AnyTogether/AnyPS5-ARM/pull/4)
- [Upstream #4194](https://github.com/boykopovar/AnyPS5/pull/4194)
