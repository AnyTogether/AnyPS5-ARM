import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_web


def library_zip(entries):
    buffer = io.BytesIO()
    with warnings.catch_warnings(), zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        warnings.simplefilter("ignore", UserWarning)
        for name, data in entries:
            archive.writestr(name, data)
    return buffer.getvalue()


class LibraryPublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        self.libraries = self.output / "libraries"
        self.libraries.mkdir()
        self.manifest = self.output / "release.json"
        self.previous = b'{"tag":"previous complete release"}\n'
        self.manifest.write_bytes(self.previous)
        self.existing = self.libraries / "previous.zip"
        self.existing.write_bytes(b"previous archive")

    def publish(self, windows, linux):
        assets = []
        responses = {}
        for platform, data in (("windows", windows), ("linux", linux)):
            url = f"https://example.invalid/{platform}.zip"
            assets.append({"name": f"prx-{platform}-v1.zip", "size": len(data),
                           "digest": "sha256:" + hashlib.sha256(data).hexdigest(), "browser_download_url": url})
            responses[url] = data
        release = {"tag_name": "v1", "html_url": "https://example.invalid/v1", "assets": assets}
        responses["https://api.github.com/repos/boykopovar/AnyPS5/releases/latest"] = json.dumps(release).encode()
        with patch.object(build_web, "request", side_effect=lambda url: io.BytesIO(responses[url])), \
                contextlib.redirect_stdout(io.StringIO()):
            build_web.publish_libraries(self.output)

    def test_colliding_paths_do_not_publish_a_release(self):
        valid = library_zip([("libs/libc.prx", b"valid archive")])
        for first, second in (("libs/libc.prx", "libs/libc.prx"),
                              ("libs/libc.prx", "libs/LIBC.prx"),
                              ("libs/extra/", "libs/EXTRA")):
            with self.subTest(first=first, second=second):
                invalid = library_zip([(first, b"" if first.endswith("/") else b"first"), (second, b"second")])
                with self.assertRaisesRegex(ValueError, "Duplicate library archive path"):
                    self.publish(invalid, valid)
                self.assertEqual(self.manifest.read_bytes(), self.previous)
                self.assertEqual(self.existing.read_bytes(), b"previous archive")
                self.assertEqual(list(self.libraries.iterdir()), [self.existing])

    def test_collision_in_second_platform_preserves_previous_manifest(self):
        valid = library_zip([("libs/libc.prx", b"valid archive")])
        invalid = library_zip([("libs/libc.prx", b"first"), ("libs/LIBC.prx", b"second")])
        with self.assertRaisesRegex(ValueError, "Duplicate library archive path"):
            self.publish(valid, invalid)
        self.assertEqual(self.manifest.read_bytes(), self.previous)
        self.assertEqual(self.existing.read_bytes(), b"previous archive")
        self.assertFalse(any(file.suffix == ".download" for file in self.libraries.iterdir()))

    def test_distinct_full_paths_publish_both_platforms(self):
        payload = library_zip([("libs/", b""), ("libs/libc.prx", b"first"), ("libs/extra/libc.prx", b"second")])
        self.publish(payload, payload)
        manifest = json.loads(self.manifest.read_text(encoding="utf-8"))
        self.assertEqual(manifest["tag"], "v1")
        self.assertEqual(set(manifest["platforms"]), {"windows", "linux"})
        for platform, asset in manifest["platforms"].items():
            digest = hashlib.sha256(payload).hexdigest()
            self.assertEqual(asset, {"path": f"libraries/{platform}-{digest}.zip", "size": len(payload),
                                     "expandedBytes": 11, "sha256": digest})
            self.assertEqual((self.output / asset["path"]).read_bytes(), payload)
        self.assertEqual(self.existing.read_bytes(), b"previous archive")
        self.assertFalse(any(file.suffix == ".download" for file in self.libraries.iterdir()))


if __name__ == "__main__":
    unittest.main()
