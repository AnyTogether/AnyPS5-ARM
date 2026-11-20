# Merging upstream into AnyPS5-ARM

How `main` of [AnyTogether/AnyPS5-ARM](https://github.com/AnyTogether/AnyPS5-ARM) takes in [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5) `main`.

**How often:** every 2 to 3 days. Upstream lands about 1,000 commits a day. At that pace a merge is a few thousand commits and a few dozen conflicts. #144 came after 12 days: 13,758 commits, 132 conflicted files and about 30 CI rounds.

**Rules:**
- A real merge commit, through a pull request. No rebase, no squash, no force push.
- Tags are never moved or deleted.
- No local builds or test runs; GitHub CI is the build.
- Every non-trivial conflict resolution is written down in the pull request body: the file, and what was kept from each side. See #67 and #144.
- Work that is not the merge, such as a performance change, goes in its own pull request (e.g. #146).

## 1. A dated branch in its own worktree

```sh
ROOT=/path/to/checkouts
DAY=$(date -u +%Y-%m-%d)
BRANCH=merge/upstream-$DAY
WT=$ROOT/AnyPS5-merge-upstream

cd $ROOT/AnyPS5
git remote get-url upstream || git remote add upstream https://github.com/boykopovar/AnyPS5
git fetch origin main && git fetch upstream main
git rev-list --count origin/main..upstream/main      # commits to bring in
git merge-base origin/main upstream/main             # the last merge point
df -h .                                              # keep at least 3 GB free
git worktree add -b $BRANCH $WT origin/main
cd $WT
git -c merge.renameLimit=20000 merge --no-ff --no-commit upstream/main
for f in $(git diff --name-only --diff-filter=U); do echo "$(grep -c '^<<<<<<<' "$f") $f"; done | sort -rn
```

## 2. Resolving

Keep upstream's new behaviour and the fork's macOS/arm64 behaviour; read both sides' history (`git log $(git merge-base HEAD MERGE_HEAD)..HEAD -- <file>` and `..MERGE_HEAD -- <file>`).

- **Both sides built the same thing.** Keep one implementation, port the other side's behaviour onto it, and say which in the pull request body. #144 had nine such cases:
  - FSR 1 upscaling;
  - the host-write flush before a kernel read;
  - macOS named `shm_open`;
  - `ANYPS5_FULLSCREEN` and `APS5_PAD_SCRIPT`;
  - the Mach-O import audit;
  - equal-offset `ds_wrxchg2`;
  - native depth clear supersession.
- **RequestSerializer.** The fork's fields always move to the version after upstream's newest. The tests cut the fork's trailing bytes (`StripForkTail`, `ForkTailBytes`). That includes upstream's hand-made `resize(size() - N)` cuts in ShaderMemory.cpp.
- **Fork code on upstream's changed APIs.** Fork-only files do not conflict, but they still break. Two examples from #144:
  - CommandState's tracked `vkCmdBindPipeline`: compute pipelines are bound through `Context::BindComputePipeline`.
  - Upstream's thread-local destructor check: use `HostThreadLocal`.
- **Code that runs on every `GuestArena::HostWrite`** must not take the GPU mutex. Upstream's c2720073b9 explains that it can hang.

## 3. Mechanical checks, then the merge commit

[merge-checks.py](../../tools/dev/merge-checks.py) compares the merged tree with both parents. It reports only what the merge made worse than both:
- the same `*_nid_postfix` / `*_nid_no_patch` symbol defined twice in one prx library;
- a `case` label a file has more often than either parent;
- a column-0 function definition at the wrong brace depth, meaning a brace was dropped or doubled;
- a column-0 definition a file has twice, where neither parent did.

It uses read-only git, takes about 2.5 minutes, and exits 1 on a problem. On #144's merge commit it finds exactly the six leftovers that took four CI rounds to surface, and nothing else.

```sh
cd $WT
git diff --name-only | xargs grep -ln '^<<<<<<< \|^>>>>>>> '   # empty
git diff --name-only --diff-filter=U                           # empty
python3 -I tools/dev/merge-checks.py                           # with the merge in progress: work tree against HEAD and MERGE_HEAD
git add -A
COUNT=$(git rev-list --count HEAD..MERGE_HEAD); TIP=$(git rev-parse --short=10 MERGE_HEAD); FROM=$(git merge-base HEAD MERGE_HEAD | cut -c1-10)
git -c user.name="Utku Halis" -c user.email="personal@utkuhalis.com.tr" commit -F - <<EOF
Merge upstream/main ($COUNT commits, up to $TIP) into the macOS port

Brings boykopovar/AnyPS5 main from $FROM to $TIP, with the fork's macOS changes kept on
top. Conflicts were resolved keeping both sides; the PR description lists each one.
EOF
python3 -I tools/dev/merge-checks.py HEAD                      # "0 problem(s)"
```

## 4. Push, and the macOS keep-going build first

```sh
git push -u origin $BRANCH || git push -u git@github.com:AnyTogether/AnyPS5-ARM.git $BRANCH
gh workflow run macos-engine.yml -R AnyTogether/AnyPS5-ARM --ref $BRANCH
gh pr create -R AnyTogether/AnyPS5-ARM --base main --head $BRANCH \
  --title "Merge upstream/main ($COUNT commits, up to $TIP) into the macOS port" --body-file body.md
```

The AnyTogether CI engine jobs stop at the first failing target, so each push shows only a few errors. `macos-engine.yml` builds everything with `ninja -k 0`: fix all of its errors in one commit before the next push.

To read a job's whole log:

```sh
JOB=$(gh run view <run> -R AnyTogether/AnyPS5-ARM --json jobs -q '.jobs[] | select(.name|test("macOS")) | .databaseId')
curl -sL -H "Authorization: Bearer $(gh auth token)" -o job.log https://api.github.com/repos/AnyTogether/AnyPS5-ARM/actions/jobs/$JOB/logs
grep -E ' error:|FAILED:|Undefined symbols|  "_' job.log | sort -u | head -80
```

macOS problems that upstream's new code brought before:
- `std::from_chars` for float needs macOS 26: use `Aps5::FloatFromChars` (core/libs/FloatChars.hpp).
- An ExternalProject needs `CMAKE_OSX_ARCHITECTURES` and `CMAKE_OSX_DEPLOYMENT_TARGET` passed to it, and the frameworks its own CMake links.
- ld64 has no `--exclude-libs`. A prx that links a static library exports only `*_nid_*` and its own plain names.
- Mach-O asm labels need `APS5_ASM_SYMBOL`.
- `mincore` takes `char *` on macOS.
- `size_t` and `std::uint64_t` are different types on macOS.

## 5. CI until everything is green

- **Batch fixes per push.** A push cancels the running CI, including a macOS job that may have waited an hour for a runner.
- **Jobs with no runner.** A job cancelled after about 15 minutes with 0 steps had no runner. Rerun it with `gh run rerun <run> -R AnyTogether/AnyPS5-ARM --failed`.
- **Read each failing test's output.** ctest runs with `--output-on-failure`, so a test's text follows its result line.
- **Merge regression or not.** Compare with main's last run of the same job. A test that passes on main and fails on the merge branch is the merge's to fix.
- **Host-dependent tests.** Tests that read the host (sensors, thread priority, page size) vary by runner. Check the `host CPU` line in the log before calling one a regression.
- **Upstream tests for behaviour the fork does differently on purpose** are adapted, and the pull request body says so. Examples from #144: `scePadOpenExt`, bias correction, the sampled cache budget.
- **The known-failures list:** [ctest-known-failures.txt](../../.github/anytogether-ci/ctest-known-failures.txt) only takes a test for a documented runner or host reason, with the evidence in its line: the Mesa version, the CPU model, Rosetta's 16 KiB kernel pages, upstream's own runner passing.
  - A new upstream test that cannot pass on macOS yet is listed with "needs a look" (#67), and fixed in a follow-up (#73).
  - A line comes off when its test passes.
- **Launcher parity.** When upstream adds relinker options, place them in both lists:
  - `tools/macos/launcher/Sources/AnyPS5Core/CustomOptions.swift`; its test `testEveryOptionOfTheRelinkerIsPlaced` fails until this is done;
  - AnyTogether/AnyPS5-Desktop `lib/core/custom_options.dart`.
- **Merge** only when `ci-ok` and every engine job, macOS included, are green:

```sh
gh pr checks <n> -R AnyTogether/AnyPS5-ARM
gh pr merge <n> -R AnyTogether/AnyPS5-ARM --merge
cd $ROOT/AnyPS5 && git worktree remove $WT && git branch -D $BRANCH
```

## 6. A nightly upstream build on macOS (not set up)

Upstream's CI builds no engine and runs no engine tests on macOS. So every macOS break in upstream code first shows up in a merge, all at once. A scheduled job would find each one the day it lands:

- **Schedule:** a workflow `upstream-macos-nightly.yml`, on `schedule` and `workflow_dispatch`, on `macos-latest`. It uses the steps of `macos-engine.yml`.
- **What it builds:** `main` merged with upstream's `main` (`git fetch https://github.com/boykopovar/AnyPS5 main && git merge --no-edit FETCH_HEAD`).
  - A conflict ends the job with the conflicted files, which tells how much the next merge will take.
  - Otherwise it runs `python3 -I tools/dev/merge-checks.py`, builds with `ninja -k 0`, and runs ctest with the known-failures list.
- **What it reports:** it never pushes. On failure it opens or updates one issue with:
  - the compile errors;
  - the failing tests not on the list;
  - the upstream commit range since the last green night.
- **Cost:** one macOS runner a night, about 1 to 1.5 hours with ccache.
- **A Linux job** with lavapipe beside it would catch fork-against-upstream test changes the same way.
