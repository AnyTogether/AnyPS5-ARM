[← All games](README.md) · **English** · [Türkçe](tr/silksong.md)

# Hollow Knight: Silksong

`PPSA12544` · Unity (IL2CPP)

**Status:** 🟢 Playable · New game through Moss Grotto · **FPS:** 120, menus and in game

Unlocked in one click in AnyPS5.app and started from it. A new game plays from the title screen through the opening into Moss Grotto, the inventory included, at a steady 120 FPS (8.3–8.4 ms a frame on average) at 1920×1080. That was ~25–50 FPS on 12 October; the upstream merges since then brought it up.

![In game: Hornet in Moss Grotto at 119 FPS](img/silksong-120-moss.jpg)
*In game: Hornet in Moss Grotto, 119 FPS, 8.4 ms a frame on average*

| | |
|---|---|
| <img src="img/silksong-120-title.jpg" width="420"><br>*Title screen, 119 FPS* | <img src="img/silksong-120-pharloom.jpg" width="420"><br>*Act 1: Pharloom* |
| <img src="img/silksong-120-cave.jpg" width="420"><br>*Further into Moss Grotto, 118 FPS* | <img src="img/silksong-120-climb.jpg" width="420"><br>*Climbing, 120 FPS* |
| <img src="img/silksong-120-inventory.jpg" width="420"><br>*The inventory (Hunter's Cloak), 120 FPS* | |

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Executable and modules converted** | The dump's SELF files (eboot and sce_module) were converted to ELF, Unity's Media/Modules and Media/Plugins modules included. |
| ✅ | **Unity modules linked** | Il2cppUserAssemblies and PS5Util are linked with the executable. The plugins (PSN, SaveData, Share...) are prepared separately and loaded at run time. |
| ✅ | **"PSN old version" error fixed** | The plugins now receive their start arguments: fablevoid's macOS relinker fix (1b865fc3e), which came through upstream. |
| ✅ | **Plugin dependencies** | The libc and libSceNpCppWebApi dependencies of the plugins under Media/Plugins are now found. |
| ✅ | **Rosetta + AVX crash fixed** | Unaligned 256-bit stores that cross a page boundary are split in two (upstream #4194). 55,017 stores were split in the executable. |
| ✅ | **Performance** | 120 FPS in menus and in game on 21 October (8.3–8.4 ms a frame on average), up from ~25–50 in game on 12 October. |
| ✅ | **One-click unlock** | AnyPS5.app relinks Unity's Media/Modules and Media/Plugins itself (15c0b29e0), so the manual steps below are no longer needed. |
| 🔧 | **Occasional crash** | Earlier, one of two five-minute runs segfaulted at second 293, with no crash report. The sessions on 12 and 21 October did not crash. Under investigation. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| ID | `PPSA12544 · version 01.000.010` |
| Engine | `Unity 2021+, IL2CPP` |
| Graphics path | `libSceAgc → Vulkan → MoltenVK → Metal` |
| CPU path | `x86-64 → Rosetta 2` |
| Split 256-bit stores | `55,017 (executable)` |
| Test hardware | `MacBook Pro M3 Pro, macOS 26.6.2` |

## Converting it

Open the dump's folder in AnyPS5.app and press **Unlock**: it converts `eboot.bin` and every module, `Media/Modules` and `Media/Plugins` included, relinks them for macOS and makes the app (about 30 seconds on an M3 Pro). By hand, the relinker needs `--module-dir Media/Modules --module-dir Media/Plugins` besides `sce_module`.

## Links

- [Upstream #4194 (splitting 256-bit stores)](https://github.com/boykopovar/AnyPS5/pull/4194)
- [Upstream #3731 (60 FPS report on Linux)](https://github.com/boykopovar/AnyPS5/issues/3731)
