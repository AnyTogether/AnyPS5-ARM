import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_conventions import allowed_notes


class AgentFileTests(unittest.TestCase):
    def test_agent_files_are_rejected_in_any_case(self):
        for name in (
            "CLAUDE.md", "claude.md", "Claude.md", "AGENTS.md", "Agents.md", "GEMINI.md",
            "Copilot-Instructions.md", ".CursorRules", ".WindsurfRules", "windsurf.md",
            "ChatGPT.md", ".ChatGPTRules", ".aider.conf.yml",
        ):
            with self.subTest(name=name):
                self.assertIs(allowed_notes(f"docs/dev/{name}"), False)
                self.assertIs(allowed_notes(name), False)

    def test_ordinary_docs_are_still_allowed(self):
        self.assertTrue(allowed_notes("docs/dev/Claudette.md"))
        self.assertTrue(allowed_notes("README.md"))
        self.assertIs(allowed_notes("core/x.cpp"), None)


if __name__ == "__main__":
    unittest.main()
