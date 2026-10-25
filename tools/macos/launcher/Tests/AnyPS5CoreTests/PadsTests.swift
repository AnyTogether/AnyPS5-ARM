import XCTest
@testable import AnyPS5Core

final class PadKindTests: XCTestCase {
    func testUSBNumbersTellTheFamily() {
        XCTAssertEqual(PadKind.classify(vendor: 0x054C, product: 0x0CE6, name: ""), .dualSense)
        XCTAssertEqual(PadKind.classify(vendor: 0x054C, product: 0x0DF2, name: ""), .dualSense, "DualSense Edge")
        XCTAssertEqual(PadKind.classify(vendor: 0x054C, product: 0x05C4, name: ""), .dualShock4)
        XCTAssertEqual(PadKind.classify(vendor: 0x054C, product: 0x09CC, name: ""), .dualShock4)
        XCTAssertEqual(PadKind.classify(vendor: 0x054C, product: 0x0268, name: ""), .dualShock3)
        XCTAssertEqual(PadKind.classify(vendor: 0x045E, product: 0x0B13, name: ""), .xbox)
        XCTAssertEqual(PadKind.classify(vendor: 0x057E, product: 0x2009, name: ""), .switchPro)
        XCTAssertEqual(PadKind.classify(vendor: 0x28DE, product: 0x11FF, name: "Steam Virtual Gamepad"), .xbox)
        XCTAssertEqual(PadKind.classify(vendor: 0x2DC8, product: 0x6101, name: "8BitDo SN30 Pro"), .generic)
    }

    func testANameAloneStillTellsTheFamily() {
        XCTAssertEqual(PadKind.classify(vendor: nil, product: nil, name: "DualSense Wireless Controller"), .dualSense)
        XCTAssertEqual(PadKind.classify(vendor: 0x054C, product: nil, name: "Wireless Controller"), .dualShock4)
        XCTAssertEqual(PadKind.classify(vendor: nil, product: nil, name: "Sony PLAYSTATION(R)3 Controller"), .dualShock3)
        XCTAssertEqual(PadKind.classify(vendor: nil, product: nil, name: "Xbox Wireless Controller"), .xbox)
        XCTAssertEqual(PadKind.classify(vendor: nil, product: nil, name: "Pro Controller"), .switchPro)
        XCTAssertEqual(PadKind.classify(vendor: nil, product: nil, name: "Logitech Dual Action"), .generic)
    }

    func testOnlyTheNewerPlayStationPadsHaveALightBar() {
        XCTAssertTrue(PadKind.dualSense.hasLightBar)
        XCTAssertTrue(PadKind.dualShock4.hasLightBar)
        XCTAssertFalse(PadKind.dualShock3.hasLightBar)
        XCTAssertFalse(PadKind.xbox.hasLightBar)
        XCTAssertTrue(PadKind.dualShock3.isPlayStation)
    }

    func testTransportNamesBecomeConnections() {
        XCTAssertEqual(PadConnection.transport("USB"), .usb)
        XCTAssertEqual(PadConnection.transport("Bluetooth"), .bluetooth)
        XCTAssertEqual(PadConnection.transport("Bluetooth Low Energy"), .bluetooth)
        XCTAssertEqual(PadConnection.transport(nil), .unknown)
        XCTAssertEqual(PadConnection.transport("SPI"), .unknown)
    }
}

final class PadRosterTests: XCTestCase {
    let sense = PadInfo(id: "a", name: "DualSense Wireless Controller", kind: .dualSense, connection: .bluetooth,
                        battery: PadBattery(percent: 80), driver: "GameController", vendor: 0x054C, product: 0x0CE6, hasRumble: true, hasLight: true)
    let xbox = PadInfo(id: "b", name: "Xbox Wireless Controller", kind: .xbox, connection: .usb, driver: "GameController")

