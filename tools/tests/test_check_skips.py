from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_skips

TOOL = Path(__file__).resolve().parents[1] / "check_skips.py"

LIMITATIONS = [
    "skipped, the device lacks fragmentShaderPixelInterlock",
    "skipped, the device lacks geometryShader",
    "skipped, the device lacks shaderSubgroupClock",
    "skipped, the device does not import guest memory",
    "skipped, the device imports no host memory",
    "skipped, the device flushes f64 subnormals without DenormPreserve",
    "skipped, the device binds fewer than 8 storage buffers per stage or set",
    "skipped, no usable Vulkan device: ErrorInitializationFailed",
    "skipped, unit shadows or host imports are unavailable",
    "skipped, the device has no compute queue",
    "skipped, the device reports 4 lanes",
    "skipped, subgroup size 8",
    "skipped, no display",
]

OTHER = [
    "skipped, flaky",
    "skipped, APS5_RAYTRACING replaces the node",
    "skipped, interpolation modes require",
]


class CheckSkipsTests(unittest.TestCase):
    def test_device_limitations_match(self):
        for message in LIMITATIONS:
            with self.subTest(message=message):
                self.assertTrue(check_skips.DEVICE_LIMITATION.search(message))

    def test_other_reasons_do_not_match(self):
        for message in OTHER:
            with self.subTest(message=message):
                self.assertFalse(check_skips.DEVICE_LIMITATION.search(message))

    def test_only_unexpected_skip_is_reported(self):
        xml = (
            '<testsuites><testsuite>'
            '<testcase name="geometry"><skipped/><system-out>skipped, the device lacks geometryShader</system-out></testcase>'
            '<testcase name="odd"><skipped/><system-out>skipped, flaky</system-out></testcase>'
            '</testsuite></testsuites>'
        )
        with tempfile.TemporaryDirectory() as directory:
            junit = Path(directory) / "junit.xml"
            junit.write_text(xml, encoding="utf-8")
            result = subprocess.run([sys.executable, "-I", str(TOOL), str(junit), "--job", "linux"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("error: odd skipped", result.stdout)
        self.assertNotIn("error: geometry skipped", result.stdout)


if __name__ == "__main__":
    unittest.main()
