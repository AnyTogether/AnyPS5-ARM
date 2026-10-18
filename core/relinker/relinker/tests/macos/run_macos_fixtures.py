"""Relink small PS5-style programs with --macos and run them under Rosetta.

    python3 run_macos_fixtures.py <relinker> <patched prx directory> [work directory]

The argv, import and TLS programs are built byte by byte. The C++ exception, guest module and thread
programs are compiled from the .cpp files here with LLVM (clang for x86_64-unknown-freebsd, llvm-nm,
llvm-objcopy, ld.lld); they are skipped when that toolchain is missing. Each program reports its
result through its exit status."""
import pathlib, shutil, signal, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import guesttools
from import_fixture import fixture as import_fixture
from tls_fixture import fixture as tls_fixture
from test_linux_entry_argv import argv_fixture


def relink_and_run(relinker, libraries, directory, expected, arguments=(), modules=False, relink_options=()):
    directory = pathlib.Path(directory)
    output = directory / "eboot"
    source = directory / "eboot.elf"
    if (directory / "sce_module").exists():
        # The relinker also looks for the executable's needed modules below the executable's directory,
        # so the link stubs (libc.prx, libkernel.prx) must not sit there.
        staged = directory / "input"
        staged.mkdir()
        shutil.move(str(source), str(staged / "eboot.elf"))
        shutil.move(str(directory / "sce_module"), str(staged / "sce_module"))
        source = staged / "eboot.elf"
    options = [*relink_options] + ([] if modules else ["--skip-sce-module"])
    relinked = subprocess.run([relinker, "--macos", *options, str(source), str(output)], capture_output=True, text=True, timeout=120)
    if relinked.returncode != 0:
        return f"relink failed: {relinked.stderr.strip()}"
    output.chmod(0o755)
    shutil.rmtree(directory / "libs", ignore_errors=True)
    shutil.copytree(libraries, directory / "libs", ignore=shutil.ignore_patterns("unpatched", "implib"))
    executed = subprocess.run([str(output), *arguments], capture_output=True, text=True, timeout=120, cwd=directory)
    return None if executed.returncode == expected else f"exit {executed.returncode}, expected {expected}: {executed.stderr.strip()[-300:]}"


def compiled_exception(directory):
    tools = guesttools
    tools.compile(str(HERE / "exception.cpp"), str(directory / "main.o"))
    names = tools.symbols(str(directory / "main.o"), "-u")
    tools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    tools.stub_library(names, str(directory / "libc.prx"), "libc.prx")
    tools.link_executable([str(directory / "main.nid.o")], [str(directory / "libc.prx")], str(directory / "eboot.elf"))


def compiled_c_cleanup(directory):
    tools = guesttools
    objects = {"cleanup": ("c_cleanup.c", ["-x", "c"]), "main": ("c_cleanup_main.cpp", [])}
    for name, (source, extra) in objects.items():
        tools.compile(str(HERE / source), str(directory / f"{name}.o"), extra=extra)
    imported = set()
    defined = set()
    for name in objects:
        imported.update(tools.symbols(str(directory / f"{name}.o"), "-u"))
        defined.update(tools.symbols(str(directory / f"{name}.o"), "-g", "--defined-only"))
    for name in objects:
        tools.nidify(str(directory / f"{name}.o"), str(directory / f"{name}.nid.o"))
    tools.stub_library(sorted(imported - defined), str(directory / "libc.prx"), "libc.prx")
    tools.link_executable([str(directory / f"{name}.nid.o") for name in objects], [str(directory / "libc.prx")], str(directory / "eboot.elf"))


def compiled_module(directory):
    tools = guesttools
    (directory / "sce_module").mkdir()
    tools.stub_library(["puts", "exit", "memset", "__tls_get_addr"], str(directory / "libc.prx"), "libc.prx")
    tools.stub_library(["sceKernelGetModuleInfoForUnwind"], str(directory / "libkernel.prx"), "libkernel.prx")
    tools.compile(str(HERE / "greet.cpp"), str(directory / "greet.o"), pic=True)
    tools.nidify(str(directory / "greet.o"), str(directory / "greet.nid.o"))
    module = directory / "sce_module" / "libgreet.prx"
    tools.link_module([str(directory / "greet.nid.o")], [str(directory / "libc.prx")], str(module), "libgreet.prx")
    tools.clear_static_tls_flag(module)
    tools.compile(str(HERE / "module_main.cpp"), str(directory / "main.o"))
    tools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    tools.link_executable([str(directory / "main.nid.o")], [str(module), str(directory / "libc.prx"), str(directory / "libkernel.prx")], str(directory / "eboot.elf"))


