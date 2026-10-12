[← All games](README.md) · **English** · [Türkçe](tr/pvz.md)

# Plants vs. Zombies: Replanted

`PPSA29802` · Unity (IL2CPP)

**Status:** 🟡 Work in progress · User agreement screen · **FPS:** 60

The opening sequence draws correctly at 60 FPS, and a five-minute run did not crash once. Next is getting past the agreement into the main menu and the game.

![EA user agreement screen, 60 FPS](img/pvz-agreement.jpg)
*EA user agreement screen, 60 FPS*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Same Unity preparation as Silksong** | SELF → ELF, modules with the executable, plugins separately. |
| ✅ | **C# exceptions are caught** | An ArgumentOutOfRangeException in a date/time calculation could not be caught by the game's own code. Fixed by reporting unwind tables on macOS (PR #4, kabonKoda). |
| ✅ | **MSAA sample locations** | The game uses nonstandard sample positions with 4x MSAA. They are applied through VK_EXT_sample_locations; main now uses upstream's implementation. |
| ✅ | **MSAA memory size** | The size of the 4x MSAA target was computed 2 MB too large and overlapped a small image; fixed with AddrLib's GFX10 rule. |
| ✅ | **Rosetta + AVX crash** | Fixed by upstream #4194; 53,718 stores were split in the executable. |
| 🔧 | **Agreement screen** | Advancing with Cross does not get past the agreement; the input script for menu navigation needs adjusting. |
| ⏭️ | **Main menu and game** | In-game drawing and performance. |

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

- [PR #4: macOS unwind tables](https://github.com/utkuhalis/AnyPS5-ARM/pull/4)
- [Upstream #4194](https://github.com/boykopovar/AnyPS5/pull/4194)
