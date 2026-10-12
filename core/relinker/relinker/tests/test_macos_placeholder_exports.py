from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

from test_windows_import_modules import consumer, executable, provider

ZERO = b"\x31\xc0\xc3"
ZERO_XMM = b"\x66\x0f\xef\xc0\x31\xc0\xc3"


def real_library(code):
    image = provider(22, code=code)
    names = b"\0shared#A#B\0other#A#B\0"
    image[0x800:0x800 + len(names)] = names
    struct.pack_into("<Q", image, 0x618, len(names))
    struct.pack_into("<IIIIII", image, 0x840, 1, 3, 2, 0, 0, 1)
    other = b"\xb8" + struct.pack("<I", 33) + b"\xc3"
    image[0x410:0x410 + len(other)] = other
    struct.pack_into("<IBBHQQ", image, 0x8B0, 12, 0x12, 0, 1, 0x1010, len(other))
    return image


def bound_names(relinker, case, code, library=None):
    (case / "sce_module").mkdir(parents=True)
    (case / "sce_module" / "libc.prx").write_bytes(library if library is not None else provider(22, code=code))
    source = case / "input.elf"
    source.write_bytes(executable("libSceLibcInternal.prx", "shared#A#B", extra_dependencies=("libc.prx",)))
    output = case / "out" / "eboot"
    result = subprocess.run([str(relinker), "--macos", str(source), str(output)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (result.stdout, result.stderr)
    return sorted(set(re.findall(rb"_shared[#\w]*", output.read_bytes())))


def guest_won_dependency(relinker, case):
    # A guest module importing from libSceLibcInternal what the bundled libc.prx exports is bound to libc.prx's
    # export, so it depends on libc.prx's guest module and initializes after it (Stray's libSceNpCppWebApi).
    (case / "sce_module").mkdir(parents=True)
    (case / "sce_module" / "libc.prx").write_bytes(provider(22))
    (case / "sce_module" / "web.prx").write_bytes(consumer("libSceLibcInternal.prx"))
    source = case / "input.elf"
    source.write_bytes(executable("libSceLibcInternal.prx", "shared#A#B", extra_dependencies=("libc.prx", "web.prx")))
    output = case / "out" / "eboot"
    result = subprocess.run([str(relinker), "--macos", str(source), str(output)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (result.stdout, result.stderr)
    web = (case / "out" / "app0" / "sce_module" / "web.prx.guest.prx").read_bytes()
    assert b"_shared#guest" in web, "the import was not bound to the guest export"
    assert b"libc.prx.guest.prx" in web, "the importer does not depend on the guest module whose export it is bound to"


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-macos-placeholder-") as directory:
        work = Path(directory)
        names = bound_names(relinker, work / "real", None)
        assert names == [b"_shared#guest"], names
        for name, code in (("zero", ZERO), ("zero-xmm", ZERO_XMM)):
            names = bound_names(relinker, work / name, code)
            assert names == [b"_shared"], (name, names)
        # A zero export of a library with real functions is its answer (Stray's _sceLibcGetMallocParam): guest.
        names = bound_names(relinker, work / "real-library-zero", None, real_library(ZERO))
        assert names == [b"_shared#guest"], names
        guest_won_dependency(relinker, work / "guest-won-dependency")
    print("macOS placeholder export tests passed")


if __name__ == "__main__":
    main()
