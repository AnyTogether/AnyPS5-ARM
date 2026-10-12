from pathlib import Path
import re
import subprocess
import sys
import tempfile

from test_windows_import_modules import executable, provider

ZERO = b"\x31\xc0\xc3"
ZERO_XMM = b"\x66\x0f\xef\xc0\x31\xc0\xc3"


def bound_names(relinker, case, code):
    (case / "sce_module").mkdir(parents=True)
    (case / "sce_module" / "libc.prx").write_bytes(provider(22, code=code))
    source = case / "input.elf"
    source.write_bytes(executable("libSceLibcInternal.prx", "shared#A#B", extra_dependencies=("libc.prx",)))
    output = case / "out" / "eboot"
    result = subprocess.run([str(relinker), "--macos", str(source), str(output)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (result.stdout, result.stderr)
    return sorted(set(re.findall(rb"_shared[#\w]*", output.read_bytes())))


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-macos-placeholder-") as directory:
        work = Path(directory)
        names = bound_names(relinker, work / "real", None)
        assert names == [b"_shared#guest"], names
        for name, code in (("zero", ZERO), ("zero-xmm", ZERO_XMM)):
            names = bound_names(relinker, work / name, code)
            assert names == [b"_shared"], (name, names)
    print("macOS placeholder export tests passed")


if __name__ == "__main__":
    main()
