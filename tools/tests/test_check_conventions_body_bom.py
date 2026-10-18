import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

BODY = (
    "### What\nFix x.\n\n### Tested\nNot tested.\n\n### Checklist\n"
    "- [x] Depends on: none\n- [x] AI-assisted: no\n"
)


class BodyBomTests(unittest.TestCase):
    def run_checker(self, body):
        checker = Path(__file__).resolve().parents[1] / "check_conventions.py"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", "-c", "user.name=Conventions Test", "-c", "user.email=test@example.com",
                     "-c", "commit.gpgsign=false", *args],
                    cwd=root, capture_output=True, text=True, check=True,
                )

            git("init", "-q")
            (root / "README.md").write_text("# Example\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "docs: add readme")
            (root / "body.md").write_bytes(body)
            return subprocess.run(
                [sys.executable, "-I", str(checker), "--base", "HEAD", "--head", "HEAD",
                 "--title", "fix: x", "--body", "body.md"],
                cwd=root, capture_output=True, text=True, encoding="utf-8",
                env={key: value for key, value in os.environ.items()
                     if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")},
            )

    def test_body_with_utf8_bom_keeps_its_first_section(self):
        result = self.run_checker(b"\xef\xbb\xbf" + BODY.encode("utf-8"))
        self.assertNotIn("section 'What' is missing", result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_body_without_bom_passes(self):
        result = self.run_checker(BODY.encode("utf-8"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
