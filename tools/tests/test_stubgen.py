from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_conventions
import stubgen


class StubgenTests(unittest.TestCase):
    def test_default_debt_link_resolves_from_docs_dev(self):
        _, td = stubgen.generate("libkernel", ["AC1FtjqMCL0"], {})
        found = check_conventions.links("docs/dev/TechnicalDebt.md", td.strip())
        self.assertTrue(found)
        for item in found:
            self.assertEqual(item[1], "core/libs/prx/libkernel/Unimplemented.cpp")

    def test_explicit_td_path_is_verbatim(self):
        _, td = stubgen.generate("libkernel", ["AC1FtjqMCL0"], {}, td_path="x/y.cpp")
        self.assertIn("(x/y.cpp)", td)

    def test_code_still_generated(self):
        code, _ = stubgen.generate("libkernel", ["AC1FtjqMCL0"], {})
        self.assertIn("APS5_VABI", code)
        self.assertIn("NotImplemented_nid_no_patch", code)


if __name__ == "__main__":
    unittest.main()
