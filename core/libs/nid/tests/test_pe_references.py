import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_macho_nids import build_dylib, exports_of, nid


def reference(*, headers=False, address=0x2000, ordinal=0):
    image = bytearray(1280)
    image[:2] = b"MZ"
    struct.pack_into("<I", image, 0x3c, 0x40)
    struct.pack_into("<IHHIIIHH", image, 0x40, 0x4550, 0x8664, 2, 0, 0, 0, 240, 0x2022)
    optional = 0x58
    struct.pack_into("<H", image, optional, 0x20b)
    struct.pack_into("<I", image, optional + 60, 512)
    struct.pack_into("<I", image, optional + 108, 16)
    start, rva = (416, 416) if headers else (512, 0x1000)
    struct.pack_into("<II", image, optional + 112, rva, 80)
    for index, (name, va, offset, size) in enumerate(((b".edata", 0x1000, 512, 256), (b".text", 0x2000, 768, 512))):
        struct.pack_into("<8sIIIIIIHHI", image, optional + 240 + index * 40,
                         name, size, va, size, offset, 0, 0, 0, 0, 0x40000040)
    struct.pack_into("<IIHHIIIIIII", image, start, 0, 0, 0, 0, rva + 50, 1, 1, 1, rva + 40, rva + 44, rva + 48)
    struct.pack_into("<IIH", image, start + 40, address, rva + 50, ordinal)
    name = b"puts_nid_postfix\0"
    image[start + 50:start + 50 + len(name)] = name
    return image


class ReferenceTests(unittest.TestCase):
    def patch_with_reference(self, data):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, ref = root / "target.dylib", root / "reference.bin"
            original = build_dylib([("_puts_nid_postfix", 0, 0x100), ("_exit_nid_postfix", 0, 0x108)], [])
            source.write_bytes(original)
            ref.write_bytes(data)
            result = subprocess.run([str(PATCHER), "libc", str(source), "--preserve-exports", str(ref)], capture_output=True, text=True)
            self.assertEqual(ref.read_bytes(), data)
            return result, source.read_bytes(), original

    def test_header_resident_export_tables(self):
        result, image, _ = self.patch_with_reference(reference(headers=True))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(exports_of(image), {"_puts_nid_postfix": (0, 0x100), "_" + nid("exit"): (0, 0x108)})

    def test_section_resident_export_tables(self):
        result, image, _ = self.patch_with_reference(reference())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("_puts_nid_postfix", exports_of(image))

    def test_null_function_slot_does_not_preserve_a_name(self):
        result, image, original = self.patch_with_reference(reference(address=0))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no named exports", result.stdout + result.stderr)
        self.assertEqual(image, original)

    def test_invalid_name_ordinal_is_rejected_without_changing_target(self):
        result, image, original = self.patch_with_reference(reference(ordinal=1))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ordinal", result.stdout + result.stderr)
        self.assertEqual(image, original)


if __name__ == "__main__":
    PATCHER = Path(sys.argv.pop(1)).resolve()
    unittest.main()
