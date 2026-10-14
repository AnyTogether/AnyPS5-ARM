import contextlib
import gzip
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import trace_digest


def complete(tid, name, ts, dur):
    return {"name": name, "ph": "X", "ts": ts, "dur": dur, "pid": 7, "tid": tid}


EVENTS = [
    {"name": "process_name", "ph": "M", "ts": 0, "pid": 7, "tid": 0, "args": {"name": "AnyPS5"}},
    {"name": "thread_name", "ph": "M", "ts": 0, "pid": 7, "tid": 1, "args": {"name": "queue worker 0x0"}},
    {"name": "thread_name", "ph": "M", "ts": 0, "pid": 7, "tid": 2, "args": {"name": "presenter"}},
    complete(1, "Driver.WorkerWait", 0, 4000),
    complete(1, "Driver.Packet", 4000, 5000),
    complete(1, "Driver.Packet.memory_wait", 5000, 2000),
    complete(1, "Driver.Packet", 12000, 16000),
    complete(1, "Driver.Packet.draw", 13000, 7000),
    complete(2, "Driver.Present", 0, 2000),
    complete(2, "Driver.Present.inflight_wait", 500, 1000),
    complete(2, "Driver.Present", 10000, 16000),
    complete(2, "Driver.Present.inflight_wait", 10500, 14500),
    {"name": "queue worker 0x0 folded", "ph": "C", "ts": 0, "pid": 7, "tid": 1, "args": {"ms": 1.5}},
    {"name": "present", "ph": "i", "ts": 0, "pid": 7, "tid": 2, "s": "g", "args": {"present": 600}},
    {"name": "present", "ph": "i", "ts": 10000, "pid": 7, "tid": 2, "s": "g", "args": {"present": 601}},
    {"name": "present", "ph": "i", "ts": 30000, "pid": 7, "tid": 2, "s": "g", "args": {"present": 602}},
]

SUMMARY = {"commit": "abc", "dirty": False, "env": {"APS5_TRACE_FRAMES": "600:3"}, "gpu": "GPU", "driver": "Driver 1", "os": "OS 1",
           "resolution": "1920x1080", "window": {"spec": "frames 600:3", "first_present": 600, "ms": 40.0}, "presents": 3,
           "frame_ms": {"p50": 10.0, "p90": 20.0, "p99": 20.0, "max": 20.0}, "gpu_busy_ms_per_present": 5.0,
           "worker_busy_pct": {"queue worker 0x0": 50.0}, "top_phases_ms_per_frame": {"Driver.Packet": 7.0}, "trace_dropped": False,
           "trace": "aps5-trace-abc-7.json.gz"}

STACKS = "# samples=5 depth=64 truncated=1\n# module a.prx 0x1000 0x1\nntdll.dll+0x1;a.prx+0x10;a.prx+0x20 3\nntdll.dll+0x1;a.prx+0x10;a.prx+0x30 1\n[truncated];a.prx+0x40;a.prx+0x30 1\n"


class TraceDigestTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.trace = root / "aps5-trace-abc-7.json.gz"
        with gzip.open(self.trace, "wt", encoding="utf-8") as handle:
            json.dump({"traceEvents": EVENTS}, handle)
        (root / "aps5-summary.jsonl").write_text(json.dumps(dict(SUMMARY, trace="other.json.gz")) + "\n" + json.dumps(SUMMARY) + "\n", encoding="utf-8")
        self.stacks = root / "worker.collapsed.txt"
        self.stacks.write_text(STACKS, encoding="utf-8")

    def tearDown(self):
        self.directory.cleanup()

    def result(self):
        return trace_digest.digest(trace_digest.load_trace(self.trace), trace_digest.load_summary(None, self.trace),
                                   trace_digest.load_stacks(self.stacks), worst=2, top=3)

    def test_summary_is_the_line_of_this_trace(self):
        self.assertEqual(self.result()["summary"]["trace"], "aps5-trace-abc-7.json.gz")

    def test_explicit_summary_selects_the_matching_trace(self):
        summary = Path(self.directory.name) / "relocated-summary.jsonl"
        other = dict(SUMMARY, trace="other.json.gz", presents=99)
        summary.write_text(json.dumps(SUMMARY) + "\n" + json.dumps(other) + "\n", encoding="utf-8")
        selected = trace_digest.load_summary(summary, self.trace)
        self.assertEqual(selected["trace"], self.trace.name)
        self.assertEqual(selected["presents"], 3)

    def test_explicit_summary_without_matching_trace_is_not_used(self):
        summary = Path(self.directory.name) / "unrelated-summary.jsonl"
        summary.write_text(json.dumps(dict(SUMMARY, trace="other.json.gz")) + "\n", encoding="utf-8")
        self.assertIsNone(trace_digest.load_summary(summary, self.trace))

    def test_frames_end_at_the_window(self):
        result = self.result()
        self.assertEqual(result["frames"], 3)
        self.assertAlmostEqual(result["window_ms"], 40.0)

    def test_slowest_frame_lists_its_slices(self):
        slowest = self.result()["slowest_frames"]
        self.assertEqual([frame["present"] for frame in slowest], [601, 600])
        self.assertAlmostEqual(slowest[0]["ms"], 20.0)
        largest = {(entry["name"], entry["thread"]): entry["ms"] for entry in slowest[0]["slices"]}
        self.assertAlmostEqual(largest[("Driver.Packet", "queue worker 0x0")], 16.0)
        self.assertAlmostEqual(largest[("Driver.Present", "presenter")], 16.0)
        self.assertAlmostEqual(largest[("Driver.Present.inflight_wait", "presenter")], 14.5)

    def test_threads_split_busy_and_wait(self):
        threads = {thread["thread"]: thread for thread in self.result()["threads"]}
        worker = threads["queue worker 0x0"]
        self.assertAlmostEqual(worker["wait_ms_per_frame"], 6.0 / 3)
        self.assertAlmostEqual(worker["busy_ms_per_frame"], 19.0 / 3)
        self.assertAlmostEqual(worker["untraced_ms_per_frame"], 15.0 / 3)
        self.assertAlmostEqual(worker["folded_ms_per_frame"], 1.5 / 3)
        self.assertEqual(worker["top"][0]["name"], "Driver.Packet")
        presenter = threads["presenter"]
        self.assertAlmostEqual(presenter["wait_ms_per_frame"], 15.5 / 3)
        self.assertAlmostEqual(presenter["busy_ms_per_frame"], 2.5 / 3)

    def test_largest_slices_per_frame(self):
        largest = self.result()["top_slices_ms_per_frame"]
        self.assertEqual(largest[0]["name"], "Driver.Packet")
        self.assertAlmostEqual(largest[0]["ms"], 21.0 / 3)

    def test_longest_waits(self):
        waits = self.result()["longest_waits"]
        self.assertEqual((waits[0]["name"], waits[0]["thread"], waits[0]["present"]), ("Driver.Present.inflight_wait", "presenter", 601))
        self.assertAlmostEqual(waits[0]["ms"], 14.5)
        self.assertEqual(waits[1]["name"], "Driver.WorkerWait")

    def test_stacks_self_and_total(self):
        stacks = self.result()["stacks"]
        self.assertEqual(stacks["samples"], 5)
        self.assertAlmostEqual(stacks["truncated_pct"], 20.0)
        self.assertEqual(stacks["self"][0], {"frame": "a.prx+0x20", "pct": 60.0})
        total = {entry["frame"]: entry["pct"] for entry in stacks["total"]}
        self.assertEqual(stacks["common_frames"], 2)
        self.assertNotIn("a.prx+0x10", total)
        self.assertEqual(total, {"a.prx+0x20": 60.0, "a.prx+0x30": 40.0, "a.prx+0x40": 20.0})

    def test_command_line_markdown_and_json(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(trace_digest.main([str(self.trace), "--stacks", str(self.stacks)]), 0)
        text = output.getvalue()
        for heading in ("**Slowest frames**", "**Threads**", "**Largest slices**", "**Longest waits**", "**Worker stacks**"):
            self.assertIn(heading, text)
        self.assertLess(len(text.encode("utf-8")), 5000)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            trace_digest.main([str(self.trace), "--json"])
        self.assertEqual(json.loads(output.getvalue())["frames"], 3)


if __name__ == "__main__":
    unittest.main()
