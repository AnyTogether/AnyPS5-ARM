import contextlib
import io
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import hw_oracle


MODES = dict(ieee=0, denorm32=0, denorm16=3, dx10_clamp=1, round32=0, round16=0, fp16_overflow=0)


class OracleCacheTests(unittest.TestCase):
    def test_failed_build_is_not_cached_and_can_be_retried(self):
        for previous in (None, b"old executable"):
            with self.subTest(previous=previous), tempfile.TemporaryDirectory() as tmp:
                cache = Path(tmp) / "cache"
                cache.mkdir()
                binary = cache / "oracle"
                if previous is not None:
                    binary.write_bytes(previous)
                    os.utime(binary, (0, 0))

                def fail(command, *, check):
                    self.assertTrue(check)
                    Path(command[command.index("-o") + 1]).write_bytes(b"partial executable")
                    raise subprocess.CalledProcessError(1, command)

                def succeed(command, *, check):
                    self.assertTrue(check)
                    Path(command[command.index("-o") + 1]).write_bytes(b"complete executable")

                with patch.object(hw_oracle, "CACHE", cache), patch.object(hw_oracle, "rocm_root", return_value=None), \
                        patch.object(hw_oracle.subprocess, "run", side_effect=fail) as compiler:
                    with self.assertRaises(subprocess.CalledProcessError):
                        hw_oracle.oracle()
                    self.assertEqual(binary.read_bytes() if binary.exists() else None, previous)
                    self.assertEqual([file for file in cache.rglob("*") if file.is_file()], [binary] if previous is not None else [])
                    compiler.side_effect = succeed
                    built = hw_oracle.oracle()
                    self.assertEqual(built.read_bytes(), b"complete executable")
                    self.assertEqual(hw_oracle.oracle(), built)
                    self.assertEqual(compiler.call_count, 2)
                    self.assertEqual(set(file for file in cache.rglob("*") if file.is_file()), {built, binary} if previous is not None else {built})
                    if previous is not None:
                        self.assertEqual(binary.read_bytes(), previous)

    def test_overlapping_builds_do_not_expose_partial_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "cache"
            outputs = []

            def compile(command, *, check):
                self.assertTrue(check)
                output = Path(command[command.index("-o") + 1])
                outputs.append(output)
                binary = output.parent.parent / "oracle"
                output.write_bytes(b"partial executable")
                if len(outputs) == 1:
                    self.assertFalse(binary.exists())
                    self.assertEqual(hw_oracle.oracle().read_bytes(), b"complete executable")
                output.write_bytes(b"complete executable")

            with patch.object(hw_oracle, "CACHE", cache), patch.object(hw_oracle, "rocm_root", return_value=None), \
                    patch.object(hw_oracle.subprocess, "run", side_effect=compile) as compiler:
                binary = hw_oracle.oracle()
                self.assertEqual(binary.read_bytes(), b"complete executable")
                self.assertEqual(compiler.call_count, 2)
                self.assertNotEqual(outputs[0], outputs[1])
                self.assertEqual([file for file in cache.rglob("*") if file.is_file()], [binary])


