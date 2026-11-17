import CRetroHost
import Darwin
import Foundation

/// One frame the launcher has pinned in a `RetroFrameRing`: the host does not write this slot until
/// the launcher's next read. Every field is the launcher's own checked copy (protocol.md "Frame
/// ring"); `pixels` is `height` rows of `width` × 4 bytes, top row first, no padding.
public struct RetroPinnedFrame: @unchecked Sendable {
    public let slot: Int
    public let width: Int
    public let height: Int
    public let epoch: Int
    /// Whether the frame has any pixel that is not black.
    public let visible: Bool
    public let pixels: UnsafeRawPointer
    public let pixelFormat: RetroPixelFormat
}

/// The shared memory a `ring` message announces, mapped and checked as protocol.md "Checks the
/// launcher makes" says. The header's geometry is read once, when the ring arrives; later reads use
/// only the copies.
public final class RetroFrameRing: @unchecked Sendable {
    static let magic: UInt32 = 0x4652_3541
    static let none: UInt32 = 0xFFFF_FFFF
    static let headerBytes = 4096
    static let maxSlotBytes = 268_435_456
    static let maxSide = 8192
    static let minBytes = 4108
    static let maxBytes = 805_310_464

    public let bytes: Int
    public let slotBytes: Int
    public let pixelFormat: RetroPixelFormat
    private let base: UnsafeMutableRawPointer
    private let mapped: Bool
    private let load: (UnsafeMutableRawPointer) -> UInt32
    private let store: (UnsafeMutableRawPointer, UInt32) -> Void
    private(set) var unmapped = false

    /// Whether the last `pin()` stored a slot in `reading`, which gives up the pin held before it,
    /// whether or not it pinned a new frame.
    public private(set) var gaveUpPin = false

    init(base: UnsafeMutableRawPointer, bytes: Int, slotBytes: Int, pixelFormat: RetroPixelFormat, mapped: Bool,
         load: @escaping (UnsafeMutableRawPointer) -> UInt32 = { anyps5_retro_load_u32($0) },
         store: @escaping (UnsafeMutableRawPointer, UInt32) -> Void = { anyps5_retro_store_u32($0, $1) }) {
        self.base = base
        self.bytes = bytes
        self.slotBytes = slotBytes
        self.pixelFormat = pixelFormat
        self.mapped = mapped
        self.load = load
        self.store = store
    }

    deinit { unmap() }

