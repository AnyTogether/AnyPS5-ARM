[← All games](README.md) · **English** · [Türkçe](tr/stray.md)

# Stray

`PPSA02100` · Unreal Engine 4

**Status:** 🟡 Main menu · Entering the game is not verified yet · **FPS:** ~18-20 in the main menu (M3 Pro, 1080p patch)

The game starts again and reaches its main menu. The macOS package applies a 1080p output patch (see below); without it the PS5 build renders at 3840x2160 and the menu runs at ~11 FPS.

![Earlier run: with GPU results written back immediately, the save screen drew completely](img/stray-saveselect.jpg)
*Earlier run: with GPU results written back immediately, the save screen drew completely*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **160 GiB buffer crash** | Indices past every vertex record count are redirected to a single zero vertex (upstream PR #4292). |
| ✅ | **Root cause: late write-back** | GPU results were written to memory late and overwrote memory the game had already reused. With immediate write-backs, menus and text drew completely (screenshot above). |
| ✅ | **Write watch bug** | Memory mapped over a reservation was not watched (fixed upstream). |
| ✅ | **Startup regression** | Fixed: a quadratic shader pass and a blocked signal mask around thread creation. |
| ✅ | **Shader arithmetic** | Pixel and compute shaders no longer turn every f32 add and mul into an unoptimized helper call under MoltenVK (the hottest shader: 17 → 5 ms). |
| ✅ | **1080p output** | The PS5 build hardcodes 3840x2160 output. [tools/macos/patches/PPSA02100.json](../../tools/macos/patches/PPSA02100.json) sets it to 1920x1080; `tools/package_macos_app.py` applies it (`--no-game-patches` skips it). |
| 🔧 | **Menu FPS** | At 1080p the driver thread is the limit (~52 ms per frame, GPU ~31 ms): GPU syncs, write-backs and queue submits. |
| ⏭️ | **Entering the game** | Write-backs in game still have to be verified. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Engine | `Unreal Engine 4` |
| Split 256-bit stores | `211,077` |
| Output | `1920x1080 with the patch, 3840x2160 without` |
| Now | `Main menu, ~18-20 FPS` |

## Links

- [Upstream PR #4292](https://github.com/boykopovar/AnyPS5/pull/4292)