    func testConnectLogsOnceAndTheFirstIsPlayerOne() {
        var roster = PadRoster()
        XCTAssertEqual(roster.connect(sense), "controller connected: DualSense Wireless Controller (DualSense, Bluetooth, battery 80%, GameController, 054c:0ce6)")
        XCTAssertNil(roster.connect(sense), "seen again: no second line")
        XCTAssertEqual(roster.playerOne, "a")
        roster.connect(xbox)
        XCTAssertEqual(roster.playerOne, "a", "a second pad does not take Player 1 by coming")
        XCTAssertEqual(roster.pads.map(\.id), ["a", "b"])
    }

    func testTheLastUsedPadIsPlayerOne() {
        var roster = PadRoster()
        roster.connect(sense)
        roster.connect(xbox)
        XCTAssertTrue(roster.used("b"))
        XCTAssertEqual(roster.playerOne, "b")
        XCTAssertFalse(roster.used("b"))
        XCTAssertFalse(roster.used("nobody"))
    }

    func testDisconnectHandsPlayerOneOnAndSaysHowLong() {
        var roster = PadRoster()
        let start = Date(timeIntervalSince1970: 1000)
        roster.connect(sense, now: start)
        roster.connect(xbox, now: start)
        roster.used("b")
        XCTAssertEqual(roster.disconnect("b", now: start.addingTimeInterval(125)), "controller disconnected: Xbox Wireless Controller (Xbox, USB, GameController) after 2 min")
        XCTAssertEqual(roster.playerOne, "a")
        XCTAssertNil(roster.disconnect("b"), "gone already")
        roster.disconnect("a")
        XCTAssertNil(roster.playerOne)
        XCTAssertTrue(roster.pads.isEmpty)
    }

