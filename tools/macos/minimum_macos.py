"""Checks the oldest macOS the Mach-O files of a toolkit, an app or a build run on.

    python3 tools/macos/minimum_macos.py <folder, file or .zip> [...] [--at-most 14.0] [--report]

A Mach-O file (thin or universal) names the oldest macOS it is built for in LC_BUILD_VERSION (minos)
or, in older files, LC_VERSION_MIN_MACOSX. The engine is built for the launcher's oldest macOS
(CMakeLists.txt sets CMAKE_OSX_DEPLOYMENT_TARGET): a library built for a newer one links against
what older systems lack, and dyld stops the game there with "Symbol not found ... (built for macOS
26.0 which is newer than running OS)". Prints each minimum with how many files name it and the
files above --at-most (the CMakeLists.txt minimum by default), and fails when there are any, unless
--report is given. Files that are not Mach-O are skipped. A .zip is read without unpacking it."""
import argparse
import os
import re
import struct
import sys
import zipfile
from pathlib import Path

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
MH_MAGIC = 0xFEEDFACE
LC_VERSION_MIN_MACOSX = 0x24
LC_BUILD_VERSION = 0x32
PLATFORM_MACOS = 1
CPU_TYPE_X86_64 = 0x01000007
HEADER_READ = 1 << 16
REPOSITORY = Path(__file__).resolve().parents[2]


def configured_minimum():
    """The ANYPS5_MACOS_MINIMUM CMakeLists.txt sets."""
    match = re.search(r"^set\(ANYPS5_MACOS_MINIMUM ([0-9.]+)\)$", (REPOSITORY / "CMakeLists.txt").read_text(encoding="utf-8"), re.M)
    if not match:
        sys.exit("minimum_macos: CMakeLists.txt sets no ANYPS5_MACOS_MINIMUM")
    return parse_version(match.group(1))


def parse_version(text):
    parts = [int(part) for part in text.split(".")]
    if not 1 <= len(parts) <= 3:
        raise ValueError(f"not a macOS version: {text}")
    return tuple(parts + [0] * (3 - len(parts)))


def unpack_version(packed):
    """A version packed as LC_BUILD_VERSION packs it: xxxx.yy.zz in 16, 8 and 8 bits."""
    return (packed >> 16, (packed >> 8) & 0xFF, packed & 0xFF)


def version_text(version):
    major, minor, patch = version
    return f"{major}.{minor}" + (f".{patch}" if patch else "")


def is_macho(head):
    if len(head) < 8:
        return False
    if struct.unpack_from(">I", head)[0] in (FAT_MAGIC, FAT_MAGIC_64):
        count = struct.unpack_from(">I", head, 4)[0]
        return 0 < count < 32
    return struct.unpack_from("<I", head)[0] in (MH_MAGIC_64, MH_MAGIC)


def thin_minimum(data, offset):
    """The macOS minimum of the thin Mach-O image at `offset` in `data`, None when it names none."""
    magic, _, _, _, count, size = struct.unpack_from("<IiiIII", data, offset)
    position = offset + (32 if magic == MH_MAGIC_64 else 28)
    end = min(position + size, len(data))
    for _ in range(count):
        if position + 8 > end:
            break
        command, length = struct.unpack_from("<II", data, position)
        if command == LC_BUILD_VERSION and position + 16 <= end:
            platform, minos = struct.unpack_from("<II", data, position + 8)
            if platform == PLATFORM_MACOS:
                return unpack_version(minos)
        elif command == LC_VERSION_MIN_MACOSX and position + 12 <= end:
            return unpack_version(struct.unpack_from("<I", data, position + 8)[0])
        if length < 8:
            break
        position += length
    return None


def slices(data):
    """The file offsets of the thin images in `data`, the x86_64 one first (games run it under Rosetta)."""
    magic = struct.unpack_from(">I", data)[0]
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        return [0]
    count = struct.unpack_from(">I", data, 4)[0]
    found = []
    for index in range(count):
        if magic == FAT_MAGIC:
            cpu, _, offset, _, _ = struct.unpack_from(">iiIII", data, 8 + index * 20)
        else:
            cpu, _, offset, _, _, _ = struct.unpack_from(">iiQQII", data, 8 + index * 32)
        found.append((cpu != CPU_TYPE_X86_64, offset))
    return [offset for _, offset in sorted(found)]


def minimum(data):
    """The newest macOS minimum among the images of a Mach-O file, None when none names one."""
    versions = [thin_minimum(data, offset) for offset in slices(data) if offset + 32 <= len(data)]
    versions = [version for version in versions if version is not None]
    return max(versions) if versions else None


def rest_needed(head):
    """Whether the load commands (or the slices of a universal file) go past `head`."""
    if struct.unpack_from(">I", head)[0] in (FAT_MAGIC, FAT_MAGIC_64):
        return True
    return len(head) >= 32 and 32 + struct.unpack_from("<I", head, 20)[0] > len(head)


def read_file(path):
    with open(path, "rb") as handle:
        head = handle.read(HEADER_READ)
        if not is_macho(head):
            return None
        return head + handle.read() if rest_needed(head) else head


def files_in(target):
    """(name, bytes) of every Mach-O file under `target`."""
    path = Path(target)
    if path.is_file() and zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                if info.is_dir() or (info.external_attr >> 16) & 0o170000 == 0o120000:
                    continue
                with archive.open(info) as handle:
                    head = handle.read(HEADER_READ)
                    if not is_macho(head):
                        continue
                    if rest_needed(head):
                        head += handle.read()
                yield f"{path.name}:{info.filename}", head
        return
    if path.is_file():
        data = read_file(path)
        if data is not None:
            yield str(path), data
        return
    if not path.is_dir():
        sys.exit(f"minimum_macos: {target} is neither a file nor a folder")
    for directory, folders, names in os.walk(path):
        folders.sort()
        for name in sorted(names):
            file = Path(directory) / name
            if file.is_symlink() or not file.is_file():
                continue
            data = read_file(file)
            if data is not None:
                yield str(file), data


def check(targets, at_most):
    """{version text: count} and the files above `at_most`, as (name, version text)."""
    counts = {}
    above = []
    for target in targets:
        for name, data in files_in(target):
            version = minimum(data)
            key = version_text(version) if version else "none"
            counts[key] = counts.get(key, 0) + 1
            if version and version > at_most:
                above.append((name, version_text(version)))
    return counts, above


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("targets", nargs="+", help="folders, files or .zip archives")
    parser.add_argument("--at-most", type=parse_version, help="the newest minimum allowed (default: CMakeLists.txt's ANYPS5_MACOS_MINIMUM)")
    parser.add_argument("--report", action="store_true", help="print the files above the minimum without failing")
    options = parser.parse_args(arguments)
    at_most = options.at_most or configured_minimum()
    counts, above = check(options.targets, at_most)
    if not counts:
        print(f"minimum_macos: no Mach-O files in {' '.join(options.targets)}", file=sys.stderr)
        return 1
    order = sorted(counts, key=lambda key: parse_version(key) if key != "none" else (0, 0, 0))
    print(f"minos in {' '.join(options.targets)}: " + ", ".join(f"{key} ({counts[key]} files)" for key in order))
    for name, version in above:
        print(f"{name}: built for macOS {version}, newer than {version_text(at_most)}", file=sys.stderr)
    if above and not options.report:
        print(f"minimum_macos: {len(above)} files need a macOS newer than {version_text(at_most)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
