import CRetroHostTesting
import Darwin
import XCTest
@testable import AnyPS5Core

/// The frame ring's checks and pinning (protocol.md "Frame ring" and "Checks the launcher makes"), as
/// on Windows and Linux (AnyPS5 Desktop's test/core/retro_host/frame_ring_test.dart), with the macOS
/// memory checks on real shared memory objects.
final class RetroFrameRingTests: XCTestCase {
    private struct Header {
        var magic: UInt32 = 0x4652_3541
        var version: UInt32 = 1
        var slotCount: UInt32 = 3
        var headerBytes: UInt32 = 4096
        var slotBytes: UInt64 = 320 * 240 * 4
        var latest: UInt32 = 0xFFFF_FFFF
        var reading: UInt32 = 0xFFFF_FFFF
        var pixelFormat: UInt32 = 1
        var slots: [(width: UInt32, height: UInt32, visible: UInt32, epoch: UInt32)] = Array(repeating: (0, 0, 0, 0), count: 3)

        var bytes: Int { 4096 + 3 * Int(slotBytes) }

        func write(to base: UnsafeMutableRawPointer) {
            base.storeBytes(of: magic.littleEndian, toByteOffset: 0, as: UInt32.self)
            base.storeBytes(of: version.littleEndian, toByteOffset: 4, as: UInt32.self)
            base.storeBytes(of: slotCount.littleEndian, toByteOffset: 8, as: UInt32.self)
            base.storeBytes(of: headerBytes.littleEndian, toByteOffset: 12, as: UInt32.self)
            base.storeBytes(of: slotBytes.littleEndian, toByteOffset: 16, as: UInt64.self)
            base.storeBytes(of: latest.littleEndian, toByteOffset: 24, as: UInt32.self)
            base.storeBytes(of: reading.littleEndian, toByteOffset: 28, as: UInt32.self)
            base.storeBytes(of: pixelFormat.littleEndian, toByteOffset: 32, as: UInt32.self)
            for (index, slot) in slots.enumerated() {
                let at = 40 + 24 * index
                base.storeBytes(of: slot.width.littleEndian, toByteOffset: at, as: UInt32.self)
                base.storeBytes(of: slot.height.littleEndian, toByteOffset: at + 4, as: UInt32.self)
                base.storeBytes(of: slot.visible.littleEndian, toByteOffset: at + 8, as: UInt32.self)
                base.storeBytes(of: slot.epoch.littleEndian, toByteOffset: at + 12, as: UInt32.self)
                base.storeBytes(of: UInt64(index + 1).littleEndian, toByteOffset: at + 16, as: UInt64.self)
            }
        }
    }

    private var buffers: [UnsafeMutableRawPointer] = []

    override func tearDown() {
        for buffer in buffers { buffer.deallocate() }
        buffers = []
    }

