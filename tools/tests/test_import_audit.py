import contextlib
import io
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import import_audit
import nid_names

GLOBAL_FUNCTION = 0x12
LOCAL_FUNCTION = 0x02
EXPORTS_TRIE, DYLD_INFO_ONLY, DYLD_INFO = 0x80000033, 0x80000022, 0x22
TRIE_NODES = (
    (b"", (("_", 1),)),
    (b"", (("A", 2), ("_Z3foo", 3))),
    (b"", (("AAAAAAAAAA", 4), ("BBBBBBBBBB", 5))),
    (b"\x08\x01_" + b"Z" * 130 + b"\0", ()),
    (b"\x00\x80\x20", ()),
    (b"\x00\x90\x20", ()),
)
STUB_SOURCE = "int APS5_VABI {name}(int value) {{ NotImplemented_nid_no_patch(__func__); return 0; }}\n"
DONE_SOURCE = "int APS5_VABI {name}(int value) {{ return value; }}\n"
MESSAGE_NID = "wTpfglkmv34"
MESSAGE_NAME = "sceMsgDialogProgressBarSetValue"


def build_elf(symbols):
    strings = b"\0"
    entries = [struct.pack("<IBBHQQ", 0, 0, 0, 0, 0, 0)]
    for name, index, info in symbols:
        entries.append(struct.pack("<IBBHQQ", len(strings), info, 0, index, 0, 0))
        strings += name.encode() + b"\0"
    table = b"".join(entries)
    table_offset = 64 + len(strings)
    table_offset += -table_offset % 8
    sections_offset = table_offset + len(table)
    sections_offset += -sections_offset % 8
    image = bytearray(sections_offset + 3 * 64)
    image[64:64 + len(strings)] = strings
    image[table_offset:table_offset + len(table)] = table
    image[sections_offset + 64:sections_offset + 128] = struct.pack("<IIQQQQIIQQ", 0, 11, 2, 0, table_offset, len(table), 2, 1, 8, 24)
    image[sections_offset + 128:sections_offset + 192] = struct.pack("<IIQQQQIIQQ", 0, 3, 2, 0, 64, len(strings), 0, 0, 1, 0)
    image[:64] = struct.pack("<16sHHIQQQIHHHHHH", b"\x7fELF\x02\x01\x01" + bytes(9), 3, 0x3e, 1, 0, 0, sections_offset, 0, 64, 0, 0, 64, 3, 0)
    return bytes(image)


def exporting(*names):
    return build_elf([(name, 1, GLOBAL_FUNCTION) for name in names])


def build_pe(names):
    section_rva, raw_offset = 0x1000, 0x200
    strings, rvas = b"", []
    start = 40 + 10 * len(names)
    for name in names:
        rvas.append(section_rva + start + len(strings))
        strings += name.encode() + b"\0"
    raw = struct.pack("<IIHHIIIIIII", 0, 0, 0, 0, 0, 1, len(names), len(names), section_rva + 40, section_rva + 40 + 4 * len(names), section_rva + 40 + 8 * len(names))
    raw += b"".join(struct.pack("<I", 0x2000 + 16 * index) for index in range(len(names)))
    raw += b"".join(struct.pack("<I", rva) for rva in rvas)
    raw += b"".join(struct.pack("<H", index) for index in range(len(names))) + strings
    image = bytearray(raw_offset)
    image[0:2] = b"MZ"
    image[0x3c:0x40] = struct.pack("<I", 0x40)
    image[0x40:0x44] = b"PE\0\0"
    image[0x44:0x58] = struct.pack("<HHIIIHH", 0x8664, 2, 0, 0, 0, 240, 0x2022)
    image[0x58:0x5a] = struct.pack("<H", 0x20b)
    image[0x58 + 60:0x58 + 64] = struct.pack("<I", raw_offset)
    image[0x58 + 108:0x58 + 112] = struct.pack("<I", 16)
    image[0x58 + 112:0x58 + 120] = struct.pack("<II", section_rva, len(raw))
    image[0x58 + 240:0x58 + 280] = struct.pack("<8sIIIIIIHHI", b".edata", len(raw), section_rva, len(raw), raw_offset, 0, 0, 0, 0, 0x40000040)
    image[0x58 + 280:0x58 + 320] = struct.pack("<8sIIIIIIHHI", b".text", 16 * max(1, len(names)), 0x2000, 16 * max(1, len(names)), raw_offset + len(raw), 0, 0, 0, 0, 0x60000020)
    return bytes(image) + raw + b"\xc3" * (16 * max(1, len(names)))


