# Native arm64 (no Rosetta): design and plan

Branch `native-arm64`. The goal is to run converted titles as arm64 processes, with no Rosetta. `main` keeps the Rosetta port ([MACOS_PORT.md](MACOS_PORT.md)).

## Where Rosetta sits today

- **Guest code:** the relinked guest x86-64 code calls host prx functions directly. dyld writes host addresses into the guest's own GOT slots, and both sides use the SysV calling convention (`APS5_VABI` is empty off Windows).
- **Host code:** host code calls guest code through plain function pointers:
  - the process entry (`Aps5StartGuest`)
  - module init/fini
  - threads (`scePthreadCreate`), Ult, Fiber
  - `atexit`, `__cxa_atexit`, thread destructors, TSD destructors, once
  - signals, C++ exception callbacks and the DWARF unwinder
  - qsort/bsearch, locale facets, guest malloc replacement
  - AvPlayer, Ngs2, Font, Agc command buffer callbacks
- **Rosetta's role:** it runs all of it, guest code and prx libraries alike, because a process has one architecture.

## Approach: translate guest code ahead of time

The relinker already decodes guest code (TLS scan, `--to-intel`). In the arm64 mode it translates every discovered guest function to arm64 at conversion time. The prx libraries build natively for arm64. A first `cmake -DCMAKE_OSX_ARCHITECTURES=arm64` build fails in only 6 of about 1250 compile steps:

- `setjmp`/`longjmp` asm
- the Fiber stack switch
- the guest TLS allocate asm
- TSC reads
- a few `__builtin_ia32_*` exports
- the 80-bit `long double` asserts

### Guest state

- **Registers:** translated code keeps the x86-64 architectural state in a per-thread `GuestState`: 16 GPRs, rip, flags, the 16 ymm registers, mxcsr, and the fs base.
- **Memory is shared:** guest memory is the host address space, so guest loads and stores are plain host loads and stores at the same addresses. No MMU is emulated, and guest pointers and host pointers are the same values.
- **Stack:** the guest stack is real memory. Guest `rsp` lives in `GuestState`, and translated functions use the native stack only for their own temporaries.

### Translation

- **Pipeline:** x86-64 is decoded with Capstone and lifted to LLVM IR, one LLVM function per guest function, operating on `GuestState`. LLVM optimizes it and emits arm64.
- **Flags:** flags are computed into `GuestState` fields; LLVM drops the dead ones.
- **SIMD:** SSE and AVX map to LLVM vector types, and 256-bit operations are lowered to two 128-bit NEON operations by LLVM.
- **Function discovery:**
  - the ELF entry, `DT_INIT`/`INIT_ARRAY`
  - exported and local symbols
  - direct call targets
  - code addresses in relocations (`R_X86_64_RELATIVE` into executable segments)
  - recursive descent over basic blocks
- **Indirect jumps:** an indirect jump inside a function dispatches over that function's known block addresses.
- **Indirect calls:** they go through a runtime lookup of guest address to native function. An unknown target stops the process with its guest address.

### Calling across the boundary

- **Guest to host:** a call whose target is outside the guest code ranges is a host function. The bridge passes rdi, rsi, rdx, rcx, r8, r9 as x0–x5, guest stack arguments 7 and 8 as x6 and x7, and xmm0–7 as v0–v7. It returns x0/x1 into rax/rdx and v0/v1 into xmm0/xmm1. Both ABIs split integer and vector arguments into separate register files, so this covers every export with up to 8 integer and 8 vector arguments passed in registers. Variadic exports differ (Apple arm64 passes variadic arguments on the stack), and so do `va_list`, structure returns (rdi vs x8) and `long double`. Those exports need per-signature bridges; there are 26 variadic `APS5_VABI` exports.
- **Host to guest:** the guest image lives in a data segment, so a host function pointer to guest code faults when it is called. The runtime's SIGBUS/SIGSEGV handler looks the address up in the function table and resumes at `aps5_enter` with the translated function in x16, so the many callback sites (the process entry through `Aps5StartGuest`, thread entries, atexit, library callbacks) need no change. `aps5_enter` builds or reuses the thread's `GuestState` and TLS block, copies the AAPCS arguments into the SysV registers and the guest stack, pushes a return address, runs the translated function, and returns rax/rdx and xmm0/xmm1 as x0/x1 and q0/q1. Faults the redirect does not own go to the previous handler (the write watch chains the same way).
- **Variadic exports:** Apple arm64 passes variadic arguments on the stack, so a host `printf(fmt, ...)` cannot read the guest's registers. On arm64 the libc exports start a System V va_list over the running guest call instead (`aps5_guest_va_start` in the runtime, `GuestVarargs.hpp` in libc) and format with the same code the Windows build uses.
- **TLS:** `fs:` accesses read `GuestState.fsBase`, which is set per thread from the guest TLS allocator. The `gs:`/pthread-key stubs of the Rosetta mode are not used.

### Hard parts, in order of risk

1. **Non-local control flow:** guest `setjmp`/`longjmp`, C++ exception landing pads (a guest unwinder resuming mid-function), and the Fiber and Ult context switches. Translated functions nest native frames, so a guest transfer to an older frame must also unwind native frames. The plan is to resume through the thread's outermost guest entry, or to switch to a dispatch-loop model if that proves insufficient.
2. **Memory ordering:** x86 is TSO and arm64 is weakly ordered. The hardware TSO mode of Apple silicon has no public interface. Guest loads and stores can be emitted as acquire and release (`LDAPR`/`STLR`); that costs throughput, so it is a translation option.
3. **Coverage:** every instruction the titles use must be lifted exactly. Each one gets differential tests against the same code running under Rosetta.
4. **Tooling at conversion time:** the converter would need LLVM and a linker, about 100 MB. A direct arm64 emitter is the alternative if that size is a problem.

## Building and running the translator

The translator builds on its own because it needs LLVM and Capstone (Homebrew `llvm` and `capstone`):

```sh
cmake -S tools/translator -B build-translator -G Ninja -DLLVM_DIR=$(brew --prefix llvm)/lib/cmake/llvm
ninja -C build-translator
python3 tools/translator/tests/run_native_fixtures.py build-translator build-arm64/core/libs/libs
```

`aps5-translator <eboot.elf> <guest.o>` writes one arm64 object with the lifted functions, the guest image and the function table. The image's relocated slots are symbolic, so the host linker binds the guest's imports to the NID exports of the arm64 prx libraries. Linking it with `libaps5-translator-runtime.a` and the needed `.prx` files gives a native executable.

## Milestones

1. ✅ The prx libraries build for arm64. The x86-only parts throw until they are ported.
2. ✅ The smallest fixture (`import_fixture`: `puts` and `exit` through the GOT) runs as an arm64 process.
2b. ✅ DOOM (homebrew, `PPSA99666`) plays natively: launcher, attract demo and E1M1 at the game's 35 FPS, rendered through AGC, with no Rosetta in the process ([screenshot](../games/img/doom-native-e1m1.jpg)). What it took: SIMD/BMI lifting checked against Rosetta (`vector_smoke.c`), functions found through rip-relative code addresses and switch jump tables, guest TLS and image metadata (`__APS5DATA,__meta` for `dl_iterate_phdr`).
3. The C and C++ fixtures run: TLS, threads, modules, exceptions.
4. Breakout runs with video, pad and audio.
5. Dreaming Sarah runs.
