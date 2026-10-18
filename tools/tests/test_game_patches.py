import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "macos"))
import game_patches

BASE = 0x140000000
SEGMENT_OFFSET = 0x1000


def executable(body):
    """A Mach-O header with one segment mapping `body` at BASE + SEGMENT_OFFSET."""
    command = struct.pack("<II16sQQQQiiII", game_patches.LC_SEGMENT_64, 72, b"__ELF0", BASE + SEGMENT_OFFSET, len(body), SEGMENT_OFFSET, len(body), 5, 5, 0, 0)
    header = struct.pack("<IiiIIIII", game_patches.MH_MAGIC_64, 0x01000007, 3, 2, 1, len(command), 0, 0)
    image = bytearray(header + command)
    image += bytes(SEGMENT_OFFSET - len(image))
    return bytes(image + body)


class GamePatchTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.eboot = self.root / "eboot"
        (self.root / "TEST00001.json").write_text(json.dumps({"patches": [{"name": "resolution", "edits": [
            {"address": hex(BASE + SEGMENT_OFFSET + 4), "original": "ba000f0000", "replacement": "ba80070000"},
            {"address": hex(BASE + SEGMENT_OFFSET + 12), "original": "0f84", "replacement": "90e9"}]}]}), encoding="utf-8")

    def run_patches(self, body, check=False):
        self.eboot.write_bytes(executable(body))
        results = game_patches.apply(self.eboot, "TEST00001", self.root, check)
        return results, self.eboot.read_bytes()[SEGMENT_OFFSET:]

    def test_applies_every_edit_through_the_segment_mapping(self):
        results, body = self.run_patches(bytes(4) + bytes.fromhex("ba000f0000") + bytes(3) + bytes.fromhex("0f84") + bytes(2))
        self.assertEqual(results, [("resolution", "applied")])
        self.assertEqual(body, bytes(4) + bytes.fromhex("ba80070000") + bytes(3) + bytes.fromhex("90e9") + bytes(2))

    def test_reapplying_changes_nothing(self):
        patched = bytes(4) + bytes.fromhex("ba80070000") + bytes(3) + bytes.fromhex("90e9") + bytes(2)
        results, body = self.run_patches(patched)
        self.assertEqual(results, [("resolution", "already applied")])
        self.assertEqual(body, patched)

    def test_other_build_is_left_untouched(self):
        other = bytes(4) + bytes.fromhex("ba000f0000") + bytes(3) + bytes.fromhex("7405") + bytes(2)
        results, body = self.run_patches(other)
        self.assertTrue(results[0][1].startswith("skipped"))
        self.assertEqual(body, other)

    def test_check_does_not_write(self):
        original = bytes(4) + bytes.fromhex("ba000f0000") + bytes(3) + bytes.fromhex("0f84") + bytes(2)
        results, body = self.run_patches(original, check=True)
        self.assertEqual(results, [("resolution", "applied")])
        self.assertEqual(body, original)

    def test_title_without_patches(self):
        self.eboot.write_bytes(executable(bytes(16)))
        self.assertEqual(game_patches.apply(self.eboot, "NONE00000", self.root), [])

    def write_resolution(self):
        (self.root / "TEST00002.json").write_text(json.dumps({"resolution": {"default": "1920x1080", "choices": ["1280x720", "1920x1080"], "fields": [
            {"value": "width", "address": hex(BASE + SEGMENT_OFFSET + 4), "instruction": "ba000f0000", "offset": 1},
            {"value": "height", "address": hex(BASE + SEGMENT_OFFSET + 12), "instruction": "ba70080000", "offset": 1}]}}), encoding="utf-8")

    def test_resolution_is_written_into_the_fields(self):
        self.write_resolution()
        self.eboot.write_bytes(executable(bytes(4) + bytes.fromhex("ba000f0000") + bytes(3) + bytes.fromhex("ba70080000") + bytes(3)))
        fields = game_patches.resolution_fields(self.eboot, "TEST00002", self.root)
        self.assertEqual(fields["fields"], [("width", SEGMENT_OFFSET + 5), ("height", SEGMENT_OFFSET + 13)])
        game_patches.set_resolution(self.eboot, fields, "1280x720")
        body = self.eboot.read_bytes()[SEGMENT_OFFSET:]
        self.assertEqual(body[4:9], bytes.fromhex("ba00050000"))
        self.assertEqual(body[12:17], bytes.fromhex("bad0020000"))
        game_patches.set_resolution(self.eboot, game_patches.resolution_fields(self.eboot, "TEST00002", self.root), "1920x1080")
        self.assertEqual(self.eboot.read_bytes()[SEGMENT_OFFSET + 4:SEGMENT_OFFSET + 9], bytes.fromhex("ba80070000"))

    def test_resolution_needs_the_instructions(self):
        self.write_resolution()
        self.eboot.write_bytes(executable(bytes(20)))
        self.assertIsNone(game_patches.resolution_fields(self.eboot, "TEST00002", self.root))
        self.assertIsNone(game_patches.resolution_fields(self.eboot, "TEST00001", self.root))

    def test_resolution_text_is_validated(self):
        for text in ("1920", "x1080", "0x720", "axb"):
            with self.assertRaises(ValueError):
                game_patches.parse_resolution(text)
        self.assertEqual(game_patches.parse_resolution("2560X1440"), (2560, 1440))

    def test_shipped_patch_files_are_well_formed(self):
        for path in game_patches.PATCHES.glob("*.json"):
            for patch in game_patches.load(path.stem):
                for edit in patch["edits"]:
                    self.assertEqual(len(bytes.fromhex(edit["original"])), len(bytes.fromhex(edit["replacement"])), path.name)
                    int(edit["address"], 16)
            section = game_patches.definition(path.stem).get("resolution")
            if section is not None:
                self.assertIn(section["default"], section["choices"], path.name)
                for choice in section["choices"]:
                    game_patches.parse_resolution(choice)
                self.assertEqual(sorted(field["value"] for field in section["fields"]), ["height", "width"], path.name)


if __name__ == "__main__":
    unittest.main()
