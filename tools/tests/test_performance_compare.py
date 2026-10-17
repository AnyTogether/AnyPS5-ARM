import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import performance_compare


SUMMARY = {
    "commit": "abc123", "dirty": False, "env": {"APS5_TRACE_FRAMES": "600:4"},
    "gpu": "GPU", "driver": "Driver 1", "os": "OS 1", "resolution": "1920x1080",
    "window": {"spec": "frames 600:4", "first_present": 600, "ms": 80.0}, "presents": 4,
    "frame_ms": {"p50": 20.0, "p90": 40.0, "p99": 40.0, "max": 40.0},
    "gpu_busy_ms_per_present": 5.0, "worker_busy_pct": {"queue worker 0x0": 50.0},
    "top_phases_ms_per_frame": {"Driver.Packet": 12.0, "Driver.Present": 2.0},
    "trace_dropped": False, "trace": "aps5-trace-abc123-7.json.gz",
}


class PerformanceCompareTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.baseline = copy.deepcopy(SUMMARY)
        self.candidate = copy.deepcopy(SUMMARY)
        self.candidate.update(commit="def456", trace="aps5-trace-def456-8.json.gz")
        self.before = Path(self.directory.name) / "before.jsonl"
        self.after = Path(self.directory.name) / "after.jsonl"

    def write(self, path, *records):
        path.write_text("\n" + "\n\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(Path(performance_compare.__file__)), str(self.before), str(self.after), *args],
                              capture_output=True, text=True, encoding="utf-8", timeout=5,
                              env=dict(os.environ, PYTHONIOENCODING="ascii"))

    def test_timings_and_mean_are_compared_without_inverting_percentiles(self):
        self.candidate["window"]["ms"] = 40.0
        self.candidate["frame_ms"] = {"p50": 10.0, "p90": 20.0, "p99": 20.0, "max": 20.0}
        self.candidate["gpu_busy_ms_per_present"] = 3.0
        self.write(self.before, self.baseline)
        self.write(self.after, self.candidate)
        result = self.run_cli("--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        report = json.loads(result.stdout)
        self.assertEqual(report["metrics_ms"]["frame_ms.p99"],
                         {"baseline": 40.0, "candidate": 20.0, "change": -20.0, "change_pct": -50.0})
        self.assertEqual(report["metrics_ms"]["mean_frame_ms"]["candidate"], 10.0)
        self.assertEqual(report["metrics_ms"]["gpu_busy_ms_per_present"]["change_pct"], -40.0)
        self.assertEqual(report["configuration_differences"], {})
        self.assertEqual(report["baseline"], self.baseline)
        self.assertEqual(report["candidate"], self.candidate)

    def test_mean_uses_each_captures_own_present_count(self):
        self.candidate["presents"] = 8
        report = performance_compare.compare(self.baseline, self.candidate)
        self.assertEqual(report["metrics_ms"]["mean_frame_ms"]["change_pct"], -50.0)

    def test_zero_baseline_and_missing_top_phases_are_not_fake_improvements(self):
        self.baseline["gpu_busy_ms_per_present"] = 0.0
        self.candidate["top_phases_ms_per_frame"] = {"Driver.Packet": 18.0, "Driver.NewPhase": 1.0}
        report = performance_compare.compare(self.baseline, self.candidate)
        self.assertIsNone(report["metrics_ms"]["gpu_busy_ms_per_present"]["change_pct"])
        self.assertEqual(report["metrics_ms"]["gpu_busy_ms_per_present"]["change"], 5.0)
        self.assertEqual(report["top_phases_ms_per_frame"]["Driver.Packet"]["change_pct"], 50.0)
        for phase in ("Driver.Present", "Driver.NewPhase"):
            self.assertIsNone(report["top_phases_ms_per_frame"][phase]["change"])
            self.assertIsNone(report["top_phases_ms_per_frame"][phase]["change_pct"])
        self.assertIn("n/a", performance_compare.markdown(report))

    def test_exact_trace_selection_does_not_pick_the_last_session(self):
        self.write(self.before, self.baseline, self.candidate)
        self.write(self.after, self.candidate, self.baseline)
        original = (self.before.read_bytes(), self.after.read_bytes())
        result = self.run_cli("--baseline-trace", self.baseline["trace"], "--candidate-trace", self.candidate["trace"], "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["baseline"]["commit"], "abc123")
        self.assertEqual(report["candidate"]["commit"], "def456")
        self.assertEqual((self.before.read_bytes(), self.after.read_bytes()), original)

    def test_empty_ambiguous_missing_and_duplicate_selections_fail(self):
        self.write(self.after, self.candidate)
        for records, selector, count in (([], [], 0), ([self.baseline, self.candidate], [], 2),
                                         ([self.baseline], ["--baseline-trace", "absent"], 0),
                                         ([self.baseline, self.baseline], ["--baseline-trace", self.baseline["trace"]], 2)):
            with self.subTest(records=len(records), selector=selector):
                self.write(self.before, *records)
                result = self.run_cli(*selector)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn(f"found {count}", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_configuration_differences_and_incomplete_evidence_are_visible(self):
        self.candidate.update(gpu="Other GPU", driver="Driver 2", os="OS 2", resolution="1280x720",
                              dirty=True, trace_dropped=True)
        self.candidate["window"].update(spec="frames 800:4", first_present=800)
        self.candidate["env"] = {"APS5_TRACE_FRAMES": "800:4", "APS5_WORKER_AFFINITY": "1"}
        report = performance_compare.compare(self.baseline, self.candidate)
        self.assertEqual(set(report["configuration_differences"]),
                         {"gpu", "driver", "os", "resolution", "window.spec", "window.first_present",
                          "env.APS5_TRACE_FRAMES", "env.APS5_WORKER_AFFINITY"})
        self.assertIsNone(report["configuration_differences"]["env.APS5_WORKER_AFFINITY"]["baseline"])
        rendered = performance_compare.markdown(report)
        for text in ("Other GPU", "Driver 2", "source tree is dirty", "trace events were dropped", "do not isolate"):
            self.assertIn(text, rendered)

    def test_unknown_metadata_is_not_a_claim_of_equivalent_machines(self):
        self.baseline.update(dirty=None, gpu="", driver="")
        report = performance_compare.compare(self.baseline, self.candidate)
        notes = "\n".join(report["notes"])
        self.assertIn("state is unknown", notes)
        self.assertIn("missing configuration: gpu, driver", notes)
        self.assertIn("do not record the CPU, title or scene", notes)

    def test_invalid_metric_and_metadata_shapes_are_rejected_with_location(self):
        cases = [(("presents",), value) for value in (0, -1, True, 1.5, 10 ** 400)]
        cases += [(("window", "ms"), value) for value in (0, -1, True, "10", None, float("nan"), float("inf"))]
        cases += [(("frame_ms", "p50"), -1), (("frame_ms", "p50"), 50), (("frame_ms",), []),
                  (("gpu_busy_ms_per_present",), float("-inf")), (("window",), None),
                  (("window", "first_present"), True), (("env",), []), (("env",), {"APS5_TRACE_FRAMES": 4}),
                  (("trace_dropped",), "false"), (("dirty",), 1), (("trace",), None),
                  (("top_phases_ms_per_frame",), []), (("top_phases_ms_per_frame",), {"phase": -1})]
        for path, value in cases:
            with self.subTest(path=path, value=value):
                invalid = copy.deepcopy(self.baseline)
                target = invalid
                for key in path[:-1]:
                    target = target[key]
                target[path[-1]] = value
                self.write(self.before, invalid)
                with self.assertRaisesRegex(ValueError, r"before.jsonl:2:"):
                    performance_compare.load_summary(self.before)

    def test_bad_json_and_missing_file_produce_only_a_cli_error(self):
        self.write(self.after, self.candidate)
        for content in ("{bad json", "[]", "{}", '{"frame_ms": Infinity}'):
            with self.subTest(content=content):
                self.before.write_text(content, encoding="utf-8")
                result = self.run_cli("--json")
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("before.jsonl:1:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
        self.before.unlink()
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("Traceback", result.stderr)

    def test_percentage_overflow_is_an_error(self):
        self.baseline["gpu_busy_ms_per_present"] = 1e-308
        self.candidate["gpu_busy_ms_per_present"] = 1e308
        self.write(self.before, self.baseline)
        self.write(self.after, self.candidate)
        result = self.run_cli("--json")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("finite numeric range", result.stderr)

    def test_markdown_reports_deltas_and_escapes_table_values(self):
        self.candidate["frame_ms"]["max"] = 60.0
        self.candidate["gpu"] = "GPU | <vendor>\nline"
        self.write(self.before, self.baseline)
        self.write(self.after, self.candidate)
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("| frame_ms.max | 40.000 | 60.000 | +20.000 | +50.000 |", result.stdout)
        self.assertIn("GPU &#124; &lt;vendor&gt; line", result.stdout)
        self.assertIn("abc123", result.stdout)
        self.assertIn("def456", result.stdout)

    def test_utf8_paths_and_metadata_work_with_a_non_utf8_output_default(self):
        self.before = Path(self.directory.name) / "avant-\u00e9.jsonl"
        self.candidate["gpu"] = "GPU \u03a9"
        self.write(self.before, self.baseline)
        self.write(self.after, self.candidate)
        for args in ((), ("--json",)):
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("GPU \u03a9", result.stdout)
        self.before.write_text("bad", encoding="utf-8")
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn("avant-\u00e9.jsonl:1:", result.stderr)

    def test_bom_summary_loads(self):
        self.before.write_text(json.dumps(self.baseline) + "\n", encoding="utf-8-sig")
        self.write(self.after, self.candidate)
        self.assertEqual(performance_compare.load_summary(self.before), self.baseline)
        result = self.run_cli("--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["baseline"], self.baseline)


if __name__ == "__main__":
    unittest.main()
