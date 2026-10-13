# Build

## Relinker only

The relinker can be built without initializing submodules or configuring SDL, Vulkan, FFmpeg, FreeType or the shader recompiler. It requires CMake, a C++20 compiler and a build tool. Python 3 enables the Python regression tests.

```sh
cmake -S . -B build-relinker -G Ninja -DCMAKE_BUILD_TYPE=Release -DANYPS5_RELINKER_ONLY=ON -DBUILD_TESTING=ON
cmake --build build-relinker --parallel
ctest --test-dir build-relinker --output-on-failure
```

Python must be found during CMake configuration for Python tests to be registered. List registered tests with `ctest --test-dir build-relinker -N` and look for `input_magic`, a Python-backed relinker test. If automatic discovery fails, add `-DPython3_EXECUTABLE="C:/path/to/python.exe"` to the configure command, using the path to your Python interpreter, then list the tests again.

This mode builds the conversion tool and its tests on Linux, Windows and macOS, including Apple Silicon. macOS uses AppleClang from the Xcode command-line tools; Windows uses the MinGW-w64 toolchain below. The executable is `build-relinker/core/relinker/relinker` (`relinker.exe` on Windows with Ninja).

The output remains x86-64 Linux ELF or Windows PE. Converted games need system libraries built for the target OS and a compatible x86-64 host. This mode does not build those libraries or provide macOS game execution. Tests inspect both output formats; execution checks run only on their compatible hosts.

Use a separate build directory for the full build.

## Full build

```sh
git submodule update --init --recursive
```

## Requirements

- x86-64, Git, CMake 3.22.1 or newer, Ninja, C++20.
- Linux display refresh queries require SDL's XRandR support (`libxrandr-dev` on Debian/Ubuntu; `libXrandr-devel` on Fedora). Bundled SDL configuration fails without it. Keep `SDL_X11_XRANDR` enabled.
- Linux: GCC, G++, binutils. SDL's X11 backend requires X11 and Xext development headers (`libx11-dev` and `libxext-dev` on Debian/Ubuntu). Audio output needs SDL's PipeWire, PulseAudio or ALSA backend, built from their development files (`libpipewire-0.3-dev`, `libpulse-dev` and `libasound2-dev` on Debian/Ubuntu; `pipewire-devel`, `pulseaudio-libs-devel` and `alsa-lib-devel` on Fedora). SDL loads them at run time. Without any of them SDL keeps only its silent dummy and disk drivers, so configuration fails.
- Fedora: if CMake reports `Could NOT find Threads`, install `glibc-static` and `libstdc++-static` with `sudo dnf install glibc-static libstdc++-static`, then rerun configuration. The project enables static executable linking, and FFmpeg's thread check needs these libraries.
- Windows: only MinGW-w64 GCC 15.2.0 (WinLibs `x86_64-ucrt-posix-seh`, release `15.2.0posix-14.0.0-ucrt-r7`) is currently supported. Add its `mingw64/bin` directory to `PATH` before configuring.
- Windows antivirus software can quarantine the executables that the relinker tests create in the temp directory, which fails `optional_plt`, `empty_tls`, `windows_address_space` and `windows_icon`. Set `TEMP` and `TMP` to a directory the scanner excludes before running `ctest`.
- FFmpeg binaries are downloaded during configuration unless `FFMPEG_PREBUILT_DIR` is set. With the WinLibs CMake, the download fails with status 60 (`SSL peer certificate or SSH remote key was not OK`) unless `SSL_CERT_FILE` names a CA bundle, for example `C:\Program Files\Git\mingw64\etc\ssl\certs\ca-bundle.crt` from Git for Windows, as in CI.

