from pathlib import Path
import json
import struct
import subprocess
import sys
import tempfile

from test_guest_symbol_names import importing_executable
from test_sce_code_extent import FUNCTION, FUNCTION_SIZE, fixture
from test_sce_module_code_extent import sce_module, unwind_table

SLOT = bytes.fromhex("48 66 66 66 66 66 66 2e 0f 1f 84 00 00 00 00 00")
SYSCALL = bytes.fromhex("0f 05 c3")
GAP = FUNCTION + FUNCTION_SIZE
TARGETS = (("linux", []), ("windows", ["--windows"]), ("macos", ["--macos"]))


def executable(gap_bytes=b"", sce_block=True, function=b"", before_function=b""):
    image, plt = fixture(sce_block=sce_block, gap=0x20)
    image[GAP:GAP + len(gap_bytes)] = gap_bytes
    image[FUNCTION:FUNCTION + len(function)] = function
    image[FUNCTION - len(before_function):FUNCTION] = before_function
    return image, plt


def module(slot_in_function):
    image = sce_module()
    text = memoryview(image)[0x400:0x500]
    text[0:len(SLOT)] = SLOT
    if not slot_in_function:
        text[0x10:0x10 + FUNCTION_SIZE] = b"\xc3" + b"\x90" * (FUNCTION_SIZE - 1)
        unwind_table(text, 0x1000, 0x1010, FUNCTION_SIZE, 0x1080, 0x10A0)
        struct.pack_into("<Q", image, 24, 0x1010)
    return image


def finish(name, result, converted, expected_errors):
    if not expected_errors:
        assert result.returncode == 0 and converted, (name, result.stdout, result.stderr)
    else:
        assert result.returncode == 2 and not converted and all(error in result.stderr for error in expected_errors), (
            name, result.returncode, result.stdout, result.stderr)


def run(relinker, work, name, built, flags, expected_errors=()):
    image, plt = built
    source = work / (name + ".elf")
    output = work / (name + ".out")
    source.write_bytes(image)
    result = subprocess.run([str(relinker), "--skip-sce-module", *flags, "--registry", str(source), str(output)],
                            capture_output=True, text=True, timeout=20)
    finish(name, result, output.exists(), expected_errors)
    if not expected_errors:
        registry = json.loads((work / (name + ".registry.json")).read_text())
        assert [entry["callSites"] for entry in registry] == [[hex(plt + 16)]], (name, registry)


def run_module(relinker, work, name, built, flags, expected_errors=()):
    case = work / name
    (case / "sce_module").mkdir(parents=True)
    (case / "input.elf").write_bytes(importing_executable([]))
    (case / "sce_module" / "libExample.prx").write_bytes(built)
    result = subprocess.run([str(relinker), *flags, str(case / "input.elf"), str(case / "output.exe")],
                            capture_output=True, text=True, timeout=30)
    finish(name, result, (case / "app0" / "sce_module" / "libExample.prx.guest.prx").exists(), expected_errors)


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-sce-code-gaps-") as directory:
        work = Path(directory)
        for target, flags in TARGETS:
            run(relinker, work, "sce-gap-slot-" + target, executable(SLOT), flags)
            run_module(relinker, work, "sce-module-gap-slot-" + target, module(False), flags)
        run(relinker, work, "sce-gap-syscall-after-slot", executable(SLOT + SYSCALL), [],
            ["Forbidden syscall instruction at code offset 0x220"])
        run(relinker, work, "sce-function-slot", executable(function=SLOT), [],
            ["Cannot decode instruction", "offset 0x200"])
        run(relinker, work, "sysv-gap-slot", executable(SLOT, sce_block=False), [],
            ["Cannot decode instruction", "offset 0x210"])
        run(relinker, work, "sce-gap-instruction-into-function", executable(function=SYSCALL, before_function=b"\x90" * 15 + b"\xb8"), [],
            ["Forbidden syscall instruction at code offset 0x200"])
        run_module(relinker, work, "sce-module-function-slot", module(True), [], ["Cannot decode instruction"])
    print("SCE code gap tests passed")


if __name__ == "__main__":
    main()
