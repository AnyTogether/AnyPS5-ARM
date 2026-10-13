import argparse
import bisect
import collections
import gzip
import json
import sys
from pathlib import Path

DESCRIPTION = """Digest of an APS5_TRACE_FRAMES / APS5_TRACE_SECONDS capture (aps5-trace-*.json.gz) for an issue or a
pull request: the summary line, the slowest frames with their largest slices, the busy and wait time of each
thread, the largest slices per frame, the longest waits and, with --stacks, the hottest functions of an
APS5_SAMPLE_WORKER collapsed-stack file. The summary line is read from aps5-summary.jsonl next to the trace
unless --summary names another file."""


def is_wait(name):
    return "wait" in name.rsplit(".", 1)[-1].lower()


class Trace:
    def __init__(self, document):
        self.threads = {}
        self.slices = collections.defaultdict(list)
        self.presents = []
        self.folded = collections.defaultdict(float)
        for event in document["traceEvents"]:
            phase = event.get("ph")
            if phase == "M" and event.get("name") == "thread_name":
                self.threads[event["tid"]] = event["args"]["name"]
            elif phase == "X":
                self.slices[event["tid"]].append([float(event["ts"]), float(event["dur"]), event["name"], 0, False])
            elif phase == "i" and event.get("name") == "present":
                self.presents.append((float(event["ts"]), event.get("args", {}).get("present")))
            elif phase == "C":
                self.folded[event["tid"]] += sum(float(value) for value in event.get("args", {}).values())
        self.presents.sort()
        for slices in self.slices.values():
            slices.sort(key=lambda entry: (entry[0], -entry[1]))
            stack = []
            for entry in slices:
                while stack and entry[0] >= stack[-1][0] + stack[-1][1]:
                    stack.pop()
                entry[3] = len(stack)
                entry[4] = any(is_wait(parent[2]) for parent in stack)
                stack.append(entry)

    def name(self, tid):
        return self.threads.get(tid, f"tid {tid}")

    def frames(self, end):
        starts = [ts for ts, _ in self.presents]
        if end is None:
            end = starts[-1] if starts else 0.0
        bounds = starts + ([end] if not starts or end > starts[-1] else [])
        return [(index, bounds[index], bounds[index + 1], self.presents[index][1]) for index in range(len(bounds) - 1)]


def load_trace(path):
    opener = gzip.open if str(path).endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8") as handle:
        return Trace(json.load(handle))


def load_summary(path, trace_path):
    candidate = Path(path) if path else Path(trace_path).with_name("aps5-summary.jsonl")
    if not candidate.exists():
        return None
    lines = [json.loads(line) for line in candidate.read_text(encoding="utf-8").splitlines() if line.strip()]
    for line in reversed(lines):
        if path or line.get("trace") == Path(trace_path).name:
            return line
    return None


def load_stacks(path):
    stacks = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        frames, _, count = line.rpartition(" ")
        stacks.append((frames.split(";"), int(count)))
    return stacks


def digest(trace, summary=None, stacks=None, worst=5, top=10):
    window_ms = summary["window"]["ms"] if summary else None
    frames = trace.frames(window_ms * 1000.0 if window_ms is not None else None)
    span_us = frames[-1][2] - frames[0][1] if frames else 0.0
    count = max(len(frames), 1)
    result = {"summary": summary, "frames": len(frames), "window_ms": span_us / 1000.0}

    slowest = []
    for index, begin, end, present in sorted(frames, key=lambda frame: frame[1] - frame[2])[:worst]:
        inside = collections.Counter()
        for tid, slices in trace.slices.items():
            for ts, dur, name, _, _ in slices:
                overlap = min(ts + dur, end) - max(ts, begin)
                if overlap > 0:
                    inside[(name, trace.name(tid))] += overlap
        slowest.append({"present": present, "ms": (end - begin) / 1000.0, "at_ms": begin / 1000.0,
                        "slices": [{"name": name, "thread": thread, "ms": us / 1000.0} for (name, thread), us in inside.most_common(4)]})
    result["slowest_frames"] = slowest

    threads = []
    totals = collections.Counter()
    waits = []
    for tid, slices in sorted(trace.slices.items()):
        traced = sum(dur for _, dur, _, depth, _ in slices if depth == 0)
        waited = sum(dur for _, dur, name, _, nested in slices if is_wait(name) and not nested)
        leaders = collections.Counter()
        for ts, dur, name, depth, nested in slices:
            totals[name] += dur
            if depth == 0 and not is_wait(name):
                leaders[name] += dur
            if is_wait(name) and not nested:
                waits.append((dur, name, trace.name(tid), ts))
        threads.append({"thread": trace.name(tid), "busy_ms_per_frame": (traced - waited) / 1000.0 / count,
                        "wait_ms_per_frame": waited / 1000.0 / count,
                        "untraced_ms_per_frame": max(span_us - traced, 0.0) / 1000.0 / count,
                        "folded_ms_per_frame": trace.folded.get(tid, 0.0) / count,
                        "busy_pct": 100.0 * (traced - waited) / span_us if span_us else 0.0,
                        "wait_pct": 100.0 * waited / span_us if span_us else 0.0,
                        "top": [{"name": name, "ms_per_frame": us / 1000.0 / count} for name, us in leaders.most_common(2)]})
    result["threads"] = threads
    result["top_slices_ms_per_frame"] = [{"name": name, "ms": us / 1000.0 / count} for name, us in totals.most_common(top)]
    starts = [ts for ts, _ in trace.presents]
    result["longest_waits"] = [{"name": name, "thread": thread, "ms": dur / 1000.0, "at_ms": ts / 1000.0,
                                "present": trace.presents[bisect.bisect_right(starts, ts) - 1][1] if starts and ts >= starts[0] else None}
                               for dur, name, thread, ts in sorted(waits, reverse=True)[:top]]

    if stacks is not None:
        samples = sum(count for _, count in stacks)
        own = collections.Counter()
        inclusive = collections.Counter()
        truncated = 0
        common = None
        for frames_of, number in stacks:
            if frames_of[0] == "[truncated]":
                truncated += number
                frames_of = frames_of[1:]
            elif frames_of:
                common = set(frames_of) if common is None else common & set(frames_of)
            if not frames_of:
                continue
            own[frames_of[-1]] += number
            for frame in set(frames_of):
                inclusive[frame] += number
        common = common or set()
        for frame in common:
            del inclusive[frame]
        share = lambda value: 100.0 * value / samples if samples else 0.0
        result["stacks"] = {"samples": samples, "truncated_pct": share(truncated), "common_frames": len(common),
                            "self": [{"frame": frame, "pct": share(value)} for frame, value in own.most_common(top)],
                            "total": [{"frame": frame, "pct": share(value)} for frame, value in inclusive.most_common(top)]}
    return result