class InputRowsTests(unittest.TestCase):
    def test_invalid_rows_fail_before_assembler_or_gpu_lookup(self):
        for row in ((1, 2, 3), (1, 2, 3, 4, 5), (-1, 0, 0, 0),
                    (0x100000000, 0, 0, 0), (1.5, 0, 0, 0), ("1", 0, 0, 0)):
            with self.subTest(row=row), patch.object(hw_oracle, "assemble", side_effect=AssertionError("assembler called")) as assemble:
                with self.assertRaisesRegex(ValueError, "row 1"):
                    hw_oracle.run("s_nop 0", [row], **MODES)
                assemble.assert_not_called()

    def test_unsigned_bits_and_indexable_values_are_preserved(self):
        class Indexable:
            def __index__(self):
                return 0xffffffff

        def dispatch(command, **kwargs):
            data = Path(command[3]).read_bytes()
            self.assertEqual(data[:16], hw_oracle.struct.pack("<4I", 0, 0xffffffff, 0x80000000, 1))
            self.assertEqual(data[16:32 * 16], bytes(31 * 16))
            self.assertEqual(data[32 * 16:], b"extra")
            Path(command[4]).write_bytes(bytes(32 * 64))

        with patch.object(hw_oracle, "assemble", return_value="kernel.co"), \
                patch.object(hw_oracle, "oracle", return_value="oracle"), \
                patch.object(hw_oracle.subprocess, "run", side_effect=dispatch):
            results = hw_oracle.run("s_nop 0", [(0, Indexable(), 0x80000000, True)], b"extra", **MODES)
        self.assertEqual(results, [tuple([0] * 16)])

    def test_cli_accepts_zero_padded_decimal_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            body, rows = Path(tmp) / "body.s", Path(tmp) / "rows.txt"
            body.write_text("s_nop 0")
            rows.write_text("0001 08 0xFFFFFFFF 0b10\n")
            argv = ["hw_oracle.py", str(body), str(rows)]
            argv += [item for name, value in MODES.items() for item in ["--" + name.replace("_", "-"), str(value)]]
            with patch("sys.argv", argv), patch.object(hw_oracle, "run", return_value=[]) as run:
                hw_oracle.main()
            self.assertEqual(run.call_args.args[1], [(1, 8, 0xffffffff, 2)])


