"""Patches the MoltenVK library bundled with a macOS title.

    python3 tools/macos/moltenvk_patches.py <libMoltenVK.dylib> [--check]

MVKDevice::encodeGPUAddressableBuffers adds every buffer created with SHADER_DEVICE_ADDRESS to each
Metal encoder whose pipeline declares PhysicalStorageBufferAddresses. The AGC driver keeps thousands
of such buffers (host imports of guest memory), and under Rosetta each of those encoders then took
0.5-2.7 ms, most of the time vkQueueSubmit spends. MoltenVK 1.4 makes its allocations resident through
an MTLResidencySet, so the patch makes the function return at once. The x86_64 slice is patched (the
title runs under Rosetta), only when the function still starts with the expected frame setup, and the
library is signed again ad hoc."""
import argparse
import struct
import subprocess
import sys
from pathlib import Path

SYMBOL = "__ZN9MVKDevice27encodeGPUAddressableBuffersER20MVKUseResourceHelper22MVKResourceUsageStages"
PROLOGUE = bytes.fromhex("554889e5")
RETURN = b"\xc3"
FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_X86_64 = 0x01000007
LC_SEGMENT_64 = 0x19


def x86_64_slice(data):
    """The file offset of the x86_64 Mach-O image in `data` (a universal or thin library)."""
    if struct.unpack_from(">I", data, 0)[0] == FAT_MAGIC:
        count = struct.unpack_from(">I", data, 4)[0]
        for index in range(count):
            cputype, _, offset, _, _ = struct.unpack_from(">iiIII", data, 8 + index * 20)
            if cputype == CPU_TYPE_X86_64:
                return offset
        raise ValueError("no x86_64 slice")
    magic, cputype = struct.unpack_from("<Ii", data, 0)
    if magic != MH_MAGIC_64 or cputype != CPU_TYPE_X86_64:
        raise ValueError("not an x86_64 Mach-O image")
    return 0


def file_offset(data, image, address):
    _, _, _, _, count, _, _, _ = struct.unpack_from("<IiiIIIII", data, image)
    cursor = image + 32
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, cursor)
        if command == LC_SEGMENT_64:
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, cursor + 24)
            if vmaddr <= address < vmaddr + min(vmsize, filesize):
                return image + fileoff + address - vmaddr
        cursor += size
    raise ValueError(f"0x{address:x} is not in a file-backed segment")


def symbol_address(library):
    listing = subprocess.run(["nm", "-arch", "x86_64", str(library)], check=True, capture_output=True, text=True).stdout
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == SYMBOL:
            return int(fields[0], 16)
    return None


def apply(library, check=False, address=None):
    """Returns "applied", "already applied" or "skipped: <reason>"."""
    library = Path(library)
    address = symbol_address(library) if address is None else address
    if address is None:
        return "skipped: MVKDevice::encodeGPUAddressableBuffers not found"
    data = bytearray(library.read_bytes())
    offset = file_offset(data, x86_64_slice(data), address)
    current = bytes(data[offset:offset + len(PROLOGUE)])
    if current[:1] == RETURN:
        return "already applied"
    if current != PROLOGUE:
        return f"skipped: the function starts with {current.hex()}, expected {PROLOGUE.hex()}"
    if check:
        return "applied"
    data[offset:offset + 1] = RETURN
    library.write_bytes(data)
    subprocess.run(["codesign", "--force", "--sign", "-", str(library)], check=True, capture_output=True)
    return "applied"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("library", type=Path)
    parser.add_argument("--check", action="store_true", help="report what would be done without writing")
    arguments = parser.parse_args()
    state = apply(arguments.library, arguments.check)
    print(f"{arguments.library.name}: {state}")
    return 1 if state.startswith("skipped") else 0


if __name__ == "__main__":
    sys.exit(main())
