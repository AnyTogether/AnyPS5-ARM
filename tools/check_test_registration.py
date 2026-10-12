import argparse
import re
import subprocess
from pathlib import Path

TEST_OUTPUT = r"tests[\\/]"
COMMAND = re.compile(r"^\s*(add_test|set_tests_properties)\s*\(", re.M | re.I)
ARGUMENT = re.compile(r'"(?:\\.|[^"\\])*"|\[(?P<equals>=*)\[.*?\](?P=equals)\]|[^\s()]+', re.S)

KNOWN_UNRUN = set()


def built(build):
    listed = subprocess.run(["ninja", "-C", str(build), "-t", "targets", "all"],
                            capture_output=True, text=True, check=True).stdout
    names = set()
    for line in listed.splitlines():
        path, _, rule = line.partition(": ")
        if "EXECUTABLE" not in rule:
            continue
        found = re.match(rf"^{TEST_OUTPUT}(?:.*[\\/])?([^\\/]+)$", path)
        if not found:
            continue
        name = found.group(1)
        if name.endswith(".exe"):
            name = name[:-4]
        if name:
            names.add(name)
    return names


def commands(content):
    parsed_until = 0
    for command in COMMAND.finditer(content):
        if command.start() < parsed_until:
            continue
        position, arguments = command.end(), []
        while position < len(content):
            if content[position].isspace():
                position += 1
                continue
            if content[position] == ")":
                parsed_until = position + 1
                yield command.group(1).lower(), arguments
                break
            if content[position] == "#":
                position = content.find("\n", position)
                if position < 0:
                    break
                continue
            token = ARGUMENT.match(content, position)
            if token is None:
                raise ValueError(f"invalid CTest argument at position {position}")
            argument = token.group(0)
            if argument.startswith('"'):
                argument = re.sub(r"\\(.)", lambda match: {"n": "\n", "r": "\r", "t": "\t"}.get(match[1], match[1]), argument[1:-1], flags=re.S)
            elif token.group("equals") is not None:
                width = len(token.group("equals")) + 2
                argument = argument[width:-width]
            arguments.append(argument)
            position = token.end()


def registered(build):
    names = set()
    for file in Path(build).rglob("CTestTestfile.cmake"):
        tests, disabled = {}, {}
        for command, arguments in commands(file.read_text(encoding="utf-8", errors="replace")):
            if command == "add_test" and arguments:
                tests[arguments[0]] = arguments[1:]
            elif command == "set_tests_properties" and "PROPERTIES" in arguments:
                properties = arguments.index("PROPERTIES")
                values = arguments[properties + 1:]
                for key, value in zip(values[::2], values[1::2]):
                    if key == "DISABLED":
                        for name in arguments[:properties]:
                            disabled[name] = value.upper() in ("1", "ON", "YES", "TRUE", "Y")
        for test, arguments in tests.items():
            if disabled.get(test, False):
                continue
            for index, argument in enumerate(arguments):
                if index and (argument.startswith("-") or re.match(r"^[A-Za-z_]\w*=", argument)):
                    continue
                base = re.split(r"[\\/]", argument)[-1]
                if base.endswith(".exe"):
                    base = base[:-4]
                if base:
                    names.add(base)
    return names


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="fail when a test executable is built that no ctest test runs")
    parser.add_argument("build", type=Path, nargs="?", default=Path("build"), help="configured build directory")
    parser.add_argument("--list", action="store_true", help="print every test executable and whether ctest runs it")
    args = parser.parse_args()
    every = sorted(built(args.build))
    run = registered(args.build)
    if args.list:
        for name in every:
            print(f"{'run' if name in run else 'NOT RUN'}  {name}")
        raise SystemExit
    unrun = sorted(set(every) - run)
    if not every:
        print(f"no test executables found under {args.build}; is it configured with -DBUILD_TESTING=ON?")
        raise SystemExit(1)
    for name in sorted(set(unrun) & KNOWN_UNRUN):
        print(f"note: {name} is built and not run, as recorded")
    stale = sorted(KNOWN_UNRUN & run)
    for name in stale:
        print(f"error: {name} is run by ctest now; remove it from KNOWN_UNRUN")
    fresh = sorted(set(unrun) - KNOWN_UNRUN)
    for name in fresh:
        print(f"error: {name} is built but no ctest test runs it")
    if fresh:
        print(f"{len(fresh)} test executable(s) would never run: ctest reports a full pass over what it knows, so a test nobody registered is invisible in CI")
    if stale or fresh:
        raise SystemExit(1)
    print(f"{len(every)} test executable(s), {len(unrun)} built and not run as recorded, none new")
