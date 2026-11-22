import XCTest
@testable import AnyPS5Core

/// The Auto Optimizer's PS1 resolution, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_auto_resolution_test.dart), fed statuses the real host sent with
/// `gamePerformance`: Spyro the Dragon at full speed (Fixtures/retro-host-performance-status.json)
/// and Jak and Daxter at 8x, which did not keep up (Fixtures/retro-host-ps2-performance-status.json),
/// both copied from anyps5-retro-host fixtures/v1/messages. Each reading's speed and work is the
/// recording's, or one measured in the host's real-game runs (Jak at 4x read 0.956 to 0.990).
final class RetroAutoResolutionTests: XCTestCase {
    static func recorded(_ name: String) throws -> [String: RetroJSON] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/\(name)").standardized
        let file = try RetroJSON.parse(Array(try Data(contentsOf: url)))
        return try XCTUnwrap(file.objectValue?["status"]?.objectValue)
    }

    static func performance(_ speed: Double, _ work: Double?) -> RetroJSON {
        .object(["speed": .number(speed), "work": work.map(RetroJSON.number) ?? .null, "seconds": .int(5)])
    }

    private func spyro() throws -> [String: RetroJSON] { try Self.recorded("retro-host-performance-status.json") }

    private func status(speed: Double? = nil, work: Double? = 0.08, fields: [String: RetroJSON] = [:]) throws -> RetroStatus {
        var map = try spyro()
        map["performance"] = speed.map { Self.performance($0, work) } ?? .null
        for (key, value) in fields { map[key] = value }
        return try RetroStatus.parse(.object(map), performance: true)
    }

    private func s(_ seconds: Int) -> Duration { .seconds(seconds) }

    private func memory(scale: Int? = nil, slow: Set<Int> = []) -> RetroAutoMemory {
        RetroAutoMemory(gpu: "", host: "1.2.0", config: "", scale: scale, slow: slow)
    }

    private func optimizer(scale: Int = 4, need: Int = 8, remembered: RetroAutoMemory? = nil) -> RetroAutoResolution {
        RetroAutoResolution(scales: [1, 2, 3, 4, 6, 8], need: need, memory: remembered ?? memory(), scale: scale)
    }

    /// Feeds one reading every 5 seconds from `from`, returning the first change asked and when.
    private func feed(_ auto: RetroAutoResolution, _ readings: [RetroStatus], from: Duration) -> (scale: Int, at: Duration)? {
        for (index, reading) in readings.enumerated() {
            let at = from + RetroAutoRules.window * index
            if let change = auto.observe(at: at, reading) { return (change, at) }
        }
        return nil
    }

    func testTheHostsStatusesReadPerformanceAndGpuWithGamePerformanceIgnoredWithout() throws {
        let spyro = try spyro()
        let ps1 = try RetroStatus.parse(.object(spyro), performance: true)
        XCTAssertEqual(ps1.performance, RetroPerformance(speed: 0.9997, work: 0.0808, seconds: 5))
        XCTAssertEqual(ps1.gpu, RetroGpu(renderer: "NVIDIA GeForce RTX 4080 SUPER/PCIe/SSE2", vendor: "NVIDIA Corporation", maxTexture: 32768))
        let ps2 = try RetroStatus.parse(.object(try Self.recorded("retro-host-ps2-performance-status.json")), ps2: true, performance: true)
        XCTAssertEqual(ps2.performance?.speed, 0.6273)
        XCTAssertEqual(ps2.performance?.work, 1.5752)
        let older = try RetroStatus.parse(.object(spyro))
        XCTAssertNil(older.performance)
        XCTAssertNil(older.gpu)
        var none = spyro
        none["performance"] = .null
        none["gpu"] = .null
        XCTAssertNil(try RetroStatus.parse(.object(none), performance: true).performance)
        var unended = spyro
        unended["performance"] = Self.performance(1, nil)
        XCTAssertNil(try RetroStatus.parse(.object(unended), performance: true).performance?.work, "no frame ended in the window")
        XCTAssertNotNil(try RetroStatus.parse(.object(unended), performance: true).performance)
        let bad: [[String: RetroJSON]] = [
            ["performance": Self.performance(-1, 0.1)],
            ["performance": .object(["speed": .int(1), "seconds": .int(5)])],
            ["performance": .object(["speed": .int(1), "work": .number(0.1), "seconds": .int(0)])],
            ["gpu": .object(["renderer": .string("x"), "vendor": .string("y"), "maxTexture": .int(-1)])],
            ["gpu": .string("x")],
        ]
        for fields in bad {
            var map = spyro
            for (key, value) in fields { map[key] = value }
            XCTAssertThrowsError(try RetroStatus.parse(.object(map), performance: true), "\(fields)") { error in
                XCTAssertTrue(error is RetroProtocolError)
            }
        }
        var missing = spyro
        missing["performance"] = nil
        XCTAssertThrowsError(try RetroStatus.parse(.object(missing), performance: true))
        XCTAssertNil(try RetroStatus.parse(.object(missing)).performance, "a host without the capability")
    }

    func testAStatusThatDiffersOnlyInItsPerformanceSaysNothingNew() throws {
        let one = try status(speed: 1)
        XCTAssertTrue(one.sameAs(try status(speed: 0.5)), "measured every call; the launcher does not redraw")
        XCTAssertFalse(one.sameAs(try status(speed: 1, fields: ["graphicsPending": .bool(true)])))
        XCTAssertEqual(one.json.objectValue?["performance"], Self.performance(1, 0.08))
        XCTAssertEqual(one.json.objectValue?["gpu"]?.objectValue?["maxTexture"], .int(32768))
    }

    func testTheScaleAGameStartsAtRememberedElse2xNeverPastTheDisplayOrASlowOne() {
        let scales = [1, 2, 3, 4, 6, 8]
        XCTAssertEqual(RetroAutoResolution.startScale(scales, need: 5), 2)
        XCTAssertEqual(RetroAutoResolution.startScale(scales, need: 1), 1, "a 240-line display")
        XCTAssertEqual(RetroAutoResolution.startScale(scales, need: 5, memory: memory(scale: 4)), 4)
        XCTAssertEqual(RetroAutoResolution.startScale(scales, need: 3, memory: memory(scale: 6)), 3)
        XCTAssertEqual(RetroAutoResolution.startScale(scales, need: 8, memory: memory(scale: 6, slow: [6])), 4,
                       "a scale that ran slow is never chosen")
        XCTAssertEqual(RetroAutoResolution.startScale([1, 2], need: 8, memory: memory(scale: 4)), 2, "listed only")
        XCTAssertEqual(RetroAutoResolution.startScale([3, 4], need: 2), 3, "the smallest the host lists")
        XCTAssertEqual(retroAutoDisplayNeed(1080), 5)
        XCTAssertEqual(retroAutoDisplayNeed(1440), 6)
        XCTAssertEqual(retroAutoDisplayNeed(2160), 9)
        XCTAssertEqual(retroAutoDisplayNeed(0), 1)
    }

    func testTwoSlowReadingsInARowStepDownOneScaleAndMarkItSlowAfterTheSettleTime() throws {
        let auto = optimizer()
        let slow = try status(speed: 0.6273, work: 1.5752)
        XCTAssertNil(auto.observe(at: s(0), slow))
        XCTAssertNil(auto.observe(at: s(10), slow))
        XCTAssertNil(auto.observe(at: s(15), slow), "loading and shader compiles: not judged")
        XCTAssertNil(auto.observe(at: s(20), slow), "one slow reading is not enough")
        XCTAssertNil(auto.observe(at: s(22), slow), "the next reading is about 5 seconds on, not overlapping")
        XCTAssertEqual(auto.observe(at: s(25), slow), 3)
        XCTAssertEqual(auto.memory.slow, [4])
        auto.changed(at: s(25), to: 3)
        XCTAssertEqual(auto.scale, 3)
        XCTAssertEqual(auto.memory.scale, 3)
        XCTAssertNil(auto.observe(at: s(30), slow), "settling at the new scale")
        let next = feed(auto, [slow, slow], from: s(45))
        XCTAssertEqual(next?.scale, 2)
        XCTAssertEqual(next?.at, s(50))
    }

    func testASlowHalfMinuteStepsDownTheJakAt4xReadingsNeverOneWindow() throws {
        let readings = try [0.990, 0.983, 0.975, 0.956, 0.989, 0.988].map { try status(speed: $0) }
        let auto = optimizer()
        XCTAssertNil(feed(auto, Array(readings.prefix(5)), from: s(20)))
        XCTAssertEqual(auto.observe(at: s(45), readings[5]), 3, "six readings in a row, each under 0.995")
        let steady = optimizer()
        XCTAssertNil(feed(steady, try [0.9964, 1.0031, 0.9970, 1.0012, 0.9997, 0.9980, 1.0004].map { try status(speed: $0) }, from: s(20)),
                     "Spyro's full-speed readings, a frame either way")
    }

    func testASlowMomentIsNotASlowScaleTheLiveSpyroReadingsAndSlowFramesThatTookLittleTime() throws {
        let dip = try [
            (1.0031, 0.1595), (0.9997, 0.1673), (0.9997, 0.2128), (0.9997, 0.216),
            (0.983, 0.2555), (0.8359, 0.7844), (0.9997, 0.17), (0.9997, 0.17),
        ].map { try status(speed: $0.0, work: $0.1) }
        XCTAssertNil(feed(optimizer(scale: 2), dip, from: s(55)),
                     "Spyro at 2x on an RTX 4080 SUPER dipped once for a scene: the scale was not the cause")
        let stalled = [try status(speed: 0.6, work: 0.3), try status(speed: 0.6, work: 0.3)]
        XCTAssertNil(feed(optimizer(), stalled, from: s(20)), "frames that took little time: not the scale")
    }

    func testATimersReadingsAFewMillisecondsEarlyStillCount() throws {
        let auto = optimizer()
        let slow = try status(speed: 0.6, work: 1.5)
        XCTAssertNil(auto.observe(at: .milliseconds(20001), slow))
        XCTAssertEqual(auto.observe(at: .milliseconds(24998), slow), 3, "a 5-second timer firing 3 ms early")
        let fast = optimizer()
        XCTAssertNil(fast.observe(at: s(20), slow))
        XCTAssertNil(fast.observe(at: s(24), slow), "a second early: it would overlap the last reading")
    }

    func testAnythingButPlayBreaksTheRunOfReadings() throws {
        let slow = try status(speed: 0.6, work: 1.5)
        for gap in [
            try status(),
            try status(speed: 0.6, work: 1.5, fields: ["graphicsPending": .bool(true)]),
            try status(speed: 0.6, work: 1.5, fields: ["progressLabel": .string("Changing disc")]),
        ] {
            let auto = optimizer()
            XCTAssertNil(auto.observe(at: s(20), slow))
            XCTAssertNil(auto.observe(at: s(25), gap))
            XCTAssertNil(auto.observe(at: s(30), slow), "the slow reading before \(gap) no longer counts")
            XCTAssertEqual(auto.observe(at: s(35), slow), 3)
        }
    }

    func testAMinuteOfHeadroomStepsUpOneScaleNeverPastTheDisplayOrASlowScale() throws {
        let fast = try status(speed: 0.9997, work: 0.0808)
        let auto = optimizer(scale: 2, need: 5)
        XCTAssertNil(feed(auto, Array(repeating: fast, count: 11), from: s(20)))
        XCTAssertEqual(auto.observe(at: s(75), fast), 3)
        auto.changed(at: s(75), to: 3)
        let next = feed(auto, Array(repeating: fast, count: 12), from: s(95))
        XCTAssertEqual(next?.scale, 4)
        XCTAssertEqual(next?.at, s(150))
        auto.changed(at: s(150), to: 4)
        XCTAssertNil(feed(auto, Array(repeating: fast, count: 30), from: s(170)), "6x is past a 1080p display")

        let marked = optimizer(scale: 4, remembered: memory(slow: [6]))
        XCTAssertNil(feed(marked, Array(repeating: fast, count: 30), from: s(20)), "6x ran slow: it caps the climb")
        let busy = optimizer(scale: 2)
        XCTAssertNil(feed(busy, Array(repeating: try status(speed: 1, work: 0.7), count: 30), from: s(20)),
                     "full speed with a frame taking most of its time is no headroom")
        let unknown = optimizer(scale: 2)
        XCTAssertNil(feed(unknown, Array(repeating: try status(speed: 1, work: nil), count: 30), from: s(20)))
    }

    func testAPauseBetweenReadingsBreaksTheirRun() throws {
        let auto = optimizer()
        let slow = try status(speed: 0.6, work: 1.5)
        XCTAssertNil(auto.observe(at: s(20), slow))
        auto.interrupted()
        XCTAssertNil(auto.observe(at: s(300), slow), "one slow reading before the pause, one after")
        XCTAssertEqual(auto.observe(at: s(305), slow), 3)
    }

    func testSlowAtTheSmallestScaleTheFloorWhereTheOptimizerStops() throws {
        let auto = optimizer(scale: 1)
        let slow = try status(speed: 0.5, work: 1.5)
        XCTAssertNil(feed(auto, Array(repeating: slow, count: 10), from: s(20)))
        XCTAssertTrue(auto.atFloor)
        XCTAssertTrue(auto.memory.slow.isEmpty, "Native stays the scale to fall back to")
    }

    func testTheMemoryKeptAsJSONAndMeasuredWithOneGpuHostAndConfiguration() throws {
        let kept = RetroAutoMemory(gpu: "RTX", host: "1.2.0", config: "a=1", scale: 4, slow: [8, 6])
        let data = try JSONEncoder().encode(kept)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? NSDictionary,
                       ["gpu": "RTX", "host": "1.2.0", "config": "a=1", "scale": 4, "slow": [6, 8]] as NSDictionary)
        XCTAssertEqual(try JSONDecoder().decode(RetroAutoMemory.self, from: data), kept)
        let fresh = try JSONEncoder().encode(RetroAutoMemory(gpu: "", host: "", config: ""))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: fresh) as? NSDictionary, ["gpu": "", "host": "", "config": ""] as NSDictionary,
                       "no scale and no slow scales are left out, as on Windows and Linux")
        XCTAssertThrowsError(try JSONDecoder().decode(RetroAutoMemory.self, from: Data(#"{"gpu":"RTX"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RetroAutoMemory.self, from: Data(#"{"gpu":"","host":"","config":"","slow":["8"]}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(RetroAutoMemory.self, from: Data(#"{"gpu":"","host":"","config":"","scale":4.5}"#.utf8)))

        let games = try JSONDecoder().decode(RetroAutoMemories.self, from: Data(
            #"{"SLUS00001":{"gpu":"RTX","host":"1.2.0","config":"","scale":3},"SLUS00002":{"gpu":"RTX"},"SLUS00003":7}"#.utf8))
        XCTAssertEqual(games.games, ["SLUS00001": RetroAutoMemory(gpu: "RTX", host: "1.2.0", config: "", scale: 3)],
                       "an entry that is not a memory is left out, the rest kept")
        struct Kept: Decodable { let auto: RetroAutoMemories }
        XCTAssertEqual(try JSONDecoder().decode(Kept.self, from: Data(#"{"auto":"x"}"#.utf8)).auto, RetroAutoMemories(),
                       "not an object of memories: nothing learned, and the rest of the file still reads")
        XCTAssertEqual(try JSONDecoder().decode(RetroAutoMemories.self, from: try JSONEncoder().encode(games)), games)

        XCTAssertTrue(kept.measuredWith(gpu: "RTX", host: "1.2.0", config: "a=1"))
        XCTAssertTrue(kept.measuredWith(gpu: "", host: "1.2.0", config: ""), "not known yet")
        XCTAssertFalse(kept.measuredWith(gpu: "Radeon", host: "1.2.0", config: "a=1"))
        XCTAssertFalse(kept.measuredWith(gpu: "RTX", host: "1.3.0", config: "a=1"))
        XCTAssertFalse(kept.measuredWith(gpu: "RTX", host: "1.2.0", config: "a=2"))
        XCTAssertEqual(retroAutoConfig(try status(speed: 1), ["swanstation_GPU_TextureFilter", "swanstation_GPU_ResolutionScale"]),
                       "swanstation_GPU_ResolutionScale=1", "the options the status lists, in key order")
    }
}
