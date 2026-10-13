from pathlib import Path
import os
import subprocess
import sys
import tempfile

from test_guest_intel_trampolines import main_fixture
from test_guest_module_directories import module_with_symbol, needed_libraries
from test_guest_needed_modules import executable_with_needed


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-executables-") as directory:
        work = Path(directory)

        def convert(case, windows, options, picker=None):
            (case / "sce_module").mkdir(parents=True, exist_ok=True)
            (case / "sce_module" / "bundled.prx").write_bytes(module_with_symbol(True))
            (case / "picker").mkdir(exist_ok=True)
            (case / "picker" / "picker.bin").write_bytes(main_fixture() if picker is None else picker)
            source = case / "eboot.bin"
            source.write_bytes(main_fixture())
            output = case / "out" / ("app.exe" if windows else "app.elf")
            output.parent.mkdir(exist_ok=True)
            result = subprocess.run([str(relinker), *(["--windows"] if windows else []), "--registry", *options, str(source), str(output)],
                                    capture_output=True, text=True, timeout=60)
            return result, output

        for windows in (False, True):
            suffix = ".exe" if windows else ".elf"
            case = work / f"{windows}-picker"
            result, output = convert(case, windows, ["--executable", "picker/picker.bin"])
            assert result.returncode == 0, (result.stdout, result.stderr)
            secondary = output.parent / ("picker.picker.bin" + suffix)
            assert secondary.read_bytes().startswith(b"MZ" if windows else b"\x7fELF"), secondary
            assert "Executable: picker/picker.bin\n" in result.stdout, result.stdout
            assert f"Executable file: {secondary}\n" in result.stdout, result.stdout
            assert f"  |-- app{suffix}\n  |-- picker.picker.bin{suffix}\n  |-- libs/\n" in result.stdout, result.stdout
            assert (output.parent / "picker.picker.bin.registry.json").is_file()
            assert sorted(path.name for path in output.parent.rglob("*.guest.prx")) == ["bundled.prx.guest.prx"]
            if not windows:
                assert "$ORIGIN/app0/sce_module/bundled.prx.guest.prx" in needed_libraries(secondary.read_bytes())
            if windows and os.name == "nt":
                for executable in (output, secondary):
                    run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
                    assert run.returncode == 42, (executable, run.returncode, run.stdout, run.stderr)

            for options, message in ((["--executable", "../eboot.bin"], "inside the guest module parent directory"),
                                     (["--executable", "picker"], "is not a file"),
                                     (["--executable", "picker/missing.bin"], "is not a file"),
                                     (["--executable", "eboot.bin"], "converted twice"),
                                     (["--executable", "picker/picker.bin", "--executable", "picker/./picker.bin"], "converted twice"),
                                     (["--module-dir", "picker", "--executable", "picker/picker.bin"], "in a guest module directory"),
                                     (["--module-dir", "picker/", "--executable", "picker/picker.bin"], "in a guest module directory")):
                case = work / f"{windows}-rejected-{len(message)}-{len(options)}"
                result, output = convert(case, windows, options)
                assert result.returncode == 2 and message in result.stderr, (options, result.stderr)
                assert not output.exists(), options

            case = work / f"{windows}-needed"
            (case / "Media" / "Modules").mkdir(parents=True)
            (case / "Media" / "Modules" / "needed.prx").write_bytes(module_with_symbol(True))
            result, output = convert(case, windows, ["--module-dir", "Media/Modules", "--executable", "picker/picker.bin"], executable_with_needed())
            if windows:
                assert result.returncode == 2 and "Guest modules convert differently for picker/picker.bin" in result.stderr, result.stderr
                assert not output.exists()
            else:
                assert result.returncode == 0, (result.stdout, result.stderr)
                secondary = output.parent / "picker.picker.bin.elf"
                assert "$ORIGIN/app0/Media/Modules/needed.prx.guest.prx" in needed_libraries(secondary.read_bytes())
                assert "$ORIGIN/app0/Media/Modules/needed.prx.guest.prx" not in needed_libraries(output.read_bytes())


if __name__ == "__main__":
    main()