## Commands

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
cmake --build build --parallel
cmake --build build --target libs --parallel
```

`libs` is a custom target: every library under [core/libs/prx](../../core/libs/prx) is built with
`EXCLUDE_FROM_ALL`. With the default `BUILD_TESTING=OFF`, the default build does not produce them,
so the explicit `--target libs` step is required. With `BUILD_TESTING=ON`, the default full build
also builds `libs` through the `patched_libraries_tests` dependency. Titles load the patched `.prx`
files from `build/core/libs/libs`; running a title after a library change without rebuilding `libs`
therefore tests the previous binaries and can show no effect at all.

[Relinker usage and runtime layout](../user/USAGE.md).

## CMake flags

Project switches accept `ON` or `OFF`:

| Flag                             | Default | Effect                                           |
|----------------------------------|---------|--------------------------------------------------|
| `-DBUILD_TESTING=ON`             | `OFF`   | Build and register tests.                        |
| `-DANYPS5_RELINKER_ONLY=ON`      | `OFF`   | Build only the relinker and its tests, without third-party dependencies. |
| `-DANYPS5_ENABLE_SPIRV_TOOLS=ON` | `OFF`   | Enable SPIR-V validation and optimization.       |
| `-DANYPS5_ENABLE_ASAN=ON`       | `OFF`   | Build with AddressSanitizer on Linux and move the guest arena out of ASan's shadow gap. |
| `-DANYPS5_USE_SYSTEM_DEPS=ON`    | `OFF`   | Resolve SDL2, freetype, Vulkan-Headers, SPIRV-Headers, glslang and SPIRV-Tools from the system instead of the submodules. |
| `-DAPS5_ENABLE_TIMING_LOG=ON`    | `OFF`   | Compile frame timing logging.                    |
| `-DAPS5_ENABLE_TRACY=ON`         | `OFF`   | Build the [Tracy](#tracy) profiler client into the agc driver. |
| `-DAPS5_AGC_CREATE_LOG=OFF`      | `ON`    | Disable successful `sceAgcCreateShader` logging. |
| `-DAGC_BUILD_VISUAL_TEST=ON`     | `OFF`   | Build the standalone AGC SPIR-V visual test.     |

Build configuration parameters:

| Flag                                   | Value                                                              |
|----------------------------------------|--------------------------------------------------------------------|
| `-DCMAKE_BUILD_TYPE=Release`           | `Debug`, `Release`, `RelWithDebInfo`, or `MinSizeRel`.             |
| `-DCMAKE_C_COMPILER=gcc`               | C compiler name or absolute path.                                  |
| `-DCMAKE_CXX_COMPILER=g++`             | C++ compiler name or absolute path.                                |
| `-DCMAKE_C_COMPILER_LAUNCHER=ccache`   | Optional C compiler cache; requires `ccache`.                      |
| `-DCMAKE_CXX_COMPILER_LAUNCHER=ccache` | Optional C++ compiler cache; requires `ccache`.                    |
| `-DFFMPEG_PREBUILT_DIR=<path>`         | Unpacked FFmpeg package for the target platform; empty by default. |

SDL and FreeType settings forced by the root `CMakeLists.txt` cannot be overridden with `-D`.

With `ANYPS5_USE_SYSTEM_DEPS=ON` those libraries come from the system (on Debian and Ubuntu: `libsdl2-dev`, `libfreetype-dev`, `libvulkan-dev`, `spirv-headers`, `glslang-dev`, `glslang-tools` and `spirv-tools`). A missing package, Vulkan-Headers older than 1.4.310 (the agc driver uses `VK_KHR_maintenance8`), or an SDL2 without the HIDAPI joystick driver (sdl2-compat over SDL3, or a build with HIDAPI disabled, which breaks the pad and disk-audio tests), fails the configure with an error and never falls back to the submodule. The forced SDL and FreeType settings from the root `CMakeLists.txt` do not apply with the flag ON: the system SDL2 comes with whatever its distribution enabled. The prx libraries are shared objects, so SDL2 is linked from the system as a shared library; the default build keeps its own static SDL2. `ffmpeg-core`, `libjpeg-turbo`, `stb`, `VulkanMemoryAllocator` and `LibAtrac9` always stay bundled and still need `git submodule update --init`.

## Write watch tests

The macOS write watch can be built and tested separately, without submodules or the prx libraries:

```sh
cmake -S core/libs/tests/write_watch -B build/write-watch -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
cmake --build build/write-watch
ctest --test-dir build/write-watch --output-on-failure
```

With `CMAKE_OSX_ARCHITECTURES=x86_64` Apple silicon runs the tests through Rosetta, which is how relinked titles run; without it they run natively. The full `BUILD_TESTING` build on macOS also registers them.

## Tracy

`-DAPS5_ENABLE_TRACY=ON` builds the [Tracy](https://github.com/wolfpld/tracy) 0.14.1 client from `3rdparty/tracy` as a shared library next to the patched `.prx` files (`libTracyClient.dll`, `libTracyClient.so.0.14.1` on Linux); copy it with them. Every `PerformanceTimer` scope of libSceAgcDriver and libSceVideoOut is a zone, every presented flip ends a frame, and the queue workers and the presenter are named threads. Connect the Tracy 0.14.1 profiler to `127.0.0.1`: the client listens only on localhost and records only while a profiler is connected. Sampling, system tracing, call stacks, code transfer and Tracy's crash handler are disabled. Without the flag nothing of Tracy is built.

On Windows MinGW frees `thread_local` objects before their destructors run, so the Tracy client is built without `thread_local` destructors and never destroys its event queue: a thread that emitted a zone and ended keeps its event blocks (2 MiB each) until the process exits.

## Compute pipeline replay

Build `agc_compute_pipeline_replay` in the full build with `-DANYPS5_ENABLE_SPIRV_TOOLS=ON`; replay validates the captured module before calling Vulkan. Set `APS5_DUMP_COMPUTE_PIPELINES` to a dedicated empty directory before starting a title to save each uncached compute pipeline's final SPIR-V, descriptor layouts, push constant ranges, specialization values, subgroup size and creation flags before compilation. Files are named `compute-<identity>/capture.aps5cp`; identical records are deduplicated. Capture stops with an error at 128 records, 256 MiB total or 36 MiB per record (at most 8,388,608 SPIR-V words, or 32 MiB of shader code). Capture files contain shader code and device metadata, but no guest buffers or textures; review them before sharing.

Set `APS5_DUMP_COMPUTE_MIN_WORDS` to capture only modules at or above that SPIR-V word count, for example `100000` when investigating large NVIDIA compilations. The default is `0` (all modules); values outside `0` through `8388608` fail. The filter applies only when capture is enabled.

```sh
cmake --build build --target agc_compute_pipeline_replay
build/core/libs/prx/libSceAgcDriver/agc_compute_pipeline_replay capture.aps5cp --cache-out pipeline.cache --output fresh.json
build/core/libs/prx/libSceAgcDriver/agc_compute_pipeline_replay capture.aps5cp --cache-in pipeline.cache --output imported.json
```

On Windows use `agc_compute_pipeline_replay.exe` and prepend `build/core/libs/libs/unpatched` to the process `PATH`. `ANYPS5_GPU` selects a device by name as for the driver. The tool uses the driver's compute pipeline creation path, without recording commands, dispatching work or importing guest memory. Compile-only devices also enable supported partially-bound, variable-count and runtime-array descriptor features to replay captured layouts; ordinary runtime devices are unchanged. Binding flags are preserved independently of update-after-bind. Replay accepts the unconditional Vulkan 1.0 capabilities listed in the pinned [Vulkan registry](https://github.com/KhronosGroup/Vulkan-Headers/blob/2fa203425eb4af9dfc6b03f97ef72b0b5bcb8350/registry/vk.xml); other capabilities must be enabled by the device target. Non-Vulkan capabilities such as Kernel and unknown capabilities fail before pipeline creation. Unsupported features, non-highest variable bindings and counts exceeding layout support fail explicitly. Unsupported inputs and mismatched cache vendor, device or UUID fail explicitly. Output files must not already exist.

Each invocation creates one pipeline. With no `--cache-in`, its application pipeline cache starts empty; `--cache-in` imports a raw cache previously written by `--cache-out` (at most 64 MiB), and `--cache-out` exports the resulting cache. The title's wrapped `vk-pipelines-*.bin` format is not accepted. It does not load or save the title's usual pipeline cache. NVIDIA and other driver caches remain uncontrolled: a fresh application cache is not a cold driver cache. JSON reports the capture identity, GPU/driver identifiers, word count, cache policy and separate wall times for shader module, layouts, pipeline creation and cache work. Device initialization is outside these timings. Pipeline statistics captures and `APS5_PIPELINE_STATS` are refused because they change compilation cost.

`--fixture` compiles a tiny synthetic compute shader with specialization, sparse descriptor binding and push constant metadata; `--write-fixture DIRECTORY` saves it without opening Vulkan. It performs no GPU work and does not reproduce a title's compile workload. With `BUILD_TESTING=ON`, `agc_compute_pipeline_capture` checks serialization and rejected inputs. With SPIRV-Tools also enabled, `agc_compute_pipeline_replay` compiles the fixture with fresh and imported application caches, verifies cache rejection, and checks required subgroup support. `agc_compute_pipeline_capture_run` verifies the existing branch-past-endpgm compute fixture's output with capture disabled and enabled, then replays the captured pipelines and checks their identities and metadata. Each test has a 30-second timeout. Runtime tests skip when Vulkan is absent; set `ANYPS5_REQUIRE_VULKAN=1` to require execution. There is no performance pass threshold.

## Pipeline statistics

Set `APS5_PIPELINE_STATS=1` to capture and print driver statistics for each newly created graphics or compute pipeline. This requires `VK_KHR_pipeline_executable_properties` and `pipelineExecutableInfo`; an unsupported device fails with an error. Statistic names and units are driver-specific. Capturing statistics can increase pipeline compilation cost. The setting is disabled by default.

## Worker sampler

Set `APS5_SAMPLE_WORKER=<file>` to sample queue worker 0 every millisecond (in practice every timer tick). Every 20 s and at exit it writes `<file>`, one `module offset self inclusive` line per sampled address, and `<file stem>.collapsed.txt`, the worker's whole stacks in the collapsed format that speedscope.app and flamegraph.pl read: one `frame;...;frame count` line per distinct stack, root first, each frame as `module+0xRVA`. A walk that ends before the thread's root starts with `[truncated]`. The `#` lines give the samples, the walk depth (64 frames), the truncated walks, the mean and longest time the worker was suspended, and the size and PE timestamp of each module, to check the binary a file is symbolized against. A frame with `.pdata` is stepped by `RtlVirtualUnwind`; any other frame by its DWARF record in `.ehfram`, the unwind data the libraries are built with. Those steps read only inside the worker's stack, and a module is indexed after the worker resumes, the first time a walk meets it.

