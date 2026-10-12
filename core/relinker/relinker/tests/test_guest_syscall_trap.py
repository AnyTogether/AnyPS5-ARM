from pathlib import Path
import struct
import subprocess
import sys
import tempfile

from test_guest_intel_trampolines import elf_bytes_at, elf_loads, guest_fixture, main_fixture


GENERIC_STUB = bytes.fromhex(
    "48 89 f8 48 89 f7 48 89 d6 48 89 ca 4d 89 c2 4d 89 c8 "
    "4c 8b 4c 24 08 0f 05 c3")
NUMBERED_STUB = bytes.fromhex("48 c7 c0 09 00 00 00 49 89 ca 0f 05 c3")


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-guest-syscall-trap-") as directory:
        work = Path(directory)
        modules = work / "sce_module"
        modules.mkdir()
        module = bytearray(guest_fixture(b"\x90" * 6))
        module[0x400:0x400 + len(GENERIC_STUB)] = GENERIC_STUB
        module[0x440:0x440 + len(NUMBERED_STUB)] = NUMBERED_STUB
        (modules / "sample.prx").write_bytes(module)
        source = work / "input.elf"
        source.write_bytes(main_fixture())
        output = work / "output.elf"
        result = subprocess.run(
            [str(relinker), "--trap-sdk-syscall-stubs", str(source), str(output)],
            capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (result.stdout, result.stderr)

        converted = output.parent / "app0" / "sce_module" / "sample.prx.guest.prx"
        image = converted.read_bytes()
        loads = elf_loads(image)
        assert elf_bytes_at(image, loads, 0x1017, 3) == b"\x0f\x0b\xc3"
        assert elf_bytes_at(image, loads, 0x104a, 3) == b"\x0f\x0b\xc3"


if __name__ == "__main__":
    main()
