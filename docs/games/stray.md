[← All games](README.md) · **English** · [Türkçe](tr/stray.md)

# Stray

`PPSA02100` · Unreal Engine 4

**Status:** 🟢 Playable, first chapter without problems · **FPS:** ~12 in game (M3 Pro, 1080p)

The first chapter plays from start to end: the opening in the overgrown pipes, the cat family, the climbs and the cardboard nap. The picture is right, with no missing or broken graphics. The frame rate is still low: ~12 FPS in game, up from ~7.6 at the start of the macOS performance work.

![The opening in the overgrown pipes](img/stray-opening.jpg)
*The opening in the overgrown pipes*

![The cat family](img/stray-family.jpg)
*The cat family*

| | |
|---|---|
| ![Light under the wall](img/stray-sunlight.jpg) | ![The cardboard nap](img/stray-cardboard.jpg) |
| *Light under the wall* | *The cardboard nap* |

![Under the vines](img/stray-vines.jpg)
*Under the vines*

Captured on 15 October 2026 from main after the third upstream merge (`cc213ee99`), at 1920x1080.

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **160 GiB buffer crash** | Indices past every vertex record count are redirected to a single zero vertex (upstream PR #4292). |
| ✅ | **Root cause: late write-back** | GPU results were written to memory late and overwrote memory the game had already reused. With immediate write-backs, menus and text drew completely. |
| ✅ | **Write watch bug** | Memory mapped over a reservation was not watched (fixed upstream). |
| ✅ | **Startup regression** | Fixed: a quadratic shader pass and a blocked signal mask around thread creation. |
| ✅ | **Shader arithmetic** | Pixel and compute shaders no longer turn every f32 add and mul into an unoptimized helper call under MoltenVK (the hottest shader: 17 → 5 ms). |
| ✅ | **Output resolution** | The PS5 build hardcodes 3840x2160 output. With [tools/macos/patches/PPSA02100.json](../../tools/macos/patches/PPSA02100.json), applied by `tools/package_macos_app.py` (`--no-game-patches` skips it), the bundle asks for 720p, 900p, 1080p (default), 1440p or 4K when it starts; `APS5_RESOLUTION=1280x720` answers in advance. |
| ✅ | **PlayGo without metadata** | The dump has no `playgo-*` file. Upstream now refuses every chunk id but 0 for such a dump, and Stray asks for chunk 1 at startup; the port takes it as fully installed. |
| ✅ | **Loading crash** | About one start in ten stopped with "MaterialInstanceConstant ... Serial size mismatch": a file read landed in guest memory while a GPU batch still in flight held an older write-back to the same range, which then overwrote the file data. A kernel read now first flushes the GPU writes pending over its range. |
| ✅ | **First chapter** | Plays through with correct graphics. |
| ✅ | **Startup and loading** | The first seconds ran at 2 frames per 10 s and the loading screen at 15: every guest memory registration copied the write watch's state for the whole 512 GiB arena (~128 MiB) under its lock. Registrations inside it now reset their pages in place. |
| ✅ | **FPS, first steps** | ~7.6 → ~12.2 FPS in game at 1080p (+62%, 3 interleaved rounds against the start of the work): lock-free write watch and allocation queries, fewer draw pipeline drains (DMA, predication, satisfied waits, inlined indirect buffers), reused descriptor sets, evicted shader results freed on a helper thread, GPU copies recorded ahead of the render pass. |
| 🔧 | **FPS** | The limit is the driver's per-draw work on its one draw committer thread (~50 us for each of ~1000 draws a frame): resource preparation takes ~75% of it (buffer snapshots, cache lookups, vertex inputs), Vulkan recording ~2%. 720p is barely faster than 1080p. The next steps are moving that preparation off the committer and running the guest code without Rosetta. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Engine | `Unreal Engine 4` |
| Split 256-bit stores | `211,077` |
| Output | `1920x1080 with the patch, 3840x2160 without` |
| Now | `First chapter playable, ~12 FPS` |

## Links

- [Upstream PR #4292](https://github.com/boykopovar/AnyPS5/pull/4292)