    func testSyncFindsWhatCameAndWent() {
        var roster = PadRoster()
        XCTAssertEqual(roster.sync([sense]).count, 1)
        let lines = roster.sync([xbox])
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("controller disconnected: DualSense"))
        XCTAssertTrue(lines[1].hasPrefix("controller connected: Xbox"))
        XCTAssertEqual(roster.playerOne, "b")
        var updated = xbox
        updated.battery = PadBattery(percent: 40)
        XCTAssertTrue(roster.sync([updated]).isEmpty, "a new battery reading is not a connect")
        XCTAssertEqual(roster.pad("b")?.battery?.percent, 40)
    }

    func testTheLogKeepsTheLastFortyLinesWithTimes() {
        var log = PadLog()
        for index in 0..<50 { log.add("line \(index)") }
        XCTAssertEqual(log.lines.count, PadLog.capacity)
        XCTAssertTrue(log.lines.first!.hasSuffix("line 10"))
        XCTAssertNotNil(log.lines.first!.range(of: #"^\d\d:\d\d:\d\d "#, options: .regularExpression))
    }

    func testTheReportPutsPlayerOneFirst() {
        var roster = PadRoster()
        roster.connect(sense)
        roster.connect(xbox)
        roster.used("b")
        var log = PadLog()
        log.add("controller connected: Xbox")
        let lines = PadLog.report(roster: roster, log: log)
        XCTAssertTrue(lines[0].hasPrefix("Player 1: Xbox Wireless Controller"))
        XCTAssertTrue(lines[1].hasPrefix("Also: DualSense"))
        XCTAssertEqual(lines[2], "Recent:")
        XCTAssertEqual(PadLog.report(roster: PadRoster(), log: PadLog()), ["none connected"])
    }

    func testBatteryText() {
        XCTAssertEqual(PadBattery(percent: 80).reportText, "80%")
        XCTAssertEqual(PadBattery(percent: 55, approximate: true, charging: true).reportText, "about 55% charging")
        XCTAssertTrue(PadBattery(percent: 10).low)
        XCTAssertFalse(PadBattery(percent: 10, charging: true).low)
        XCTAssertEqual(PadBattery(percent: 140).percent, 100)
    }
}

final class PadSettingsTests: XCTestCase {
    func testDeadzoneCentresDriftAndKeepsTheEdge() {
        let drift = StickDeadzone.apply(x: 0.08, y: -0.05, percent: 10)
        XCTAssertEqual(drift.x, 0)
        XCTAssertEqual(drift.y, 0)
        let edge = StickDeadzone.apply(x: 1, y: 0, percent: 10)
        XCTAssertEqual(edge.x, 1, accuracy: 1e-9)
        let middle = StickDeadzone.apply(x: 0.55, y: 0, percent: 10)
        XCTAssertEqual(middle.x, 0.5, accuracy: 1e-9)
        let off = StickDeadzone.apply(x: 0.03, y: 0.02, percent: 0)
        XCTAssertEqual(off.x, 0.03)
    }

    func testGamesKeepTheirOwnDeadzones() {
        var own = InputTuning()
        own.leftDeadzone = 20
        let tuning = StickDeadzone.tuning(own, percent: 8)
        XCTAssertEqual(tuning.leftDeadzone, 20)
        XCTAssertEqual(tuning.rightDeadzone, 8)
        XCTAssertEqual(StickDeadzone.tuning(nil, percent: 0), InputTuning())
        XCTAssertTrue(StickDeadzone.tuning(nil, percent: 6).lines.contains("LeftStickDeadzone = 6"))
    }

    func testCircleConfirmsSwapsSelectAndBackAndTheGlyphs() {
        XCTAssertEqual(ConfirmButton.command(.select, circleConfirms: true), .back)
        XCTAssertEqual(ConfirmButton.command(.back, circleConfirms: true), .select)
        XCTAssertEqual(ConfirmButton.command(.options, circleConfirms: true), .options)
        XCTAssertEqual(ConfirmButton.command(.select, circleConfirms: false), .select)
        XCTAssertEqual(ConfirmButton.glyphs("↩ / ✕", circleConfirms: true), "↩ / ○")
        XCTAssertEqual(ConfirmButton.glyphs("esc / ○", circleConfirms: true), "esc / ✕")
        XCTAssertEqual(ConfirmButton.glyphs("esc / ○", circleConfirms: false), "esc / ○")
    }

    func testLightColours() {
        XCTAssertNil(PadLight.theme.rgb)
        XCTAssertEqual(PadLight.off.rgb?.0, 0)
        XCTAssertEqual(PadLight(rawValue: "red"), .red)
    }
}

final class DualShock3ReportTests: XCTestCase {
    func report(first: UInt8 = 0, second: UInt8 = 0, ps: UInt8 = 0, sticks: [UInt8] = [128, 128, 128, 128], l2: UInt8 = 0, r2: UInt8 = 0, battery: UInt8 = 0x05) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 49)
        data[0] = 0x01
        data[2] = first
        data[3] = second
        data[4] = ps
        data.replaceSubrange(6..<10, with: sticks)
        data[18] = l2
        data[19] = r2
        data[30] = battery
        return data
    }

    func testButtonsByPlace() {
        XCTAssertEqual(DualShock3Report.parse(report(second: 0x40))?.pressed, [.south], "Cross")
        XCTAssertEqual(DualShock3Report.parse(report(second: 0x20))?.pressed, [.east], "Circle")
        XCTAssertEqual(DualShock3Report.parse(report(second: 0x80))?.pressed, [.west], "Square")
        XCTAssertEqual(DualShock3Report.parse(report(second: 0x10))?.pressed, [.north], "Triangle")
        XCTAssertEqual(DualShock3Report.parse(report(second: 0x0C))?.pressed, [.l1, .r1])
        XCTAssertEqual(DualShock3Report.parse(report(first: 0x09))?.pressed, [.select, .start])
        XCTAssertEqual(DualShock3Report.parse(report(first: 0xF0))?.pressed, [.dpadUp, .dpadRight, .dpadDown, .dpadLeft])
        XCTAssertEqual(DualShock3Report.parse(report(ps: 0x01))?.pressed, [.guide])
    }

    func testSticksAndTriggers() throws {
        let state = try XCTUnwrap(DualShock3Report.parse(report(sticks: [255, 0, 128, 128], l2: 255, r2: 0)))
        XCTAssertEqual(state.leftX, 1, accuracy: 1e-9)
        XCTAssertEqual(state.leftY, -1, accuracy: 0.01)
        XCTAssertEqual(state.rightX, 0, accuracy: 1e-9)
        XCTAssertEqual(state.l2, 1, accuracy: 1e-9)
        XCTAssertNil(DualShock3Report.parse([0x02] + [UInt8](repeating: 0, count: 48)), "another report")
        XCTAssertNil(DualShock3Report.parse([0x01, 0, 0]), "too short")
    }

    func testBattery() {
        XCTAssertEqual(DualShock3Report.battery(report(battery: 0xEE))?.charging, true)
        XCTAssertEqual(DualShock3Report.battery(report(battery: 0x05))?.percent, 100)
        XCTAssertEqual(DualShock3Report.battery(report(battery: 0x01))?.percent, 20)
        XCTAssertNil(DualShock3Report.battery(report(battery: 0x77)))
    }

    func testOutputReportCarriesMotorsAndPlayerLight() {
        let output = DualShock3Report.output(strong: 1, weak: 1, player: 1)
        XCTAssertEqual(output.count, 49)
        XCTAssertEqual(output[0], 0x01)
        XCTAssertEqual(output[3], 0x01)
        XCTAssertEqual(output[5], 0xFF)
        XCTAssertEqual(output[10], 0x02, "player 1's light")
        XCTAssertEqual(Array(output[11..<16]), [0xFF, 0x27, 0x10, 0x00, 0x32])
        let still = DualShock3Report.output(strong: 0, weak: 0, player: 0)
        XCTAssertEqual(still[3], 0)
        XCTAssertEqual(still[5], 0)
        XCTAssertEqual(still[10], 0)
    }
}

