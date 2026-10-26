@testable import AnyPS5Core
import XCTest

/// A DualShock 3 as the handshake sees it: which feature reports it answers, and every call made.
private final class FakeTransport: DualShock3Transport {
    var answers: [UInt8: Int32] = [:]
    var setCode: Int32 = 0
    var calls: [String] = []
    var f2 = [UInt8](repeating: 0, count: 17)

    func getFeature(_ id: UInt8, length: Int) -> Result<[UInt8], DualShock3Failure> {
        calls.append(String(format: "get %02X/%d", id, length))
        let code = answers[id] ?? 0
        if code != 0 { return .failure(DualShock3Failure(code)) }
        return .success(id == 0xF2 ? f2 : [id] + [UInt8](repeating: 0, count: length - 1))
    }

    func setFeature(_ bytes: [UInt8]) -> Int32 {
        calls.append("set " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        return setCode
    }
}

final class DualShock3HandshakeTests: XCTestCase {
    let unsupported: Int32 = Int32(bitPattern: 0xE00002C7)

    func testReadsF2ThenF5AndNothingElse() {
        let fake = FakeTransport()
        let outcome = DualShock3Handshake.run(fake)
        XCTAssertEqual(fake.calls, ["get F2/17", "get F5/8"], "the PS3's order; no set report, no output report")
        XCTAssertTrue(outcome.reached)
        XCTAssertEqual(outcome.logText, "get feature 0xF2 (17 bytes) ok, get feature 0xF5 (8 bytes) ok")
    }

    func testF5RefusedIsStillReached() {
        let fake = FakeTransport()
        fake.answers[0xF5] = unsupported
        let outcome = DualShock3Handshake.run(fake)
        XCTAssertEqual(fake.calls, ["get F2/17", "get F5/8"], "a clone without 0xF5 still has 0xF2: no fallback")
        XCTAssertTrue(outcome.reached)
        XCTAssertTrue(outcome.logText.hasSuffix("0xE00002C7"))
    }

    func testBothReadsRefusedFallsBackToTheSetReport() {
        let fake = FakeTransport()
        fake.answers = [0xF2: unsupported, 0xF5: unsupported]
        let outcome = DualShock3Handshake.run(fake)
        XCTAssertEqual(fake.calls, ["get F2/17", "get F5/8", "set F4 42 0C 00 00"])
        XCTAssertTrue(outcome.reached)
        XCTAssertEqual(outcome.steps.last?.step, DualShock3Handshake.enableCommand)
    }

    func testNothingReachedIsSaid() {
        let fake = FakeTransport()
        fake.answers = [0xF2: unsupported, 0xF5: unsupported]
        fake.setCode = unsupported
        let outcome = DualShock3Handshake.run(fake)
        XCTAssertFalse(outcome.reached)
        XCTAssertEqual(outcome.steps.count, 3)
    }

    func testRetriedOnlyWhileNothingComes() {
        XCTAssertTrue(DualShock3Handshake.retries(after: 0, reports: 0))
        XCTAssertFalse(DualShock3Handshake.retries(after: 0, reports: 1), "reporting: done")
        XCTAssertFalse(DualShock3Handshake.retries(after: DualShock3Handshake.retries.count, reports: 0), "a few times, then left")
        XCTAssertEqual(DualShock3Handshake.retries, DualShock3Handshake.retries.sorted())
    }

    func testAddressFromF2() {
        var report = [UInt8](repeating: 0, count: 17)
        report[0] = 0xF2
        report.replaceSubrange(4..<10, with: [0x00, 0x1b, 0xfb, 0x63, 0x4a, 0x10])
        XCTAssertEqual(DualShock3Handshake.address(report), "00:1b:fb:63:4a:10")
        XCTAssertEqual(DualShock3Handshake.address(Array(report.dropFirst())), "00:1b:fb:63:4a:10", "without the id in front")
        XCTAssertNil(DualShock3Handshake.address([0xF2] + [UInt8](repeating: 0, count: 16)), "all zero")
        XCTAssertNil(DualShock3Handshake.address([0xF2, 0, 0]), "too short")
        let fake = FakeTransport()
        fake.f2 = report
        XCTAssertEqual(DualShock3Handshake.run(fake).address, "00:1b:fb:63:4a:10")
    }
}

final class DualShock3OutputGateTests: XCTestCase {
    func testNothingBeforeReportsAndSettling() {
        var gate = DualShock3OutputGate()
        XCTAssertFalse(gate.allows(player: 1, rumble: false), "a clone that has not stayed gets no output report")
        gate.reportArrived()
        XCTAssertFalse(gate.allows(player: 1, rumble: false))
        gate.settle()
        XCTAssertTrue(gate.allows(player: 1, rumble: false))
    }

    func testTheSameLightOnceAndRumbleAlways() {
        var gate = DualShock3OutputGate()
        gate.reportArrived()
        gate.settle()
        XCTAssertTrue(gate.allows(player: 1, rumble: false))
        XCTAssertFalse(gate.allows(player: 1, rumble: false), "the same light again")
        XCTAssertTrue(gate.allows(player: 2, rumble: false))
        XCTAssertTrue(gate.allows(player: 2, rumble: true))
        XCTAssertTrue(gate.allows(player: 2, rumble: false), "the motors off again after a pulse")
    }