    private func headerBuffer(_ header: Header) -> UnsafeMutableRawPointer {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: 16)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 4096)
        header.write(to: buffer)
        buffers.append(buffer)
        return buffer
    }

    private func check(_ header: Header, bytes: Int? = nil, format: RetroPixelFormat = .rgba8, current: Int? = nil) throws -> Int {
        try RetroFrameRing.checkHeader(UnsafeRawPointer(headerBuffer(header)), bytes: bytes ?? header.bytes,
                                       pixelFormat: format, currentSlotBytes: current)
    }

    private func assertProtocolError(_ body: @autoclosure () throws -> Any, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertTrue(error is RetroProtocolError, "\(error)", file: file, line: line)
        }
    }

    func testAGoodHeaderGivesItsSlotSize() throws {
        XCTAssertEqual(try check(Header()), 307_200)
        var bgra = Header()
        bgra.pixelFormat = 2
        XCTAssertEqual(try check(bgra, format: .bgra8), 307_200)
    }

    func testEachFixedFieldIsChecked() {
        var header = Header()
        header.magic = 0x4652_3542
        assertProtocolError(try check(header))
        header = Header()
        header.version = 2
        assertProtocolError(try check(header))
        header = Header()
        header.slotCount = 2
        assertProtocolError(try check(header))
        header = Header()
        header.headerBytes = 8192
        assertProtocolError(try check(header))
        header = Header()
        assertProtocolError(try check(header, format: .bgra8))
    }

    func testSlotBytesIsRangeCheckedBeforeTheSizeIsComputed() {
        var header = Header()
        for slotBytes: UInt64 in [0, 2, 6, 268_435_460, 1 << 62, UInt64.max - 3] {
            header.slotBytes = slotBytes
            assertProtocolError(try check(header, bytes: 805_310_464))
        }
        header.slotBytes = 268_435_456
        XCTAssertNoThrow(try check(header, bytes: 805_310_464))
    }

    func testTheSizeMustMatchTheHeader() {
        assertProtocolError(try check(Header(), bytes: Header().bytes + 4096))
        assertProtocolError(try check(Header(), bytes: Header().bytes - 4))
    }

    func testANewRingMustAtLeastDoubleUpToTheLimit() throws {
        var header = Header()
        header.slotBytes = 614_400
        XCTAssertEqual(try check(header, current: 307_200), 614_400)
        header.slotBytes = 614_396
        assertProtocolError(try check(header, current: 307_200))
        header.slotBytes = 307_200
        assertProtocolError(try check(header, current: 307_200))
        header.slotBytes = 268_435_456
        XCTAssertNoThrow(try check(header, current: 200_000_000))
        assertProtocolError(try check(header, current: 268_435_456))
    }

    private func ring(_ header: Header, load: ((UnsafeMutableRawPointer) -> UInt32)? = nil) -> RetroFrameRing {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: header.bytes, alignment: 4096)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: header.bytes)
        header.write(to: buffer)
        buffers.append(buffer)
        if let load {
            return RetroFrameRing(base: buffer, bytes: header.bytes, slotBytes: Int(header.slotBytes), pixelFormat: .rgba8,
                                  mapped: false, load: load)
        }
        return RetroFrameRing(base: buffer, bytes: header.bytes, slotBytes: Int(header.slotBytes), pixelFormat: .rgba8,
                              mapped: false)
    }

    func testNoFrameYetPinsNothing() throws {
        let made = ring(Header())
        XCTAssertNil(try made.pin())
        XCTAssertFalse(made.gaveUpPin)
    }

    func testTheNewestFrameIsPinnedWithItsOwnCopies() throws {
        var header = Header()
        header.latest = 2
        header.slots[2] = (320, 240, 1, 7)
        let made = ring(header)
        let frame = try XCTUnwrap(made.pin())
        XCTAssertEqual(frame.slot, 2)
        XCTAssertEqual(frame.width, 320)
        XCTAssertEqual(frame.height, 240)
        XCTAssertEqual(frame.epoch, 7)
        XCTAssertTrue(frame.visible)
        XCTAssertTrue(made.gaveUpPin)
    }

    func testPinningStoresTheSlotInReading() throws {
        var header = Header()
        header.latest = 1
        header.slots[1] = (2, 2, 0, 1)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: header.bytes, alignment: 4096)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: header.bytes)
        header.write(to: buffer)
        buffers.append(buffer)
        let made = RetroFrameRing(base: buffer, bytes: header.bytes, slotBytes: Int(header.slotBytes), pixelFormat: .rgba8, mapped: false)
        _ = try made.pin()
        XCTAssertEqual(buffer.load(fromByteOffset: 28, as: UInt32.self), 1)
    }

    func testALatestOutsideTheSlotsIsAProtocolError() {
        var header = Header()
        header.latest = 3
        assertProtocolError(try ring(header).pin())
    }

    func testAFrameOutsideItsLimitsIsAProtocolError() {
        for slot in [(UInt32(0), UInt32(240)), (320, 0), (8193, 1), (1, 8193)] {
            var header = Header()
            header.latest = 0
            header.slots[0] = (slot.0, slot.1, 1, 1)
            assertProtocolError(try ring(header).pin())
        }
        var header = Header()
        header.latest = 0
        header.slots[0] = (640, 480, 1, 1)
        assertProtocolError(try ring(header).pin())
    }

    func testALatestThatKeepsMovingForThreeTriesGivesUpThePin() throws {
        var header = Header()
        header.latest = 0
        header.slots = Array(repeating: (320, 240, 1, 1), count: 3)
        var counter: UInt32 = 0
        let made = ring(header) { _ in
            counter += 1
            return counter % 3
        }
        XCTAssertNil(try made.pin())
        XCTAssertTrue(made.gaveUpPin)
        XCTAssertEqual(counter, 6)
    }

    // MARK: macOS memory

    private func sharedMemory(_ bytes: Int) throws -> Int32 {
        let descriptor = anyps5_retro_test_shm(bytes)
        guard descriptor >= 0 else { throw XCTSkip("shm_open failed (errno \(errno))") }
        return descriptor
    }

    func testASharedMemoryObjectOfTheRightSizePasses() throws {
        let descriptor = try sharedMemory(Header().bytes)
        defer { close(descriptor) }
        XCTAssertNoThrow(try RetroFrameRing.checkMemory(descriptor: descriptor, bytes: Header().bytes, pageSize: Int(getpagesize())))
    }

    func testAnObjectSmallerOrAPageLargerFails() throws {
        let page = Int(getpagesize())
        let small = try sharedMemory(Header().bytes - page)
        defer { close(small) }
        assertProtocolError(try RetroFrameRing.checkMemory(descriptor: small, bytes: Header().bytes, pageSize: page))
        let large = try sharedMemory(Header().bytes + 2 * page)
        defer { close(large) }
        assertProtocolError(try RetroFrameRing.checkMemory(descriptor: large, bytes: Header().bytes, pageSize: page))
    }

    func testAWritableFileFailsBecauseItTakesAnFtruncate() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("retro-ring-\(UUID().uuidString)").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer {
            close(descriptor)
            unlink(path)
        }
        XCTAssertEqual(ftruncate(descriptor, off_t(Header().bytes)), 0)
        assertProtocolError(try RetroFrameRing.checkMemory(descriptor: descriptor, bytes: Header().bytes, pageSize: Int(getpagesize())))
    }

    func testAReadOnlyDescriptorFails() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("retro-ring-\(UUID().uuidString)").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data(count: Header().bytes)))
        defer { unlink(path) }
        let descriptor = open(path, O_RDONLY)
        defer { close(descriptor) }
        assertProtocolError(try RetroFrameRing.checkMemory(descriptor: descriptor, bytes: Header().bytes, pageSize: Int(getpagesize())))
    }

    func testARingMapsFromSharedMemoryAndPins() throws {
        var header = Header()
        header.latest = 1
        header.slots[1] = (320, 240, 1, 3)
        let descriptor = try sharedMemory(header.bytes)
        defer { close(descriptor) }
        let address = try XCTUnwrap(mmap(nil, header.bytes, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0))
        defer { munmap(address, header.bytes) }
        header.write(to: address)
        let made = try RetroFrameRing.map(descriptor: descriptor, bytes: header.bytes, pixelFormat: .rgba8, current: nil)
        XCTAssertEqual(made.slotBytes, 307_200)
        XCTAssertEqual(try made.pin()?.epoch, 3)
        made.unmap()
        assertProtocolError(try RetroFrameRing.map(descriptor: descriptor, bytes: header.bytes, pixelFormat: .bgra8, current: nil))
        assertProtocolError(try RetroFrameRing.map(descriptor: descriptor, bytes: header.bytes, pixelFormat: .rgba8, current: made))
        assertProtocolError(try RetroFrameRing.map(descriptor: descriptor, bytes: 4107, pixelFormat: .rgba8, current: nil))
    }
}
