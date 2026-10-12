[← All games](README.md) · **English** · [Türkçe](tr/stray.md)

# Stray

`PPSA02100` · Unreal Engine 4

**Status:** 🔴 Does not start · Crashes at startup (regression) · **FPS:** —

The root cause of the earlier corruption is understood. Since the latest upstream merges, though, the game crashes already at startup. That regression is being investigated.

![Earlier run: with GPU results written back immediately, the save screen drew completely](img/stray-saveselect.jpg)
*Earlier run: with GPU results written back immediately, the save screen drew completely*

## Step by step

| | Stage | Details |
|---|---|---|
| ✅ | **160 GiB buffer crash** | Indices past every vertex record count are redirected to a single zero vertex (upstream PR #4292). |
| ✅ | **Root cause: late write-back** | GPU results were written to memory late and overwrote memory the game had already reused. With immediate write-backs, menus and text drew completely (screenshot above). |
| ✅ | **Write watch bug** | Memory mapped over a reservation was not watched (fixed upstream). |
| 🔧 | **Startup regression** | While Unreal's allocator is being set up: atexit → the game's libc → malloc → an allocator that is not ready yet. It came with the latest merges; the responsible change still has to be found. |
| ⏭️ | **Fast write-back fix** | A version that limits immediate write-backs to memory that cannot be watched is ready and will be tested. |

✅ done · 🔧 in progress · ⏭️ next

## Technical details

| | |
|---|---|
| Engine | `Unreal Engine 4` |
| Split 256-bit stores | `211,077` |
| Last working state | `Menu/save screen (with immediate write-back, ~0.4 FPS)` |
| Now | `Segfault at startup` |

## Links

- [Upstream PR #4292](https://github.com/boykopovar/AnyPS5/pull/4292)