def compiled_intel(directory):
    tools = guesttools
    amd = ["-msse4a", "-mclzero", "-mmwaitx", "-mrdseed", "-mrdpid", "-mclwb"]
    (directory / "sce_module").mkdir()
    tools.stub_library(["exit"], str(directory / "libc.prx"), "libc.prx")
    tools.compile(str(HERE / "intel_module.cpp"), str(directory / "amd.o"), pic=True, extra=amd)
    tools.nidify(str(directory / "amd.o"), str(directory / "amd.nid.o"))
    module = directory / "sce_module" / "libamd.prx"
    tools.link_module([str(directory / "amd.nid.o")], [str(directory / "libc.prx")], str(module), "libamd.prx")
    tools.compile(str(HERE / "intel_main.cpp"), str(directory / "main.o"), extra=amd)
    tools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    tools.link_executable([str(directory / "main.nid.o")], [str(module), str(directory / "libc.prx")], str(directory / "eboot.elf"))


def compiled_tls_modules(directory):
    tools = guesttools
    (directory / "sce_module").mkdir()
    tools.stub_library(["exit", "__tls_get_addr"], str(directory / "libc.prx"), "libc.prx")
    tools.stub_library(["scePthreadCreate", "scePthreadJoin"], str(directory / "libkernel.prx"), "libkernel.prx")
    owner = directory / "sce_module" / "libowner.prx"
    user = directory / "sce_module" / "libuser.prx"
    for source, name, module, libraries in (("tls_owner.cpp", "owner", owner, []), ("tls_user.cpp", "user", user, [str(owner)])):
        tools.compile(str(HERE / source), str(directory / f"{name}.o"), pic=True)
        tools.nidify(str(directory / f"{name}.o"), str(directory / f"{name}.nid.o"))
        tools.link_module([str(directory / f"{name}.nid.o")], [*libraries, str(directory / "libc.prx")], str(module), module.name)
    tools.compile(str(HERE / "tls_modules_main.cpp"), str(directory / "main.o"))
    tools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    tools.link_executable([str(directory / "main.nid.o")], [str(user), str(owner), str(directory / "libc.prx"), str(directory / "libkernel.prx")], str(directory / "eboot.elf"))


def compiled_threads(directory):
    tools = guesttools
    tools.stub_library(["exit"], str(directory / "libc.prx"), "libc.prx")
    tools.stub_library(["scePthreadCreate", "scePthreadJoin"], str(directory / "libkernel.prx"), "libkernel.prx")
    tools.compile(str(HERE / "threads.cpp"), str(directory / "threads.o"), extra=["-mno-tls-direct-seg-refs"])
    tools.nidify(str(directory / "threads.o"), str(directory / "threads.nid.o"))
    tools.link_executable([str(directory / "threads.nid.o")], [str(directory / "libc.prx"), str(directory / "libkernel.prx")], str(directory / "eboot.elf"))


def compiled_video_guest(directory, source, kernel, video):
    """A guest that uses video out; it needs a title id, so it gets app0/sce_sys/param.json."""
    tools = guesttools
    tools.stub_library(["puts", "exit"], str(directory / "libc.prx"), "libc.prx")
    tools.stub_library(kernel, str(directory / "libkernel.prx"), "libkernel.prx")
    tools.stub_library(video, str(directory / "libSceVideoOut.prx"), "libSceVideoOut.prx")
    tools.compile(str(HERE / source), str(directory / "main.o"))
    tools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    tools.link_executable([str(directory / "main.nid.o")], [str(directory / x) for x in ("libc.prx", "libkernel.prx", "libSceVideoOut.prx")], str(directory / "eboot.elf"))
    (directory / "app0" / "sce_sys").mkdir(parents=True)
    (directory / "app0" / "sce_sys" / "param.json").write_text('{"titleId": "APS5TEST0", "localizedParameters": {"en-US": {"titleName": "AnyPS5 on macOS"}}}')


# The video guests talk to the window server (and videoout draws in a window), so they are not run
# automatically: build one with compiled_videoout_open or compiled_videoout and run it by hand.
def compiled_videoout_open(directory):
    compiled_video_guest(directory, "videoout_open.cpp", ["sceKernelUsleep"], ["sceVideoOutOpen", "sceVideoOutClose"])


def compiled_videoout(directory):
    compiled_video_guest(directory, "videoout.cpp", ["sceKernelAllocateDirectMemory", "sceKernelMapDirectMemory"],
                         ["sceVideoOutOpen", "sceVideoOutSetBufferAttribute2", "sceVideoOutRegisterBuffers2", "sceVideoOutSubmitFlip",
                          "sceVideoOutWaitVblank", "sceVideoOutClose"])


