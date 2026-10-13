import ctypes
import os
import struct
import subprocess
import sys
import tempfile
from ctypes import wintypes
from pathlib import Path

from test_guest_intel_trampolines import main_fixture
from test_guest_module_directories import module_with_symbol, needed_libraries
from test_guest_tls import data_directory, guest_with_tls


def check_native_load_paths(output, libraries):
    pe = output.read_bytes()
    header = struct.unpack_from('<I', pe, 0x3c)[0]
    optional = header + 24
    section_table = optional + struct.unpack_from('<H', pe, header + 20)[0]
    sections = {}
    for index in range(struct.unpack_from('<H', pe, header + 6)[0]):
        offset = section_table + index * 40
        name = pe[offset:offset + 8].rstrip(b'\0')
        size, rva, raw_size, raw = struct.unpack_from('<IIII', pe, offset + 8)
        sections[name] = (rva, pe[raw:raw + min(size, raw_size)])

    def file_offset(rva):
        for index in range(struct.unpack_from('<H', pe, header + 6)[0]):
            offset = section_table + index * 40
            size, start, raw_size, raw = struct.unpack_from('<IIII', pe, offset + 8)
            if start <= rva < start + min(size, raw_size):
                return raw + rva - start
        raise AssertionError(f'RVA {rva:#x} has no file data')

    descriptor = file_offset(struct.unpack_from('<I', pe, optional + 112 + 8)[0])
    slots = {}
    while any(pe[descriptor:descriptor + 20]):
        lookup, _, _, _, iat = struct.unpack_from('<IIIII', pe, descriptor)
        index = 0
        while (name_rva := struct.unpack_from('<Q', pe, file_offset((lookup or iat) + index * 8))[0]):
            if not name_rva & (1 << 63):
                name_offset = file_offset(name_rva) + 2
                slots[pe[name_offset:pe.index(b'\0', name_offset)]] = iat + index * 8
            index += 1
        descriptor += 20
    load_library_iat = slots.get(b'LoadLibraryExW')
    assert load_library_iat is not None, 'LoadLibraryExW is not imported'
    attributes_iat = slots.get(b'GetFileAttributesW')

    data_rva, data = sections[b'.startup']
    code_rva, code = sections[b'.entry']
    path_loads = []
    for library in libraries:
        path = ('libs\\' + library + '\0').encode('utf-16le')
        path_rva = data_rva + data.index(path)
        references = [offset for offset in range(len(code) - 6)
                      if code[offset:offset + 3] == b'\x48\x8d\x35'
                      and code_rva + offset + 7 + struct.unpack_from('<i', code, offset + 3)[0] == path_rva]
        assert len(references) == 1, f'{library}: expected a loader path reference, found {len(references)}'
        path_loads.append((references[0], library))
    path_loads.sort()
    for index, (start, library) in enumerate(path_loads):
        end = path_loads[index + 1][0] if index + 1 < len(path_loads) else len(code)
        def calls_through(slot):
            return [offset for offset in range(start, end - 5)
                    if code[offset:offset + 2] == b'\xff\x15'
                    and code_rva + offset + 6 + struct.unpack_from('<i', code, offset + 2)[0] == slot]

        calls = calls_through(load_library_iat)
        assert calls, f'{library}: loader path does not reach a LoadLibraryExW call'
        assert code[calls[0] - 11:calls[0]] == b'\x48\x89\xf1\x31\xd2\x41\xb8\x00\x11\x00\x00', library
        probes = [offset for offset in calls_through(attributes_iat) if offset < calls[0]]
        assert len(probes) == 1, f'{library}: optional provider is not probed with GetFileAttributesW before LoadLibraryExW'
        probe = probes[0]
        assert code[probe - 3:probe] == b'\x48\x89\xf1' and code[probe + 6:probe + 11] == b'\x83\xf8\xff\x0f\x85', library
        assert probe + 15 + struct.unpack_from('<i', code, probe + 11)[0] == calls[0] - 11, \
            f'{library}: a present optional provider does not continue to LoadLibraryExW'


def dynamic(image, offset, phoff, tags):
    for index, tag in enumerate(tags + [(0, 0)]):
        struct.pack_into('<qQ', image, offset + index * 16, *tag)
    struct.pack_into('<QQ', image, phoff + 32, (len(tags) + 1) * 16, (len(tags) + 1) * 16)


