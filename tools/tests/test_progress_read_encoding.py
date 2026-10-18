import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]

CODE = """
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import progress
group = progress.scan_library(Path(sys.argv[2]) / "libSceExample")
print(group.get("shared_sources"))
"""

INCLUDE = 'include("${CMAKE_CURRENT_SOURCE_DIR}/../libSceOther/libSceOther.cmake")\n'


class ProgressReadEncodingTests(unittest.TestCase):
    def test_utf8_cmake_with_ascii_default_codec(self):
        with tempfile.TemporaryDirectory(prefix="progress read ") as directory:
            root = Path(directory)
            (root / "libSceOther").mkdir()
            library = root / "libSceExample"
            library.mkdir()
            (library / "CMakeLists.txt").write_bytes(("# \u2010 \u2192 shared\n" + INCLUDE).encode("utf-8"))
            env = {key: value for key, value in os.environ.items() if key != "PYTHONIOENCODING"}
            env.update({"PYTHONUTF8": "0", "LC_ALL": "C", "LANG": "C"})
            result = subprocess.run([sys.executable, "-I", "-X", "utf8=0", "-c", CODE, str(TOOLS), str(root)],
                                    env=env, capture_output=True, timeout=20)
        stderr = result.stderr.decode("utf-8", errors="replace")
        self.assertNotIn("UnicodeDecodeError", stderr)
        self.assertEqual(result.returncode, 0, stderr)
        self.assertEqual(result.stdout.decode("ascii").strip(), "libSceOther")


if __name__ == "__main__":
    unittest.main()
