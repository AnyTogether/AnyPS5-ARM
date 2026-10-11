from pathlib import Path
import json
import struct
import subprocess
import sys
import tempfile

PT_LOAD = 1
PT_DYNAMIC = 2
PT_GNU_EH_FRAME = 0x6474E550
PT_SCE_DYNLIBDATA = 0x61000000
PT_SCE_VERSION = 0x6FFFFF01
FUNCTION = 0x200
FUNCTION_SIZE = 0x10
GOT = 0xA00
EH_FRAME_HEADER = 0x800
EH_FRAME = 0x840


def fixture(sce_block=True, plt_push_offset=8, gap=0):
    plt = FUNCTION + FUNCTION_SIZE + gap
    data = plt + 0x20
    image = bytearray(0x1000)
    image[:16] = b"\x7fELF\x02\x01\x01" + bytes(9)
    struct.pack_into("<HHIQQQIHHHHHH", image, 16, 3, 62, 1, FUNCTION, 64, 0, 0, 64, 56, 4, 64, 0, 0)
    tags = [
        (1, 1),
        (0x61000035, 0x600), (0x61000037, 16),
        (0x61000039, 0x620), (0x6100003B, 24), (0x6100003F, 48),
        (0x6100002F, 0x700), (0x61000031, 0), (0x61000033, 24),
        (0x61000027, GOT), (0x61000029, 0x720), (0x6100002B, 7), (0x6100002D, 24),
        (0, 0),
    ]
    struct.pack_into("<IIQQQQQQ", image, 64, PT_LOAD, 7, 0, 0, 0, len(image), len(image), 0x1000)
    struct.pack_into("<IIQQQQQQ", image, 120, PT_DYNAMIC, 6, 0x400, 0x400, 0x400, len(tags) * 16, len(tags) * 16, 8)
    struct.pack_into("<IIQQQQQQ", image, 176,
                     *((PT_SCE_DYNLIBDATA, 0, 0, 0, 0, len(image), len(image), 1) if sce_block
                       else (PT_SCE_VERSION, 0, 0, 0, 0, 0, 0, 1)))
    struct.pack_into("<IIQQQQQQ", image, 232, PT_GNU_EH_FRAME, 4, EH_FRAME_HEADER, EH_FRAME_HEADER, EH_FRAME_HEADER,
                     20, 20, 4)
    for index, tag in enumerate(tags):
        struct.pack_into("<qQ", image, 0x400 + index * 16, *tag)
    image[0x600:0x610] = b"\x00lib.so\x00symbol\x00\x00"
    struct.pack_into("<IBBHQQ", image, 0x620 + 24, 8, 0x12, 0, 0, 0, 0)
    struct.pack_into("<QQq", image, 0x720, GOT + 24, (1 << 32) | 7, 0)

    image[FUNCTION:FUNCTION + FUNCTION_SIZE] = b"\xc3" + b"\x90" * (FUNCTION_SIZE - 1)
    image[FUNCTION + FUNCTION_SIZE:plt] = b"\x90" * gap
    image[plt:plt + 2] = b"\xff\x35"
    struct.pack_into("<i", image, plt + 2, GOT + plt_push_offset - (plt + 6))
    image[plt + 6:plt + 8] = b"\xff\x25"
    struct.pack_into("<i", image, plt + 8, GOT + 16 - (plt + 12))
    image[plt + 12:plt + 16] = b"\x0f\x1f\x40\x00"
    image[plt + 16:plt + 18] = b"\xff\x25"
    struct.pack_into("<i", image, plt + 18, GOT + 24 - (plt + 22))
    image[plt + 22] = 0x68
    struct.pack_into("<I", image, plt + 23, 0)
    image[plt + 27] = 0xE9
    struct.pack_into("<i", image, plt + 28, plt - (plt + 32))
    image[data:data + 0x30] = b"\x0f\x79\xc0" * 0x10

    cie = EH_FRAME
    cie_body = b"\x00\x00\x00\x00\x01zR\x00\x01\x78\x10\x01\x1b\x00\x00\x00"
    struct.pack_into("<I", image, cie, len(cie_body))
    image[cie + 4:cie + 4 + len(cie_body)] = cie_body
    fde = cie + 4 + len(cie_body)
    struct.pack_into("<IIiiB3x", image, fde, 16, fde + 4 - cie, FUNCTION - (fde + 8), FUNCTION_SIZE, 0)
    struct.pack_into("<I", image, fde + 20, 0)
    struct.pack_into("<BBBBiIii", image, EH_FRAME_HEADER, 1, 0x1B, 0x03, 0x3B,
                     EH_FRAME - (EH_FRAME_HEADER + 4), 1, FUNCTION - EH_FRAME_HEADER, fde - EH_FRAME_HEADER)
    return image, plt


def run(relinker, work, name, built, expected_error=None):
    image, plt = built
    source = work / (name + ".elf")
    output = work / (name + ".out")
    source.write_bytes(image)
    result = subprocess.run([str(relinker), "--skip-sce-module", "--windows", "--registry", str(source), str(output)],
                            capture_output=True, text=True, timeout=20)
    if expected_error is None:
        assert result.returncode == 0 and output.exists(), (name, result.stdout, result.stderr)
        registry = json.loads((work / (name + ".registry.json")).read_text())
        assert [entry["callSites"] for entry in registry] == [[hex(plt + 16)]], (name, registry)
    else:
        assert result.returncode == 2 and expected_error in result.stderr and not output.exists(), (
            name, result.returncode, result.stdout, result.stderr)


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="anyps5-sce-code-extent-") as directory:
        work = Path(directory)
        run(relinker, work, "sce-data-after-plt", fixture())
        run(relinker, work, "sce-code-between-function-and-plt", fixture(gap=0x40))
        run(relinker, work, "sce-plt-missing", fixture(plt_push_offset=0),
            "PLT not found after the last unwind function")
        run(relinker, work, "sysv-data-after-plt", fixture(sce_block=False),
            "Cannot decode instruction")
    print("SCE code extent tests passed")


if __name__ == "__main__":
    main()