def uleb(value):
    out = b""
    while value >= 0x80:
        out += bytes([value & 0x7f | 0x80])
        value >>= 7
    return out + bytes([value])


def trie_node(terminal, *children):
    out = uleb(len(terminal)) + terminal + bytes([len(children)])
    for edge, offset in children:
        out += edge.encode() + b"\0" + uleb(offset)
    return out


def build_trie(nodes=TRIE_NODES):
    offsets = [0] * len(nodes)
    while True:
        out, found = b"", []
        for terminal, children in nodes:
            found.append(len(out))
            out += trie_node(terminal, *((edge, offsets[child]) for edge, child in children))
        if found == offsets:
            return out
        offsets = found


def build_macho(exports):
    loads, tries = b"", b""
    offset = 32 + sum(16 if command == EXPORTS_TRIE else 48 for command in exports)
    for command, trie in exports.items():
        if command == EXPORTS_TRIE:
            loads += struct.pack("<IIII", command, 16, offset + len(tries), len(trie))
        else:
            loads += struct.pack("<12I", command, 48, *[0] * 8, offset + len(tries), len(trie))
        tries += trie
    return struct.pack("<IiiIIIII", 0xfeedfacf, 0x01000007, 3, 6, len(exports), len(loads), 0, 0) + loads + tries


def write_source(root, library, text):
    directory = Path(root) / library
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "Export.cpp").write_text(text)


def write_registry(path, entries, encoding="utf-8"):
    path.write_text(json.dumps([{"nid": nid, "library": library, "relocationType": "R_X86_64_GLOB_DAT"} for nid, library in entries]), encoding=encoding)


class Workspace:
    def __init__(self):
        self._directory = tempfile.TemporaryDirectory()
        self.root = Path(self._directory.name)
        self.libs = self.root / "libs"
        self.modules = self.root / "modules"
        self.source = self.root / "prx"
        for path in (self.libs, self.modules, self.source):
            path.mkdir()

    def close(self):
        self._directory.cleanup()

    def run(self, registry, *extra):
        out, err = io.StringIO(), io.StringIO()
        arguments = [str(registry), "--libs", str(self.libs), "--modules", str(self.modules), "--source", str(self.source), *extra]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = import_audit.main(arguments)
        return code, out.getvalue(), err.getvalue()