def compiled_breakout(directory):
    """A small game (breakout.cpp) that opens a window and plays sound; it is built here and run by hand."""
    tools = guesttools
    libraries = {
        "libc.prx": ["exit", "memset", "memcpy"],
        "libkernel.prx": ["sceKernelAllocateDirectMemory", "sceKernelMapDirectMemory", "scePthreadCreate"],
        "libSceVideoOut.prx": ["sceVideoOutOpen", "sceVideoOutSetBufferAttribute2", "sceVideoOutRegisterBuffers2", "sceVideoOutSubmitFlip",
                               "sceVideoOutWaitVblank", "sceVideoOutClose"],
        "libScePad.prx": ["scePadInit", "scePadOpen", "scePadReadState"],
        "libSceAudioOut.prx": ["sceAudioOutInit", "sceAudioOutOpen", "sceAudioOutOutput"],
        "libSceUserService.prx": ["sceUserServiceInitialize", "sceUserServiceGetInitialUser"],
    }
    for name, functions in libraries.items():
        tools.stub_library(functions, str(directory / name), name)
    tools.compile(str(HERE / "breakout.cpp"), str(directory / "main.o"))
    tools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    tools.link_executable([str(directory / "main.nid.o")], [str(directory / name) for name in libraries], str(directory / "eboot.elf"))
    (directory / "app0" / "sce_sys").mkdir(parents=True)
    (directory / "app0" / "sce_sys" / "param.json").write_text('{"titleId": "APS5TEST1", "localizedParameters": {"en-US": {"titleName": "AnyPS5 Breakout"}}}')
    (directory / "anyps5-input.ini").write_text("Left = KEY:Left\nRight = KEY:Right\nCross = KEY:Space\nOptions = KEY:Escape\n")
    (directory / "app0" / "sce_sys" / "icon0.png").write_bytes(breakout_icon())


def breakout_icon(size=512):
    """icon0.png for the Breakout guest: rows of bricks, the paddle and the ball, as an RGB PNG."""
    import struct, zlib
    colors = [(0xe5, 0x48, 0x4d), (0xf7, 0x6b, 0x15), (0xff, 0xc5, 0x3d), (0x46, 0xa7, 0x58), (0x3e, 0x63, 0xdd)]
    rows = []
    for y in range(size):
        row = bytearray(b"\0")
        for x in range(size):
            pixel = (0x14, 0x18, 0x28 + y * 0x20 // size)
            band, within = divmod(y - 96, 44)
            if 0 <= band < len(colors) and within < 34 and (x - 40) % 88 < 76 and 40 <= x < size - 40:
                pixel = colors[band]
            if 400 <= y < 424 and 176 <= x < 336:
                pixel = (0xe8, 0xec, 0xf2)
            if 340 <= y < 368 and 300 <= x < 328:
                pixel = (0xff, 0xff, 0xff)
            row += bytes(pixel)
        rows.append(bytes(row))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")


def stale_libraries(libraries):
    """Patched libraries older than their unpatched build: `ninja libs` was not run after a change."""
    libraries = pathlib.Path(libraries)
    stale = []
    for unpatched in sorted((libraries / "unpatched").glob("*.prx")):
        patched = libraries / unpatched.name
        if not patched.exists() or patched.stat().st_mtime < unpatched.stat().st_mtime:
            stale.append(unpatched.name)
    return stale


def main():
    if sys.platform != "darwin":
        print("macOS fixtures skipped: not macOS")
        return
    relinker, libraries = sys.argv[1], sys.argv[2]
    if stale := stale_libraries(libraries):
        raise SystemExit(f"patched libraries are older than their build, run `ninja libs`: {', '.join(stale[:5])}")
    temporary = len(sys.argv) <= 3
    work = pathlib.Path(sys.argv[3]) if not temporary else pathlib.Path(tempfile.mkdtemp(prefix="anyps5-macos-"))
    cases = [
        ("argv", lambda d: (d / "eboot.elf").write_bytes(argv_fixture()), -signal.SIGTRAP, ["Z"], False),
        ("import", lambda d: (d / "eboot.elf").write_bytes(import_fixture()), 0, [], False),
        ("tls", lambda d: (d / "eboot.elf").write_bytes(tls_fixture()), 136, [], False),
    ]
    if guesttools.available():
        cases += [("exception", compiled_exception, 43, [], False),
                  ("c-cleanup", compiled_c_cleanup, 47, [], False),
                  ("threads", compiled_threads, 51, [], False),
                  ("module", compiled_module, 143, [], True),
                  ("tls-modules", compiled_tls_modules, 47, [], True),
                  # Without --to-rosetta the AMD-only instructions fault under Rosetta; with it they run.
                  ("intel-unconverted", compiled_intel, -signal.SIGILL, [], True),
                  ("intel", compiled_intel, 47, [], True, ["--to-rosetta"])]
    else:
        print("compiled macOS fixtures skipped: LLVM clang/llvm-objcopy/ld.lld not found")
    failures = 0
    for name, build, expected, arguments, modules, *relink_options in cases:
        directory = work / name
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        build(directory)
        error = relink_and_run(relinker, libraries, directory, expected, arguments, modules, *relink_options)
        print(f"{'PASS' if error is None else 'FAIL'} {name}" + ("" if error is None else f": {error}"))
        failures += error is not None
    if failures:
        raise SystemExit(f"{failures} macOS fixture(s) failed; their files are in {work}")
    if temporary:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