def markdown(result):
    lines = []
    summary = result["summary"]
    if summary:
        frame = summary["frame_ms"]
        lines.append(f"**{summary['window']['spec']}** from present {summary['window']['first_present']}: {summary['presents']} presents, "
                     f"frame p50 {frame['p50']:.1f} / p90 {frame['p90']:.1f} / p99 {frame['p99']:.1f} / max {frame['max']:.1f} ms, "
                     f"GPU busy {summary['gpu_busy_ms_per_present']:.1f} ms per present")
        lines.append(f"{summary['gpu']}, {summary['driver']}, {summary['os']}, {summary['resolution']}, commit {summary['commit']}"
                     f"{' (dirty)' if summary.get('dirty') else ''}, dropped: {'yes' if summary['trace_dropped'] else 'no'}")
        lines.append("")
        lines.append("```json")
        lines.append(json.dumps(summary, separators=(",", ":")))
        lines.append("```")
    else:
        lines.append(f"{result['frames']} frames over {result['window_ms']:.1f} ms (no summary line found)")
    lines.append("")
    lines.append("**Slowest frames** (largest slices inside each, inclusive)")
    lines.append("")
    for frame in result["slowest_frames"]:
        parts = ", ".join(f"{entry['name']} ({entry['thread']}) {entry['ms']:.1f}" for entry in frame["slices"])
        lines.append(f"- present {frame['present']}: {frame['ms']:.1f} ms at {frame['at_ms']:.0f} ms: {parts}")
    lines.append("")
    lines.append("**Threads** (ms per frame)")
    lines.append("")
    lines.append("| thread | busy | wait | untraced | in slices < 20 us | largest |")
    lines.append("|---|---|---|---|---|---|")
    for thread in result["threads"]:
        largest = ", ".join(f"{entry['name']} {entry['ms_per_frame']:.1f}" for entry in thread["top"])
        lines.append(f"| {thread['thread']} | {thread['busy_ms_per_frame']:.1f} ({thread['busy_pct']:.0f} %) | {thread['wait_ms_per_frame']:.1f} ({thread['wait_pct']:.0f} %) "
                     f"| {thread['untraced_ms_per_frame']:.1f} | {thread['folded_ms_per_frame']:.1f} | {largest} |")
    lines.append("")
    lines.append("**Largest slices** (ms per frame, inclusive, all threads): " + ", ".join(f"{entry['name']} {entry['ms']:.1f}" for entry in result["top_slices_ms_per_frame"]))
    lines.append("")
    lines.append("**Longest waits**")
    lines.append("")
    for wait in result["longest_waits"]:
        lines.append(f"- {wait['name']} ({wait['thread']}) {wait['ms']:.1f} ms at {wait['at_ms']:.0f} ms, present {wait['present']}")
    if "stacks" in result:
        stacks = result["stacks"]
        lines.append("")
        lines.append(f"**Worker stacks** ({stacks['samples']} samples, {stacks['truncated_pct']:.1f} % truncated; total leaves out the {stacks['common_frames']} frames every complete stack shares)")
        lines.append("")
        lines.append("- self: " + ", ".join(f"{entry['frame']} {entry['pct']:.1f} %" for entry in stacks["self"]))
        lines.append("- total: " + ", ".join(f"{entry['frame']} {entry['pct']:.1f} %" for entry in stacks["total"]))
    return "\n".join(lines) + "\n"


def main(arguments=None):
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("trace", help="aps5-trace-*.json.gz (or .json)")
    parser.add_argument("--summary", help="file with the summary line (default: aps5-summary.jsonl next to the trace)")
    parser.add_argument("--stacks", help="collapsed-stack file of APS5_SAMPLE_WORKER (<file stem>.collapsed.txt)")
    parser.add_argument("--frames", type=int, default=5, help="slowest frames to list (default 5)")
    parser.add_argument("--top", type=int, default=10, help="entries per list (default 10)")
    parser.add_argument("--json", action="store_true", help="print the digest as JSON")
    options = parser.parse_args(arguments)
    result = digest(load_trace(options.trace), load_summary(options.summary, options.trace),
                    load_stacks(options.stacks) if options.stacks else None, options.frames, options.top)
    sys.stdout.write(json.dumps(result, indent=1) + "\n" if options.json else markdown(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
