import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

from test_guest_intel_trampolines import PLAIN_SITE, guest_fixture
from test_guest_symbol_names import importing_executable

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "tools"))
import import_audit


def named_module(tag):
    image = guest_fixture(PLAIN_SITE)
    strings = b"\0Party.prx\0"
    image[0x800:0x800 + len(strings)] = strings
    struct.pack_into("<Q", image, 0x618, len(strings))
    struct.pack_into("<qQqQ", image, 0x680, tag, 1, 0, 0)
    struct.pack_into("<QQ", image, 208, 10 * 16, 10 * 16)
    return image


def executable_with_dependencies(libraries):
    image = importing_executable([], modules=libraries)
    dynamic_size, = struct.unpack_from("<Q", image, 152)
    struct.pack_into("<qQqQ", image, 0x4800 + dynamic_size - 16, 0x6100003F, 24, 0, 0)
    struct.pack_into("<QQ", image, 152, dynamic_size + 16, dynamic_size + 16)
    return image


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-needed-libraries-") as directory:
        work = Path(directory)
        for windows in (False, True):
            for bundled in (False, True):
                case = work / f"{windows}-{bundled}"
                modules = case / "sce_module"
                modules.mkdir(parents=True)
                source = case / "input.elf"
                source.write_bytes(executable_with_dependencies([] if bundled else ["Party"]))
                if bundled:
                    (modules / "engine.prx").write_bytes(named_module(1))
                output = case / ("output.exe" if windows else "output.elf")
                result = subprocess.run([str(relinker), "--registry", "unused-filter=2",
                                         *(["--windows"] if windows else []), str(source), str(output)],
                                        capture_output=True, text=True, timeout=20)
                assert result.returncode == 0, (windows, bundled, result.stdout, result.stderr)
                registry = case / ("output.engine.prx.guest.prx.registry.json" if bundled else "output.registry.json")
                assert json.loads(registry.read_text()) == [], (windows, bundled)
                needed = import_audit.read_needed_registry(import_audit.needed_registry_path(registry))
                assert needed == ["Party.prx"], (windows, bundled, needed)
                records, missing = import_audit.audit(import_audit.read_registry(registry), {}, {}, set(), set(), needed_libraries=needed)
                assert records == [] and missing == {"Party.prx": 0}, (records, missing)
                (modules / "provider.prx").write_bytes(named_module(14))
                result = subprocess.run([str(relinker), "--registry", *(["--windows"] if windows else []),
                                         str(source), str(output)], capture_output=True, text=True, timeout=20)
                assert result.returncode == 0, (windows, bundled, result.stdout, result.stderr)
                needed = import_audit.read_needed_registry(import_audit.needed_registry_path(registry))
                assert needed == [], (windows, bundled, needed)
                assert import_audit.audit([], {}, {}, set(), set(), needed_libraries=needed) == ([], {})
        for windows in (False, True):
            case = work / f"executables-{windows}"
            picker = case / "picker" / "picker.bin"
            picker.parent.mkdir(parents=True)
            modules = case / "sce_module"
            modules.mkdir()
            picker.write_bytes(executable_with_dependencies(["Party"]))
            source = case / "input.elf"
            source.write_bytes(executable_with_dependencies([]))
            output = case / ("output.exe" if windows else "output.elf")
            command = [str(relinker), "--registry", "--executable", "picker/picker.bin",
                       *(["--windows"] if windows else []), str(source), str(output)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
            assert result.returncode == 0, (windows, result.stdout, result.stderr)
            main_needed = case / "output.needed.json"
            picker_needed = case / "picker.picker.bin.needed.json"
            assert import_audit.read_needed_registry(main_needed) == []
            assert import_audit.read_needed_registry(picker_needed) == ["Party.prx"]
            (modules / "provider.prx").write_bytes(named_module(14))
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
            assert result.returncode == 0, (windows, result.stdout, result.stderr)
            assert import_audit.read_needed_registry(main_needed) == []
            assert import_audit.read_needed_registry(picker_needed) == []
            assert import_audit.read_needed_registry(case / "output.provider.prx.guest.prx.needed.json") == []
    print("Dependency-only library audit tests passed")


if __name__ == "__main__":
    main()
