[← All games](README.md) · **English** · [Türkçe](tr/doom.md)

# DOOM (homebrew)

`PPSA99666` · lowbit/ps5-doom

**Status:** 🟢 Playable · E1M1 onwards · **FPS:** 35 (the game's own target)

Plays in game. The relinker now recognizes the empty placeholder functions in the packaged libc.prx and binds the system's real implementations in their place.

![E1M1: HUD, weapon and Doomguy's face](img/doom-e1m1.jpg)
*E1M1: HUD, weapon and Doomguy's face*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Conversion and packaging** | Homebrew package, SELF → ELF, with its own libc.prx. |
| ✅ | **Root cause found** | In the packaged libc.prx, exports such as memset and snprintf are placeholders that only return 0; the real ones are in the system's libSceLibcInternal. On macOS the guest export won, so logs and messages stayed empty and the game could not find its WAD. |
| ✅ | **General relinker rule** | On macOS, guest exports that only return 0 (the `xor eax,eax; ret` and `pxor xmm0` forms) are left to the host library; real functions still use the guest's. This is the macOS counterpart of the Windows loader's ZeroReturnExports rule. |
| ✅ | **Playable** | It finds the WAD and enters E1M1 and later maps; checked together with Dreaming Sarah, PvZ and Silksong. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Source | `github.com/lowbit/ps5-doom v1.1.1` |
| Presentation | `CPU rendering + AGC compute copy` |
| WAD | `doom1.wad (shareware)` |
| Relinker test | `macos_placeholder_exports` |

## Links

- [ps5-doom source code](https://github.com/lowbit/ps5-doom)
