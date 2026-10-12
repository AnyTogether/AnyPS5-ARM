import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).resolve().parents[1] / "check_conventions.py"
DEFINITION = "int APS5_VABI sceFooBar(int a, int b) { return a + b; }\n"


class WrappedDeclarationTests(unittest.TestCase):
    def check(self, first_file, first_text):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", "-c", f"safe.directory={root}", "-c", "user.name=Conventions Test",
                     "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", *args],
                    cwd=root, capture_output=True, text=True, check=True,
                )

            git("init", "-q")
            first = root / "core/libs/prx/libSceA" / first_file
            first.parent.mkdir(parents=True)
            first.write_text(first_text, encoding="utf-8")
            other = root / "core/libs/prx/libSceA/Other.cpp"
            other.write_text("int APS5_VABI sceOther() { return 1; }\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "feat: add library a")
            second = root / "core/libs/prx/libSceB/Export.cpp"
            second.parent.mkdir(parents=True)
            second.write_text(DEFINITION, encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "feat: add library b")
            env = {key: value for key, value in os.environ.items()
                   if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")}
            env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="safe.directory", GIT_CONFIG_VALUE_0=str(root))
            return subprocess.run(
                [sys.executable, "-I", str(CHECKER), "--base", "HEAD~1", "--head", "HEAD"],
                cwd=root, capture_output=True, text=True, env=env, timeout=20,
            )

    def test_wrapped_declaration_is_not_a_duplicate(self):
        result = self.check("Export.h", "int APS5_VABI sceFooBar(int a,\n    int b);\n")
        self.assertNotIn("duplicate-export", result.stdout, result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_wrapped_definition_is_a_duplicate(self):
        result = self.check("Export.cpp", "int APS5_VABI sceFooBar(int a,\n    int b) {\n    return 0;\n}\n")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("[duplicate-export]", result.stdout)


if __name__ == "__main__":
    unittest.main()
