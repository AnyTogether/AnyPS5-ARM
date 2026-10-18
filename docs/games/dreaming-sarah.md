[← All games](README.md) · **English** · [Türkçe](tr/dreaming-sarah.md)

# Dreaming Sarah

`PPSA02929` · Construct 2

**Status:** 🟢 Playable · **FPS:** 60

Runs from start to finish. 2D, with a light GPU load.

![Title screen, 60 FPS](img/dreaming-sarah.jpg)
*Title screen, 60 FPS*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **Conversion** | The .esbak backup files in sce_module are removed from the working copy; the relinker took them for a second libc. |
| ✅ | **Drawing** | Barycentric interpolation is computed on the host side on MoltenVK. |
| ✅ | **Playable** | Picture, sound and controller work. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Engine | `Construct 2 (JavaScript runtime)` |
| Game data | `data.js + images/ + media/` |
| FPS | `60` |
