# Apple Silicon (macOS) port: fork status

This branch combines current `main` with the community macOS port from [mugurc/AnyPS5 `macos-port`](https://github.com/mugurc/AnyPS5/tree/macos-port), which upstream is reviewing in pieces (#927, #1597, #1499, #1686). It adds the fixes needed to build and run on top of current `main`.

Guest code stays x86-64 and runs under Rosetta 2. The relinker writes Mach-O (`--macos`), the prx libraries build as x86-64 dylibs, and Vulkan runs through MoltenVK. Apple has announced that macOS 27 is the last release with full Rosetta support, so this route has a limited lifetime.

## Build

```sh
git submodule update --init --recursive
cmake -S . -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -DBUILD_TESTING=ON
ninja -C build-mac all libs
```

Requirements:

- Xcode command-line tools
- Rosetta 2
- Ninja
- the [Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac) (universal loader and MoltenVK)
- for the guest fixtures only: `brew install llvm lld`

## Run

```sh
build-mac/core/relinker/relinker --macos --to-rosetta source/eboot.bin out/eboot
python3 tools/package_macos_app.py --relinked out --game source --libs build-mac/core/libs/libs --vulkan ~/VulkanSDK/<version>/macOS Title.app
```

## Status

Measured on an M3 Pro with macOS 26.6, Vulkan SDK 1.4.363.0 and MoltenVK:

| Check | Result |
|---|---|
| Full build (all targets and 115 prx libraries) | builds |
| `macos_fixtures`: argv, imports, TLS, C++ exceptions, C cleanup, threads, modules, TLS across modules, `--to-intel` | 10/10 run under Rosetta |
| Breakout guest (video out, pad, audio out), relinked and packaged as `.app` | runs at about 60 fps |
| ctest, full suite on MoltenVK | 832 tests: 775 pass, 43 skip features the device lacks (64-bit atomics, Float64, mesh shaders), 14 fail |
| Dreaming Sarah (PPSA02929), relinked with `--macos --to-rosetta`, packaged as `.app` and opened from Finder | runs the animated main menu at 60 fps (about 18 fps before the write watch) |

The 14 tests that fail (macOS 26.1, MoltenVK 1.4.2):

- **Apple GPU or Metal limits (4):** `f32_dot2_rounding` needs the Float64 capability, `f32_constant_factor_tininess` gets a product flushed to zero where RDNA2 keeps the smallest normal, `float16_rounding` gets a differently rounded `v_mul_f16` product, and `pixel_interlock` needs fragment shader interlock, which SPIRV-Cross cannot write as MSL.
- **A product that should give `-0.0` gives `+0.0` (4):** `f32_denormal_flush`, `f32_output_modifier`, `packed_alu`, `sdwa_float_selectors`. See [TechnicalDebt](TechnicalDebt.md).
- **Host platform (5):** `agc_thread_priority_refused_rt`, `agc_thread_priority_refused_high` and `agc_driver_pm4_priority_refused` expect a refused priority request to throw, `agc_shared_write` cannot inspect mapping lifetimes, and `check_skips` passes from the repository root but not from the working directory ctest gives it.
- **`patched_libraries`:** loads all patched libraries and exceeds the 300 s test timeout only when the whole suite runs in parallel after a rebuild; it passes alone.

`macos_fixtures` passes once on a fresh build and times out in every later run: its `argv` fixture, which ends with `int3`, stays exiting in the kernel under Rosetta until a reboot. It was left out of the run above. A title quit with Cmd-Q while the write watch was on showed the same state (`ps` state `UNE`, every thread asleep, memory held until a reboot; `APS5_NO_WRITE_WATCH=1` quit cleanly): `exit` ran the host static destructors while guest threads kept storing into the watch's protected pages, the destroyed watch's handler fell through to the default action, and the signal death hung in the kernel. `exit` now disarms the watch and ends the process with `_Exit` after the guest handlers (see [TechnicalDebt](TechnicalDebt.md)); a process that dies by a signal under Rosetta still hangs the same way.

Changes on top of the merged port:

- [GuestMemory.cpp](../../core/libs/prx/libSceAgcDriver/Execution/src/GuestMemory.cpp) and [DynamicLoader.cpp](../../core/libs/prx/libkernel/Module/src/DynamicLoader.cpp) compile on macOS. `main` had added Linux-only code to both after the port was based.
- When the device has no `robustness2.nullDescriptor` (MoltenVK), the empty slots of the typed image heaps bind zeroed [placeholder images](../../core/libs/prx/libSceAgcDriver/Graphics/src/PlaceholderImages.cpp). Before this, every draw and dispatch failed on macOS.
- Shader stages without host subgroups (MoltenVK: vertex and tessellation evaluation) run each invocation as a one-lane wave instead of failing validation.
- Guest thread destructors register through `_tlv_atexit`. libSystem's `__cxa_thread_atexit` returns void, and reading its result as an int freed a live registration twice.
- `dlsym`'s default scope finds the main program through dyld.
- Guest `mprotect` rounds to 16 KiB pages relative to the guest image's load bias. dyld only aligns a slide to 4 KiB, so rounding the absolute address protected the wrong pages (SIGBUS in Dreaming Sarah). Guest segments get maxprot rwx, and the image's no-access padding segments are registered.
- Without storage MSAA, multisampled image dimensions are emitted single-sample. This matches the single-sample images the driver creates; Dreaming Sarah's first shader clears an MSAA surface with `image_store`.
- Merged upstream #1653: no fragment barycentric on MoltenVK. SPIRV-Cross cannot write `PerVertexKHR` to MSL.
- macOS has a guest [write watch](../../core/libs/prx/libc/src/GuestWriteWatch.cpp). Without it the driver compared guest memory before every draw, a third of Dreaming Sarah's frame time; it write-protects watched pages and records the first write to each in a fault handler. See [TechnicalDebt](TechnicalDebt.md) for its costs and limits.
- Packaged titles start from Finder: `Contents/MacOS/app0` links to the game folder, where the executable loads its guest modules, and the soft open-file limit (256 for apps Finder opens) is raised when direct memory runs out of descriptors.
- MoltenVK's Metal argument buffers are enabled through `VK_EXT_layer_settings`. Together with upstream #1580 (merged here), they lift the 31 storage buffers per stage limit.
- Test fixes for macOS:
  - case-insensitive APFS in `guest_path_case`
  - the portability loader in `oversized_descriptor_sets`
  - the fixtures' temporary directory, about 720 MiB per run, is now cleaned up

## Feasibility probes

[tools/macos/spikes](../../tools/macos/spikes) holds the probes used to choose this route:

- gs TSD reads
- AVX2, FMA and BMI2
- JIT code
- fs base: unavailable under Rosetta
- the guest arena layout
- MoltenVK features

Run them with `run.sh [libMoltenVK.dylib]`.
