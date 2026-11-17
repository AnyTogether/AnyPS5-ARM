import XCTest
@testable import AnyPS5Core

/// Where the emulator host repository's fixtures and fake host are: ANYPS5_RETRO_HOST_CHECKOUT names
/// a checkout of AnyTogether/anyps5-retro-host (CI fetches the commit .github/workflows/anytogether-ci.yml
/// pins). Without it the tests that need them are skipped.
enum RetroHostFixtures {
    static var checkout: URL? {
        guard let path = ProcessInfo.processInfo.environment["ANYPS5_RETRO_HOST_CHECKOUT"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("fixtures/v1/sessions").path) else { return nil }
        return url
    }

    static func read(_ url: URL) throws -> RetroJSON { try RetroJSON.parse(Data(contentsOf: url)) }
}

/// How a `status` is read (protocol.md "status"), as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_status_test.dart).
final class RetroStatusTests: XCTestCase {
    private func status(_ changes: [String: RetroJSON] = [:], without: [String] = []) -> RetroJSON {
        var map: [String: RetroJSON] = [
            "ready": .bool(true), "ended": .bool(false), "error": .string(""), "errorCode": .string(""),
            "aspect": .number(4.0 / 3.0), "hardware": .bool(true), "resolutionError": .string(""),
            "graphicsPending": .bool(false), "progressLabel": .null, "progressPercent": .null,
            "options": .object([
                "swanstation_GPU_ResolutionScale": .object([
                    "title": .string("Internal Resolution"), "values": .array([.string("1"), .string("2")]),
                    "labels": .array([.string("1x"), .string("2x")]), "selected": .int(1), "activeValue": .string("2"),
                    "restart": .bool(false),
                ]),
            ]),
        ]
        for (key, value) in changes { map[key] = value }
        for key in without { map[key] = nil }
        return .object(map)
    }

    private func discs(_ changes: [String: RetroJSON] = [:]) -> RetroJSON {
        var map: [String: RetroJSON] = [
            "labels": .array([.string("Disc 1"), .string("Disc 2")]), "inserted": .int(0),
            "insertedDiscPath": .string("/Games/a.cue"), "playedDiscPath": .string(""), "busy": .bool(false),
            "failed": .bool(false),
        ]
        for (key, value) in changes { map[key] = value }
        return .object(map)
    }

    func testAWholeStatusReadsAndWritesBack() throws {
        let value = status(["discs": discs(), "laterField": .int(3)])
        let read = try RetroStatus.parse(value)
        XCTAssertTrue(read.ready)
        XCTAssertEqual(read.options["swanstation_GPU_ResolutionScale"]?.selected, 1)
        XCTAssertEqual(read.discs?.inserted, 0)
        XCTAssertFalse(read.cardUnreadable)
        var expected = value.objectValue!
        expected["laterField"] = nil
        expected["cardUnreadable"] = .bool(false)
        XCTAssertEqual(read.json, .object(expected))
    }

    func testCardUnreadableIsReadAndFalseWithoutTheField() throws {
        XCTAssertTrue(try RetroStatus.parse(status(["cardUnreadable": .bool(true)])).cardUnreadable)
        XCTAssertFalse(try RetroStatus.parse(status()).cardUnreadable)
        XCTAssertThrowsError(try RetroStatus.parse(status(["cardUnreadable": .int(1)])))
    }

    func testTheClientsOwnCodesFromAHostReadAsOther() throws {
        XCTAssertEqual(try RetroStatus.parse(status(["errorCode": .string("hostExited")])).errorCode, "other")
        XCTAssertEqual(try RetroStatus.parse(status(["errorCode": .string("hostHung")])).errorCode, "other")
        XCTAssertEqual(try RetroStatus.parse(status(["errorCode": .string("laterCode")])).errorCode, "laterCode")
    }

    func testAFieldOutsideTheProtocolIsAProtocolError() {
        let bad: [RetroJSON] = [
            .array([]),
            status(without: ["progressPercent"]),
            status(without: ["progressLabel"]),
            status(without: ["options"]),
            status(["progressPercent": .int(101)]),
            status(["progressPercent": .number(2.5)]),
            status(["aspect": .int(0)]),
            status(["aspect": .number(10.5)]),
            status(["ready": .int(1)]),
            status(["discs": discs(["inserted": .int(2)])]),
            status(["discs": discs(["labels": .array(Array(repeating: .string("d"), count: 129))])]),
            status(["discs": .object(discs().objectValue!.filter { $0.key != "inserted" })]),
            status(["options": .object(["k": .object([
                "title": .string("t"), "values": .array([.string("1")]), "labels": .array([]), "selected": .int(0),
                "activeValue": .string("1"), "restart": .bool(false),
            ])])]),
            status(["options": .object(["k": .object([
                "title": .string("t"), "values": .array([.string("1")]), "labels": .array([.string("a")]),
                "selected": .int(1), "activeValue": .string("1"), "restart": .bool(false),
            ])])]),
        ]
        for value in bad {
            XCTAssertThrowsError(try RetroStatus.parse(value), "accepted \(value)") { error in
                XCTAssertTrue(error is RetroProtocolError, "\(error)")
            }
        }
    }

