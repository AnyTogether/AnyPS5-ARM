import XCTest
@testable import AnyPS5Core

final class PowerProfilesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func state(battery: Bool = false, thermal: ThermalLevel = .nominal, lowPower: Bool = false, percent: Int? = 80) -> PowerReading {
        PowerReading(hasBattery: true, onBattery: battery, batteryPercent: percent, minutesToEmpty: nil, thermal: thermal, lowPowerMode: lowPower)
    }

    // MARK: The policy

    func testPluggedInChangesNothing() {
        var policy = PowerPolicy()
        XCTAssertEqual(policy.update(state(), at: at(0)), .none)
        XCTAssertEqual(policy.mode, .pluggedIn)
        XCTAssertEqual(policy.update(state(thermal: .fair), at: at(5)), .none, "fair is a normal working Mac")
    }

    func testOnBatteryAtStartTheBatteryProfileHoldsAtOnce() {
        var policy = PowerPolicy()
        let adjustment = policy.update(state(battery: true), at: at(0))
        XCTAssertEqual(policy.mode, .battery)
        XCTAssertEqual(adjustment.frameCap, 40)
        XCTAssertTrue(adjustment.pauseFrameGeneration)
        XCTAssertTrue(adjustment.dimEffects)
        XCTAssertFalse(adjustment.lowerResolution)
    }

    func testUnpluggingSettlesBeforeTheProfileChanges() {
        var policy = PowerPolicy()
        _ = policy.update(state(), at: at(0))
        XCTAssertEqual(policy.update(state(battery: true), at: at(1)), .none, "a cable that slips for a moment changes nothing")
        XCTAssertEqual(policy.update(state(battery: true), at: at(1 + PowerPolicy.sourceSettle - 1)), .none)
        XCTAssertEqual(policy.update(state(battery: true), at: at(1 + PowerPolicy.sourceSettle)).frameCap, 40)
        XCTAssertEqual(policy.mode, .battery)
    }

    func testASlippingCableDoesNotFlap() {
        var policy = PowerPolicy()
        _ = policy.update(state(), at: at(0))
        for second in stride(from: 1.0, to: 60, by: 2) {
            _ = policy.update(state(battery: true), at: at(second))
            XCTAssertEqual(policy.update(state(battery: false), at: at(second + 1)), .none)
        }
        XCTAssertEqual(policy.mode, .pluggedIn)
    }

    func testPluggingBackInRestoresAfterSettling() {
        var policy = PowerPolicy()
        _ = policy.update(state(battery: true), at: at(0))
        XCTAssertEqual(policy.update(state(), at: at(1)).frameCap, 40)
        XCTAssertEqual(policy.update(state(), at: at(1 + PowerPolicy.sourceSettle)), .none)
        XCTAssertEqual(policy.mode, .pluggedIn)
    }

    func testLowPowerModeCountsAsSavingPower() {
        var policy = PowerPolicy()
        XCTAssertEqual(policy.update(state(lowPower: true), at: at(0)).frameCap, 40)
        XCTAssertEqual(policy.mode, .battery)
    }

    func testHotTakesHoldAtOnce() {
        var policy = PowerPolicy()
        _ = policy.update(state(), at: at(0))
        let adjustment = policy.update(state(thermal: .serious), at: at(1))
        XCTAssertEqual(policy.mode, .hot)
        XCTAssertEqual(adjustment.frameCap, 40)
        XCTAssertTrue(adjustment.pauseFrameGeneration)
        XCTAssertTrue(policy.update(state(thermal: .critical), at: at(2)).pauseFrameGeneration)
    }

    func testCoolingDownWaitsSoTheCapDoesNotFlap() {
        var policy = PowerPolicy()
        _ = policy.update(state(thermal: .serious), at: at(0))
        // The Mac goes fair and serious again: the cap holds the whole time.
        for second in stride(from: 1.0, to: 300, by: 20) {
            XCTAssertEqual(policy.update(state(thermal: .fair), at: at(second)).frameCap, 40)
            XCTAssertEqual(policy.update(state(thermal: .serious), at: at(second + 10)).frameCap, 40)
        }
        XCTAssertEqual(policy.mode, .hot)
        // Cool for the whole cool-down: back to normal.
        _ = policy.update(state(thermal: .fair), at: at(400))
        XCTAssertEqual(policy.update(state(thermal: .fair), at: at(400 + PowerPolicy.coolDown - 1)).frameCap, 40)
        XCTAssertEqual(policy.update(state(thermal: .nominal), at: at(400 + PowerPolicy.coolDown)), .none)
        XCTAssertEqual(policy.mode, .pluggedIn)
    }

    func testHotOnBatteryTakesTheStricterOfBoth() {
        var profiles = PowerProfiles()
        profiles.battery = PowerProfile(on: true, frameCap: 45, lowerResolution: false, pauseFrameGeneration: false, dimEffects: true)
        profiles.hot = PowerProfile(on: true, frameCap: 30, lowerResolution: true, pauseFrameGeneration: true, dimEffects: false)
        var policy = PowerPolicy(profiles: profiles)
        let adjustment = policy.update(state(battery: true, thermal: .serious), at: at(0))
        XCTAssertEqual(policy.mode, .hot)
        XCTAssertEqual(adjustment, PowerAdjustment(frameCap: 30, lowerResolution: true, pauseFrameGeneration: true, dimEffects: true))
    }

    func testAnUncappedProfileLeavesTheOtherCap() {
        var profiles = PowerProfiles()
        profiles.battery.frameCap = 0
        profiles.hot.frameCap = 45
        var policy = PowerPolicy(profiles: profiles)
        XCTAssertEqual(policy.update(state(battery: true, thermal: .critical), at: at(0)).frameCap, 45)
    }

    func testAProfileTurnedOffChangesNothing() {
        var profiles = PowerProfiles()
        profiles.battery.on = false
        var policy = PowerPolicy(profiles: profiles)
        XCTAssertEqual(policy.update(state(battery: true), at: at(0)), .none)
        XCTAssertEqual(policy.mode, .battery, "the Mac is still on battery, the profile does nothing")
    }

    func testChangingTheProfilesAppliesAtOnce() {
        var policy = PowerPolicy()
        _ = policy.update(state(battery: true), at: at(0))
        policy.profiles.battery.frameCap = 30
        XCTAssertEqual(policy.adjustment.frameCap, 30)
    }

    // MARK: Undo

    func testUndoLiftsTheHeatAdjustmentForThisEpisode() {
        var policy = PowerPolicy()
        _ = policy.update(state(thermal: .serious), at: at(0))
        XCTAssertTrue(policy.canUndo)
        XCTAssertEqual(policy.undo(), .none)
        XCTAssertFalse(policy.canUndo)
        XCTAssertEqual(policy.update(state(thermal: .serious), at: at(30)), .none, "still hot, still undone")
        XCTAssertEqual(policy.update(state(thermal: .fair), at: at(40)), .none)
        XCTAssertEqual(policy.update(state(thermal: .serious), at: at(50)), .none, "the same episode: not before it cooled down")
    }

    func testUndoGivesWayWhenItGetsHotter() {
        var policy = PowerPolicy()
        _ = policy.update(state(thermal: .serious), at: at(0))
        _ = policy.undo()
        XCTAssertEqual(policy.update(state(thermal: .critical), at: at(10)).frameCap, 40, "critical is past what was undone")
    }

    func testANewEpisodeAfterCoolingAppliesAgain() {
        var policy = PowerPolicy()
        _ = policy.update(state(thermal: .serious), at: at(0))
        _ = policy.undo()
        _ = policy.update(state(thermal: .nominal), at: at(10))
        _ = policy.update(state(thermal: .nominal), at: at(10 + PowerPolicy.coolDown))
        XCTAssertEqual(policy.mode, .pluggedIn)
        XCTAssertEqual(policy.update(state(thermal: .serious), at: at(200)).frameCap, 40)
        XCTAssertTrue(policy.canUndo)
    }

    func testUndoWhileHotOnBatteryKeepsTheBatteryProfile() {
        var profiles = PowerProfiles()
        profiles.battery.frameCap = 45
        profiles.hot.frameCap = 30
        var policy = PowerPolicy(profiles: profiles)
        _ = policy.update(state(battery: true, thermal: .serious), at: at(0))
        XCTAssertEqual(policy.undo().frameCap, 45, "only the heat's part goes")
        XCTAssertEqual(policy.mode, .battery)
        XCTAssertTrue(policy.canUndo)
        XCTAssertEqual(policy.undo(), .none, "then the battery's")
    }

    func testBatteryUndoLastsUntilThePowerSourceChanges() {
        var policy = PowerPolicy()
        _ = policy.update(state(battery: true), at: at(0))
        _ = policy.undo()
        XCTAssertEqual(policy.update(state(battery: true), at: at(100)), .none)
        _ = policy.update(state(), at: at(101))
        _ = policy.update(state(), at: at(101 + PowerPolicy.sourceSettle))
        _ = policy.update(state(battery: true), at: at(200))
        XCTAssertEqual(policy.update(state(battery: true), at: at(200 + PowerPolicy.sourceSettle)).frameCap, 40)
    }

    func testNothingToUndoPluggedIn() {
        var policy = PowerPolicy()
        _ = policy.update(state(), at: at(0))
        XCTAssertFalse(policy.canUndo)
        XCTAssertEqual(policy.undo(), .none)
    }

    func testEnteringHeatIsReportedOnce() {
        var policy = PowerPolicy()
        _ = policy.update(state(), at: at(0))
        XCTAssertFalse(policy.becameHot)
        _ = policy.update(state(thermal: .serious), at: at(1))
        XCTAssertTrue(policy.becameHot)
        _ = policy.update(state(thermal: .critical), at: at(2))
        XCTAssertFalse(policy.becameHot)
    }

    // MARK: Profiles saved

    func testProfilesDecodeWithMissingFields() throws {
        let decoded = try JSONDecoder().decode(PowerProfiles.self, from: Data(#"{"battery":{"frameCap":30}}"#.utf8))
        XCTAssertEqual(decoded.battery.frameCap, 30)
        XCTAssertTrue(decoded.battery.on)
        XCTAssertTrue(decoded.battery.pauseFrameGeneration)
        XCTAssertEqual(decoded.hot, PowerProfile.hot)
    }

    func testFrameCapsOffered() {
        XCTAssertEqual(PowerProfile.frameCaps, [0, 30, 40, 45])
    }

    // MARK: Resolution

    func testLowerResolutionIsTheNextChoiceDown() {
        let choices = ["3840x2160", "2560x1440", "1920x1080", "1280x720"]
        XCTAssertEqual(PowerResolution.lower(than: "2560x1440", choices: choices), "1920x1080")
        XCTAssertEqual(PowerResolution.lower(than: "1280x720", choices: choices), nil, "already the lowest")
        XCTAssertEqual(PowerResolution.lower(than: "1920x1080", choices: ["1280x720", "3840x2160", "1600x900"]), "1600x900", "by pixels, in any order")
        XCTAssertNil(PowerResolution.lower(than: "nonsense", choices: choices))
    }

    // MARK: The engine's side

    func testControlFileText() {
        XCTAssertEqual(EngineControl.text(PowerAdjustment(frameCap: 40, lowerResolution: true, pauseFrameGeneration: true, dimEffects: true)), "fps_cap=40\nframe_gen=0\n")
        XCTAssertEqual(EngineControl.text(.none), "fps_cap=0\nframe_gen=1\n")
    }

    func testLaunchEnvironment() {
        let file = URL(fileURLWithPath: "/tmp/power.txt")
        let environment = EngineControl.environment(file: file, adjustment: PowerAdjustment(frameCap: 30, lowerResolution: false, pauseFrameGeneration: false, dimEffects: false))
        XCTAssertEqual(environment, ["ANYPS5_POWER_CONTROL": "/tmp/power.txt", "ANYPS5_FPS_CAP": "30"])
        XCTAssertEqual(EngineControl.environment(file: file, adjustment: .none)["ANYPS5_FPS_CAP"], "0")
    }

    func testControlFileIsWrittenWhole() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("power-\(UUID().uuidString)/control.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try EngineControl.write(PowerAdjustment(frameCap: 45, lowerResolution: false, pauseFrameGeneration: false, dimEffects: false), to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "fps_cap=45\nframe_gen=1\n")
    }

    // MARK: Battery time

    func testTheSystemsEstimateComesFirst() {
        var estimate = BatteryEstimate()
        estimate.add(percent: 80, onBattery: true, at: at(0))
        XCTAssertEqual(estimate.minutesLeft(system: 125), 125)
    }

    func testWithoutTheSystemsEstimateTheDrainIsMeasured() {
        var estimate = BatteryEstimate()
        estimate.add(percent: 80, onBattery: true, at: at(0))
        XCTAssertNil(estimate.minutesLeft(system: nil), "nothing measured yet")
        estimate.add(percent: 78, onBattery: true, at: at(60))
        XCTAssertNil(estimate.minutesLeft(system: nil), "too short to tell")
        estimate.add(percent: 76, onBattery: true, at: at(600))
        // 4 % in 10 minutes: 76 % lasts 190 minutes.
        XCTAssertEqual(estimate.minutesLeft(system: nil), 190)
    }

    func testChargingStartsTheMeasureAgain() {
        var estimate = BatteryEstimate()
        estimate.add(percent: 80, onBattery: true, at: at(0))
        estimate.add(percent: 70, onBattery: true, at: at(600))
        estimate.add(percent: 71, onBattery: false, at: at(700))
        XCTAssertNil(estimate.minutesLeft(system: nil))
        estimate.add(percent: 71, onBattery: true, at: at(800))
        XCTAssertNil(estimate.minutesLeft(system: nil))
    }

    func testThermalLevelsFromTheSystem() {
        XCTAssertEqual(ThermalLevel(.nominal), .nominal)
        XCTAssertEqual(ThermalLevel(.fair), .fair)
        XCTAssertEqual(ThermalLevel(.serious), .serious)
        XCTAssertEqual(ThermalLevel(.critical), .critical)
        XCTAssertTrue(ThermalLevel.serious > .fair)
    }
}
