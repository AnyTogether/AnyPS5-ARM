#!/usr/bin/env python3
"""Checks for an upstream merge of AnyPS5-ARM that git's text merge cannot see.

Run from the merge worktree after the conflicts are resolved (staged or committed):
    python3 -I tools/dev/merge-checks.py [MERGE]
MERGE is a merge commit and defaults to HEAD; with a merge still in progress (MERGE_HEAD exists) the
work tree is compared with HEAD and MERGE_HEAD. See docs/dev/UPSTREAM_SYNC.md.

It compares the merged tree with both parents (ours = MERGE^1 or HEAD, theirs = MERGE^2 or MERGE_HEAD) and
reports only what the merge made worse than both parents:
  1. duplicate *_nid_postfix / *_nid_no_patch definitions inside one prx library (core/libs/prx/<lib>);
  2. `case X:` labels a file has more often than either parent has (a duplicate case value);
  3. column-0 function definitions at the wrong brace depth (a brace the resolution dropped or doubled),
  4. column-0 function definitions a file has more often than either parent (both sides added the same
     function, e.g. a test), in C/C++ files both sides changed since the merge base.
Exit status 1 when any is found.
"""
import collections, os, re, subprocess, sys

def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, text=True, errors="replace")
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout

def show(rev, path):
    r = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True, errors="replace")
    return r.stdout if r.returncode == 0 else None

def merged_text(merge, path):
    if merge == "WORKTREE":
        try:
            return open(path, errors="replace").read()
        except OSError:
            return None
    return show(merge, path)

def strip(text):
    """C/C++ text without comments, string and character literals (newlines kept)."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); seg = text[i:n if j < 0 else j + 2]
            out.append("\n" * seg.count("\n")); i = n if j < 0 else j + 2; continue
        m = re.match(r'R"([^(\s]{0,16})\(', text[i:i + 20])
        if m:
            end = ")" + m.group(1) + '"'; j = text.find(end, i); seg = text[i:n if j < 0 else j + len(end)]
            out.append("\n" * seg.count("\n")); i = n if j < 0 else j + len(end); continue
        c = text[i]
        if c in "\"'" and not (c == "'" and i > 0 and (text[i - 1].isalnum())):
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            i = j + 1; continue
        out.append(c); i += 1
    return "".join(out)

NID_DEF = re.compile(r'^(?!\s)(?!return|#|//|using|typedef)[^;]*?\b(\w+_nid_(?:postfix|no_patch))\s*(\(|=|\{|\[)')

def nid_definitions(files_text):
    found = collections.defaultdict(list)
    for path, text in files_text.items():
        if "/tests/" in path or not path.startswith("core/libs/prx/"):
            continue
        lib = path.split("/")[3]
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = NID_DEF.match(line)
            if not m:
                continue
            if m.group(2) == "(":
                window = "\n".join(lines[i:i + 8])
                brace, semi = window.find("{"), window.find(";")
                if brace < 0 or (0 <= semi < brace):
                    continue
            elif line.rstrip().endswith(";") and "=" not in line:
                continue
            found[(lib, m.group(1))].append(f"{path}:{i + 1}")
    return {key: sites for key, sites in found.items() if len(sites) > 1}

CASE = re.compile(r'\bcase\s+([^:;]+?)\s*:(?!:)')
DEF0 = re.compile(r'^[A-Za-z_][\w:<>,\s\*&~]*\([^;]*\)\s*(const)?\s*(noexcept)?\s*(override)?\s*(->\s*[\w:<>]+)?\s*\{\s*$')

def depth_problems(text):
    problems, depth, ns, pending = [], 0, 0, False
    for number, line in enumerate(strip(text).split("\n"), 1):
        if DEF0.match(line) and not line.startswith(("namespace", "struct", "class", "enum", "union", "extern")) and depth != ns:
            problems.append((number, depth, ns, line[:100]))
        if re.match(r'^\s*(inline\s+)?namespace\b[^;]*\{', line) or re.match(r'^extern "C"\s*\{', line):
            ns += 1
        elif re.match(r'^\s*(inline\s+)?namespace\b[^;{]*$', line) or re.match(r'^extern "C"\s*$', line):
            pending = True; continue
        elif pending and line.strip() == "{":
            ns += 1
        pending = False
        for c in line:
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                ns = min(ns, depth)
    return problems

def main():
    merge = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    if merge == "HEAD" and os.path.exists(git("rev-parse", "--git-path", "MERGE_HEAD").strip()):
        merge, ours, theirs = "WORKTREE", "HEAD", "MERGE_HEAD"
    else:
        ours, theirs = f"{merge}^1", f"{merge}^2"
    base = git("merge-base", ours, theirs).strip()
    changed = lambda a, b: set(git("diff", "--name-only", base, b).split()) if a else set()
    both = sorted(changed(1, ours) & changed(1, theirs))
    cpp = [p for p in both if p.endswith((".cpp", ".cc", ".hpp", ".h")) and not p.startswith("3rdparty/")]
    bad = 0

    tree_rev = "HEAD" if merge == "WORKTREE" else merge
    prx = [p for p in git("ls-tree", "-r", "--name-only", tree_rev, "core/libs/prx").split() if p.endswith((".cpp", ".cc"))]
    texts = {rev: {} for rev in ("merged", ours, theirs)}
    for p in prx:
        texts["merged"][p] = merged_text(merge, p) or ""
    for rev in (ours, theirs):
        listed = set(git("ls-tree", "-r", "--name-only", rev, "core/libs/prx").split())
        for p in prx:
            if p in listed:
                texts[rev][p] = show(rev, p) or ""
    known = set(nid_definitions(texts[ours])) | set(nid_definitions(texts[theirs]))
    for key, sites in sorted(nid_definitions(texts["merged"]).items()):
        if key not in known:
            bad += 1; print(f"duplicate NID definition {key[1]} in {key[0]}: {' '.join(sites)}")

    for path in cpp:
        merged = merged_text(merge, path)
        if merged is None:
            continue
        o, t = show(ours, path) or "", show(theirs, path) or ""
        cm, co, ct = (collections.Counter(CASE.findall(strip(x))) for x in (merged, o, t))
        for label, count in sorted(cm.items()):
            if count > max(co[label], ct[label]):
                bad += 1; print(f"{path}: case {label} x{count} (ours {co[label]}, theirs {ct[label]})")
        defs = lambda x: collections.Counter(line for line in strip(x).split("\n") if DEF0.match(line) and not line.startswith(("namespace", "struct", "class", "enum", "union", "extern")))
        dm, do, dt = defs(merged), defs(o), defs(t)
        for line, count in sorted(dm.items()):
            if count >= 2 and count > max(do[line], dt[line]):
                bad += 1; print(f"{path}: definition x{count} (ours {do[line]}, theirs {dt[line]}): {line[:100]}")
        before = {line for _, _, _, line in depth_problems(o)} | {line for _, _, _, line in depth_problems(t)}
        for number, depth, ns, line in depth_problems(merged):
            if line not in before:
                bad += 1; print(f"{path}:{number}: definition at brace depth {depth} (namespace depth {ns}): {line}")
                break
    print(f"{bad} problem(s) in {len(cpp)} C/C++ files both sides changed")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
