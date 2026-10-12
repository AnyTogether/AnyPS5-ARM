[← All games](README.md) · **English** · [Türkçe](tr/silksong.md)

# Hollow Knight: Silksong

`PPSA12544` · Unity (IL2CPP)

**Status:** 🟡 Work in progress · In game, first area · **FPS:** menu 60 · in game ~28–48

The game starts, goes through its menus and plays in the first area. The one problem left is an occasional crash in long sessions.

![In game: Hornet in the first area, with the HUD and the "Bind" hint](img/silksong-ingame.jpg)
*In game: Hornet in the first area, with the HUD and the "Bind" hint*

![Profile selection screen (Select Profile)](img/silksong-profiles.jpg)
*Profile selection screen (Select Profile)*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Executable and modules converted** | The dump's SELF files (eboot and sce_module) were converted to ELF, Unity's Media/Modules and Media/Plugins modules included. |
| ✅ | **Unity modules linked** | Il2cppUserAssemblies and PS5Util are linked with the executable. The plugins (PSN, SaveData, Share...) are prepared separately and loaded at run time. |
| ✅ | **"PSN old version" error fixed** | The plugins now receive their start arguments: fablevoid's macOS relinker fix (1b865fc3e), which came through upstream. |
| ✅ | **Plugin dependencies** | The libc and libSceNpCppWebApi dependencies of the plugins under Media/Plugins are now found. |
| ✅ | **Rosetta + AVX crash fixed** | Unaligned 256-bit stores that cross a page boundary are split in two (upstream #4194). 55,017 stores were split in the executable. |
| 🔧 | **Occasional crash** | In one of two five-minute runs it segfaulted at second 293, with no crash report. Under investigation. |
| ⏭️ | **Performance** | FPS drops in game; the Rosetta and MoltenVK layers and GPU synchronization will be looked at. |

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

- [Upstream #4194 (splitting 256-bit stores)](https://github.com/boykopovar/AnyPS5/pull/4194)
- [Upstream #3731 (60 FPS report on Linux)](https://github.com/boykopovar/AnyPS5/issues/3731)
