from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "macos"))
import moltenvk_patches

FUNCTION = 0x2010


def thin_image(body):
    command = struct.pack("<II16sQQQQiiII", moltenvk_patches.LC_SEGMENT_64, 72, b"__TEXT", 0, 0x4000, 0, 0x4000, 5, 5, 0, 0)
    header = struct.pack("<IiiIIIII", moltenvk_patches.MH_MAGIC_64, moltenvk_patches.CPU_TYPE_X86_64, 3, 6, 1, len(command), 0, 0)
    image = bytearray(header + command)
    image += bytes(0x4000 - len(image))
    image[FUNCTION:FUNCTION + len(body)] = body
    return bytes(image)


def universal(image):
    offset = 0x1000
    header = struct.pack(">II", moltenvk_patches.FAT_MAGIC, 2)
    header += struct.pack(">iiIII", 0x0100000C, 0, offset + len(image), 16, 12)
    header += struct.pack(">iiIII", moltenvk_patches.CPU_TYPE_X86_64, 3, offset, len(image), 12)
    return header + bytes(offset - len(header)) + image + bytes(16)


class MoltenVkPatchTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.library = Path(directory.name) / "libMoltenVK.dylib"
        signing = mock.patch.object(moltenvk_patches.subprocess, "run")
        self.sign = signing.start()
        self.addCleanup(signing.stop)

    def test_patches_the_x86_64_slice_of_a_universal_library(self):
        self.library.write_bytes(universal(thin_image(moltenvk_patches.PROLOGUE + b"\x41\x57")))
        self.assertEqual(moltenvk_patches.apply(self.library, address=FUNCTION), "applied")
        data = self.library.read_bytes()
        self.assertEqual(data[0x1000 + FUNCTION:0x1000 + FUNCTION + 4], b"\xc3\x48\x89\xe5")
        self.assertEqual(self.sign.call_args.args[0][:3], ["codesign", "--force", "--sign"])
        self.assertEqual(moltenvk_patches.apply(self.library, address=FUNCTION), "already applied")

    def test_other_code_is_left_alone(self):
        original = thin_image(b"\x55\x48\x8b\xec")
        self.library.write_bytes(original)
        self.assertTrue(moltenvk_patches.apply(self.library, address=FUNCTION).startswith("skipped"))
        self.assertEqual(self.library.read_bytes(), original)
        self.sign.assert_not_called()

    def test_check_does_not_write(self):
        original = thin_image(moltenvk_patches.PROLOGUE)
        self.library.write_bytes(original)
        self.assertEqual(moltenvk_patches.apply(self.library, check=True, address=FUNCTION), "applied")
        self.assertEqual(self.library.read_bytes(), original)

    def test_missing_symbol_is_reported(self):
        self.library.write_bytes(thin_image(moltenvk_patches.PROLOGUE))
        with mock.patch.object(moltenvk_patches, "symbol_address", return_value=None):
            self.assertTrue(moltenvk_patches.apply(self.library).startswith("skipped"))


if __name__ == "__main__":
    unittest.main()