    /// Checks the memory behind `descriptor` (macOS: open for reading and writing, `fstat` at least
    /// `bytes` and less than one page more, `ftruncate` refused), maps it, and checks the header.
    /// `bytes` is the `ring` message's, already range-checked. The descriptor is the caller's to
    /// close. Throws `RetroProtocolError` when a check or the map fails.
    static func map(descriptor: Int32, bytes: Int, pixelFormat: RetroPixelFormat, current: RetroFrameRing?,
                    pageSize: Int = Int(getpagesize())) throws -> RetroFrameRing {
        guard (minBytes...maxBytes).contains(bytes) else { throw RetroProtocolError("ring.bytes is out of range.") }
        try checkMemory(descriptor: descriptor, bytes: bytes, pageSize: pageSize)
        let address = mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0)
        guard let address, address != UnsafeMutableRawPointer(bitPattern: -1) else {
            throw RetroProtocolError("mmap of the ring failed (errno \(errno)).")
        }
        do {
            let slotBytes = try checkHeader(UnsafeRawPointer(address), bytes: bytes, pixelFormat: pixelFormat,
                                            currentSlotBytes: current?.slotBytes)
            return RetroFrameRing(base: address, bytes: bytes, slotBytes: slotBytes, pixelFormat: pixelFormat, mapped: true)
        } catch {
            munmap(address, bytes)
            throw error
        }
    }

    /// The macOS memory checks of protocol.md "Checks the launcher makes", step 1. A POSIX shared
    /// memory object takes only its first `ftruncate`, so one that is refused shows the size is
    /// fixed; a writable regular file would take it.
    static func checkMemory(descriptor: Int32, bytes: Int, pageSize: Int) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, flags & O_ACCMODE == O_RDWR else {
            throw RetroProtocolError("The ring's memory is not open for reading and writing.")
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw RetroProtocolError("fstat of the ring failed (errno \(errno)).") }
        let size = Int64(info.st_size)
        guard size >= Int64(bytes), size < Int64(bytes) + Int64(pageSize) else {
            throw RetroProtocolError("The ring's memory is \(size) bytes, not \(bytes) rounded up to a page.")
        }
        guard ftruncate(descriptor, off_t(bytes)) != 0 else {
            throw RetroProtocolError("The ring's memory took an ftruncate, so its size can change.")
        }
    }

    /// The header checks of protocol.md "Checks the launcher makes", steps 2 and 3, on the header at
    /// `header`, each field loaded once into a copy. Gives `slotBytes`. `currentSlotBytes` is the
    /// current ring's, which the new one must outgrow.
    static func checkHeader(_ header: UnsafeRawPointer, bytes: Int, pixelFormat: RetroPixelFormat,
                            currentSlotBytes: Int?) throws -> Int {
        let magic = header.load(fromByteOffset: 0, as: UInt32.self)
        let version = header.load(fromByteOffset: 4, as: UInt32.self)
        let slotCount = header.load(fromByteOffset: 8, as: UInt32.self)
        let headerSize = header.load(fromByteOffset: 12, as: UInt32.self)
        let slotField = header.load(fromByteOffset: 16, as: UInt64.self)
        let format = header.load(fromByteOffset: 32, as: UInt32.self)
        guard UInt32(littleEndian: magic) == Self.magic else { throw RetroProtocolError("The ring's magic is wrong.") }
        guard UInt32(littleEndian: version) == 1 else { throw RetroProtocolError("The ring's version is not 1.") }
        guard UInt32(littleEndian: slotCount) == 3 else { throw RetroProtocolError("The ring does not have 3 slots.") }
        guard UInt32(littleEndian: headerSize) == UInt32(headerBytes) else {
            throw RetroProtocolError("The ring's header is not 4096 bytes.")
        }
        guard UInt32(littleEndian: format) == pixelFormat.code else {
            throw RetroProtocolError("The ring's pixel format is not the one welcome agreed.")
        }
        let slotBytes64 = UInt64(littleEndian: slotField)
        guard slotBytes64 >= 4, slotBytes64 <= UInt64(maxSlotBytes), slotBytes64 % 4 == 0 else {
            throw RetroProtocolError("The ring's slotBytes is out of range.")
        }
        let slotBytes = Int(slotBytes64)
        guard Int64(headerBytes) + 3 * Int64(slotBytes) == Int64(bytes) else {
            throw RetroProtocolError("The ring's size does not match its header.")
        }
        if let currentSlotBytes {
            let needed = min(currentSlotBytes * 2, maxSlotBytes)
            guard slotBytes > currentSlotBytes, slotBytes >= needed else {
                throw RetroProtocolError("A new ring is not at least twice as large as the last.")
            }
        }
        return slotBytes
    }

    /// Pins the newest frame: nil when there is none, or when `latest` kept moving for three tries.
    /// In that second case the frame pinned before is given up too (`gaveUpPin`), so the caller must
    /// stop showing it. Throws `RetroProtocolError` for a `latest` outside 0 to 2 or a slot whose
    /// size breaks the rules.
    public func pin() throws -> RetroPinnedFrame? {
        precondition(!unmapped, "pin on an unmapped ring")
        let latestAddress = base + 24
        let readingAddress = base + 28
        var pinned: Int?
        gaveUpPin = false
        for _ in 0..<3 {
            let latest = UInt32(littleEndian: load(latestAddress))
            if latest == Self.none { return nil }
            guard latest <= 2 else { throw RetroProtocolError("The ring's latest is \(latest).") }
            store(readingAddress, latest.littleEndian)
            gaveUpPin = true
            if UInt32(littleEndian: load(latestAddress)) == latest {
                pinned = Int(latest)
                break
            }
        }
        guard let slot = pinned else { return nil }
        let fields = UnsafeRawPointer(base + 40 + 24 * slot)
        let width = Int(UInt32(littleEndian: fields.load(fromByteOffset: 0, as: UInt32.self)))
        let height = Int(UInt32(littleEndian: fields.load(fromByteOffset: 4, as: UInt32.self)))
        let visible = UInt32(littleEndian: fields.load(fromByteOffset: 8, as: UInt32.self))
        let epoch = Int(UInt32(littleEndian: fields.load(fromByteOffset: 12, as: UInt32.self)))
        guard (1...Self.maxSide).contains(width), (1...Self.maxSide).contains(height) else {
            throw RetroProtocolError("A frame of \(width) x \(height) is outside 1 to 8192 pixels a side.")
        }
        guard Int64(width) * Int64(height) * 4 <= Int64(slotBytes) else {
            throw RetroProtocolError("A frame of \(width) x \(height) does not fit its slot.")
        }
        return RetroPinnedFrame(
            slot: slot, width: width, height: height, epoch: epoch, visible: visible != 0,
            pixels: UnsafeRawPointer(base + Self.headerBytes + slot * slotBytes), pixelFormat: pixelFormat)
    }

    /// Unmaps the ring; frames pinned in it may no longer be read.
    func unmap() {
        guard !unmapped else { return }
        unmapped = true
        if mapped { munmap(base, bytes) }
    }
}
