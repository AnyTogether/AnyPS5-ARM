import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_conventions import STUB_BODY, SYSTEM_DEPENDENCY, Check, function_body


class FunctionBodyTests(unittest.TestCase):
    def test_line_comments_preserve_following_statements(self):
        sources = (
            "int APS5_VABI sceExample() {\n// pending implementation\nreturn 0;\n}",
            "int APS5_VABI sceExample() // pending implementation\n{\nreturn 0;\n}",
            "int APS5_VABI sceExample() {\n(void)arg; // unused argument\nreturn 0;\n}",
            "int APS5_VABI sceExample() {\n// ignored } ; { tokens\nreturn 0;\n}",
        )
        for source in sources:
            with self.subTest(source=source):
                body = function_body(source.splitlines(), 0)
                self.assertIsNotNone(body)
                self.assertIsNotNone(STUB_BODY.fullmatch(body))

    def test_line_comment_does_not_turn_an_implementation_into_a_stub(self):
        source = "int APS5_VABI sceExample() {\n// validate the request\nvalidate();\nreturn 0;\n}"
        body = function_body(source.splitlines(), 0)
        self.assertEqual(body, "validate();return0;")
        self.assertIsNone(STUB_BODY.fullmatch(body))

    def test_block_comments_preserve_following_statements(self):
        source = "int APS5_VABI sceExample() {\n/* pending\nimplementation */\nreturn 0;\n}"
        self.assertEqual(function_body(source.splitlines(), 0), "return0;")

    def test_comment_markers_and_braces_in_strings_are_ignored(self):
        source = 'int APS5_VABI sceExample() {\nuse("// }", "/* { */");\nreturn 0;\n}'
        self.assertEqual(function_body(source.splitlines(), 0), 'use("","");return0;')

    def test_apostrophes_in_comments_do_not_open_character_literals(self):
        source = "int APS5_VABI sceExample() {\n// don't fail here\nvalidate();\n// it's fine\nreturn 0;\n}"
        body = function_body(source.splitlines(), 0)
        self.assertEqual(body, "validate();return0;")
        self.assertIsNone(STUB_BODY.fullmatch(body))
        source = "int APS5_VABI sceExample() {\n/* don't */\nreturn 0;\n}\nstatic const char Separator = '/';"
        self.assertEqual(function_body(source.splitlines(), 0), "return0;")
        source = "int APS5_VABI sceExample() {\nuse(\"http://x\"); // isn't a stub\nreturn 0;\n}"
        self.assertEqual(function_body(source.splitlines(), 0), 'use("");return0;')

    def test_declaration_has_no_body(self):
        source = "int APS5_VABI sceExample();\nint APS5_VABI sceOther() { return 0; }"
        self.assertIsNone(function_body(source.splitlines(), 0))

    def test_unterminated_function_has_no_body(self):
        source = "int APS5_VABI sceExample() {\n// pending implementation\nreturn 0;"
        self.assertIsNone(function_body(source.splitlines(), 0))


