"""A minimal PS5-style ELF that imports puts and exit by NID from one needed library, libc.prx by default."""
import struct, sys
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
from nid import nid

def fixture(message=b"hello from a PS5 ELF on macOS\0", library=b"libc.prx", extra_libraries=(), loads=None):
    code, data = 0x4000, 0x5000
    size = 0x6000
    if loads is None:
        loads = [(5, code, 0x1000, 0x1000), (6, data, 0x1000, 0x1000)]
    else:
        code = next(vaddr for flags, vaddr, _, _ in loads if flags & 1)
        data = next(vaddr for flags, vaddr, _, _ in loads if flags & 2)
        size = max(vaddr + file_size for _, vaddr, file_size, _ in loads)
    image = bytearray(size)
    image[:16] = b"\x7fELF\x02\x01\x01" + bytes(9)
    struct.pack_into("<HHIQQQIHHHHHH", image, 16, 3, 62, 1, code, 64, 0, 0, 64, 56, len(loads) + 1, 64, 0, 0)
    for index, (flags, vaddr, file_size, memory_size) in enumerate(loads):
        struct.pack_into("<IIQQQQQQ", image, 64 + index * 56, 1, flags, vaddr, vaddr, vaddr, file_size, memory_size, 0x1000)
    body = bytearray(b"\x48\x83\xec\x08")
    body += b"\x48\x8d\x3d" + struct.pack("<i", data + 0x100 - (code + 4 + 7))
    body += b"\xff\x15" + struct.pack("<i", data - (code + 11 + 6))
    body += b"\x31\xff"
    body += b"\xff\x15" + struct.pack("<i", data + 8 - (code + 19 + 6))
    body += b"\x0f\x0b"
    image[code:code + len(body)] = body
    image[data + 0x100:data + 0x100 + len(message)] = message
    names = [library, *extra_libraries]
    strings = b"\0" + b"".join(name + b"\0" for name in names)
    needed = [1 + sum(len(name) + 1 for name in names[:index]) for index in range(len(names))]
    puts_name = len(strings)
    strings += (nid("puts") + "#A#B").encode() + b"\0"
    exit_name = len(strings)
    strings += (nid("exit") + "#A#B").encode() + b"\0"
    image[data + 0xA00:data + 0xA00 + len(strings)] = strings
    struct.pack_into("<IBBHQQ", image, data + 0xB00 + 24, puts_name, 0x12, 0, 0, 0, 0)
    struct.pack_into("<IBBHQQ", image, data + 0xB00 + 48, exit_name, 0x12, 0, 0, 0, 0)
    struct.pack_into("<QQq", image, data + 0xC00, data, (1 << 32) | 6, 0)
    struct.pack_into("<QQq", image, data + 0xC18, data + 8, (2 << 32) | 6, 0)
    tags = [(1, offset) for offset in needed]
    tags += [(5, data + 0xA00), (10, len(strings)), (6, data + 0xB00), (11, 24), (0x6100003f, 72), (7, data + 0xC00), (8, 48), (9, 24), (0, 0)]
    for index, tag in enumerate(tags):
        struct.pack_into("<qQ", image, data + 0x800 + index * 16, *tag)
    struct.pack_into("<IIQQQQQQ", image, 64 + len(loads) * 56, 2, 6, data + 0x800, data + 0x800, data + 0x800, len(tags) * 16, len(tags) * 16, 8)
    return image

if __name__ == "__main__":
    open(sys.argv[1], "wb").write(fixture())