def provider(value, soname=None, code=None):
    image = module_with_symbol(True)
    code = code or b'\xb8' + struct.pack('<I', value) + b'\xc3'
    image[0x400:0x400 + len(code)] = code
    struct.pack_into('<Q', image, 0x898 + 16, len(code))
    if soname:
        strings = b'\0shared#A#B\0' + soname.encode() + b'\0'
        image[0x800:0x800 + len(strings)] = strings
        tags = [(5, 0x2200), (10, len(strings)), (6, 0x2280), (11, 24),
                (4, 0x2240), (7, 0x2300), (8, 0), (9, 24), (14, 12)]
        dynamic(image, 0x600, 176, tags)
    return image


def check_internal_guest_libc(convert, work, relinker):
    result, dummy = convert('empty-native-provider', 'c.prx')
    assert result.returncode == 0, result.stderr
    result, shared = convert('shared-native-provider', 'a.prx')
    assert result.returncode == 0, result.stderr
    empty_provider = dummy.parent / 'app0' / 'prx' / 'c.prx.guest.prx'
    shared_provider = shared.parent / 'app0' / 'prx' / 'a.prx.guest.prx'
    zero = b'\x31\xc0\xc3'
    zero_xmm = b'\x66\x0f\xef\xc0\x31\xc0\xc3'
    for name, native_owner, symbol, code, expected in (
            ('guest-only', None, 'shared#A#B', None, 22),
            ('internal-first', 'libSceLibcInternal.prx', 'shared#A#B', None, 11),
            ('native-libc-first', 'libc.prx', 'shared#A#B', None, 11),
            ('unresolved', None, 'absent#A#B', None, None),
            ('guest-zero-return', None, 'shared#A#B', zero, None),
            ('guest-zero-return-xmm', None, 'shared#A#B', zero_xmm, None),
            ('internal-first-zero-return', 'libSceLibcInternal.prx', 'shared#A#B', zero, 11)):
        case = work / ('internal-guest-libc-' + name)
        (case / 'sce_module').mkdir(parents=True)
        (case / 'sce_module' / 'libc.prx').write_bytes(provider(22, code=code))
        source = case / 'input.elf'
        source.write_bytes(executable('libSceLibcInternal.prx', symbol, extra_dependencies=('libc.prx',)))
        output = case / 'output.exe'
        result = subprocess.run([str(relinker), '--windows', str(source), str(output)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        (case / 'libs').mkdir()
        for owner in ('libSceLibcInternal.prx', 'libc.prx'):
            selected = shared_provider if owner == native_owner else empty_provider
            (case / 'libs' / owner).write_bytes(selected.read_bytes())
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            if expected is None:
                assert run.returncode != 0 and 'unresolved ELF import ' + symbol.split('#')[0] in run.stderr, (run.returncode, run.stdout, run.stderr)
            else:
                assert run.returncode == expected, (run.returncode, run.stdout, run.stderr)


def consumer(owner, symbol='shared#A#B', expected=22, module_name=None):
    image = module_with_symbol(False)
    strings = b'\0' + symbol.encode() + b'\0' + owner.encode() + b'\0'
    owner_offset = len(symbol) + 2
    module_offset = owner_offset
    if module_name is not None:
        module_offset = len(strings)
        strings += module_name.encode() + b'\0'
    image[0x800:0x800 + len(strings)] = strings
    tags = [(5, 0x2200), (10, len(strings)), (6, 0x2280), (11, 24),
            (4, 0x2240), (7, 0x2300), (8, 24), (9, 24), (12, 0x1010),
            (1, owner_offset), (0x61000045, (1 << 48) | module_offset)]
    dynamic(image, 0x600, 176, tags)
    code = b'\xff\x15' + struct.pack('<i', 0x2320 - 0x1016) + bytes([0x83, 0xf8, expected, 0x74, 2, 0x0f, 0x0b, 0xc3])
    image[0x410:0x410 + len(code)] = code
    return image


def executable(owner, symbol='shared#A#B', module_name=None, extra_dependencies=()):
    image = main_fixture()
    struct.pack_into('<I', image, 68, 7)
    strings = b'\0' + symbol.encode() + b'\0' + owner.encode() + b'\0'
    owner_offset = len(symbol) + 2
    module_offset = owner_offset
    if module_name is not None:
        module_offset = len(strings)
        strings += module_name.encode() + b'\0'
    dependency_offsets = []
    for dependency in extra_dependencies:
        dependency_offsets.append(len(strings))
        strings += dependency.encode() + b'\0'
    image[0x4800:0x4800 + len(strings)] = strings
    tags = [(5, 0x4800), (10, len(strings)), (6, 0x4880), (11, 24),
            (4, 0x4840), (7, 0x4900), (8, 24), (9, 24),
            (1, owner_offset), (0x61000045, (1 << 48) | module_offset)]
    tags.extend((1, offset) for offset in dependency_offsets)
    dynamic(image, 0x4600, 120, tags)
    struct.pack_into('<IIIII', image, 0x4840, 1, 2, 1, 0, 0)
    struct.pack_into('<IBBHQQ', image, 0x4898, 1, 0x12, 0, 0, 0, 0)
    struct.pack_into('<QQq', image, 0x4900, 0x4a20, (1 << 32) | 6, 0)
    image[0x4000:0x4007] = b'\xff\x15' + struct.pack('<i', 0x4a20 - 0x4006) + b'\xc3'
    return image


def exit_code_without_standard_handles(executable_path):
    sem_failcriticalerrors = 0x0001
    sem_nogpfaulterrorbox = 0x0002
    startf_usestdhandles = 0x00000100
    wait_object_0 = 0
    wait_timeout = 0x00000102

    class StartupInfo(ctypes.Structure):
        _fields_ = [
            ('cb', wintypes.DWORD),
            ('lpReserved', wintypes.LPWSTR),
            ('lpDesktop', wintypes.LPWSTR),
            ('lpTitle', wintypes.LPWSTR),
            ('dwX', wintypes.DWORD),
            ('dwY', wintypes.DWORD),
            ('dwXSize', wintypes.DWORD),
            ('dwYSize', wintypes.DWORD),
            ('dwXCountChars', wintypes.DWORD),
            ('dwYCountChars', wintypes.DWORD),
            ('dwFillAttribute', wintypes.DWORD),
            ('dwFlags', wintypes.DWORD),
            ('wShowWindow', wintypes.WORD),
            ('cbReserved2', wintypes.WORD),
            ('lpReserved2', wintypes.LPVOID),
            ('hStdInput', wintypes.HANDLE),
            ('hStdOutput', wintypes.HANDLE),
            ('hStdError', wintypes.HANDLE),
        ]

    class ProcessInformation(ctypes.Structure):
        _fields_ = [
            ('hProcess', wintypes.HANDLE),
            ('hThread', wintypes.HANDLE),
            ('dwProcessId', wintypes.DWORD),
            ('dwThreadId', wintypes.DWORD),
        ]

    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel32.GetErrorMode.restype = wintypes.UINT
    kernel32.SetErrorMode.argtypes = [wintypes.UINT]
    kernel32.SetErrorMode.restype = wintypes.UINT
    kernel32.CreateProcessW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.LPVOID, wintypes.LPVOID, wintypes.BOOL,
                                        wintypes.DWORD, wintypes.LPVOID, wintypes.LPCWSTR, ctypes.POINTER(StartupInfo),
                                        ctypes.POINTER(ProcessInformation)]
    kernel32.CreateProcessW.restype = wintypes.BOOL
    kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel32.WaitForSingleObject.restype = wintypes.DWORD
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel32.GetExitCodeProcess.restype = wintypes.BOOL
    kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel32.TerminateProcess.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    kernel32.SetErrorMode(kernel32.GetErrorMode() | sem_failcriticalerrors | sem_nogpfaulterrorbox)
    info = StartupInfo()
    info.cb = ctypes.sizeof(info)
    info.dwFlags = startf_usestdhandles
    process = ProcessInformation()
    command = ctypes.create_unicode_buffer(f'"{executable_path}"')
    if not kernel32.CreateProcessW(str(executable_path), command, None, None, False, 0, None, None,
                                   ctypes.byref(info), ctypes.byref(process)):
        raise OSError(ctypes.get_last_error(), 'CreateProcessW failed')
    try:
        result = kernel32.WaitForSingleObject(process.hProcess, 30_000)
        if result == wait_timeout:
            kernel32.TerminateProcess(process.hProcess, 0xffffffff)
            kernel32.WaitForSingleObject(process.hProcess, 0xffffffff)
            raise TimeoutError('GUI child did not exit')
        if result != wait_object_0:
            raise OSError(f'WaitForSingleObject returned {result}')
        exit_code = wintypes.DWORD()
        if not kernel32.GetExitCodeProcess(process.hProcess, ctypes.byref(exit_code)):
            raise OSError(ctypes.get_last_error(), 'GetExitCodeProcess failed')
        return exit_code.value
    finally:
        kernel32.CloseHandle(process.hThread)
        kernel32.CloseHandle(process.hProcess)


def main():
    relinker = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='anyps5-import-modules-') as directory:
        work = Path(directory)

        def convert(name, owner, symbol='shared#A#B', guest_owner=None, module_name=None, provider_name='b.prx', extra_dependencies=(), windows_gui=False):
            case = work / name
            modules = case / 'prx'
            modules.mkdir(parents=True)
            (modules / 'a.prx').write_bytes(provider(11))
            (modules / provider_name).write_bytes(provider(22, 'alias.prx'))
            other = provider(33)
            other[0x800:0x80c] = b'\0other#A#B\0\0'
            (modules / 'c.prx').write_bytes(other)
            if guest_owner:
                (modules / 'consumer.prx').write_bytes(consumer(guest_owner, symbol, module_name=module_name))
            for dependency in extra_dependencies:
                (modules / dependency).write_bytes(provider(44))
            source = case / 'input.elf'
            source.write_bytes(executable(owner, symbol, module_name, extra_dependencies))
            output = case / 'output.exe'
            arguments = [str(relinker), '--windows']
            if windows_gui:
                arguments.append('--windows-gui')
            arguments.extend([str(source), str(output)])
            result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
            return result, output

        for owner in ('a.prx', 'b.prx', 'alias.prx'):
            result, output = convert(owner, owner, guest_owner='b.prx')
            assert result.returncode == 0, (result.stdout, result.stderr)
            if os.name == 'nt':
                run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
                assert run.returncode == (11 if owner == 'a.prx' else 22), (run.returncode, run.stdout, run.stderr)

        result, output = convert('unicode-ü日', 'a.prx', guest_owner='b.prx')
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert output.is_file() and (output.parent / 'app0' / 'prx' / 'a.prx.guest.prx').is_file()

        result, native_output = convert('unscoped-native-provider', 'b.prx')
        assert result.returncode == 0, result.stderr
        case = work / 'unscoped-native-import'
        (case / 'prx').mkdir(parents=True)
        (case / 'libs').mkdir()
        (case / 'prx' / 'tls.prx').write_bytes(guest_with_tls(True))
        native_provider = native_output.parent / 'app0' / 'prx' / 'b.prx.guest.prx'
        (case / 'libs' / 'available.prx').write_bytes(native_provider.read_bytes())
        source = case / 'input.elf'
        source.write_bytes(executable('available.prx', 'shared', extra_dependencies=('unused.prx',)))
        output = case / 'output.exe'
        result = subprocess.run([str(relinker), '--windows', str(source), str(output)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        check_native_load_paths(output, ('available.prx', 'unused.prx'))
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode == 22 and 'unused.prx' not in run.stderr, (run.returncode, run.stdout, run.stderr)

        broken = (case / 'app0' / 'prx' / 'tls.prx.guest.prx').read_bytes()
        assert data_directory(broken, 1)[0] and broken.count(b'KERNEL32.dll\0') == 1
        broken = broken.replace(b'KERNEL32.dll\0', b'APS5MISS.dll\0')
        (case / 'libs' / 'unused.prx').write_bytes(broken)
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode != 0 and 'Failed to load module:' in run.stderr and 'unused.prx' in run.stderr and 'GetLastError: 126' in run.stderr, (run.returncode, run.stdout, run.stderr)
            assert 'nothing is imported from it' not in run.stderr, run.stderr

        check_internal_guest_libc(convert, work, relinker)

        for filename, module_name in [('foo.native.prx', 'foo_native'),
                                      ('libSceFont-module.prx', 'libSceFont')]:
            result, output = convert(module_name, filename, guest_owner=filename,
                                     module_name=module_name, provider_name=filename)
            assert result.returncode == 0, (result.stdout, result.stderr)
            if os.name == 'nt':
                run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
                assert run.returncode == 22, (run.returncode, run.stdout, run.stderr)

        for index, filename in enumerate(('party.prx', 'party.PRX')):
            result, output = convert('case-' + str(index), 'Party.prx', guest_owner='Party.prx', provider_name=filename)
            assert result.returncode == 0, (result.stdout, result.stderr)
            if os.name == 'nt':
                run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
                assert run.returncode == 22, (run.returncode, run.stdout, run.stderr)

        case = work / 'exact-soname-before-filename-case'
        modules = case / 'prx'
        modules.mkdir(parents=True)
        (modules / 'party.prx').write_bytes(provider(11))
        (modules / 'other.prx').write_bytes(provider(22, 'Party.prx'))
        (modules / 'consumer.prx').write_bytes(consumer('Party.prx'))
        source = case / 'input.elf'
        source.write_bytes(executable('Party.prx'))
        output = case / 'output.exe'
        result = subprocess.run([str(relinker), '--windows', str(source), str(output)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (result.stdout, result.stderr)
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode == 22, (run.returncode, run.stdout, run.stderr)

        result, output = convert('wrong-case-soname', 'ALIAS.prx')
        assert result.returncode == 0, result.stderr
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode != 0 and 'Failed to load module:' in run.stderr and 'ALIAS.prx' in run.stderr, (run.returncode, run.stderr)

        case = work / 'linux-filename-case'
        modules = case / 'prx'
        modules.mkdir(parents=True)
        (modules / 'party.prx').write_bytes(provider(22))
        source = case / 'input.elf'
        source.write_bytes(executable('Party.prx'))
        output = case / 'output.elf'
        result = subprocess.run([str(relinker), str(source), str(output)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert 'Party.prx' in needed_libraries(output.read_bytes())

        result, output = convert('ambiguous-alias', 'foo.native.prx', module_name='foo_native',
                                 provider_name='foo.native.prx', extra_dependencies=('foo.native-module.prx',))
        assert result.returncode == 2 and 'Ambiguous import module dependency' in result.stderr, result.stderr
        assert not output.exists()

        result, output = convert('exact-before-alias', 'foo.native.prx', module_name='foo.native',
                                 provider_name='foo.native.prx', extra_dependencies=('foo_native.prx',))
        assert result.returncode == 0, result.stderr
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode == 22, (run.returncode, run.stdout, run.stderr)

        result, output = convert('unmatched-module', 'libFoo2.prx', module_name='libFoo', provider_name='libFoo2.prx')
        assert result.returncode == 0, result.stderr
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode == 11, (run.returncode, run.stdout, run.stderr)

        for symbol, message in [('shared#A#C', 'Unknown import module ID'),
                                ('shared#A#', 'Invalid qualified import'),
                                ('shared#A#?', 'Invalid import module ID'),
                                ('shared#A#BBBBBBBB', 'Invalid import module ID')]:
            result, output = convert(symbol.replace('?', 'invalid'), 'b.prx', symbol)
            assert result.returncode == 2 and message in result.stderr, result.stderr
            assert not output.exists()

        result, output = convert('legacy', 'b.prx', 'shared', guest_owner='b.prx')
        assert result.returncode == 2 and 'Ambiguous guest import' in result.stderr, result.stderr
        assert not output.exists()

        if os.name == 'nt':
            for name, owner, symbol, expected in [
                    ('missing-symbol-gui', 'a.prx', 'absent#A#B', 0xc0000139),
                    ('missing-dependency-gui', 'missing.prx', 'shared#A#B', 0xc0000135)]:
                result, output = convert(name, owner, symbol, windows_gui=True)
                assert result.returncode == 0, result.stderr
                run_status = exit_code_without_standard_handles(output)
                assert run_status == expected, (name, hex(run_status), hex(expected))

        result, output = convert('missing-symbol', 'a.prx', 'absent#A#B')
        assert result.returncode == 0, result.stderr
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode != 0 and 'unresolved ELF import absent' in run.stderr, (run.returncode, run.stderr)
        result, output = convert('wrong-provider', 'c.prx')
        assert result.returncode == 0, result.stderr
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode != 0 and 'unresolved ELF import shared' in run.stderr, (run.returncode, run.stderr)
        result, output = convert('missing-dependency', 'missing.prx')
        assert result.returncode == 0, result.stderr
        if os.name == 'nt':
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode != 0 and 'Failed to load module:' in run.stderr and 'missing.prx' in run.stderr, (run.returncode, run.stderr)
            assert run.stderr.startswith('Failed to load module:'), run.stderr

        for index, (symbol, module_name) in enumerate([('shared#A#B', None), ('shared', None), ('shared#A#B', 'libSceJson')]):
            case = work / ('missing-unused-dependency-' + str(index))
            modules = case / 'prx'
            modules.mkdir(parents=True)
            (modules / 'a.prx').write_bytes(provider(11))
            source = case / 'input.elf'
            source.write_bytes(executable('a.prx', symbol, module_name, extra_dependencies=('unused.prx',)))
            output = case / 'output.exe'
            result = subprocess.run([str(relinker), '--windows', str(source), str(output)], capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, (symbol, module_name, result.stdout, result.stderr)
            if os.name == 'nt':
                run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
                assert run.returncode == 11 and 'unused.prx' not in run.stderr, (symbol, module_name, run.returncode, run.stdout, run.stderr)

    print('Windows module-scoped import tests passed')


if __name__ == '__main__':
    main()
