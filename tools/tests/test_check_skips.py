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
    "skipped, the device lacks VK_EXT_shader_stencil_export",
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
    def test_disabled_tests_fail_in_both_jobs_including_agc(self):
        xml = '<testsuite><testcase name="agc_disabled" status="disabled"/></testsuite>'
        with tempfile.TemporaryDirectory() as directory:
            junit = Path(directory) / "junit.xml"
            junit.write_text(xml, encoding="utf-8")
            for job in ("linux", "windows"):
                with self.subTest(job=job):
                    result = subprocess.run(
                        [sys.executable, "-I", str(TOOL), str(junit), "--job", job],
                        capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("agc_disabled", result.stderr)
                    self.assertIn("disabled", result.stderr)

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




class SkipReportTests(unittest.TestCase):
    def skipped(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ctest.xml"
            path.write_text(content, encoding="utf-8")
            return list(check_skips.skips(path))

    def test_ctest_disabled_status_is_not_silently_ignored(self):
        with self.assertRaisesRegex(ValueError, "disabled.*not run"):
            self.skipped('<testsuite><testcase name="coverage" status="disabled"/></testsuite>')

    def test_device_message_does_not_excuse_a_disabled_test(self):
        with self.assertRaisesRegex(ValueError, "disabled.*not run"):
            self.skipped('<testsuite><testcase name="gpu" status="disabled"><skipped message="no display"/></testcase></testsuite>')

    def test_running_test_without_skipped_marker_is_not_a_skip(self):
        self.assertEqual(self.skipped('<testsuite><testcase name="coverage" status="run"/></testsuite>'), [])

    def test_skip_message_preserves_the_device_reason(self):
        found = self.skipped('<testsuite><testcase name="gpu"><skipped message="the device has no required extension"/></testcase></testsuite>')
        self.assertEqual(len(found), 1)
        self.assertRegex(found[0][1], check_skips.DEVICE_LIMITATION)

    def test_stderr_preserves_the_device_reason(self):
        found = self.skipped('<testsuite><testcase name="gpu"><skipped/><system-err>skipped, no display</system-err></testcase></testsuite>')
        self.assertEqual(len(found), 1)
        self.assertRegex(found[0][1], check_skips.DEVICE_LIMITATION)

    def test_unnamed_skipped_test_is_an_error(self):
        with self.assertRaises(ValueError):
            self.skipped('<testsuite><testcase><skipped/></testcase></testsuite>')

    def test_unexpected_reason_stays_unexpected(self):
        found = self.skipped('<testsuite><testcase name="gpu"><skipped message="producer finished too early"/></testcase></testsuite>')
        self.assertIsNone(check_skips.DEVICE_LIMITATION.search(found[0][1]))

    def test_ctest_stdout_is_retained(self):
        found = self.skipped('<testsuite><testcase name="gpu"><skipped/><system-out>skipped, the device reports too few descriptors</system-out></testcase></testsuite>')
        self.assertRegex(found[0][1], check_skips.DEVICE_LIMITATION)

    def test_message_and_element_text_are_both_retained(self):
        found = self.skipped('<testsuite><testcase name="gpu"><skipped message="unsupported">the device has no required extension</skipped></testcase></testsuite>')
        self.assertRegex(found[0][1], check_skips.DEVICE_LIMITATION)


if __name__ == "__main__":
    unittest.main()
