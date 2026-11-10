from pathlib import Path
import contextlib
import io
import re
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "macos"))
import minimum_macos

REPOSITORY = Path(__file__).resolve().parents[2]


def packed(major, minor, patch=0):
    return major << 16 | minor << 8 | patch


def build_version(major, minor, platform=minimum_macos.PLATFORM_MACOS):
    return struct.pack("<IIIIII", minimum_macos.LC_BUILD_VERSION, 24, platform, packed(major, minor), packed(26, 0), 0)


def version_min(major, minor):
    return struct.pack("<IIII", minimum_macos.LC_VERSION_MIN_MACOSX, 16, packed(major, minor), packed(26, 0))


def uuid_command():
    return struct.pack("<II16s", 0x1B, 24, bytes(16))


def thin_image(*commands, cpu=minimum_macos.CPU_TYPE_X86_64):
    body = b"".join(commands)
    header = struct.pack("<IiiIIIII", minimum_macos.MH_MAGIC_64, cpu, 3, 6, len(commands), len(body), 0, 0)
    return header + body + bytes(64)


def universal(*images):
    offset = 0x1000
    header = struct.pack(">II", minimum_macos.FAT_MAGIC, len(images))
    placed = b""
    for cpu, image in images:
        header += struct.pack(">iiIII", cpu, 3, offset + len(placed), len(image), 12)
        placed += image + bytes(-len(image) % 0x1000)
    return header + bytes(offset - len(header)) + placed


class MinimumMacOsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.folder = Path(directory.name)

    def write(self, name, data):
        path = self.folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def run_main(self, *arguments):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = minimum_macos.main([str(argument) for argument in arguments])
        return code, output.getvalue(), errors.getvalue()

    def test_reads_the_build_version_after_other_commands(self):
        self.assertEqual(minimum_macos.minimum(thin_image(uuid_command(), build_version(26, 0))), (26, 0, 0))

    def test_reads_the_older_version_min_command(self):
        self.assertEqual(minimum_macos.minimum(thin_image(version_min(10, 15))), (10, 15, 0))

    def test_a_build_version_for_another_platform_names_no_macos(self):
        self.assertIsNone(minimum_macos.minimum(thin_image(build_version(17, 0, platform=2))))

    def test_a_universal_file_names_its_newest_slice(self):
        data = universal((minimum_macos.CPU_TYPE_X86_64, thin_image(build_version(11, 0))),
                         (0x0100000C, thin_image(build_version(14, 0), cpu=0x0100000C)))
        self.assertEqual(minimum_macos.minimum(data), (14, 0, 0))

    def test_a_folder_passes_at_the_minimum_and_skips_other_files(self):
        self.write("libs/libkernel.prx", thin_image(build_version(14, 0)))
        self.write("vulkan/libMoltenVK.dylib", universal((minimum_macos.CPU_TYPE_X86_64, thin_image(build_version(12, 0)))))
        self.write("patches/PPSA00000.json", b"{}")
        self.write("version.txt", b"0.2.36-arm-0123456789ab\n")
        code, output, errors = self.run_main(self.folder, "--at-most", "14.0")
        self.assertEqual(code, 0, errors)
        self.assertIn("12.0 (1 files), 14.0 (1 files)", output)

    def test_a_file_above_the_minimum_fails_and_is_named(self):
        self.write("relinker", thin_image(build_version(14, 0)))
        self.write("libs/libSceVideoOut.prx", thin_image(build_version(26, 0)))
        code, _, errors = self.run_main(self.folder, "--at-most", "14.0")
        self.assertEqual(code, 1)
        self.assertIn("libSceVideoOut.prx: built for macOS 26.0, newer than 14.0", errors)
        self.assertNotIn("relinker:", errors)

    def test_report_only_names_the_files(self):
        self.write("libs/libc.prx", thin_image(build_version(15, 4)))
        code, _, errors = self.run_main(self.folder, "--at-most", "14.0", "--report")
        self.assertEqual(code, 0)
        self.assertIn("libc.prx: built for macOS 15.4", errors)

    def test_reads_a_zip_without_unpacking_it(self):
        archive = self.folder / "AnyPS5-toolkit-macos-0.2.36-arm.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zipped:
            zipped.writestr("AnyPS5-toolkit-macos-0.2.36-arm/relinker", thin_image(build_version(14, 0)))
            zipped.writestr("AnyPS5-toolkit-macos-0.2.36-arm/libs/libSceNKWebKit.prx", thin_image(build_version(26, 0)))
            zipped.writestr("AnyPS5-toolkit-macos-0.2.36-arm/toolkit.json", "{}")
        code, output, errors = self.run_main(archive, "--at-most", "14.0")
        self.assertEqual(code, 1)
        self.assertIn("14.0 (1 files), 26.0 (1 files)", output)
        self.assertIn("libs/libSceNKWebKit.prx: built for macOS 26.0", errors)

    def test_no_mach_o_files_is_an_error(self):
        self.write("toolkit.json", b"{}")
        code, _, errors = self.run_main(self.folder, "--at-most", "14.0")
        self.assertEqual(code, 1)
        self.assertIn("no Mach-O files", errors)

    def test_the_default_is_the_minimum_cmake_builds_for(self):
        self.assertEqual(minimum_macos.configured_minimum(), (14, 0, 0))

    def test_the_engine_and_the_launcher_name_the_same_oldest_macos(self):
        major, minor, _ = minimum_macos.configured_minimum()
        package = (REPOSITORY / "tools/macos/launcher/Package.swift").read_text(encoding="utf-8")
        self.assertIn(f".macOS(.v{major})", package)
        app = (REPOSITORY / "tools/macos/build_launcher_app.sh").read_text(encoding="utf-8")
        self.assertIn(f"<key>LSMinimumSystemVersion</key><string>{major}.{minor}</string>", app)
        layout = (REPOSITORY / "tools/macos/toolkit_layout.sh").read_text(encoding="utf-8")
        self.assertTrue(re.search(r"minimum_macos\.py", layout), "the toolkit is checked when it is put together")


if __name__ == "__main__":
    unittest.main()