    func testAnInsertedDiscMayBeNullAndSoMayItsPath() throws {
        let read = try RetroStatus.parse(status(["discs": discs(["inserted": .null, "insertedDiscPath": .null])]))
        XCTAssertNil(read.discs?.inserted)
        XCTAssertNil(read.discs?.insertedDiscPath)
    }

    func testTheFailureReportIsTheFourFieldsOfHostFailure() {
        let failed = RetroStatus.failed(error: "The emulator closed unexpectedly.", errorCode: RetroErrorCode.hostExited)
        XCTAssertEqual(failed.failureJSON, .object([
            "ready": .bool(false), "ended": .bool(true), "error": .string("The emulator closed unexpectedly."),
            "errorCode": .string("hostExited"),
        ]))
        XCTAssertTrue(RetroStatus.isFailureReport(failed.failureJSON))
        XCTAssertFalse(RetroStatus.isFailureReport(status(["errorCode": .string("hostExited")])))
    }

    /// Every status the fixture messages and sessions send reads.
    func testEveryFixtureStatusReads() throws {
        guard let checkout = RetroHostFixtures.checkout else { throw XCTSkip("ANYPS5_RETRO_HOST_CHECKOUT is not set") }
        let root = checkout.appendingPathComponent("fixtures/v1")
        var read = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("messages").path)
        where name.hasPrefix("call-status") {
            let file = try RetroHostFixtures.read(root.appendingPathComponent("messages/\(name)"))
            let result = file.objectValue?["reply"]?.objectValue?["result"] ?? .null
            if !result.isNull {
                XCTAssertNoThrow(try RetroStatus.parse(result), name)
                read += 1
            }
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sessions").path) {
            let session = try RetroHostFixtures.read(root.appendingPathComponent("sessions/\(name)"))
            for step in session.objectValue?["steps"]?.arrayValue ?? [] {
                if let result = step.objectValue?["status"], !result.isNull {
                    XCTAssertNoThrow(try RetroStatus.parse(result), name)
                    read += 1
                }
            }
        }
        XCTAssertGreaterThan(read, 2)
    }

    /// A host that lists `ps2` names the console in every status, `ps1` or `ps2`; any other host's
    /// `console` is ignored, and so are `core` and `timing`, which this client does not read yet.
    func testTheConsoleIsReadOnlyFromAHostThatListsPs2() throws {
        XCTAssertEqual(try RetroStatus.parse(status(["console": .string("ps2")]), ps2: true).console, RetroConsole.ps2)
        XCTAssertEqual(try RetroStatus.parse(status(["console": .string("ps1")]), ps2: true).console, RetroConsole.ps1)
        XCTAssertThrowsError(try RetroStatus.parse(status(), ps2: true))
        XCTAssertThrowsError(try RetroStatus.parse(status(["console": .string("ps3")]), ps2: true))
        XCTAssertThrowsError(try RetroStatus.parse(status(["console": .int(2)]), ps2: true))
        XCTAssertNil(try RetroStatus.parse(status(["console": .string("ps3")])).console)
        let extra = status(["core": .object(["name": .string("SwanStation"), "version": .string("1")]),
                            "timing": .object(["fps": .number(59.8), "region": .string("ntsc")])])
        XCTAssertNoThrow(try RetroStatus.parse(extra, ps2: false))
    }

    func testTheConsoleIsWrittenBackWhenItWasRead() throws {
        let read = try RetroStatus.parse(status(["console": .string("ps2")]), ps2: true)
        XCTAssertEqual(read.json.objectValue?["console"], .string("ps2"))
        XCTAssertEqual(try RetroStatus.parse(read.json, ps2: true), read)
        XCTAssertNil(try RetroStatus.parse(status()).json.objectValue?["console"])
    }

    /// The host's PS2 status fixture, from LRPS2 without a BIOS, reads with the console it names, as on
    /// Windows and Linux.
    func testThePs2StatusFixtureReads() throws {
        guard let checkout = RetroHostFixtures.checkout else { throw XCTSkip("ANYPS5_RETRO_HOST_CHECKOUT is not set") }
        let file = try RetroHostFixtures.read(checkout.appendingPathComponent("fixtures/v1/messages/call-status-ps2-no-bios.json"))
        let result = file.objectValue?["reply"]?.objectValue?["result"] ?? .null
        let read = try RetroStatus.parse(result, ps2: true)
        XCTAssertEqual(read.ended, true)
        XCTAssertEqual(read.errorCode, RetroErrorCode.bios)
        XCTAssertEqual(read.console, RetroConsole.ps2)
        XCTAssertFalse(read.options.isEmpty)
        XCTAssertTrue(read.options.keys.allSatisfy { $0.hasPrefix("pcsx2_") }, "\(read.options.keys)")
        for name in ["call-status.json", "call-status-pal.json", "call-status-no-bios.json"] {
            let fixture = try RetroHostFixtures.read(checkout.appendingPathComponent("fixtures/v1/messages/\(name)"))
            let status = fixture.objectValue?["reply"]?.objectValue?["result"] ?? .null
            XCTAssertEqual(try RetroStatus.parse(status, ps2: true).console, RetroConsole.ps1, name)
        }
    }
}
