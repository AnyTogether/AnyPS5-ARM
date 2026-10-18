import struct
import sys
import unittest
from pathlib import Path

from test_symbol_versions import build_image, symbols, patch, HASH_OFFSET, SHOFF, read_dynsym, gnu_hash


class GnuHashTests(unittest.TestCase):
    def image(self, buckets=4, bloom=1, shift=6, symoffset=3):
        image = build_image(symbols(False), False)
        count = len(symbols(False))
        struct.pack_into("<IIII", image, HASH_OFFSET, buckets, symoffset, bloom, shift)
        size = 16 + 8 * bloom + 4 * buckets + 4 * max(0, count - symoffset)
        struct.pack_into("<Q", image, SHOFF + 3 * 64 + 32, size)
        return image

    def test_non_power_of_two_bloom_is_rejected(self):
        self.reject(self.image(bloom=3))

    def test_hash_shift_outside_word_is_rejected(self):
        self.reject(self.image(shift=32))

    def test_unsafe_geometry_is_rejected(self):
        for fields in ({"bloom": 0}, {"buckets": 0}, {"symoffset": 100}):
            with self.subTest(fields=fields):
                self.reject(self.image(**fields))

    def test_declared_section_extent_is_checked(self):
        for size in (12, 16, 0x10000):
            with self.subTest(size=size):
                image = self.image()
                struct.pack_into("<Q", image, SHOFF + 3 * 64 + 32, size)
                self.reject(image)

    def reject(self, image):
        result, after = patch(PATCHER, bytes(image), "geometry.so")
        self.assertEqual(result.returncode, 2, (result.returncode, result.stderr))
        self.assertIn(b"gnu.hash", result.stderr)
        self.assertEqual(after, image)

    def test_rebuilt_hash_finds_every_export(self):
        image = self.image(bloom=2)
        result, after = patch(PATCHER, image, "valid.so")
        self.assertEqual(result.returncode, 0, result.stderr)
        entries = read_dynsym(after)
        buckets, first, bloom, shift = struct.unpack_from("<4I", after, HASH_OFFSET)
        bucket_offset = HASH_OFFSET + 16 + bloom * 8
        chain_offset = bucket_offset + buckets * 4
        for index in range(first, len(entries)):
            name = entries[index][0]
            hashed = gnu_hash(name)
            word = struct.unpack_from("<Q", after, HASH_OFFSET + 16 + ((hashed // 64) % bloom) * 8)[0]
            self.assertTrue(word & (1 << (hashed % 64)))
            self.assertTrue(word & (1 << ((hashed >> shift) % 64)))
            start = struct.unpack_from("<I", after, bucket_offset + (hashed % buckets) * 4)[0]
            found = False
            for candidate in range(start, len(entries)):
                value = struct.unpack_from("<I", after, chain_offset + (candidate - first) * 4)[0]
                if (value | 1) == (hashed | 1) and entries[candidate][0] == name:
                    found = True
                if value & 1:
                    break
            self.assertTrue(found, name)

    def test_empty_hash_with_no_buckets_is_supported(self):
        image = self.image(buckets=0, symoffset=len(symbols(False)))
        result, after = patch(PATCHER, image, "empty.so")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(struct.unpack_from("<I", after, HASH_OFFSET)[0], 0)


if __name__ == "__main__":
    PATCHER = Path(sys.argv.pop(1)).resolve()
    unittest.main()
