"""Check that weak undefined imports stay weak on Linux and bind to null on Windows when no module exports them."""

import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from test_windows_import_modules import executable, provider

SHT_DYNSYM = 11
STB_GLOBAL = 1
STB_WEAK = 2


def weak_executable(owner, symbol):
    image = executable(owner, symbol)
    image[0x4898 + 4] = (STB_WEAK << 4) | 2
    code = (b'\x48\x8b\x05' + struct.pack('<i', 0x4a20 - 0x4007)
            + b'\x48\x85\xc0\x74\x02\xff\xe0\xb8\x21\x00\x00\x00\xc3')
    image[0x4000:0x4000 + len(code)] = code
    return image


def import_bindings(elf):
    shoff, = struct.unpack_from('<Q', elf, 0x28)
    shentsize, shnum, _ = struct.unpack_from('<HHH', elf, 0x3A)
    sections = [struct.unpack_from('<IIQQQQIIQQ', elf, shoff + index * shentsize) for index in range(shnum)]
    dynsym = next(section for section in sections if section[1] == SHT_DYNSYM)
    strings = sections[dynsym[6]][4]
    bindings = {}
    for offset in range(dynsym[4] + 24, dynsym[4] + dynsym[5], 24):
        name, info, _, index = struct.unpack_from('<IBBH', elf, offset)
        if index == 0:
            bindings[elf[strings + name:elf.index(b'\0', strings + name)].decode()] = info >> 4
    return bindings


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='anyps5-weak-imports-') as directory:
        work = Path(directory)

        for name, image, symbol, expected in (('linux-weak', weak_executable('a.prx', 'absent#A#B'), 'absent', STB_WEAK),
                                              ('linux-global', executable('a.prx', 'absent#A#B'), 'absent', STB_GLOBAL)):
            source = work / (name + '.elf')
            source.write_bytes(image)
            output = work / (name + '.out')
            result = subprocess.run([str(relinker), '--skip-sce-module', str(source), str(output)],
                                    capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, (name, result.stdout, result.stderr)
            bindings = import_bindings(output.read_bytes())
            assert bindings.get(symbol) == expected, (name, bindings)

        for name, symbol, expected in (('windows-weak-missing', 'absent#A#B', 33),
                                       ('windows-weak-present', 'shared#A#B', 11)):
            case = work / name
            (case / 'prx').mkdir(parents=True)
            (case / 'prx' / 'a.prx').write_bytes(provider(11))
            source = case / 'input.elf'
            source.write_bytes(weak_executable('a.prx', symbol))
            output = case / 'output.exe'
            result = subprocess.run([str(relinker), '--windows', str(source), str(output)],
                                    capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, (name, result.stdout, result.stderr)
            if os.name == 'nt':
                run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
                assert run.returncode == expected, (name, run.returncode, run.stdout, run.stderr)

    print('Weak import tests passed')


if __name__ == '__main__':
    main()