`APS5_SAMPLE_THREADS=<file>` samples every thread of the process every 2 ms and writes the 40 hottest addresses of each busy thread to `<file>`, 12 frames deep and through `.pdata` only. Both samplers exist only on Windows; the addresses are symbolized offline, for example with `nm` on the `.prx`.

## Performance trace

Set `APS5_TRACE_FRAMES=<start>:<count>` to record `<count>` presents from present `<start>` (counted from 0), or `APS5_TRACE_SECONDS=<start>:<length>` to record from the first present at least `<start>` seconds after the first present until the first present `<length>` seconds later. Both values are whole numbers and the length is above 0; a malformed value, or both switches together, fails the first present. The window opens and closes at presents.

Inside the window the queue workers and the presenter record every `PerformanceTimer` scope and stage as a complete event named after its frame timing key: `Driver.WorkerWait`, `Driver.Packet`, `Driver.Packet.draw`, `Graphics.Draw`, `Driver.Present`, `Driver.Present.inflight_wait`, `Vulkan.Retire` and so on. A slice shorter than 20 us is only counted: its time is in the thread's counter `<thread> folded` (milliseconds per present) and in the summary. A thread writes a present's counter sample at its first slice after the next present, so the last present of the window has no sample; its time is still in the summary. Each thread allocates a buffer for 262,144 events when it starts; a full buffer stops that thread's recording and sets `trace_dropped`. When the window closes, the presenter formats the trace once and a `ProfileOutput` writer thread writes `aps5-trace-<commit>-<pid>.json.gz` (Chrome trace-event JSON, opened by ui.perfetto.dev or chrome://tracing) and appends one line to `aps5-summary.jsonl`, both in `APS5_TRACE_DIR` or the working directory. A window that is still open when the title exits writes nothing.

