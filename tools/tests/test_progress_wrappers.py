import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import progress


def scan(source):
    with tempfile.TemporaryDirectory() as directory:
        library = Path(directory) / "libSceExample"
        library.mkdir()
        (library / "Export.cpp").write_text(source)
        return progress.scan_library(library)


STUB_BODY = "{ NotImplemented_nid_no_patch(__func__); return 0; }\n"
CALLER = "int APS5_VABI sceExampleCall() { return Helper(); }\n"


class WrapperTests(unittest.TestCase):
    def assertTodo(self, source):
        group = scan(source)
        self.assertEqual(group["done_names"], [])
        self.assertEqual(group["todo_names"], ["sceExampleCall"])

    def test_non_static_helper_in_anonymous_namespace(self):
        self.assertTodo("namespace {\nint Helper() " + STUB_BODY + "}\n" + CALLER)

    def test_noexcept_helper(self):
        self.assertTodo("static int Helper() noexcept " + STUB_BODY + CALLER)

    def test_trailing_return_type_helper(self):
        self.assertTodo("static auto Helper() -> int " + STUB_BODY + CALLER)

    def test_pointer_next_to_name_helper(self):
        self.assertTodo("static int *Helper() { NotImplemented_nid_no_patch(__func__); return nullptr; }\n" + CALLER)

    def test_static_helper_still_works(self):
        self.assertTodo("static int Helper() " + STUB_BODY + CALLER)

    def test_unrelated_helper_stays_done(self):
        group = scan("namespace {\nint Other() { return 1; }\nint Helper() " + STUB_BODY + "}\n"
                     "int APS5_VABI sceExampleCall() { return Other(); }\n")
        self.assertEqual(group["done_names"], ["sceExampleCall"])
        self.assertEqual(group["todo_names"], [])


if __name__ == "__main__":
    unittest.main()