final class PadTroubleshooterTests: XCTestCase {
    func testNothingConnectedGivesTheTips() {
        let findings = PadTroubleshooter.diagnose(.init(pads: []))
        XCTAssertEqual(findings.map(\.id), ["noControllers", "usbCable", "bluetoothPairing", "dualShock3"])
        XCTAssertTrue(findings[0].isProblem)
    }

    func testAControllerMacOSCannotReadIsNamed() {
        let findings = PadTroubleshooter.diagnose(.init(pads: [], hidControllers: [(name: "Logitech Dual Action", vendor: 0x046D, product: 0xC216)]))
        XCTAssertEqual(findings.first, .unmapped("Logitech Dual Action"))
        XCTAssertFalse(findings.contains(.noControllers))
        // A DualSense in the HID list is one GameController reads.
        let sense = PadTroubleshooter.diagnose(.init(pads: [], hidControllers: [(name: "DualSense", vendor: 0x054C, product: 0x0CE6)]))
        XCTAssertEqual(sense.first, .noControllers)
    }

    func testLowBatteryAndSteam() {
        let pad = PadInfo(id: "a", name: "DualSense", kind: .dualSense, battery: PadBattery(percent: 8), driver: "GameController")
        let findings = PadTroubleshooter.diagnose(.init(pads: [pad], running: ["com.apple.finder", "com.valvesoftware.steam"]))
        XCTAssertEqual(findings, [.lowBattery("DualSense", 8), .steamRunning, .dualShock3])
        XCTAssertEqual(PadTroubleshooter.statusLine([pad]), "DualSense · 8%")
        XCTAssertNil(PadTroubleshooter.statusLine([]))
    }
}

final class ControllerReportTests: XCTestCase {
    func testTheCrashReportListsTheControllers() {
        var report = SessionReport(gameName: "Game", titleID: "PPSA00001", gameVersion: "01.000", settings: GameSettings(),
                                   system: SystemInfo(model: "Mac", chip: "M", memoryGB: 8, macOS: "15", displayHz: nil), launcherVersion: "1",
                                   session: "log", privacy: ReportPrivacy(home: "/Users/nobody"))
        XCTAssertFalse(report.text().contains("Controllers:"))
        report.controllers = ["Player 1: DualSense (DualSense, USB, GameController)"]
        XCTAssertTrue(report.text().contains("Controllers:\n  Player 1: DualSense (DualSense, USB, GameController)"))
        XCTAssertTrue(IssueDraft.crash(report).preview.contains("Controller: Player 1: DualSense"))
    }
}