The summary line has `commit` and `dirty` of the build, `env` (every `APS5_*` variable; a value containing `/` or `\` is written as `<path>`), `gpu`, `driver`, `os`, `resolution` (the video output's), `window`, `presents`, `frame_ms` (p50, p90, p99 and max of the intervals between presents), `gpu_busy_ms_per_present` (the batch timestamps behind `[present]`), `worker_busy_pct` (share of the window each queue worker spends in `Driver.Packet`, `Driver.Suspend`, `Driver.EndSubmission`, `Driver.Rewind` and `Driver.Completion`), `top_phases_ms_per_frame` (the eight largest scopes and stages, without `Driver.WorkerWait`), `trace_dropped` and `trace`. A trace holds timings, scope names, counts and thread names; no guest memory, paths or strings of the title.

The shader preparation threads are traced as well, `shader prepare`, with a buffer for 32,768 events each. A wait for the GPU mutex on a traced thread is a `GpuMutex.wait.<site>` slice (`dispatch`, `draw`, `present`, `flush` and so on, as on the `[lock]` line).

The `gpu` track holds one `batch` slice per recorder batch, from the batch's timestamp pair. With `APS5_PROFILE_GPU=1` it also holds a slice per command class range, under the class names of the `[gputime]` line (`draw`, `copy`, `fill`, `present-blit`, ...); program ranges are left out. The track keeps up to 262,144 ranges; more set `trace_dropped`. The GPU clock is mapped onto the CPU clock with calibrated timestamps (`VK_KHR_calibrated_timestamps` or the EXT version, enabled only when a trace switch is set) taken when the window opens and when it closes, so the two clocks are matched at both ends of the window. A batch is added when the driver reads its timestamps, after its fence signals, so the batches of the last frames of the window, which complete after it closes, are missing. Without calibrated timestamps the trace has no `gpu` track, and the `[trace]` line says so.

With either switch set, the recorder writes a timestamp pair per batch for the whole run, as with `APS5_PROFILE_DRAW`. Without them, a `PerformanceTimer`, a GPU mutex acquisition and a read of batch timestamps each cost one more predictable branch.

## Driver thread priority

Set `APS5_THREAD_PRIORITY=high` to raise the AGC driver's queue workers and the video output presenter above the title's threads. On Linux the threads get nice `APS5_THREAD_NICE` (default -10) through rtkit; on Windows they get `THREAD_PRIORITY_HIGHEST`. `APS5_THREAD_PRIORITY=rt` asks rtkit for real-time priority `APS5_THREAD_RT` (default 10, at most rtkit's `MaxRealtimePriority`) under rtkit's policy, `SCHED_RR` by default; on Windows it sets `THREAD_PRIORITY_TIME_CRITICAL`. rtkit only grants it when the process's hard `RLIMIT_RTTIME` is at most its `RTTimeUSecMax` (200000 us by default), so a hard limit above `APS5_THREAD_RTTIME_US` (default 200000, capped at `RTTimeUSecMax`) is lowered to it and the soft limit to at most half of it. The hard limit cannot be raised again and stays lowered for the whole process even if rtkit then refuses; see [technical debt](TechnicalDebt.md#functional). There is no fallback between the modes: when rtkit or `SetThreadPriority` refuses, a queue worker reports the refusal as a driver failure, which the next submission, wait or shutdown rethrows, and the presenter's start throws it. Each raised thread logs its priority once as `[thread-priority]`. The setting is `off` by default; a value other than `off`, `high` or `rt` is reported the same way as a refusal.

## Shader recompiler

The shader recompilation logic in [core/shader/recompiler](../../core/shader/recompiler) is isolated from the rest of the project and is a pure function of its input data, designed for integration into any other project. The current CMake target also includes cache support and links a supplied runtime target, glslang, and optionally SPIRV-Tools.

## Register context tests

The x86-64 register capture and restore tests can be built separately on Linux and macOS, without submodules or the prx libraries. On macOS:

```sh
cmake -S core/libs/tests/register_context -B build/register-context -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
cmake --build build/register-context
ctest --test-dir build/register-context --output-on-failure
```

On Linux x86-64, omit `CMAKE_OSX_ARCHITECTURES`; the full `BUILD_TESTING` build also registers these tests. Apple silicon runs the x86-64 tests through Rosetta. They cover the unwinder's register transfer, not the complete macOS runtime or guest exception handling.