    func testAFailedWriteStopsTheWrites() {
        var gate = DualShock3OutputGate()
        gate.reportArrived()
        gate.settle()
        XCTAssertTrue(gate.allows(player: 1, rumble: false))
        gate.wrote(Int32(bitPattern: 0xE00002ED))
        XCTAssertFalse(gate.allows(player: 2, rumble: false))
        XCTAssertFalse(gate.allows(player: 2, rumble: true))
    }
}

final class PadSettleTests: XCTestCase {
    let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testShownAfterTheDelay() {
        var settle = PadSettle()
        settle.came("ds3-100000", at: start)
        XCTAssertEqual(settle.due(at: start.addingTimeInterval(1.0)), [])
        XCTAssertEqual(settle.due(at: start.addingTimeInterval(PadSettle.delay)), ["ds3-100000"])
        XCTAssertTrue(settle.isShown("ds3-100000"))
        XCTAssertEqual(settle.due(at: start.addingTimeInterval(5)), [], "once")
        XCTAssertEqual(settle.left("ds3-100000", at: start.addingTimeInterval(9)), .shown)
    }

    func testACloneSwitchingModesIsNeverShown() {
        var settle = PadSettle()
        // As logged: 054c:0268 "PS3 Controller" for 1.07 s, then 045e:028e.
        settle.came("ds3-100000", at: start)
        guard case .unseen(let after) = settle.left("ds3-100000", at: start.addingTimeInterval(1.07)) else { return XCTFail("shown") }
        XCTAssertEqual(after, 1.07, accuracy: 1e-6)
        XCTAssertEqual(settle.due(at: start.addingTimeInterval(3)), [])
        XCTAssertEqual(settle.left("ds3-100000"), .unknown)
    }

    func testInTheOrderTheyCame() {
        var settle = PadSettle()
        settle.came("b", at: start)
        settle.came("a", at: start.addingTimeInterval(0.2))
        XCTAssertEqual(settle.due(at: start.addingTimeInterval(3)), ["b", "a"])
    }
}

final class PadMergeTests: XCTestCase {
    func entry(_ id: String, _ name: String, _ kind: PadKind = .dualShock3) -> PadMerge.Entry { .init(id: id, name: name, kind: kind) }

    func testTheFrameworkCopyOfADualShock3IsOnePad() {
        // As seen: GameController's 'HID'/'PLAYSTATION(R)3 Controller' and the reader's device.
        let merged = PadMerge.aliases(framework: [entry("gc-1", "PLAYSTATION(R)3 Controller")],
                                      reader: [entry("ds3-100000", "PLAYSTATION(R)3 Controller")])
        XCTAssertEqual(merged, ["gc-1": "ds3-100000"])
    }

    func testOneForOneByNameFirst() {
        let merged = PadMerge.aliases(framework: [entry("gc-1", "PS3 Controller"), entry("gc-2", "PLAYSTATION(R)3 Controller")],
                                      reader: [entry("ds3-100000", "PLAYSTATION(R)3 Controller"), entry("ds3-200000", "PS3 Controller")])
        XCTAssertEqual(merged, ["gc-2": "ds3-100000", "gc-1": "ds3-200000"])
    }

    func testANameThatDiffersStillPairsByKind() {
        let merged = PadMerge.aliases(framework: [entry("gc-1", "Sony PLAYSTATION(R)3 Controller")],
                                      reader: [entry("ds3-100000", "PLAYSTATION(R)3 Controller")])
        XCTAssertEqual(merged, ["gc-1": "ds3-100000"])
    }

    func testOtherPadsAndSpareCopiesStay() {
        let merged = PadMerge.aliases(framework: [entry("gc-x", "Xbox 360 Controller", .xbox), entry("gc-1", "PLAYSTATION(R)3 Controller"),
                                                  entry("gc-2", "PLAYSTATION(R)3 Controller")],
                                      reader: [entry("ds3-100000", "PLAYSTATION(R)3 Controller")])
        XCTAssertEqual(merged.count, 1, "two copies, one device: the other copy is its own pad")
        XCTAssertNil(merged["gc-x"])
        XCTAssertEqual(PadMerge.aliases(framework: [entry("gc-1", "PLAYSTATION(R)3 Controller")], reader: []), [:], "no reader device: the copy is the pad")
    }

    func testTheReaderIsPreferredWhileItDelivers() {
        XCTAssertFalse(PadMerge.preferFramework(readerReports: 120, frameworkChanges: 40))
        XCTAssertFalse(PadMerge.preferFramework(readerReports: 0, frameworkChanges: 0))
        XCTAssertTrue(PadMerge.preferFramework(readerReports: 0, frameworkChanges: 3), "the reader got nothing: the copy's input counts")
    }

    func testTheCloneNamesClassify() {
        XCTAssertEqual(PadKind.classify(vendor: nil, product: nil, name: "PS3 Controller HID"), .dualShock3)
        XCTAssertEqual(PadKind.classify(vendor: 0x045E, product: 0x028E, name: "Controller"), .xbox, "the clone in its Xbox mode")
    }
}
