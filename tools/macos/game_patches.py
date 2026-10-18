"""Applies per-title byte patches to an executable relinked with `relinker --macos`.

    python3 tools/macos/game_patches.py <eboot> <title id> [--patches <dir>] [--check] [--resolution WxH]

Patches live in tools/macos/patches/<title id>.json:

    {"patches": [{"name": "...", "description": "...", "edits": [
        {"address": "0x14410675e", "original": "0f84d2000000", "replacement": "90e9d2000000"}]}],
     "resolution": {"default": "1920x1080", "choices": ["1280x720", "1920x1080"], "fields": [
        {"value": "width", "address": "0x1417e90d5", "instruction": "ba000f0000", "offset": 1}]}}

An address is a virtual address of the relinked executable; it is mapped to a file offset through
the executable's Mach-O segments. A patch is applied only when every one of its edits finds its
original bytes (or its replacement, when it was applied before), so another build of the title is
left as it is and reported.

The optional resolution section names the 32-bit little-endian values that set the title's output
size: each field is the instruction at `address`, whose value starts `offset` bytes in. A field is
found when the instruction's bytes before the value match; the value itself may already hold an
earlier choice. The macOS bundle's launcher writes a choice into those values before it starts the
title (see package_macos_app.py)."""
import argparse
import json
import struct
import sys
from pathlib import Path

PATCHES = Path(__file__).resolve().parent / "patches"
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19


def segments(data):
    magic, _, _, _, count, _, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != MH_MAGIC_64:
        raise ValueError("not a 64-bit Mach-O executable")
    result = []
    cursor = 32
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, cursor)
        if command == LC_SEGMENT_64:
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, cursor + 24)
            if filesize != 0:
                result.append((vmaddr, fileoff, filesize))
        cursor += size
    return result


def file_offset(segment_list, address, length):
    for vmaddr, fileoff, filesize in segment_list:
        if vmaddr <= address and address + length <= vmaddr + filesize:
            return fileoff + address - vmaddr
    raise ValueError(f"0x{address:x} is not in a file-backed segment")


def definition(title_id, directory=PATCHES):
    path = directory / f"{title_id}.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def load(title_id, directory=PATCHES):
    return definition(title_id, directory).get("patches", [])


def parse_resolution(text):
    width, _, height = text.lower().partition("x")
    if not width.isdigit() or not height.isdigit() or int(width) == 0 or int(height) == 0:
        raise ValueError(f"not a WIDTHxHEIGHT resolution: {text}")
    return int(width), int(height)


def resolution_fields(eboot, title_id, directory=PATCHES):
    """The title's resolution section with the file offset of every field's value, or None when the
    title has none or a field's instruction is not where it is expected."""
    section = definition(title_id, directory).get("resolution")
    if section is None:
        return None
    data = Path(eboot).read_bytes()
    segment_list = segments(data)
    fields = []
    for field in section["fields"]:
        instruction = bytes.fromhex(field["instruction"])
        offset = file_offset(segment_list, int(field["address"], 16), len(instruction))
        prefix = instruction[:field["offset"]]
        if data[offset:offset + len(prefix)] != prefix:
            return None
        fields.append((field["value"], offset + field["offset"]))
    return {"default": section["default"], "choices": section["choices"], "fields": fields}


def set_resolution(eboot, fields, resolution):
    values = dict(zip(("width", "height"), parse_resolution(resolution)))
    with open(eboot, "r+b") as file:
        for name, offset in fields["fields"]:
            file.seek(offset)
            file.write(struct.pack("<I", values[name]))


def apply(eboot, title_id, directory=PATCHES, check=False):
    """Applies the title's patches to `eboot`; returns (name, state) pairs, state being
    "applied", "already applied" or "skipped: <reason>"."""
    patches = load(title_id, directory)
    if not patches:
        return []
    data = bytearray(Path(eboot).read_bytes())
    segment_list = segments(data)
    results = []
    for patch in patches:
        planned = []
        state = None
        for edit in patch["edits"]:
            address = int(edit["address"], 16)
            original = bytes.fromhex(edit["original"])
            replacement = bytes.fromhex(edit["replacement"])
            if len(original) != len(replacement):
                raise ValueError(f"{patch['name']}: original and replacement at {edit['address']} differ in length")
            offset = file_offset(segment_list, address, len(original))
            current = bytes(data[offset:offset + len(original)])
            if current == original:
                planned.append((offset, replacement))
            elif current != replacement:
                state = f"skipped: {edit['address']} holds {current.hex()}, expected {original.hex()}"
                break
        if state is None:
            state = "applied" if planned else "already applied"
            if not check:
                for offset, replacement in planned:
                    data[offset:offset + len(replacement)] = replacement
        results.append((patch["name"], state))
    if not check:
        Path(eboot).write_bytes(data)
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("eboot", type=Path)
    parser.add_argument("title_id")
    parser.add_argument("--patches", type=Path, default=PATCHES)
    parser.add_argument("--check", action="store_true", help="report what would be applied without writing")
    parser.add_argument("--resolution", help="also write this WIDTHxHEIGHT output resolution")
    arguments = parser.parse_args()
    results = apply(arguments.eboot, arguments.title_id, arguments.patches, arguments.check)
    if not results:
        print(f"no patches for {arguments.title_id}")
    if arguments.resolution is not None and not arguments.check:
        fields = resolution_fields(arguments.eboot, arguments.title_id, arguments.patches)
        if fields is None:
            print(f"{arguments.title_id} has no output resolution to set in this build")
            return 1
        set_resolution(arguments.eboot, fields, arguments.resolution)
        print(f"resolution: {arguments.resolution}")
    for name, state in results:
        print(f"{name}: {state}")
    return 1 if any(state.startswith("skipped") for _, state in results) else 0


if __name__ == "__main__":
    sys.exit(main())
