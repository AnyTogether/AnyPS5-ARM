import os
import sys
import tarfile
import tempfile
import unittest
import zipfile
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import package_release


@contextmanager
def working_directory(path):
    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class ReleasePackageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "source"
        self.build = self.root / "build"
        self.output = self.root / "output"
        (self.source / "core/libs/prx/libc").mkdir(parents=True)
        (self.source / "core/libs/prx/libc/Export.cpp").write_text("", encoding="utf-8")
        libraries = self.build / "core/libs/libs"
        libraries.mkdir(parents=True)
        self.library = libraries / "libc.prx"
        self.library.write_bytes(b"library bytes")
        binary = self.build / "core/relinker/relinker"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"relinker bytes")
        self.addCleanup(patch.stopall)
        patch.object(package_release, "ROOT", self.source, create=True).start()

    def test_source_discovery_does_not_depend_on_working_directory(self):
        with working_directory(self.root):
            package_release.package("linux", self.build, self.output, "v1.0")
        self.assertEqual((self.output / "relinker-v1.0").read_bytes(), b"relinker bytes")
        with zipfile.ZipFile(self.output / "prx-linux-v1.0.zip") as archive:
            self.assertEqual(archive.read("libs/libc.prx"), b"library bytes")

    def test_hidden_cache_directory_is_not_a_required_library(self):
        (self.source / "core/libs/prx/.cache").mkdir()
        with working_directory(self.source):
            package_release.package("linux", self.build, self.output, "v1.0")
        with zipfile.ZipFile(self.output / "prx-linux-v1.0.zip") as archive:
            self.assertEqual(archive.namelist(), ["libs/libc.prx"])

    def test_removed_libraries_are_not_packaged_from_a_reused_build(self):
        stale = self.library.with_name("libRemoved.prx")
        stale.write_bytes(b"obsolete library")
        package_release.package("linux", self.build, self.output, "v1.0")
        with zipfile.ZipFile(self.output / "prx-linux-v1.0.zip") as archive:
            self.assertEqual(archive.namelist(), ["libs/libc.prx"])
            self.assertEqual(archive.read("libs/libc.prx"), b"library bytes")
        with tarfile.open(self.output / "prx-linux-v1.0.tar.gz") as archive:
            self.assertEqual(archive.getnames(), ["libs/libc.prx"])
            self.assertEqual(archive.extractfile("libs/libc.prx").read(), b"library bytes")
        self.assertEqual(stale.read_bytes(), b"obsolete library")

    def test_tar_and_zip_include_the_same_symlink_contents(self):
        target = self.library.with_name("libc.target")
        self.library.rename(target)
        try:
            self.library.symlink_to(target.name)
        except (OSError, NotImplementedError) as error:
            self.skipTest(str(error))
        with working_directory(self.source):
            package_release.package("linux", self.build, self.output, "v1.0")
        with tarfile.open(self.output / "prx-linux-v1.0.tar.gz") as archive:
            member = archive.getmember("libs/libc.prx")
            self.assertTrue(member.isfile())
            self.assertEqual(archive.extractfile(member).read(), b"library bytes")
        with zipfile.ZipFile(self.output / "prx-linux-v1.0.zip") as archive:
            self.assertEqual(archive.read("libs/libc.prx"), b"library bytes")

    def test_missing_real_library_still_fails(self):
        self.library.unlink()
        with working_directory(self.source), self.assertRaisesRegex(RuntimeError, "Missing patched libraries"):
            package_release.package("linux", self.build, self.output, "v1.0")

    def test_invalid_tag_creates_no_assets(self):
        with self.assertRaises(ValueError):
            package_release.package("linux", self.build, self.output, "../v1.0")
        self.assertFalse(self.output.exists())



class DocumentationAssetsTests(unittest.TestCase):
    def test_unique_nested_documents_are_flattened(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            (source / "nested").mkdir(parents=True)
            (source / "A.md").write_text("A", encoding="utf-8")
            (source / "nested/B.md").write_text("B", encoding="utf-8")
            output = Path(tmp) / "assets"
            package_release.collect_docs(source, output)
            self.assertEqual({file.name: file.read_text(encoding="utf-8") for file in output.iterdir()}, {"A.md": "A", "B.md": "B"})

    def test_existing_case_collision_preserves_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            source.mkdir()
            (source / "guide.md").write_text("new guide", encoding="utf-8")
            output = Path(tmp) / "assets"
            output.mkdir()
            (output / "Guide.md").write_text("old guide", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Duplicate release asset"):
                package_release.collect_docs(source, output)
            self.assertEqual([file.name for file in output.iterdir()], ["Guide.md"])
            self.assertEqual((output / "Guide.md").read_text(encoding="utf-8"), "old guide")

    def test_markdown_directory_is_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            source.mkdir()
            (source / "A.md").write_text("A", encoding="utf-8")
            (source / "Z.md").mkdir()
            output = Path(tmp) / "assets"
            package_release.collect_docs(source, output)
            self.assertEqual([file.name for file in output.iterdir()], ["A.md"])
            self.assertEqual((output / "A.md").read_text(encoding="utf-8"), "A")

    def test_case_colliding_assets_fail_before_copying(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            (source / "one").mkdir(parents=True)
            (source / "two").mkdir()
            (source / "one/Guide.md").write_text("one", encoding="utf-8")
            (source / "two/guide.md").write_text("two", encoding="utf-8")
            output = Path(tmp) / "assets"
            with self.assertRaisesRegex(RuntimeError, "Duplicate release asset"):
                package_release.collect_docs(source, output)
            self.assertFalse(output.exists())

    def test_dangling_asset_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            source.mkdir()
            (source / "Guide.md").write_text("guide", encoding="utf-8")
            output = Path(tmp) / "assets"
            output.mkdir()
            target = Path(tmp) / "outside.md"
            try:
                (output / "Guide.md").symlink_to(target)
            except (OSError, NotImplementedError) as error:
                self.skipTest(str(error))
            with self.assertRaisesRegex(RuntimeError, "Duplicate release asset"):
                package_release.collect_docs(source, output)
            self.assertFalse(target.exists())
            self.assertTrue((output / "Guide.md").is_symlink())


class ReleaseAssetsTests(unittest.TestCase):
    def test_failed_tar_creation_preserves_existing_release_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            (source / "core/libs/prx/libc").mkdir(parents=True)
            build = root / "build"
            (build / "core/libs/libs").mkdir(parents=True)
            (build / "core/libs/libs/libc.prx").write_bytes(b"new library")
            (build / "core/relinker").mkdir(parents=True)
            (build / "core/relinker/relinker").write_bytes(b"new executable")
            output = root / "assets"
            output.mkdir()
            names = ["prx-linux-v1.zip", "prx-linux-v1.tar.gz", "relinker-v1"]
            for name in names:
                (output / name).write_bytes(b"old " + name.encode())
            with working_directory(source), patch.object(package_release, "ROOT", source), \
                    patch.object(package_release.tarfile, "open", side_effect=OSError("disk full")), \
                    self.assertRaisesRegex(OSError, "disk full"):
                package_release.package("linux", build, output, "v1")
            self.assertEqual(sorted(file.name for file in output.iterdir()), sorted(names))
            for name in names:
                self.assertEqual((output / name).read_bytes(), b"old " + name.encode())


if __name__ == "__main__":
    unittest.main()