class FloatModeTests(unittest.TestCase):
    def test_python_requires_each_mode(self):
        for name in MODES:
            with self.subTest(name=name):
                modes = {key: value for key, value in MODES.items() if key != name}
                with self.assertRaises(TypeError), patch.object(hw_oracle, "assemble") as assemble:
                    hw_oracle.run("s_nop 0", [], **modes)
                assemble.assert_not_called()

    def test_invalid_modes_fail_before_tool_lookup(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(hw_oracle, "target") as target:
            for name in MODES:
                limit = 4 if name in ("denorm32", "denorm16", "round32", "round16") else 2
                for value in (-1, limit, 0.5, "0"):
                    with self.subTest(name=name, value=value):
                        with self.assertRaisesRegex(ValueError, name):
                            hw_oracle.assemble("s_nop 0", Path(tmp), False, **(MODES | {name: value}))
            target.assert_not_called()

    def test_cli_requires_each_mode(self):
        flags = {name: ["--" + name.replace("_", "-"), str(value)] for name, value in MODES.items()}
        for name in MODES:
            argv = ["hw_oracle.py", "missing.s", "missing.txt"]
            argv += [item for key, flag in flags.items() if key != name for item in flag]
            with self.subTest(name=name), patch("sys.argv", argv), contextlib.redirect_stderr(io.StringIO()) as errors:
                with self.assertRaises(SystemExit) as error:
                    hw_oracle.main()
                self.assertEqual(error.exception.code, 2)
                self.assertIn(flags[name][0], errors.getvalue())

    def test_cli_forwards_explicit_modes(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = Path(tmp) / "body.s"
            rows = Path(tmp) / "rows.txt"
            body.write_text("s_nop 0")
            rows.write_text("1 2 3 4\n")
            modes = dict(ieee=1, denorm32=2, denorm16=1, dx10_clamp=0, round32=3, round16=2, fp16_overflow=1)
            argv = ["hw_oracle.py", str(body), str(rows), "--wave64", "--coarse"]
            argv += [item for name, value in modes.items() for item in ["--" + name.replace("_", "-"), str(value)]]
            with patch("sys.argv", argv), patch.object(hw_oracle, "run", return_value=[]) as run:
                hw_oracle.main()
            run.assert_called_once_with("s_nop 0", [(1, 2, 3, 4)], b"", True, True, **modes, lds=4096)

    def test_run_forwards_modes_to_assembler(self):
        with patch.object(hw_oracle, "assemble") as assemble:
            hw_oracle.run("s_nop 0", [], wave64=True, **MODES)
        self.assertEqual(assemble.call_args.args[0], "s_nop 0")
        self.assertTrue(assemble.call_args.args[2])
        self.assertEqual(assemble.call_args.kwargs, MODES | {"lds": 4096})


class TargetOverrideTests(unittest.TestCase):
    def setUp(self):
        detector = getattr(hw_oracle, "detected_target", hw_oracle.target)
        detector.cache_clear()

    def tearDown(self):
        detector = getattr(hw_oracle, "detected_target", hw_oracle.target)
        detector.cache_clear()

    def test_override_is_read_for_each_call_without_a_gpu_probe(self):
        with patch.object(hw_oracle, "oracle", side_effect=AssertionError("GPU probe")):
            with patch.dict(os.environ, {"HW_ORACLE_TARGET": "gfx1030"}):
                self.assertEqual(hw_oracle.target(), "gfx1030")
            with patch.dict(os.environ, {"HW_ORACLE_TARGET": "gfx1100"}):
                self.assertEqual(hw_oracle.target(), "gfx1100")

    def test_removing_override_restores_cached_detection_for_that_binary(self):
        reply = subprocess.CompletedProcess([], 0, "gfx1030\n", "")
        with patch.object(hw_oracle, "oracle", return_value=Path("oracle-a")), \
                patch.object(hw_oracle.subprocess, "run", return_value=reply) as probe:
            with patch.dict(os.environ, {"HW_ORACLE_TARGET": ""}):
                self.assertEqual(hw_oracle.target(), "gfx1030")
                self.assertEqual(hw_oracle.target(), "gfx1030")
            with patch.dict(os.environ, {"HW_ORACLE_TARGET": "gfx1100"}):
                self.assertEqual(hw_oracle.target(), "gfx1100")
            with patch.dict(os.environ, {"HW_ORACLE_TARGET": ""}):
                self.assertEqual(hw_oracle.target(), "gfx1030")
            self.assertEqual(probe.call_count, 1)
            with patch.object(hw_oracle, "oracle", return_value=Path("oracle-b")), \
                    patch.dict(os.environ, {"HW_ORACLE_TARGET": ""}):
                probe.return_value = subprocess.CompletedProcess([], 0, "gfx1200\n", "")
                self.assertEqual(hw_oracle.target(), "gfx1200")
            self.assertEqual(probe.call_count, 2)


class OracleConfigurationTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux compiler and shared-library fixture")
    def test_cache_and_compiler_command_with_host_toolchain(self):
        compiler = shutil.which("cc")
        if compiler is None:
            self.skipTest("C compiler not found")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / "runtime"
            (runtime / "lib").mkdir(parents=True)
            stub = root / "runtime.c"
            stub.write_text("void runtime_stub(void) {}\n", encoding="utf-8")
            subprocess.run([compiler, "-shared", "-fPIC", str(stub), "-o", str(runtime / "lib/libhsa-runtime64.so")], check=True)
            source = root / "source"
            source.mkdir()
            source_file = source / "oracle.c"
            source_file.write_text('#include <stdio.h>\nint main(void) { printf("%d", VALUE); }\n', encoding="utf-8")
            os.utime(source_file, (0, 0))
            wrapper = root / "compiler wrapper"
            wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(compiler) + ' "$@"\n', encoding="utf-8")
            wrapper.chmod(0o755)
            with patch.object(hw_oracle, "HERE", source), patch.object(hw_oracle, "CACHE", root / "cache"), \
                    patch.object(hw_oracle, "rocm_root", return_value=runtime):
                with patch.dict(os.environ, {"CC": shlex.quote(str(wrapper)) + " -DVALUE=7"}):
                    first = hw_oracle.oracle()
                    self.assertEqual(subprocess.check_output([first]), b"7")
                    self.assertEqual(hw_oracle.oracle(), first)
                with patch.dict(os.environ, {"CC": shlex.quote(str(wrapper)) + " -DVALUE=8"}):
                    second = hw_oracle.oracle()
                    self.assertNotEqual(second, first)
                    self.assertEqual(subprocess.check_output([second]), b"8")
                    source_file.write_text('#include <stdio.h>\nint main(void) { printf("%d", VALUE + 1); }\n', encoding="utf-8")
                    os.utime(source_file, (0, 0))
                    third = hw_oracle.oracle()
                    self.assertNotEqual(third, second)
                    self.assertEqual(subprocess.check_output([third]), b"9")

    def test_compiler_command_supports_wrapper_and_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            def compile(command, *, check):
                self.assertEqual(command[:3], ["ccache", "cc", "-fno-omit-frame-pointer"])
                Path(command[command.index("-o") + 1]).write_bytes(b"executable")

            with patch.object(hw_oracle, "CACHE", Path(tmp)), patch.object(hw_oracle, "rocm_root", return_value=None), \
                    patch.dict(os.environ, {"CC": "ccache cc -fno-omit-frame-pointer"}), \
                    patch.object(hw_oracle.subprocess, "run", side_effect=compile):
                self.assertEqual(hw_oracle.oracle().read_bytes(), b"executable")

    def test_source_change_with_preserved_timestamp_invalidates_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            source.mkdir()
            source_file = source / "oracle.c"
            source_file.write_text("first", encoding="utf-8")
            os.utime(source_file, (0, 0))

            def compile(command, *, check):
                Path(command[command.index("-o") + 1]).write_bytes(source_file.read_bytes())

            with patch.object(hw_oracle, "HERE", source), patch.object(hw_oracle, "CACHE", root / "cache"), \
                    patch.object(hw_oracle, "rocm_root", return_value=None), \
                    patch.object(hw_oracle.subprocess, "run", side_effect=compile) as compiler:
                self.assertEqual(hw_oracle.oracle().read_bytes(), b"first")
                source_file.write_text("second", encoding="utf-8")
                os.utime(source_file, (0, 0))
                self.assertEqual(hw_oracle.oracle().read_bytes(), b"second")
                self.assertEqual(compiler.call_count, 2)

    def test_compiler_change_invalidates_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            def compile(command, *, check):
                Path(command[command.index("-o") + 1]).write_bytes(command[0].encode())

            with patch.object(hw_oracle, "CACHE", Path(tmp)), patch.object(hw_oracle, "rocm_root", return_value=None), \
                    patch.object(hw_oracle.subprocess, "run", side_effect=compile) as compiler:
                with patch.dict(os.environ, {"CC": "cc"}):
                    self.assertEqual(hw_oracle.oracle().read_bytes(), b"cc")
                with patch.dict(os.environ, {"CC": "clang"}):
                    self.assertEqual(hw_oracle.oracle().read_bytes(), b"clang")
                self.assertEqual(compiler.call_count, 2)

    def test_runtime_path_change_invalidates_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            def compile(command, *, check):
                library_path = next(option for option in command if option.startswith("-L"))
                Path(command[command.index("-o") + 1]).write_bytes(library_path.encode())

            with patch.object(hw_oracle, "CACHE", root / "cache"), \
                    patch.object(hw_oracle.subprocess, "run", side_effect=compile) as compiler:
                with patch.object(hw_oracle, "rocm_root", return_value=root / "one"):
                    first = hw_oracle.oracle()
                    self.assertEqual(first.read_bytes(), ("-L" + str((root / "one").resolve() / "lib")).encode())
                with patch.object(hw_oracle, "rocm_root", return_value=root / "two"):
                    second = hw_oracle.oracle()
                    self.assertNotEqual(second, first)
                    self.assertEqual(second.read_bytes(), ("-L" + str((root / "two").resolve() / "lib")).encode())
                self.assertEqual(compiler.call_count, 2)


class GroupSegmentTests(unittest.TestCase):
    def test_wave64_dispatches_at_most_512_rows(self):
        rows = [(index, 0, 0, 0) for index in range(1025)]
        for wave64, expected in ((False, [1024, 32]), (True, [512, 512, 64])):
            with self.subTest(wave64=wave64), tempfile.TemporaryDirectory() as tmp:
                dispatch_sizes = []

                def dispatch(command, *, check, env):
                    self.assertTrue(check)
                    dispatch_sizes.append(int(command[2]))
                    Path(command[4]).write_bytes(bytes(int(command[2]) * 64))

                with patch.object(hw_oracle, "assemble", return_value=Path(tmp) / "kernel.co"), \
                        patch.object(hw_oracle, "oracle", return_value="oracle"), \
                        patch.object(hw_oracle.subprocess, "run", side_effect=dispatch):
                    result = hw_oracle.run("s_nop 0", rows, wave64=wave64, **MODES)

                self.assertEqual(dispatch_sizes, expected)
                self.assertEqual(len(result), len(rows))

    def test_cli_forwards_lds(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = Path(tmp) / "body.s"
            rows = Path(tmp) / "rows.txt"
            body.write_text("s_nop 0")
            rows.write_text("1 2 3 4\n")
            argv = ["hw_oracle.py", str(body), str(rows), "--lds", "8192"]
            argv += [item for name, value in MODES.items() for item in ["--" + name.replace("_", "-"), str(value)]]
            with patch("sys.argv", argv), patch.object(hw_oracle, "run", return_value=[]) as run:
                hw_oracle.main()
            self.assertEqual(run.call_args.kwargs["lds"], 8192)

    def test_run_forwards_lds_to_assembler(self):
        with patch.object(hw_oracle, "assemble") as assemble:
            hw_oracle.run("s_nop 0", [], lds=65536, **MODES)
        self.assertEqual(assemble.call_args.kwargs["lds"], 65536)

    def test_invalid_lds_fails_before_tool_lookup(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(hw_oracle, "target") as target:
            for value in (-1, 65537, 0.5, "4096"):
                with self.subTest(value=value), self.assertRaisesRegex(ValueError, "lds"):
                    hw_oracle.assemble("s_nop 0", Path(tmp), False, lds=value, **MODES)
            target.assert_not_called()

    def test_template_takes_lds(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(hw_oracle, "target", return_value="gfx1036"), \
                patch.object(hw_oracle.subprocess, "run"), patch.object(hw_oracle, "tool", return_value="clang"):
            hw_oracle.assemble("s_nop 0", Path(tmp), False, lds=8192, **MODES)
            text = (Path(tmp) / "k.s").read_text()
        self.assertIn(".amdhsa_group_segment_fixed_size 8192", text)
        self.assertIn(".group_segment_fixed_size: 8192", text)
        self.assertNotIn("@LDS@", text)


class AssemblyTests(unittest.TestCase):
    def test_condition_operands_match_wave_size(self):
        for name in ("clang", "ld.lld"):
            try:
                hw_oracle.tool(name)
            except SystemExit as error:
                self.skipTest(str(error))
        targets = subprocess.run([hw_oracle.tool("clang"), "--print-targets"], capture_output=True, text=True).stdout
        if "amdgcn" not in targets:
            self.skipTest("clang has no AMDGPU target")
        for wave64, vcc, sgpr in ((False, "vcc_lo", "s8"), (True, "vcc", "s[8:9]")):
            body = (f"  v_cmp_lt_f32 {vcc}, v4, v5\n"
                    f"  v_cndmask_b32 v10, v6, v7, {vcc}\n"
                    f"  v_cmp_lt_f32 {sgpr}, v4, v5\n"
                    f"  v_cndmask_b32 v11, v6, v7, {sgpr}\n")
            with self.subTest(wave64=wave64), tempfile.TemporaryDirectory() as tmp:
                with patch.object(hw_oracle, "target", return_value="gfx1036"):
                    code = hw_oracle.assemble(body, Path(tmp), wave64, **MODES)
                self.assertTrue(code.is_file())


if __name__ == "__main__":
    unittest.main()
