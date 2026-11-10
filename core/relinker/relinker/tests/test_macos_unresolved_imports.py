"""A macOS function import that no library exports loads and reports its NID and library when called; data imports stay strict."""

import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

from guest_import_fixtures import executable
from test_macos_output import MachO


PROVIDER = "#include <unistd.h>\nint shared(void) { _exit(11); }\n"
EMPTY = "int Unrelated(void) { return 0; }\n"
REPORTER = ("#include <string.h>\n"
            "#include <unistd.h>\n"
            "static void put(const char* text) { write(2, text, strlen(text)); }\n"
            "void UnresolvedImport_nid_no_patch(const char* name, const char* library) {\n"
            "    put(\"unresolved \");\n"
            "    put(name);\n"
            "    put(\" from \");\n"
            "    put(library);\n"
            "    put(\"\\n\");\n"
            "    _exit(3);\n"
            "}\n"
            "void* TraceImport_nid_no_patch(void* target, const char* name, const char* library) { return target; }\n")
START = "void Aps5StartGuest_nid_no_patch(void (*entry)(void)) { entry(); }\n"
HELPER = b"_UnresolvedImport_nid_no_patch\0"


def relink(relinker, source, output, *options):
    return subprocess.run([str(relinker), "--macos", "--skip-sce-module", *options, str(source), str(output)],
                          capture_output=True, text=True, timeout=30)


def library(work, name, code):
    source = work / (name + ".c")
    source.write_text(code)
    output = work / (name + ".dylib")
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-dynamiclib", str(source),
                    "-Wl,-install_name,@rpath/" + name + ".prx", "-o", str(output)],
                   check=True, capture_output=True, timeout=20)
    return output


def run_binary(output):
    command = (["/usr/bin/arch", "-x86_64"] if platform.machine() == "arm64" else []) + [str(output)]
    return subprocess.run(command, capture_output=True, text=True, timeout=30)


def binds(data):
    macho = MachO(data)
    offset, size = macho.dyld_info[2:4]
    return data[offset:offset + size]


def bind_opcode(stream, symbol):
    at = stream.find(symbol)
    assert at > 0, (symbol, stream)
    return stream[at - 1]


def main():
    relinker = Path(sys.argv[1]).resolve()
    runnable = sys.platform == "darwin" and platform.machine() in ("x86_64", "arm64")
    with tempfile.TemporaryDirectory(prefix="anyps5-macos-unresolved-imports-") as directory:
        work = Path(directory)
        libraries = {}
        if runnable:
            libraries = {name: library(work, name, code) for name, code in (
                ("provider", PROVIDER), ("empty", EMPTY), ("reporter", REPORTER), ("libkernel", START))}

        for name, symbol_info, provider, libc, options, expected, message in (
                ("present", 0x12, "provider", "reporter", (), 11, None),
                ("missing", 0x12, "empty", "reporter", (), 3, "unresolved shared from a.prx"),
                ("missing-traced", 0x12, "empty", "reporter", ("--trace-imports",), 3, "unresolved shared from a.prx"),
                ("missing-without-reporter", 0x12, "empty", "empty", (), None, None),
                ("data-present", 0x11, "provider", "reporter", (), 11, None),
                ("data-missing", 0x11, "empty", "reporter", (), None, "_shared")):
            case = work / name
            case.mkdir()
            image = executable("a.prx", extra_dependencies=("libc.prx",))
            image[0x4898 + 4] = symbol_info
            source = case / "input.elf"
            source.write_bytes(image)
            output = case / "output"
            result = relink(relinker, source, output, *options)
            assert result.returncode == 0, (name, result.stdout, result.stderr)
            stream = binds(output.read_bytes())
            function = symbol_info & 15 == 2
            assert bind_opcode(stream, b"_shared\0") == (0x41 if function else 0x40), (name, stream)
            assert (HELPER in stream) == function, (name, stream)
            if function:
                assert bind_opcode(stream, HELPER) == 0x41, (name, stream)
                assert ("__APS5DATA", "__mod_init_func") in MachO(output.read_bytes()).sections, name
            if not runnable:
                continue
            (case / "libs").mkdir()
            os.link(libraries[provider], case / "libs" / "a.prx")
            os.link(libraries[libc], case / "libs" / "libc.prx")
            os.link(libraries["libkernel"], case / "libs" / "libkernel.prx")
            output.chmod(0o755)
            run = run_binary(output)
            if run.returncode != expected and "Bad CPU type in executable" in run.stderr:
                assert os.environ.get("GITHUB_ACTIONS") != "true", "macOS CI must execute the x86_64 unresolved import probe"
                runnable = False
                continue
            if expected is None:
                assert run.returncode not in (0, 3, 11), (name, run.returncode, run.stdout, run.stderr)
            else:
                assert run.returncode == expected, (name, run.returncode, run.stdout, run.stderr)
            if message is not None:
                assert message in run.stderr, (name, run.returncode, run.stdout, run.stderr)
            if name == "data-missing":
                assert "symbol not found" in run.stderr, (name, run.stdout, run.stderr)

        weak = work / "weak"
        weak.mkdir()
        image = executable("a.prx", extra_dependencies=("libc.prx",))
        image[0x4898 + 4] = 0x22
        (weak / "input.elf").write_bytes(image)
        result = relink(relinker, weak / "input.elf", weak / "output")
        assert result.returncode == 0, (result.stdout, result.stderr)
        stream = binds((weak / "output").read_bytes())
        assert bind_opcode(stream, b"_shared\0") == 0x41 and HELPER not in stream, stream

    print("macOS unresolved import tests passed")


if __name__ == "__main__":
    main()