class SilentStubTests(unittest.TestCase):
    def test_commented_stub_is_reported_when_debt_change_allows_comments(self):
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
            debt = root / "docs/dev/TechnicalDebt.md"
            debt.parent.mkdir(parents=True)
            debt.write_text("# Project technical debt\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "docs: record technical debt")
            source = root / "core/libs/prx/libSceExample/Export.cpp"
            source.parent.mkdir(parents=True)
            source.write_text("int APS5_VABI sceExample() {\n// pending implementation\nreturn 0;\n}\n", encoding="utf-8")
            debt.write_text("# Project technical debt\n\nAn unrelated build limitation.\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "feat: add example export")
            result = subprocess.run(
                [sys.executable, str(checker), "--base", "HEAD~1"],
                cwd=root, capture_output=True, text=True,
                env={key: value for key, value in os.environ.items()
                     if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")},
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("[silent-stub]", result.stdout)
            self.assertNotIn("[comment]", result.stdout)


class QuotedPathTests(unittest.TestCase):
    def test_non_ascii_path_does_not_crash_the_checker(self):
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
            git("config", "core.quotePath", "true")
            readme = root / "README.md"
            readme.write_text("# Example\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "docs: add readme")
            note = root / "docs/dev/caf\u00e9.md"
            note.parent.mkdir(parents=True)
            note.write_text("# Cafe\n\nA short note.\n", encoding="utf-8")
            source = root / "core/x.cpp"
            source.parent.mkdir(parents=True)
            source.write_text("int x; // note\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "feat: add cafe note")
            result = subprocess.run(
                [sys.executable, "-I", str(checker), "--base", "HEAD~1"],
                cwd=root, capture_output=True, text=True, encoding="utf-8",
                env={key: value for key, value in os.environ.items()
                     if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")},
            )
            self.assertNotIn("Traceback", result.stderr)
            self.assertIn("[comment]", result.stdout)
            self.assertIn("core/x.cpp", result.stdout)


class SilentStubSectionTests(unittest.TestCase):
    path = "core/libs/prx/libSceExample/Export.cpp"
    entry = f"- [Existing limitation](../../{path}) - console layout is unknown.\n"

    def check_stub(self, debt_text):
        checker = Path(__file__).resolve().parents[1] / "check_conventions.py"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", "-c", f"safe.directory={root}", "-c", "user.name=Conventions Test",
                     "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", *args],
                    cwd=root, capture_output=True, text=True, check=True,
                )

            git("init", "-q")
            debt = root / "docs/dev/TechnicalDebt.md"
            debt.parent.mkdir(parents=True)
            debt.write_text("# Project technical debt\n", encoding="utf-8")
            for library in ("libSceExample", "libSceOther"):
                reference = root / "core/libs/prx" / library / "Reference.hpp"
                reference.parent.mkdir(parents=True)
                reference.write_text("", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "docs: record technical debt")
            source = root / self.path
            source.write_text("int APS5_VABI sceExample() { return 0; }\n", encoding="utf-8")
            debt.write_text(debt_text, encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "feat: add example export")
            env = {key: value for key, value in os.environ.items()
                   if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")}
            env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="safe.directory", GIT_CONFIG_VALUE_0=str(root))
            return subprocess.run(
                [sys.executable, str(checker), "--base", "HEAD~1"],
                cwd=root, capture_output=True, text=True, env=env, timeout=10,
            )

    def require_rejected(self, debt):
        result = self.check_stub(debt)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("[silent-stub]", result.stdout)
        self.assertNotIn("[doc-link]", result.stdout)

    def require_accepted(self, debt):
        result = self.check_stub(debt)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("All conventions checks passed", result.stdout)

    def test_debt_outside_silent_stubs_does_not_exempt_export(self):
        for section in ("Build", "Unknown function info", "Functional"):
            with self.subTest(section=section):
                self.require_rejected(f"# Project technical debt\n\n### {section}\n\n{self.entry}")

    def test_entries_after_silent_stubs_do_not_exempt_export(self):
        for heading in ("# Other debt", "## Other debt", "### Functional"):
            with self.subTest(heading=heading):
                self.require_rejected(f"# Project technical debt\n\n### Silent stubs\n\n{heading}\n\n{self.entry}")

    def test_file_entry_in_silent_stubs_exempts_export(self):
        self.require_accepted(f"# Project technical debt\n\n### Silent stubs\n\n{self.entry}")

    def test_named_entry_in_same_library_exempts_export(self):
        entry = "- sceExample: [reference](../../core/libs/prx/libSceExample/Reference.hpp)\n"
        self.require_accepted(f"# Project technical debt\n\n### Silent stubs\n\n{entry}")

    def test_named_entry_in_another_library_does_not_exempt_export(self):
        entry = "- sceExample: [reference](../../core/libs/prx/libSceOther/Reference.hpp)\n"
        self.require_rejected(f"# Project technical debt\n\n### Silent stubs\n\n{entry}")

    def test_different_function_in_same_library_does_not_exempt_export(self):
        entry = "- sceExampleOther: [reference](../../core/libs/prx/libSceExample/Reference.hpp)\n"
        self.require_rejected(f"# Project technical debt\n\n### Silent stubs\n\n{entry}")

    def test_subsection_in_silent_stubs_keeps_exemption(self):
        self.require_accepted(f"# Project technical debt\n\n### Silent stubs\n\n#### Dialogs\n\n{self.entry}")


class PullRequestTemplateTests(unittest.TestCase):
    def findings(self, line):
        check = Check.__new__(Check)
        check.findings = []
        body = f"### What\nx\n### Tested\nLinux\n### Checklist\n{line}\n- [x] Depends on: none\n- [x] AI-assisted: no\n"
        check.pull_request("fix: x", body)
        return check.findings

    def test_unchecked_items_with_any_bullet_are_reported(self):
        for bullet in ("-", "*", "+"):
            with self.subTest(bullet=bullet):
                self.assertEqual(self.findings(f"{bullet} [ ] all"), [("pr-template", "", 0, "unchecked: all")])

    def test_checked_item_is_accepted(self):
        self.assertEqual(self.findings("- [x] all"), [])


class SpacedPathTests(unittest.TestCase):
    def test_comment_in_path_with_space_is_reported(self):
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
            (root / "readme.txt").write_text("x\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "docs: add readme")
            source = root / "core/a b.cpp"
            source.parent.mkdir(parents=True)
            source.write_text("int x; // note\n", encoding="utf-8")
            git("add", ".")
            git("commit", "-qm", "feat: add spaced file")
            result = subprocess.run(
                [sys.executable, "-I", str(checker), "--base", "HEAD~1"],
                cwd=root, capture_output=True, text=True,
                env={key: value for key, value in os.environ.items()
                     if key not in ("GITHUB_EVENT_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_ACTIONS")},
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("core/a b.cpp:1: error: [comment]", result.stdout)


class SystemDependencyTests(unittest.TestCase):
    def test_flags_system_lookups(self):
        for line in ("find_package( SDL2 REQUIRED)", "FIND_PACKAGE(SDL2)", "find_path(X x.h)", "find_program(P prog)"):
            with self.subTest(line=line):
                self.assertIsNotNone(SYSTEM_DEPENDENCY.search(line))

    def test_allows_exempt_lines(self):
        for line in ("find_package(Python3 COMPONENTS Interpreter)", "find_package( Threads REQUIRED )", "FIND_PACKAGE(Git)", "add_library(x)"):
            with self.subTest(line=line):
                self.assertIsNone(SYSTEM_DEPENDENCY.search(line))


if __name__ == "__main__":
    unittest.main()
