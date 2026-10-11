import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import progress


class ProgressTests(unittest.TestCase):
    def test_nonvoid_stub_wrappers_keep_callers_unimplemented(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "libSceExample"
            library.mkdir()
            (library / "Export.cpp").write_text(
                "static int SupportFormat() { NotImplemented_nid_no_patch(__func__); return 0; }\n"
                "int APS5_VABI sceExampleSupportFormat() { return SupportFormat(); }\n")
            group = progress.scan_library(library)
            self.assertEqual(group["done_names"], [])
            self.assertEqual(group["todo_names"], ["sceExampleSupportFormat"])

    def test_braces_in_literals_and_comments_do_not_delimit_bodies(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "libSceExample"
            library.mkdir()
            (library / "Export.cpp").write_text(
                "static int Helper() { const char* brace = \"}\"; NotImplemented_nid_no_patch(__func__); return 0; }\n"
                "int APS5_VABI sceExampleOpen(char* out) { *out = '{'; return 0; }\n"
                "int APS5_VABI sceExampleClose(char* out) { *out = '}'; NotImplemented_nid_no_patch(__func__); return 0; }\n"
                "int APS5_VABI sceExampleQuote(std::string& out) { out += \"{\\\"\"; return 0; }\n"
                "int APS5_VABI sceExampleNoted() { // }\n    NotImplemented_nid_no_patch(__func__); return 0; }\n"
                "int APS5_VABI sceExampleBlock() { /* { */ return 0; }\n"
                "int APS5_VABI sceExampleWrapped() { return Helper(); }\n"
                "int APS5_VABI sceExampleReady() { return 0; }\n")
            group = progress.scan_library(library)
            self.assertEqual(group["done_names"], ["sceExampleBlock", "sceExampleOpen", "sceExampleQuote", "sceExampleReady"])
            self.assertEqual(group["todo_names"], ["sceExampleClose", "sceExampleNoted", "sceExampleWrapped"])

    def test_apostrophe_in_a_comment_does_not_pair_with_a_later_literal(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "libSceExample"
            library.mkdir()
            (library / "Export.cpp").write_text(
                "int APS5_VABI sceExamplePending() {\n    /* it's */ log('}');\n"
                "    NotImplemented_nid_no_patch(__func__);\n    return 0;\n}\n"
                "int APS5_VABI sceExampleReady() { return 0; }\n")
            group = progress.scan_library(library)
            self.assertEqual(group["done_names"], ["sceExampleReady"])
            self.assertEqual(group["todo_names"], ["sceExamplePending"])

    def test_test_sources_do_not_change_library_progress(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "tests" / "prx"
            library = root / "libSceExample"
            source = library / "src"
            source.mkdir(parents=True)
            (source / "Export.cpp").write_text(
                "int APS5_VABI Ready() { return 0; }\n"
                "int APS5_VABI Pending() { NotImplemented_nid_no_patch(__func__); }\n")
            alias = root / "libSceExample.native"
            alias.mkdir()
            (alias / "CMakeLists.txt").write_text('include("${CMAKE_CURRENT_SOURCE_DIR}/../libSceExample/Library.cmake")\n')
            with patch.object(progress, "PRX", root):
                base = progress.collect_libraries()
                self.assertEqual(base["groups"][0]["done_names"], ["Ready"])
                self.assertEqual(base["groups"][0]["todo_names"], ["Pending"])
                tests = library / "tests"
                nested = tests / "fixtures"
                nested.mkdir(parents=True)
                (tests / "Callbacks.cpp").write_text(
                    "int APS5_VABI FixtureReady() { return 0; }\n"
                    "int APS5_VABI Pending() { return 0; }\n"
                    "int APS5_VABI FixturePending() { NotImplemented_nid_no_patch(__func__); }\n")
                (nested / "Callbacks.cpp").write_text("int APS5_VABI NestedFixture() { return 0; }\n")
                (alias / "tests").mkdir()
                (alias / "tests" / "Callbacks.cpp").write_text("int APS5_VABI AliasFixture() { return 0; }\n")
                head = progress.collect_libraries()
                self.assertEqual(head, base)
                self.assertEqual(progress.compare("Libraries", "Library", "functions", base, head), [])

    def test_shared_source_refactor_preserves_functions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            owner = root / "libSceExample"
            alias = root / "libSceExample.native"
            empty = root / "libSceEmpty"
            for path in (owner, alias, empty):
                path.mkdir()
            source = "int APS5_VABI Ready() { return 0; }\nint APS5_VABI Pending() { NotImplemented_nid_no_patch(__func__); }\n"
            (owner / "Export.cpp").write_text(source)
            (alias / "Export.cpp").write_text(source)
            (owner / "Library.cmake").write_text("add_library(example SHARED Export.cpp)\n")
            (empty / "CMakeLists.txt").write_text('# include(${CMAKE_CURRENT_SOURCE_DIR}/../libSceExample/Library.cmake)\n')
            with patch.object(progress, "PRX", root):
                base = progress.collect_libraries()
                self.assertEqual((base["done"], base["total"]), (2, 4))
                (alias / "Export.cpp").unlink()
                (alias / "CMakeLists.txt").write_text('include("${CMAKE_CURRENT_SOURCE_DIR}/../libSceExample/Library.cmake")\n')
                head = progress.collect_libraries()
                self.assertEqual((head["done"], head["total"]), (1, 2))
                groups = {group["name"]: group for group in head["groups"]}
                self.assertEqual(groups[alias.name]["shared_sources"], owner.name)
                self.assertNotIn("shared_sources", groups[empty.name])
                html = progress.table("Libraries", "Library", head)
                self.assertIn('colspan="3">Shared sources:', html)
                self.assertIn("shared by " + alias.name, "\n".join(progress.treemap("Libraries", head, 0)))
                report = "\n".join(progress.compare("Libraries", "Library", "functions", base, head))
                self.assertIn("sharing sources", report)
                self.assertNotIn("removed", report)
                self.assertNotIn("implemented", report)
                self.assertEqual(progress.compare("Libraries", "Library", "functions", head, head), [])
                (owner / "Export.cpp").write_text(source.replace("return 0;", "NotImplemented_nid_no_patch(__func__);"))
                regressed = progress.collect_libraries()
                report = "\n".join(progress.compare("Libraries", "Library", "functions", base, regressed))
                self.assertIn("-1 reverted", report)
                self.assertIn("Ready", report)
                (owner / "Export.cpp").write_text("int APS5_VABI Ready() { return 0; }\n")
                removed = progress.collect_libraries()
                report = "\n".join(progress.compare("Libraries", "Library", "functions", base, removed))
                self.assertIn("-1 removed", report)
                self.assertIn("Pending", report)

    def test_inert_bodies_are_marked_without_changing_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "libSceExample"
            library.mkdir()
            (library / "Export.cpp").write_text(
                "static int Support() { return 0; }\n"
                "static int Compute(int x) { return x * 2; }\n"
                "int APS5_VABI A() { return 0; }\n"
                "int APS5_VABI B(const void* p) { (void)p; return SCE_KERNEL_ERROR_EOPNOTSUPP; }\n"
                "int APS5_VABI C(void* p) { (void)p; return 0x8A810001; }\n"
                'const char* APS5_VABI I() { return "constant; { text }"; }\n'
                'int APS5_VABI D() { throw std::runtime_error("no"); }\n'
                'std::string APS5_VABI J() { return std::string("not constant"); }\n'
                "int APS5_VABI E() { return Support(); }\n"
                "int APS5_VABI F(int a, int b) { return a + b; }\n"
                "int APS5_VABI G() { NotImplemented_nid_no_patch(__func__); return 0; }\n"
                "int APS5_VABI H(int a) { return Compute(a); }\n")
            group = progress.scan_library(library)
            self.assertEqual(group["inert_names"], ["A", "B", "C", "D", "E", "I"])
            self.assertEqual(group["done_names"], ["A", "B", "C", "D", "E", "F", "H", "I", "J"])
            self.assertEqual(group["todo_names"], ["G"])

    def test_compare_marks_behaviourally_empty_implementations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / "libSceExample"
            library.mkdir()
            kept = (
                "int APS5_VABI Ready() { return 0; }\n"
                "int APS5_VABI Stubbed() { NotImplemented_nid_no_patch(__func__); return 0; }\n"
                "static int Compute(int x) { return x * 2; }\n"
                "int APS5_VABI Wrapped(int a) { return Compute(a); }\n")
            added = (
                "static int Support() { return 0; }\n"
                "int APS5_VABI A() { return 0; }\n"
                "int APS5_VABI B(const void* p) { (void)p; return SCE_KERNEL_ERROR_EOPNOTSUPP; }\n"
                "int APS5_VABI C(void* p) { (void)p; return 0x8A810001; }\n"
                'int APS5_VABI D() { throw std::runtime_error("no"); }\n'
                "int APS5_VABI E() { return Support(); }\n"
                "int APS5_VABI F(int a, int b) { return a + b; }\n")
            (library / "Export.cpp").write_text(kept)
            with patch.object(progress, "PRX", root):
                base = progress.collect_libraries()
            for group in base["groups"]:
                del group["inert_names"]
            (library / "Export.cpp").write_text(kept + added)
            with patch.object(progress, "PRX", root):
                head = progress.collect_libraries()
            report = "\n".join(progress.compare("Libraries", "Library", "functions", base, head))
            self.assertIn("+6 implemented", report)
            self.assertIn("<summary>⚪ 5 behaviourally empty (constant return or throw)</summary>", report)
            empty = report.split("behaviourally empty (constant return or throw)</summary>")[1]
            self.assertEqual([line for line in empty.splitlines() if line.startswith("|")],
                             ["| Library | Name |", "| - | - |"]
                             + [f"| libSceExample | `{name}` |" for name in "ABCDE"])
            self.assertEqual(progress.compare("Libraries", "Library", "functions", head, head), [])
            (library / "Export.cpp").write_text("int APS5_VABI Ready() { return 0; }\n")
            with patch.object(progress, "PRX", root):
                before = progress.collect_libraries()
            (library / "Export.cpp").write_text(
                "int APS5_VABI Ready() { return 0; }\nint APS5_VABI F(int a, int b) { return a + b; }\n")
            with patch.object(progress, "PRX", root):
                after = progress.collect_libraries()
            report = "\n".join(progress.compare("Libraries", "Library", "functions", before, after))
            self.assertIn("+1 implemented", report)
            self.assertNotIn("behaviourally empty", report)
            (library / "Export.cpp").write_text(
                "int APS5_VABI Ready() { return 0; }\nint APS5_VABI F(int a, int b) { return a + b; }\nint APS5_VABI A() { return 0; }\n")
            with patch.object(progress, "PRX", root):
                grown = progress.collect_libraries()
            report = "\n".join(progress.compare("Libraries", "Library", "functions", after, grown))
            self.assertIn("+1 implemented", report)
            self.assertIn("| libSceExample | `A` |", report)
            self.assertIn("<summary>⚪ 1 behaviourally empty (constant return or throw)</summary>", report)

    def test_empty_libraries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            owner = root / "libSceExample"
            alias = root / "libSceExampleBackend"
            dummy = root / "libSceDummy"
            for path in (owner, alias, dummy):
                path.mkdir()
            (owner / "Export.cpp").write_text("int APS5_VABI Ready() { return 0; }\n")
            (alias / "Export.cpp").write_text('#include "prx/libSceExample/Export.cpp"\n')
            (dummy / "Export.cpp").write_text('#include "prx/libc/include/General.hpp"\nextern "C" {\nAPS5_DUMMY_FUN\n}\n')
            with patch.object(progress, "PRX", root):
                data = progress.collect_libraries()
            groups = {group["name"]: group for group in data["groups"]}
            self.assertEqual(groups[alias.name]["shared_sources"], owner.name)
            self.assertNotIn("shared_sources", groups[dummy.name])
            self.assertEqual((data["done"], data["total"]), (1, 1))
            html = progress.table("Libraries", "Library", data)
            self.assertIn(f'<td>{alias.name}</td><td colspan="3">Shared sources:', html)
            self.assertIn(f'<td>{dummy.name}</td><td colspan="3">No exports</td>', html)
            self.assertNotIn("<td>0</td>", html)


if __name__ == "__main__":
    unittest.main()