class ImportAuditTests(unittest.TestCase):
    def setUp(self):
        self.work = Workspace()
        self.addCleanup(self.work.close)

    def test_classification_accounts_for_every_reference(self):
        work = self.work
        (work.libs / "libSceMsgDialog.prx").write_bytes(build_elf([
            (MESSAGE_NID, 1, GLOBAL_FUNCTION), ("AAAAAAAAAAA", 1, GLOBAL_FUNCTION), ("BBBBBBBBBBB", 1, GLOBAL_FUNCTION),
            ("UNDEFINED11", 0, GLOBAL_FUNCTION), ("LOCALLOCAL1", 1, LOCAL_FUNCTION)]))
        (work.libs / "libc.prx").write_bytes(exporting("CCCCCCCCCCC"))
        (work.modules / "libSceNpCppWebApi.prx").write_bytes(b"\x7fELF")
        write_source(work.source, "libSceMsgDialog", STUB_SOURCE.format(name=MESSAGE_NAME) + 'APS5_EXPORT("BBBBBBBBBBB", sceFooUnknown_B);\n' + STUB_SOURCE.format(name="sceFooUnknown_B"))
        registry = work.root / "game.registry.json"
        write_registry(registry, [
            (MESSAGE_NID + "#A#B", "libSceMsgDialog.prx"), (MESSAGE_NID, "libSceMsgDialog.prx"),
            ("AAAAAAAAAAA", "libSceMsgDialog.prx"), ("BBBBBBBBBBB", "libSceMsgDialog.prx"),
            ("DDDDDDDDDDD", "libSceMsgDialog.prx"), ("EEEEEEEEEEE", "libSceNpCppWebApi.prx"),
            ("CCCCCCCCCCC", "libSceFoo.prx"), ("AAAAAAAAAAA", "libSceOther.prx"),
            ("UNDEFINED11", "libSceMsgDialog.prx"), ("LOCALLOCAL1", "libSceMsgDialog.prx")])
        result = work.root / "audit.json"
        code, out, err = work.run(registry, "--json", str(result))
        self.assertEqual((code, err), (1, ""))
        data = json.loads(result.read_text())
        self.assertEqual(data["references"], 10)
        self.assertEqual(data["unique_imports"], 9)
        self.assertEqual(data["unique_by_class"], {"implemented": 3, "stub": 2, "absent": 3, "module": 1})
        self.assertEqual(data["references_by_class"], {"implemented": 3, "stub": 3, "absent": 3, "module": 1})
        self.assertEqual(data["missing_libraries"], {"libSceFoo.prx": 1, "libSceOther.prx": 1})
        self.assertEqual(data["library_mismatch"], 1)
        kinds = {(record["nid"], record["library"]): record["class"] for record in data["imports"]}
        self.assertEqual(kinds[(MESSAGE_NID, "libSceMsgDialog.prx")], "stub")
        self.assertEqual(kinds[("BBBBBBBBBBB", "libSceMsgDialog.prx")], "stub")
        self.assertEqual(kinds[("UNDEFINED11", "libSceMsgDialog.prx")], "absent")
        self.assertEqual(kinds[("LOCALLOCAL1", "libSceMsgDialog.prx")], "absent")
        self.assertEqual(kinds[("EEEEEEEEEEE", "libSceNpCppWebApi.prx")], "module")
        self.assertIn(f"{MESSAGE_NID}  {MESSAGE_NAME}", out)
        self.assertIn("DDDDDDDDDDD", out)

    def test_clean_audit_exits_zero_and_empty_registry_is_empty(self):
        work = self.work
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "clean.json"
        write_registry(registry, [("AAAAAAAAAAA", "libSceA.prx")])
        self.assertEqual(work.run(registry)[0], 0)
        write_registry(registry, [])
        result = work.root / "empty.json"
        code, out, _ = work.run(registry, "--json", str(result))
        data = json.loads(result.read_text())
        self.assertEqual((code, data["references"], data["unique_imports"], data["imports"]), (0, 0, 0, []))
        self.assertIn("0 references, 0 unique imports", out)

    def test_removing_an_export_flips_the_class(self):
        work = self.work
        registry = work.root / "game.json"
        write_registry(registry, [("AAAAAAAAAAA", "libSceA.prx")])
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        self.assertEqual(work.run(registry)[0], 0)
        (work.libs / "libSceA.prx").write_bytes(exporting("ZZZZZZZZZZZ"))
        code, out, _ = work.run(registry)
        self.assertEqual(code, 1)
        self.assertIn("AAAAAAAAAAA", out)

    def test_source_stubs(self):
        source = self.work.source
        write_source(source, "libSceTwin", STUB_SOURCE.format(name="sceTwinCall") + STUB_SOURCE.format(name="printf_nid_postfix"))
        write_source(source, "libSceTwin.native", DONE_SOURCE.format(name="sceTwinCall"))
        write_source(source, "libSceOnly", STUB_SOURCE.format(name="sceOnlyPending"))
        stubs = import_audit.source_stubs(source)
        twin = nid_names.compute_nid("sceTwinCall")
        self.assertEqual(stubs, {
            ("libSceTwin.prx", twin): "sceTwinCall",
            ("libSceTwin.prx", nid_names.compute_nid("printf")): "printf_nid_postfix",
            ("libSceOnly.prx", nid_names.compute_nid("sceOnlyPending")): "sceOnlyPending"})
        self.assertNotIn(("libSceTwin.native.prx", twin), stubs)
        self.assertNotEqual(nid_names.compute_nid("printf"), nid_names.compute_nid("printf_nid_postfix"))

    def test_stub_in_one_library_is_not_hidden_by_another(self):
        source = self.work.source
        write_source(source, "libA", DONE_SOURCE.format(name="sceTwinCall"))
        write_source(source, "libB", STUB_SOURCE.format(name="sceTwinCall"))
        nid = nid_names.compute_nid("sceTwinCall")
        stubs = import_audit.source_stubs(source)
        exports = {nid: ["libA.prx", "libB.prx"]}
        records, _ = import_audit.audit([(nid, "libB.prx")], {nid: ["libB.prx"]}, stubs, {"libB.prx"}, set())
        self.assertEqual((records[0]["class"], records[0]["name"]), ("stub", "sceTwinCall"))
        records, _ = import_audit.audit([(nid, "libA.prx")], {nid: ["libA.prx"]}, stubs, {"libA.prx"}, set())
        self.assertEqual((records[0]["class"], records[0]["name"]), ("implemented", None))
        records, _ = import_audit.audit([(nid, "libB.prx")], exports, stubs, {"libA.prx", "libB.prx"}, set())
        self.assertEqual(records[0]["class"], "implemented")

    def test_formatted_export_aliases_remain_stubs(self):
        work = self.work
        nid = "AAAAAAAAAAA"
        (work.libs / "libSceAlias.prx").write_bytes(exporting(nid))
        registry = work.root / "game.json"
        result = work.root / "audit.json"
        write_registry(registry, [(nid, "libSceAlias.prx")])
        aliases = [
            'APS5_EXPORT (\n "AAAAAAAAAAA",\n NAME\n);\n',
            'APS5_EXPORT(/* nid */ "AAAAAAAAAAA", /* name */ NAME);\n',
            'APS5_EX\\\nPORT("AAAAAAAAAAA", NAME);\n',
        ]
        for name in ("sceAliasUnknown", "sceAliasedCall"):
            for alias in aliases:
                with self.subTest(name=name, alias=alias):
                    write_source(work.source, "libSceAlias", alias.replace("NAME", name) + STUB_SOURCE.format(name=name))
                    code, _, err = work.run(registry, "--json", str(result))
                    self.assertEqual((code, err), (0, ""))
                    record, = json.loads(result.read_text())["imports"]
                    self.assertEqual((record["class"], record["name"]), ("stub", name))

    def test_comments_and_literals_do_not_override_export_aliases(self):
        work = self.work
        nid, name = "AAAAAAAAAAA", "sceAliasUnknown"
        (work.libs / "libSceAlias.prx").write_bytes(exporting(nid))
        registry = work.root / "game.json"
        result = work.root / "audit.json"
        write_registry(registry, [(nid, "libSceAlias.prx")])
        source = 'APS5_EXPORT("AAAAAAAAAAA", sceAliasUnknown);\n' + STUB_SOURCE.format(name=name)
        decoys = [
            '// APS5_EXPORT("BBBBBBBBBBB", sceAliasUnknown);\n',
            '/* APS5_EXPORT("BBBBBBBBBBB", sceAliasUnknown); */\n',
            'auto example = R"text(APS5_EXPORT("BBBBBBBBBBB", sceAliasUnknown);)text";\n',
        ]
        for decoy in decoys:
            with self.subTest(decoy=decoy):
                write_source(work.source, "libSceAlias", source + decoy)
                code, _, err = work.run(registry, "--json", str(result))
                self.assertEqual((code, err), (0, ""))
                record, = json.loads(result.read_text())["imports"]
                self.assertEqual((record["class"], record["name"]), ("stub", name))

    @unittest.skipUnless((import_audit.ROOT / ".git").exists(), "needs a git checkout")
    def test_json_is_stamped_with_the_source_commit(self):
        work = self.work
        import_audit.subprocess.run(["git", "-C", str(work.source), "init", "-q"], check=True)
        import_audit.subprocess.run(["git", "-C", str(work.source), "-c", "user.name=Audit test", "-c", "user.email=audit@example.invalid", "commit", "--allow-empty", "-qm", "Source stamp fixture"], check=True)
        commit, dirty = import_audit.git_stamp(work.source)
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "game.json"
        write_registry(registry, [("AAAAAAAAAAA", "libSceA.prx")])
        result = work.root / "stamped.json"
        work.run(registry, "--json", str(result))
        data = json.loads(result.read_text())
        self.assertRegex(data["source_commit"], r"^[0-9a-f]{40}$")
        self.assertEqual((data["source_commit"], data["source_dirty"]), (commit, dirty))
        self.assertEqual(data["registries"], [str(registry)])

    def test_nid_anchor_matches_the_known_pair(self):
        self.assertEqual(nid_names.compute_nid(MESSAGE_NAME), MESSAGE_NID)

    def test_elf_reader(self):
        image = build_elf([("one", 1, GLOBAL_FUNCTION), ("weak", 1, 0x22), ("undefined", 0, GLOBAL_FUNCTION), ("local", 1, LOCAL_FUNCTION)])
        path = Path("lib.prx")
        self.assertEqual(import_audit.elf_exports(path, image), {"one", "weak"})
        self.assertEqual(import_audit.elf_exports(path, exporting()), set())
        for cut in (10, 64, len(image) - 5):
            with self.assertRaisesRegex(import_audit.AuditError, "lib.prx"):
                import_audit.elf_exports(path, image[:cut])

    def test_pe_reader(self):
        path = Path("lib.prx")
        self.assertEqual(import_audit.pe_exports(path, build_pe(["alpha", "beta"])), {"alpha", "beta"})
        self.assertEqual(import_audit.pe_exports(path, build_pe([])), set())
        image = build_pe(["alpha"])
        for cut in (0x3c, 0x60, 0x210):
            with self.assertRaisesRegex(import_audit.AuditError, "lib.prx"):
                import_audit.pe_exports(path, image[:cut])

    def test_macho_reader(self):
        path = Path("lib.prx")
        names = {"AAAAAAAAAAA", "ABBBBBBBBBB", "_Z3foo"}
        self.assertEqual(import_audit.uleb128(b"\xe5\x8e\x26", 0, path, "value"), (624485, 3))
        trie = build_trie()
        self.assertGreater(len(trie), 0x7f)
        self.assertEqual(import_audit.macho_exports(path, build_macho({EXPORTS_TRIE: trie})), names)
        self.assertEqual(import_audit.macho_exports(path, build_macho({DYLD_INFO_ONLY: trie})), names)
        self.assertEqual(import_audit.macho_exports(path, build_macho({DYLD_INFO: trie})), names)
        other = build_trie(((b"", (("_zzz", 1),)), (b"\x00\x80\x20", ())))
        self.assertEqual(import_audit.macho_exports(path, build_macho({DYLD_INFO_ONLY: other})), {"zzz"})
        self.assertEqual(import_audit.macho_exports(path, build_macho({DYLD_INFO_ONLY: other, EXPORTS_TRIE: trie})), names)
        self.assertEqual(import_audit.macho_exports(path, build_macho({EXPORTS_TRIE: trie, DYLD_INFO_ONLY: other})), names)
        self.assertEqual(import_audit.macho_exports(path, build_macho({EXPORTS_TRIE: b""})), set())
        self.assertEqual(import_audit.macho_exports(path, build_macho({EXPORTS_TRIE: trie_node(b"")})), set())
        image = build_macho({EXPORTS_TRIE: trie})
        for cut in (16, 40, len(image) - 5):
            with self.assertRaisesRegex(import_audit.AuditError, "lib.prx"):
                import_audit.macho_exports(path, image[:cut])
        corrupt = ((trie_node(b"", ("x", 0)), "reached twice"), (trie_node(b"", ("x", 99)), "outside the export trie"),
                   (b"\x80" * 12, "ULEB128"), (b"\x00\x01x", "NUL-terminated"))
        for bad, message in corrupt:
            with self.assertRaisesRegex(import_audit.AuditError, message):
                import_audit.macho_exports(path, build_macho({EXPORTS_TRIE: bad}))
        with self.assertRaisesRegex(import_audit.AuditError, "no export trie"):
            import_audit.macho_exports(path, build_macho({}))
        for magic in (b"\xca\xfe\xba\xbe", b"\xce\xfa\xed\xfe"):
            with self.assertRaisesRegex(import_audit.AuditError, "only little-endian 64-bit Mach-O"):
                import_audit.macho_exports(path, magic + image[4:])

    def test_pe_ignores_bytes_after_the_declared_directory_count(self):
        image = bytearray(build_pe(["alpha"]))
        struct.pack_into("<I", image, 0x58 + 108, 0)
        with self.assertRaises(import_audit.AuditError):
            import_audit.pe_exports(Path("lib.prx"), image)

    def test_pe_null_export_address_is_not_an_export(self):
        image = bytearray(build_pe(["alpha"]))
        struct.pack_into("<I", image, 0x200 + 40, 0)
        self.assertEqual(import_audit.pe_exports(Path("lib.prx"), image), set())

    def test_pe_export_ordinal_must_index_the_address_table(self):
        image = bytearray(build_pe(["alpha"]))
        struct.pack_into("<H", image, 0x200 + 48, 1)
        with self.assertRaises(import_audit.AuditError):
            import_audit.pe_exports(Path("lib.prx"), image)

    def test_pe_export_name_cannot_terminate_in_unmapped_overlay(self):
        image = bytearray(build_pe(["alpha"]))
        image[0x200 + 55] = ord("x")
        image[0x238:] = b"y" * (len(image) - 0x238)
        image += b"\0"
        with self.assertRaises(import_audit.AuditError):
            import_audit.pe_exports(Path("lib.prx"), image)

    def test_pe_exports_can_reside_in_headers(self):
        image = bytearray(build_pe(["alpha"]))
        raw = bytes(image[0x200:0x238])
        image[0x200:0x200] = bytes(0x200)
        image[0x200:0x238] = raw
        struct.pack_into("<I", image, 0x58 + 60, 0x400)
        struct.pack_into("<I", image, 0x58 + 112, 0x200)
        struct.pack_into("<III", image, 0x200 + 28, 0x228, 0x22c, 0x230)
        struct.pack_into("<I", image, 0x22c, 0x232)
        struct.pack_into("<I", image, 0x58 + 240 + 20, 0x400)
        struct.pack_into("<I", image, 0x58 + 280 + 20, 0x438)
        self.assertEqual(import_audit.pe_exports(Path("lib.prx"), image), {"alpha"})

    def test_elf_extended_section_count_keeps_exports(self):
        image = bytearray(exporting("alpha"))
        section_offset = struct.unpack_from("<Q", image, 40)[0]
        image.extend(bytes((0xff00 - 3) * 64))
        struct.pack_into("<H", image, 60, 0)
        struct.pack_into("<Q", image, section_offset + 32, 0xff00)
        self.assertEqual(import_audit.elf_exports(Path("lib.prx"), image), {"alpha"})

    def test_elf_extended_undefined_index_is_not_an_export(self):
        image = bytearray(exporting("alpha"))
        section_offset = struct.unpack_from("<Q", image, 40)[0]
        symbol_offset = struct.unpack_from("<Q", image, section_offset + 64 + 24)[0]
        index_offset = len(image) + 64
        image.extend(struct.pack("<IIQQQQIIQQ", 0, 18, 0, 0, index_offset, 8, 1, 0, 4, 4))
        image.extend(struct.pack("<II", 0, 0))
        struct.pack_into("<H", image, 60, 4)
        struct.pack_into("<H", image, symbol_offset + 24 + 6, 0xffff)
        self.assertEqual(import_audit.elf_exports(Path("lib.prx"), image), set())
        struct.pack_into("<I", image, index_offset + 4, 1)
        self.assertEqual(import_audit.elf_exports(Path("lib.prx"), image), {"alpha"})

    def test_pe_export_aliases_share_an_address(self):
        image = bytearray(build_pe(["alpha", "beta"]))
        struct.pack_into("<H", image, 0x200 + 56 + 2, 0)
        self.assertEqual(import_audit.pe_exports(Path("lib.prx"), image), {"alpha", "beta"})

    def test_pe32_uses_its_own_directory_layout(self):
        image = bytearray(build_pe(["alpha"]))
        struct.pack_into("<H", image, 0x58, 0x10b)
        struct.pack_into("<I", image, 0x58 + 92, 16)
        struct.pack_into("<II", image, 0x58 + 96, 0x1000, 56)
        self.assertEqual(import_audit.pe_exports(Path("lib.prx"), image), {"alpha"})


    def test_elf_unnamed_defined_symbol_is_not_an_export(self):
        image = bytearray(exporting("alpha"))
        section_offset = struct.unpack_from("<Q", image, 40)[0]
        symbol_offset = struct.unpack_from("<Q", image, section_offset + 64 + 24)[0]
        struct.pack_into("<I", image, symbol_offset + 24, 0)
        self.assertEqual(import_audit.elf_exports(Path("lib.prx"), image), set())

    def test_elf_preserves_non_utf8_symbol_bytes(self):
        image = bytearray(exporting("alpha"))
        image[65] = 0xff
        self.assertEqual(import_audit.elf_exports(Path("lib.prx"), image), {"\udcfflpha"})

    def test_elf_rejects_missing_regular_symbol_section(self):
        image = build_elf([("alpha", 3, GLOBAL_FUNCTION)])
        with self.assertRaisesRegex(import_audit.AuditError, "section index"):
            import_audit.elf_exports(Path("lib.prx"), image)
        self.assertEqual(import_audit.elf_exports(Path("lib.prx"), build_elf([("absolute", 0xfff1, GLOBAL_FUNCTION)])), {"absolute"})

    def test_pe_forwarder_cannot_end_outside_export_directory(self):
        image = bytearray(build_pe(["alpha"]))
        struct.pack_into("<I", image, 0x200 + 40, 0x1032)
        struct.pack_into("<II", image, 0x58 + 112, 0x1000, 55)
        with self.assertRaisesRegex(import_audit.AuditError, "forwarder"):
            import_audit.pe_exports(Path("lib.prx"), image)

    def test_pe_forwarder_inside_export_directory_keeps_public_name(self):
        image = bytearray(build_pe(["alpha"]))
        target = b"NTDLL.#27\0"
        image[0x238:0x238] = target
        struct.pack_into("<I", image, 0x200 + 40, 0x1038)
        struct.pack_into("<II", image, 0x58 + 112, 0x1000, 56 + len(target))
        struct.pack_into("<I", image, 0x58 + 240 + 8, 56 + len(target))
        struct.pack_into("<I", image, 0x58 + 240 + 16, 56 + len(target))
        struct.pack_into("<I", image, 0x58 + 280 + 20, 0x238 + len(target))
        self.assertEqual(import_audit.pe_exports(Path("lib.prx"), image), {"alpha"})

    def test_pe_export_name_pointer_table_must_be_sorted(self):
        image = build_pe(["beta", "alpha"])
        with self.assertRaisesRegex(import_audit.AuditError, "sorted"):
            import_audit.pe_exports(Path("lib.prx"), image)

    def test_pe_export_name_must_be_ascii(self):
        image = bytearray(build_pe(["alpha"]))
        image[0x200 + 50:0x200 + 52] = b"\xc3\xa9"
        with self.assertRaisesRegex(import_audit.AuditError, "ASCII"):
            import_audit.pe_exports(Path("lib.prx"), image)

    def test_libraries_with_conflicting_basenames_are_not_merged(self):
        first, second = self.work.libs, self.work.root / "other-libs"
        second.mkdir()
        (first / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        (second / "libSceA.prx").write_bytes(exporting("BBBBBBBBBBB"))
        with self.assertRaisesRegex(import_audit.AuditError, "ambiguous"):
            import_audit.built_libraries([first, second])
        (second / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        self.assertEqual(import_audit.built_libraries([first, second, first]), ({"AAAAAAAAAAA": ["libSceA.prx"]}, {"libSceA.prx"}))

    def test_json_output_cannot_overwrite_registry_or_names(self):
        work = self.work
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "game.json"
        write_registry(registry, [("AAAAAAAAAAA", "libSceA.prx")])
        before = registry.read_bytes()
        code, out, err = work.run(registry, "--json", str(registry))
        self.assertEqual((code, out), (2, ""))
        self.assertIn("input", err)
        self.assertEqual(registry.read_bytes(), before)
        names = work.root / "names.csv"
        names.write_text("AAAAAAAAAAA name\n")
        code, out, err = work.run(registry, "--json", str(names), "--names", str(names))
        self.assertEqual((code, out), (2, ""))
        self.assertEqual(names.read_text(), "AAAAAAAAAAA name\n")

    def test_json_output_cannot_overwrite_hard_linked_input(self):
        work = self.work
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "game.json"
        write_registry(registry, [("AAAAAAAAAAA", "libSceA.prx")])
        output = work.root / "hard-link.json"
        output.hardlink_to(registry)
        before = registry.read_bytes()
        code, out, err = work.run(registry, "--json", str(output))
        self.assertEqual((code, out), (2, ""))
        self.assertIn("input", err)
        self.assertEqual(registry.read_bytes(), before)

    def test_git_stamp_uses_selected_source_tree(self):
        completed = type("Completed", (), {"stdout": "abcdef\n"})()
        with patch.object(import_audit.subprocess, "run", return_value=completed) as run:
            self.assertEqual(import_audit.git_stamp(self.work.source), ("abcdef", True))
        self.assertEqual([call.args[0][2] for call in run.call_args_list], [str(self.work.source), str(self.work.source)])

    def test_library_directories(self):
        work = self.work
        (work.libs / "libSceA.prx").write_bytes(build_pe(["AAAAAAAAAAA"]))
        (work.libs / "libSceB.prx").write_bytes(exporting("AAAAAAAAAAA", "BBBBBBBBBBB"))
        (work.libs / "libSceC.prx").write_bytes(build_macho({EXPORTS_TRIE: build_trie()}))
        exports, libraries = import_audit.built_libraries([work.libs])
        self.assertEqual(exports, {"AAAAAAAAAAA": ["libSceA.prx", "libSceB.prx", "libSceC.prx"], "ABBBBBBBBBB": ["libSceC.prx"], "BBBBBBBBBBB": ["libSceB.prx"], "_Z3foo": ["libSceC.prx"]})
        self.assertEqual(libraries, {"libSceA.prx", "libSceB.prx", "libSceC.prx"})
        (work.libs / "libSceD.prx").write_bytes(b"text")
        with self.assertRaisesRegex(import_audit.AuditError, r"libSceD.prx: neither ELF, PE nor Mach-O"):
            import_audit.built_libraries([work.libs])
        with self.assertRaisesRegex(import_audit.AuditError, "no .prx files"):
            import_audit.built_libraries([work.modules])
        with self.assertRaisesRegex(import_audit.AuditError, "not a directory"):
            import_audit.built_libraries([work.root / "absent"])

    def test_registry_errors(self):
        path = self.work.root / "registry.json"
        path.write_text("{}")
        with self.assertRaisesRegex(import_audit.AuditError, "JSON list"):
            import_audit.read_registry(path)
        path.write_text("[1")
        with self.assertRaisesRegex(import_audit.AuditError, "cannot read registry"):
            import_audit.read_registry(path)
        path.write_bytes(b"\xff\xfe\x00")
        with self.assertRaisesRegex(import_audit.AuditError, "cannot read registry"):
            import_audit.read_registry(path)
        path.write_text('[{"nid": "AAAAAAAAAAA"}]')
        with self.assertRaisesRegex(import_audit.AuditError, r"entry 0 needs string fields"):
            import_audit.read_registry(path)
        write_registry(path, [("AAAAAAAAAAA", ""), ("bad\x01nid", "")])
        with self.assertRaisesRegex(import_audit.AuditError, r"entry 1 has an invalid NID 'bad\\x01nid'"):
            import_audit.read_registry(path)
        write_registry(path, [("AAAAAAAAAAA#A#B", "libSceA.prx")], encoding="utf-8-sig")
        self.assertEqual(import_audit.read_registry(path), [("AAAAAAAAAAA", "libSceA.prx")])

    def test_names_never_download(self):
        work = self.work
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "game.json"
        write_registry(registry, [(MESSAGE_NID, "libSceA.prx"), ("DDDDDDDDDDD", "libSceA.prx")])
        with patch.object(nid_names.urllib.request, "urlretrieve", side_effect=AssertionError("download attempted")):
            code, _, err = work.run(registry, "--names", str(work.root / "missing.csv"))
        self.assertEqual(code, 2)
        self.assertIn("never downloads", err)
        names = work.root / "aerolib.csv"
        names.write_text(f"{MESSAGE_NID} {MESSAGE_NAME}\nDDDDDDDDDDD wrongname\n")
        result = work.root / "named.json"
        work.run(registry, "--names", str(names), "--json", str(result))
        named = {record["nid"]: record for record in json.loads(result.read_text())["imports"]}
        self.assertEqual((named[MESSAGE_NID]["name"], named[MESSAGE_NID]["name_verified"]), (MESSAGE_NAME, True))
        self.assertEqual((named["DDDDDDDDDDD"]["name"], named["DDDDDDDDDDD"]["name_verified"]), ("wrongname", False))

    def test_conservation_check_fires(self):
        records = [{"references": 2, "class": "absent"}, {"references": 1, "class": "stub"}]
        import_audit.check_conservation(3, records)
        with self.assertRaisesRegex(import_audit.AuditError, "3 classified"):
            import_audit.check_conservation(4, records)
        with self.assertRaisesRegex(import_audit.AuditError, "unknown classes"):
            import_audit.check_conservation(1, [{"references": 1, "class": "lost"}])

    def test_errors_exit_two_with_the_failing_value(self):
        work = self.work
        (work.libs / "libSceA.prx").write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "game.json"
        write_registry(registry, [("short", "libSceA.prx")])
        code, out, err = work.run(registry)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("game.json: entry 0 has an invalid NID 'short'", err)

    def test_unreadable_library_and_unwritable_json_exit_two(self):
        work = self.work
        library = work.libs / "libSceA.prx"
        library.write_bytes(exporting("AAAAAAAAAAA"))
        registry = work.root / "game.json"
        write_registry(registry, [("AAAAAAAAAAA", "libSceA.prx")])
        code, out, err = work.run(registry, "--json", str(work.modules))
        self.assertEqual((code, out), (2, ""))
        self.assertIn("FAIL: ", err)
        self.assertIn(str(work.modules), err)
        denied = PermissionError(13, "Permission denied", str(library))
        with patch.object(Path, "read_bytes", side_effect=denied):
            code, out, err = work.run(registry)
        self.assertEqual((code, out), (2, ""))
        self.assertIn(f"FAIL: Permission denied: {library}", err)


if __name__ == "__main__":
    unittest.main()
