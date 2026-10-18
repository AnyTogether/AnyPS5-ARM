"""Translates a title's eboot to arm64 and packages it as a macOS application that runs without Rosetta.

    python3 tools/translator/package_native_app.py --eboot <eboot.bin|eboot.elf> --game <dir> \\
        --libs <build-arm64/core/libs/libs> --vulkan <Vulkan SDK macOS dir> [--translator <build-translator>] <Title.app>

--eboot is the title's executable, a decrypted SELF (unwrapped here) or a plain ELF. --game is the title's
folder (sce_sys and its data), copied as app0. --libs is the arm64 prx directory and --vulkan the macOS
directory of a Vulkan SDK. aps5-translator lifts the eboot to an arm64 object; imports that no arm64
library exports are linked to stubs that name the missing NID and abort. The bundle has the same layout
as tools/package_macos_app.py makes for the Rosetta mode, without the x86 game and MoltenVK patches.

Guest prx modules the title bundles (sce_module) are not translated yet."""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
sys.path.insert(0, str(TOOLS))
import package_macos_app

LLVM = Path("/opt/homebrew/opt/llvm/bin")
NID = re.compile(r"_[A-Za-z0-9+-]{11}")


def elf_of(eboot, work):
    if eboot.read_bytes()[:4] == b"\x7fELF":
        return eboot
    elf = work / "eboot.elf"
    subprocess.run([sys.executable, str(TOOLS / "unwrap_self.py"), str(eboot), str(elf)], check=True)
    return elf


def exported_names(libs):
    """The names dyld binds against. The NID patcher renames exports in the export trie only, so the
    symbol table (nm) still shows the original names."""
    names = set()
    for library in sorted(libs.glob("*.prx")):
        listing = subprocess.run([str(LLVM / "llvm-objdump"), "--macho", "--exports-trie", str(library)], capture_output=True, text=True).stdout
        for line in listing.splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[0].startswith("0x"):
                names.add(fields[1])
    return names


def needed_libraries(elf, libs):
    listing = subprocess.run([str(LLVM / "llvm-readelf"), "-d", str(elf)], capture_output=True, text=True, check=True).stdout
    needed = re.findall(r"Shared library: \[(.+?)\]", listing)
    return [libs / name for name in ["libkernel.prx", "libc.prx", *needed] if (libs / name).is_file()]


def write_stubs(missing, path):
    with path.open("w") as out:
        out.write("#include <stdio.h>\n#include <stdlib.h>\n")
        for index, name in enumerate(missing):
            out.write(f'void stub{index}(void) __asm__("{name}");\n')
            out.write(f'void stub{index}(void) {{ fprintf(stderr, "[native] missing import {name[1:]}\\n"); abort(); }}\n')


def build_executable(elf, libs, translator, work):
    guest = work / "guest.o"
    translated = subprocess.run([str(translator / "aps5-translator"), str(elf), str(guest)], capture_output=True, text=True)
    print(translated.stderr.strip())
    if translated.returncode != 0:
        raise RuntimeError("translation failed")
    undefined = subprocess.run([str(LLVM / "llvm-nm"), "-u", "--format=just-symbols", str(guest)], capture_output=True, text=True, check=True).stdout.split()
    exported = exported_names(libs)
    # Plain names such as ___divti3 come from libSystem; only NIDs get stubs.
    missing = sorted(name for name in set(undefined) - exported if NID.fullmatch(name))
    if missing:
        print(f"{len(missing)} imports have no arm64 export and abort when called: {' '.join(name[1:] for name in missing)}")
    write_stubs(missing, work / "stubs.c")
    subprocess.run(["clang", "-arch", "arm64", "-c", str(work / "stubs.c"), "-o", str(work / "stubs.o")], check=True)
    output = work / "relinked"
    output.mkdir()
    subprocess.run(["clang++", "-arch", "arm64", str(guest), str(work / "stubs.o"), str(translator / "libaps5-translator-runtime.a"),
                    *map(str, needed_libraries(elf, libs)), "-Wl,-rpath,@executable_path/libs", "-o", str(output / "eboot")], check=True)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--eboot", required=True, type=Path)
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--libs", required=True, type=Path)
    parser.add_argument("--vulkan", required=True, type=Path)
    parser.add_argument("--translator", type=Path, default=Path("build-translator"))
    parser.add_argument("bundle", type=Path)
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="anyps5-native-") as directory:
        work = Path(directory)
        relinked = build_executable(elf_of(arguments.eboot, work), arguments.libs, arguments.translator, work)
        name, identifier = package_macos_app.package(relinked, arguments.game, arguments.libs, arguments.vulkan, None, arguments.bundle, patch=False)
    print(f"{arguments.bundle}: {name} ({identifier}), arm64")


if __name__ == "__main__":
    main()
