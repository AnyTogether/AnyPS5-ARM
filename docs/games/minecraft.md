[← All games](README.md) · **English** · [Türkçe](tr/minecraft.md)

# Minecraft

`PPSA17221` · Bedrock Edition (v1.21.43) · Render Dragon, Coherent Gameface UI

**Status:** 🟡 Reaches a world, crashes about 20 s in · **FPS:** menus 60 · in game ~7-8 (M3 Pro, 1080p output)

The first try went far: the title screen, the main menu, world creation and loading all run at a steady 60 FPS, and a new survival world loads with the HUD, the hearts, hunger and the hotbar. About 20 seconds after the world appears the game stops with `create direct memory backing: Too many open files`: every direct memory block holds its own file descriptor on macOS and the world's allocations run out of them. In the world the frame rate drops to ~7-8 FPS, and like Stray the GPU is idle most of each frame.

![Title screen](img/minecraft-title.jpg)
*Title screen, 60 FPS*

| | |
|---|---|
| ![Main menu](img/minecraft-menu.jpg) | ![World list](img/minecraft-worlds.jpg) |
| *Main menu* | *World list* |
| ![Loading a world](img/minecraft-loading.jpg) | ![Spawning in](img/minecraft-spawn.jpg) |
| *Loading a world* | *Spawning in* |

![In the world](img/minecraft-ingame.jpg)
*In a new survival world*

Captured on 15 October 2026 from main (`7759cfca6`), relinked with `--module-dir .` so the four modules in the game folder (`libcohtml`, `libRenoirCore`, `libfmod`, `MediaDecoders`) are converted too.

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Starts** | The eboot and every `.prx` are fake-signed SELFs; `tools/unwrap_self.py` turns each into an ELF before relinking. |
| ✅ | **Menus** | Title screen, main menu, Play, world creation and loading at 60 FPS. |
| ✅ | **Into a world** | A new survival world loads with the HUD. |
| 🟡 | **"Get started" panels** | The panels of the first-run setup screens draw their header and frame but not their contents. |
| ⏭️ | **Open file limit** | `Too many open files` while creating direct memory about 20 s into the world. On macOS each direct memory block is its own POSIX shared memory object with a descriptor; the fix is to back them with fewer objects or a higher limit. |
| ⏭️ | **FPS in the world** | ~7-8 FPS: the GPU works ~10 ms per frame with 110-130 ms idle gaps, so the driver thread is the limit, as in Stray. |

✅ done · 🟡 partly · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Engine | `Bedrock Edition, Render Dragon` |
| Extra modules | `libcohtml.Prospero, libRenoirCore.PS5, libfmod, MediaDecoders.Prospero` |
| Relink | `relinker --macos --to-rosetta --module-dir . eboot.bin out/eboot` |
| Menus | `600 presents per 10 s` |
| In the world | `69-84 presents per 10 s, GPU busy ~10 ms per frame` |
| Now | `Reaches a world, crashes on the open file limit` |
