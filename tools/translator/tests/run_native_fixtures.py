"""Translates the macOS fixtures to native arm64 and runs them without Rosetta.

usage: run_native_fixtures.py <build-translator> <arm64 libs directory> [work directory]"""
import pathlib, shutil, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE.parents[2] / "core/relinker/relinker/tests/macos"
sys.path.insert(0, str(FIXTURES))

import guesttools
from import_fixture import fixture as import_fixture


VECTOR_FLAGS = ["-mavx2", "-mfma", "-mbmi", "-mbmi2", "-mlzcnt", "-mpopcnt"]


def compiled(source, flags=()):
    def build(directory):
        compiled_guest(directory, source, flags)
    return build


def compiled_guest(directory, source, flags):
    guesttools.compile(str(HERE / source), str(directory / "main.o"), extra=["-x", "c", *flags])
    names = guesttools.symbols(str(directory / "main.o"), "-u")
    guesttools.nidify(str(directory / "main.o"), str(directory / "main.nid.o"))
    guesttools.stub_library(names, str(directory / "libc.prx"), "libc.prx")
    guesttools.link_executable([str(directory / "main.nid.o")], [str(directory / "libc.prx")], str(directory / "eboot.elf"))


def host_reference(source, flags, work):
    """Builds the source for x86-64 macOS and runs it under Rosetta: (exit code, output), or None.

    The reference is built without optimization: Rosetta (macOS 26) miscomputes some optimized AVX
    sequences, such as a vcvtss2sd of a reloaded register right after vcmpunordss and vextractps."""
    binary = work / (pathlib.Path(source).stem + "-host")
    built = subprocess.run([f"{guesttools.LLVM}/clang", "-arch", "x86_64", "-O0", *flags, "-DMAIN_WRAPPER", str(HERE / source), "-o", str(binary)], capture_output=True, text=True)
    if built.returncode != 0:
        print(f"SKIP {source}: host build failed: {built.stderr.strip()[-300:]}")
        return None
    executed = subprocess.run(["arch", "-x86_64", str(binary)], capture_output=True, text=True, timeout=60)
    return executed.returncode, executed.stdout.strip()


def translate_and_run(build, libraries, directory, expected_exit, expected_output):
    translated = subprocess.run([str(build / "aps5-translator"), str(directory / "eboot.elf"), str(directory / "guest.o")], capture_output=True, text=True)
    if translated.returncode != 0:
        return f"translation failed: {translated.stderr.strip()}"
    shutil.rmtree(directory / "libs", ignore_errors=True)
    (directory / "libs").mkdir()
    shutil.copy2(libraries / "libc.prx", directory / "libs" / "libc.prx")
    subprocess.run(["clang++", "-arch", "arm64", str(directory / "guest.o"), str(build / "libaps5-translator-runtime.a"), str(directory / "libs/libc.prx"),
                    "-Wl,-rpath,@executable_path/libs", "-o", str(directory / "eboot")], check=True)
    executed = subprocess.run([str(directory / "eboot")], capture_output=True, text=True, timeout=60, cwd=directory)
    if executed.returncode != expected_exit or executed.stdout.strip() != expected_output:
        return f"exit {executed.returncode}, expected {expected_exit}; output {executed.stdout.strip()!r}: {executed.stderr.strip()[-300:]}"
    return None


def main():
    build, libraries = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    temporary = len(sys.argv) <= 3
    work = pathlib.Path(sys.argv[3]) if not temporary else pathlib.Path(tempfile.mkdtemp(prefix="anyps5-native-"))
    cases = [("import", lambda d: (d / "eboot.elf").write_bytes(import_fixture()), 0, "hello from a PS5 ELF on macOS")]
    if guesttools.available():
        # The expected values come from the same source compiled for the host.
        cases.append(("lifter-smoke", compiled("lifter_smoke.c"), 28, "3b0c6e4bf8726a1c"))
        expected = host_reference("vector_smoke.c", VECTOR_FLAGS, work)
        if expected is not None:
            cases.append(("vector-smoke", compiled("vector_smoke.c", VECTOR_FLAGS), *expected))
    failures = 0
    for name, build_fixture, expected_exit, expected_output in cases:
        directory = work / name
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        build_fixture(directory)
        error = translate_and_run(build, libraries, directory, expected_exit, expected_output)
        print(f"{'PASS' if error is None else 'FAIL'} {name}" + ("" if error is None else f": {error}"))
        failures += error is not None
    if failures:
        raise SystemExit(f"{failures} native fixture(s) failed; their files are in {work}")
    if temporary:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
