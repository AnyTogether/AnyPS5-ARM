import json
import os
import subprocess
import tempfile
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pr_overlap


class OpenPullRequestsTests(unittest.TestCase):
    def test_collects_pull_requests_beyond_the_previous_limit(self):
        pull_requests = [
            {"number": number, "user": {"login": f"author{number}"},
             "head": {"sha": f"sha{number}"}, "body": None}
            for number in range(1, 202)
        ]
        pull_requests[-1]["body"] = "Depends on: #12\n- #34\n"

        def response(*args):
            if args[0] == "api":
                return json.dumps(pull_requests)
            limit = int(args[args.index("-L") + 1])
            return json.dumps([
                {"number": pr["number"], "author": pr["user"], "headRefOid": pr["head"]["sha"],
                 "body": pr["body"]} for pr in pull_requests[:limit]
            ])

        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "gh", side_effect=response):
            found = pr_overlap.open_prs("main")
        self.assertEqual(set(found), set(range(1, 202)))
        self.assertEqual(found[201], {
            "ref": "refs/pr/201", "sha": "sha201", "author": "author201", "depends": {12, 34},
        })
        self.assertEqual(found[1]["depends"], set())

    def test_base_branch_is_encoded_in_the_paginated_request(self):
        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "gh", return_value="[]") as gh:
            self.assertEqual(pr_overlap.open_prs("topic/one&two"), {})
        gh.assert_called_once_with(
            "api", "--paginate",
            "repos/owner/project/pulls?state=open&base=topic%2Fone%26two&per_page=100",
        )

    def test_single_page_preserves_author_head_and_dependencies(self):
        pull_requests = [{"number": 7, "user": {"login": "contributor"}, "head": {"sha": "head-sha"},
                          "body": "Depends on: none\nUnrelated issue #42"}]
        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "gh", return_value=json.dumps(pull_requests)):
            found = pr_overlap.open_prs("main")
        self.assertEqual(found, {
            7: {"ref": "refs/pr/7", "sha": "head-sha", "author": "contributor", "depends": set()},
        })

    def test_collects_concatenated_json_pages_from_paginated_gh_output(self):
        pull_requests = [
            {"number": number, "user": {"login": f"author{number}"},
             "head": {"sha": f"sha{number}"}, "body": None}
            for number in range(1, 4)
        ]
        pages = [pull_requests[:2], pull_requests[2:]]
        output = "\n".join(json.dumps(page) for page in pages)

        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "gh", return_value=output):
            found = pr_overlap.open_prs("main")

        self.assertEqual(set(found), {1, 2, 3})
        self.assertEqual(found[3]["sha"], "sha3")

    def test_rejects_empty_paginated_output(self):
        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "gh", return_value="  \n"):
            with self.assertRaisesRegex(ValueError, "returned no JSON pages"):
                pr_overlap.open_prs("main")


class FetchTests(unittest.TestCase):
    def test_fetches_each_head_commit_the_api_reported(self):
        prs = {
            7: {"ref": "refs/pr/7", "sha": "a" * 40, "author": "one", "depends": set()},
            9: {"ref": "refs/pr/9", "sha": "b" * 40, "author": "two", "depends": set()},
        }
        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "git", return_value="") as git:
            pr_overlap.fetch("main", prs)
        git.assert_called_once_with(
            "fetch", "--no-tags", "-q", "https://github.com/owner/project.git",
            "+refs/heads/main:refs/pr/base", f"+{'a' * 40}:refs/pr/7", f"+{'b' * 40}:refs/pr/9",
        )

    def test_batches_large_sets_of_pull_request_heads(self):
        prs = {
            number: {
                "ref": f"refs/pr/{number}", "sha": f"{number:040x}",
                "author": "contributor", "depends": set(),
            }
            for number in range(250)
        }
        with patch.object(pr_overlap, "REPO", "owner/project", create=True), \
                patch.object(pr_overlap, "git", return_value="") as git:
            pr_overlap.fetch("main", prs)
        self.assertEqual(git.call_count, 3)
        self.assertEqual([len(call.args) - 4 for call in git.call_args_list], [100, 100, 51])
        self.assertEqual(git.call_args_list[0].args[4], "+refs/heads/main:refs/pr/base")
        self.assertEqual(git.call_args_list[-1].args[-1], "+00000000000000000000000000000000000000f9:refs/pr/249")


class ConflictTests(unittest.TestCase):
    def test_uses_the_shared_base_parent_without_newer_merge_tree_option(self):
        first = {"tree": "first-tree", "files": {"shared.cpp"}, "added": set()}
        second = {"tree": "second-tree", "files": {"shared.cpp"}, "added": set()}
        with patch.object(pr_overlap, "merge", return_value=("merged-tree", set())) as merge:
            self.assertEqual(pr_overlap.conflicts(first, second), {})
        merge.assert_called_once_with("first-tree", "second-tree")


class UnicodePathTests(unittest.TestCase):
    def test_scans_and_reports_conflicts_with_git_path_quoting_enabled(self):
        previous = os.getcwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", "-c", "user.name=Overlap Test", "-c", "user.email=test@example.com",
                     "-c", "commit.gpgsign=false", *args], cwd=root,
                    capture_output=True, text=True, encoding="utf-8", check=True).stdout.strip()

            filename = "core/libs/prx/libSceExample/caf\u00e9.cpp"
            source = root / filename
            source.parent.mkdir(parents=True)
            source.write_text("int value = 0;\n", encoding="utf-8")
            git("init", "-q")
            git("config", "core.quotePath", "true")
            git("add", ".")
            git("commit", "-qm", "test: create base")
            base = git("rev-parse", "HEAD")
            git("update-ref", "refs/pr/base", base)
            for branch, value in (("left", 1), ("right", 2)):
                git("checkout", "-qb", branch, base)
                source.write_text(f"int value = {value};\n", encoding="utf-8")
                git("add", ".")
                git("commit", "-qm", "fix: change value")
            try:
                os.chdir(root)
                left, right = {"ref": "left"}, {"ref": "right"}
                pr_overlap.scan(left)
                pr_overlap.scan(right)
                self.assertEqual(left["files"], {filename})
                self.assertEqual(right["files"], {filename})
                self.assertEqual(pr_overlap.conflicts(left, right), {filename: [(1, 1)]})
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
