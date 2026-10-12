import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import nid_names
import progress

ROOT = Path(__file__).resolve().parent.parent
PRX = ROOT / "core" / "libs" / "prx"
NID = re.compile(r"[A-Za-z0-9+\-]{11}")
NID_POSTFIX = "_nid_postfix"
CLASSES = ("implemented", "stub", "absent", "module")
PE_DIRECTORY_OFFSET = {0x20b: 112, 0x10b: 96}
MACHO_MAGIC = b"\xcf\xfa\xed\xfe"
MACHO_MAGICS = (MACHO_MAGIC, b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf")
MACHO_EXPORT_COMMANDS = {0x80000033: 8, 0x80000022: 40, 0x22: 40}


class AuditError(Exception):
    pass


def take(data, offset, size, path, what, region="file"):
    if offset < 0 or size < 0 or offset + size > len(data):
        raise AuditError(f"{path}: {what} at 0x{offset:x} with size {size} lies outside the {region} ({len(data)} bytes)")
    return data[offset:offset + size]


def unpack(layout, data, offset, path, what):
    return struct.unpack(layout, take(data, offset, struct.calcsize(layout), path, what))


def cstring(data, offset, limit, path, what, encoding="utf-8", errors="surrogateescape"):
    end = data.find(b"\0", offset, limit)
    if offset < 0 or offset >= limit or end < 0:
        raise AuditError(f"{path}: {what} at 0x{offset:x} is not a NUL-terminated string inside 0x{limit:x} bytes")
    try:
        return data[offset:end].decode(encoding, errors=errors)
    except UnicodeDecodeError as error:
        raise AuditError(f"{path}: {what} at 0x{offset:x} is not {encoding}: {error}") from error


def uleb128(data, offset, path, what, region="file"):
    value, shift = 0, 0
    for position in range(offset, offset + 10):
        byte = take(data, position, 1, path, what, region)[0]
        value |= (byte & 0x7f) << shift
        shift += 7
        if not byte & 0x80:
            return value, position + 1
    raise AuditError(f"{path}: {what} at 0x{offset:x} is a ULEB128 longer than 10 bytes")


def elf_exports(path, data):
    header = unpack("<16sHHIQQQIHHHHHH", data, 0, path, "ELF header")
    ident, section_offset, section_size, section_count = header[0], header[6], header[11], header[12]
    if ident[4] != 2 or ident[5] != 1 or section_size != 64:
        raise AuditError(f"{path}: only little-endian ELF64 with 64-byte section headers is supported (class {ident[4]}, data {ident[5]}, shentsize {section_size})")
    if not section_offset:
        raise AuditError(f"{path}: ELF exports without a section header table are not supported")
    if not section_count:
        section_count = unpack("<IIQQQQIIQQ", data, section_offset, path, "extended section count")[5]
    take(data, section_offset, section_count * 64, path, "section header table")
    sections = [unpack("<IIQQQQIIQQ", data, section_offset + index * 64, path, f"section header {index}") for index in range(section_count)]
    names = set()
    for section_index, section in enumerate(sections):
        kind, offset, size, link, entry = section[1], section[4], section[5], section[6], section[9]
        if kind != 11:
            continue
        if entry != 24 or size % 24 or link >= len(sections) or sections[link][1] != 3:
            raise AuditError(f"{path}: invalid dynamic symbol table (entry size {entry}, size {size}, string table section {link})")
        strings_offset, strings_size = sections[link][4], sections[link][5]
        take(data, strings_offset, strings_size, path, "dynamic string table")
        indexes = [candidate for candidate in sections if candidate[1] == 18 and candidate[6] == section_index]
        if len(indexes) > 1:
            raise AuditError(f"{path}: multiple extended section index tables for section {section_index}")
        for position in range(0, size, 24):
            name, info, other, index, _, _ = unpack("<IBBHQQ", data, offset + position, path, "dynamic symbol")
            if index == 0xffff:
                if not indexes or indexes[0][9] != 4 or indexes[0][5] != size // 24 * 4:
                    raise AuditError(f"{path}: invalid or missing extended section index table for section {section_index}")
                index = unpack("<I", data, indexes[0][4] + position // 24 * 4, path, "extended symbol section index")[0]
                if index >= len(sections):
                    raise AuditError(f"{path}: extended symbol section index {index} lies outside the section table")
            elif 0 < index < 0xff00 and index >= len(sections):
                raise AuditError(f"{path}: symbol section index {index} lies outside the section table")
            binding, visibility = info >> 4, other & 3
            if name == 0 or index == 0 or binding not in (1, 2, 10) or visibility not in (0, 3):
                continue
            names.add(cstring(data, strings_offset + name, strings_offset + strings_size, path, "export name"))
    return names


def pe_exports(path, data):
    header = unpack("<I", data, 0x3c, path, "PE header offset")[0]
    if unpack("<I", data, header, path, "PE signature")[0] != 0x4550:
        raise AuditError(f"{path}: invalid PE signature at 0x{header:x}")
    section_count, optional_size = unpack("<H", data, header + 6, path, "section count")[0], unpack("<H", data, header + 20, path, "optional header size")[0]
    optional = header + 24
    magic = unpack("<H", data, optional, path, "optional header magic")[0]
    if magic not in PE_DIRECTORY_OFFSET:
        raise AuditError(f"{path}: unsupported PE optional header magic 0x{magic:x}")
    directory = PE_DIRECTORY_OFFSET[magic]
    if optional_size < directory + 8:
        raise AuditError(f"{path}: PE optional header of {optional_size} bytes has no export directory")
    take(data, optional, optional_size, path, "PE optional header")
    if unpack("<I", data, optional + directory - 4, path, "data directory count")[0] == 0:
        raise AuditError(f"{path}: PE file declares no data directories")
    headers_size = unpack("<I", data, optional + 60, path, "header size")[0]
    rva, size = unpack("<II", data, optional + directory, path, "export data directory")
    if not rva or size < 40:
        raise AuditError(f"{path}: PE file has no export table")
    sections = [unpack("<8sIIIIIIHHI", data, optional + optional_size + index * 40, path, f"PE section {index}") for index in range(section_count)]

    def to_offset(address, length):
        if address < headers_size and length <= headers_size - address:
            take(data, address, length, path, f"header data at RVA 0x{address:x}")
            return address, min(headers_size, len(data))
        for section in sections:
            virtual, raw_size, raw_offset = section[2], section[3], section[4]
            if address < virtual:
                continue
            relative = address - virtual
            if relative >= raw_size or length > raw_size - relative:
                continue
            take(data, raw_offset + relative, length, path, f"data at RVA 0x{address:x}")
            return raw_offset + relative, min(raw_offset + raw_size, len(data))
        raise AuditError(f"{path}: RVA 0x{address:x} is not inside any section")

    table = unpack("<IIHHIIIIIII", data, to_offset(rva, 40)[0], path, "export directory")
    function_count, name_count, functions_rva, names_rva, ordinals_rva = table[6:11]
    names = set()
    if not name_count:
        return names
    if not functions_rva or not names_rva or not ordinals_rva:
        raise AuditError(f"{path}: named PE exports require address, name and ordinal tables")
    functions_offset = to_offset(functions_rva, function_count * 4)[0]
    names_offset = to_offset(names_rva, name_count * 4)[0]
    ordinals_offset = to_offset(ordinals_rva, name_count * 2)[0]
    previous_name = None
    for index in range(name_count):
        name_rva = unpack("<I", data, names_offset + index * 4, path, "export name RVA")[0]
        offset, limit = to_offset(name_rva, 1)
        name = cstring(data, offset, limit, path, "export name", "ASCII", "strict")
        if previous_name is not None and name < previous_name:
            raise AuditError(f"{path}: PE export name pointer table is not sorted")
        previous_name = name
        ordinal = unpack("<H", data, ordinals_offset + index * 2, path, "export ordinal")[0]
        if ordinal >= function_count:
            raise AuditError(f"{path}: export ordinal {ordinal} lies outside the address table ({function_count} entries)")
        function_rva = unpack("<I", data, functions_offset + ordinal * 4, path, "export address")[0]
        if not function_rva:
            continue
        if rva <= function_rva < rva + size:
            offset, limit = to_offset(function_rva, 1)
            cstring(data, offset, min(limit, offset + rva + size - function_rva), path, "export forwarder", "ASCII", "strict")
        names.add(name)
    return names


def macho_exports(path, data):
    if data[:4] != MACHO_MAGIC:
        raise AuditError(f"{path}: only little-endian 64-bit Mach-O is supported (magic {data[:4].hex()})")
    count = unpack("<8I", data, 0, path, "Mach-O header")[4]
    found = {}
    position = 32
    for index in range(count):
        command, size = unpack("<II", data, position, path, f"load command {index}")
        if size < 8:
            raise AuditError(f"{path}: load command {index} at 0x{position:x} has size {size}")
        if command in MACHO_EXPORT_COMMANDS:
            field = MACHO_EXPORT_COMMANDS[command]
            if size < field + 8:
                raise AuditError(f"{path}: load command {index} (0x{command:x}) of {size} bytes has no export trie fields")
            found[command] = unpack("<II", data, position + field, path, f"load command {index}")
        position += size
    for command in MACHO_EXPORT_COMMANDS:
        if command in found:
            offset, size = found[command]
            break
    else:
        raise AuditError(f"{path}: Mach-O file has no export trie")
    trie = take(data, offset, size, path, "export trie")
    names, seen, pending = set(), set(), [(0, b"")] if size else []
    while pending:
        node, prefix = pending.pop()
        if node in seen:
            raise AuditError(f"{path}: export trie node at 0x{node:x} is reached twice")
        seen.add(node)
        terminal, position = uleb128(trie, node, path, "terminal size", "export trie")
        if terminal:
            names.add(prefix.decode("utf-8", "surrogateescape").removeprefix("_"))
            position += terminal
        children = take(trie, position, 1, path, "child count", "export trie")[0]
        position += 1
        for _ in range(children):
            edge = cstring(trie, position, len(trie), path, "export trie edge").encode("utf-8", "surrogateescape")
            position += len(edge) + 1
            child, position = uleb128(trie, position, path, "child offset", "export trie")
            pending.append((child, prefix + edge))
    return names


def read_exports(path, data=None):
    if data is None:
        data = path.read_bytes()
    if data[:4] == b"\x7fELF":
        return elf_exports(path, data)
    if data[:2] == b"MZ":
        return pe_exports(path, data)
    if data[:4] in MACHO_MAGICS:
        return macho_exports(path, data)
    raise AuditError(f"{path}: neither ELF, PE nor Mach-O (first bytes {data[:4]!r})")


def directory_files(directory, pattern):
    path = Path(directory)
    if not path.is_dir():
        raise AuditError(f"{directory}: not a directory")
    return sorted(item for item in path.glob(pattern) if item.is_file())


def built_libraries(directories):
    exports = defaultdict(set)
    libraries = set()
    images = {}
    for directory in directories:
        files = directory_files(directory, "*.prx")
        if not files:
            raise AuditError(f"{directory}: no .prx files; pass the directory the libs target builds (build/core/libs/libs)")
        for file in files:
            data = file.read_bytes()
            digest = hashlib.sha256(data).digest()
            if file.name in images:
                previous, fingerprint = images[file.name]
                if digest != fingerprint:
                    raise AuditError(f"ambiguous built library {file.name}: {previous} and {file} have different contents")
                continue
            images[file.name] = (file, digest)
            libraries.add(file.name)
            for name in read_exports(file, data):
                exports[name].add(file.name)
    return {name: sorted(files) for name, files in exports.items()}, libraries


def module_files(directories):
    return {file.name for directory in directories for file in directory_files(directory, "*")}


def nid_of(name, aliases):
    if name in aliases:
        return aliases[name]
    return nid_names.compute_nid(name.removesuffix(NID_POSTFIX))


def source_stubs(source):
    if not Path(source).is_dir():
        raise AuditError(f"{source}: not a directory")
    stubs = {}
    for library in sorted(item for item in Path(source).iterdir() if item.is_dir()):
        aliases = {}
        for file in library.rglob("*.cpp"):
            for nid, name in nid_names.source_aliases(file.read_text(errors="ignore")):
                aliases[name] = nid
        group = progress.scan_library(library)
        done = {nid_of(name, aliases) for name in group["done_names"]}
        for name in group["todo_names"]:
            nid = nid_of(name, aliases)
            if nid not in done:
                stubs.setdefault((library.name + ".prx", nid), name)
    return stubs


def read_registry(path):
    try:
        entries = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuditError(f"{path}: cannot read registry: {error}") from error
    if not isinstance(entries, list):
        raise AuditError(f"{path}: a registry is a JSON list, got {type(entries).__name__}")
    imports = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict) or not isinstance(entry.get("nid"), str) or not isinstance(entry.get("library"), str):
            raise AuditError(f"{path}: entry {index} needs string fields 'nid' and 'library': {entry!r}")
        nid = entry["nid"].split("#", 1)[0]
        if not NID.fullmatch(nid):
            raise AuditError(f"{path}: entry {index} has an invalid NID {entry['nid']!r}")
        imports.append((nid, entry["library"]))
    return imports


def check_conservation(references, records):
    classified = sum(record["references"] for record in records)
    unknown = sorted({record["class"] for record in records} - set(CLASSES))
    if classified != references or unknown:
        raise AuditError(f"conservation failed: {references} references in, {classified} classified, unknown classes {unknown}")


def audit(imports, exports, stubs, libraries, modules):
    records = {}
    for nid, library in imports:
        record = records.setdefault((nid, library), {"nid": nid, "library": library, "references": 0})
        record["references"] += 1
    for record in records.values():
        nid, library = record["nid"], record["library"]
        providers = exports.get(nid, [])
        if library and library in modules:
            kind = "module"
        elif not providers:
            kind = "absent"
        elif all((provider, nid) in stubs for provider in providers):
            kind = "stub"
        else:
            kind = "implemented"
        record["class"] = kind
        record["providers"] = providers
        record["library_mismatch"] = kind in ("implemented", "stub") and bool(library) and library not in providers and "libc.prx" not in providers
        record["name"] = next((stubs[(provider, nid)] for provider in providers if (provider, nid) in stubs), None) if kind == "stub" else None
    ordered = sorted(records.values(), key=lambda record: (record["class"], record["library"], record["nid"]))
    check_conservation(len(imports), ordered)
    missing = defaultdict(int)
    for record in ordered:
        library = record["library"]
        if library and library not in libraries and library not in modules:
            missing[library] += 1
    return ordered, dict(sorted(missing.items()))


def load_names(path):
    if not Path(path).is_file():
        raise AuditError(f"{path}: names file not found; the audit never downloads one (see tools/nid_names.py for the source)")
    return nid_names.load_db(Path(path))


def attach_names(records, names):
    for record in records:
        if record["name"] is None and record["class"] == "absent" and record["nid"] in names:
            name = names[record["nid"]]
            record["name"] = name
            record["name_verified"] = nid_names.compute_nid(name) == record["nid"]


def git_stamp(source=ROOT):
    try:
        commit = subprocess.run(["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        dirty = bool(subprocess.run(["git", "-C", str(source), "status", "--porcelain"], capture_output=True, text=True, check=True).stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        return None, None
    return commit, dirty


def summarize(records, references, missing):
    counts = {kind: sum(1 for record in records if record["class"] == kind) for kind in CLASSES}
    by_references = {kind: sum(record["references"] for record in records if record["class"] == kind) for kind in CLASSES}
    return {
        "references": references,
        "unique_imports": len(records),
        "unique_by_class": counts,
        "references_by_class": by_references,
        "missing_libraries": missing,
        "library_mismatch": sum(1 for record in records if record["library_mismatch"]),
    }


def label(record):
    if record["name"] is None:
        return record["nid"]
    mark = "" if record.get("name_verified", True) else " (name does not hash to this NID)"
    return f"{record['nid']}  {record['name']}{mark}"


def render(summary, records, missing):
    lines = [f"{summary['references']} references, {summary['unique_imports']} unique imports"]
    for kind in CLASSES:
        lines.append(f"  {kind:<12}{summary['unique_by_class'][kind]:>6} imports  {summary['references_by_class'][kind]:>6} references")
    for title, kind in (("Absent: no built library exports these, so the loader fails", "absent"), ("Stub: exported but throws when called", "stub")):
        selected = [record for record in records if record["class"] == kind]
        if selected:
            lines.append("")
            lines.append(f"{title} ({len(selected)})")
            current = None
            for record in selected:
                if record["library"] != current:
                    current = record["library"]
                    lines.append(f"  [{current or 'library not named'}]")
                lines.append(f"    {label(record)}")
    if missing:
        lines.append("")
        lines.append(f"Needed libraries with no file in --libs or --modules ({len(missing)})")
        lines.extend(f"  {library}: {count} imports" for library, count in missing.items())
    if summary["library_mismatch"]:
        lines.append("")
        lines.append(f"{summary['library_mismatch']} imports are exported only by a library other than the one they name: they resolve on Linux and can fail on Windows")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="classify the imports of a converted game against the built system libraries")
    parser.add_argument("registries", nargs="+", type=Path, help="JSON written by 'relinker --registry'")
    parser.add_argument("--libs", action="append", required=True, help="directory of built .prx files; repeat for several")
    parser.add_argument("--modules", action="append", default=[], help="directory of the title's own modules; libraries named there are not checked")
    parser.add_argument("--source", default=str(PRX), help="core/libs/prx tree used to find throwing stubs (default: this repository's)")
    parser.add_argument("--names", help="aerolib.csv style file (NID, name per line) used to name absent imports")
    parser.add_argument("--json", type=Path, help="write the full result to this file")
    args = parser.parse_args(argv)
    try:
        if args.json:
            inputs = args.registries + ([Path(args.names)] if args.names else [])
            inputs += [file for directory in args.libs for file in directory_files(directory, "*.prx")]
            inputs += [file for directory in args.modules for file in directory_files(directory, "*")]
            inputs += list(Path(args.source).rglob("*.cpp"))
            output = args.json.resolve()
            if any(output == path.resolve() or (args.json.exists() and args.json.samefile(path)) for path in inputs):
                raise AuditError(f"{args.json}: JSON output would overwrite an input file")
        imports = [entry for registry in args.registries for entry in read_registry(registry)]
        exports, libraries = built_libraries(args.libs)
        modules = module_files(args.modules)
        records, missing = audit(imports, exports, source_stubs(args.source), libraries, modules)
        if args.names:
            attach_names(records, load_names(args.names))
        summary = summarize(records, len(imports), missing)
        if args.json:
            commit, dirty = git_stamp(Path(args.source))
            result = {"source_commit": commit, "source_dirty": dirty, "registries": [str(path) for path in args.registries], **summary, "imports": records}
            args.json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    except AuditError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"FAIL: {error.strerror}: {error.filename}" if error.filename else f"FAIL: {error}", file=sys.stderr)
        return 2
    print(render(summary, records, missing))
    return 1 if summary["unique_by_class"]["absent"] or missing else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
