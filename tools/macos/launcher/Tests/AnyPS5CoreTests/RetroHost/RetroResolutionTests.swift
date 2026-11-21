import XCTest
@testable import AnyPS5Core

/// The internal resolution in the PS menu, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_resolution_test.dart and the resolution cases of #176): the values
/// the launcher offers that the host lists, the line under the row, the PS2 resolution sent only
/// to a host that limits it, and LRPS2's VR never shown or sent. The PS2 status is the host's
/// call-status-ps2-resolution.json at 44060c0 (Fixtures/retro-host-ps2-resolution-status.json,
/// Desktop's file).
@MainActor
final class RetroResolutionTests: XCTestCase {
    private func recordedPs2Status() throws -> RetroStatus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Fixtures/retro-host-ps2-resolution-status.json").standardized
        let file = try RetroJSON.parse(Array(try Data(contentsOf: url)))
        let result = try XCTUnwrap(file.objectValue?["reply"]?.objectValue?["result"])
        return try RetroStatus.parse(result, ps2: true)
    }

    /// A PS1 status drawn with the GPU, its resolution 1 to 16, `chosen` selected and `active`
    /// in effect.
    private func ps1Status(chosen: String, active: String, hardware: Bool = true, pending: Bool = false, refusal: String = "") throws -> RetroStatus {
        let values = (1...16).map { "\"\($0)\"" }.joined(separator: ",")
        let labels = (1...16).map { "\"\($0)x\"" }.joined(separator: ",")
        let text = """
        {"ready":true,"ended":false,"error":"","errorCode":"","aspect":1.3333333333333333,"hardware":\(hardware),\
        "resolutionError":"\(refusal)","graphicsPending":\(pending),"progressLabel":null,"progressPercent":null,"options":{\
        "swanstation_GPU_ResolutionScale":{"title":"Internal Resolution Scale","values":[\(values)],"labels":[\(labels)],\
        "selected":\(Int(chosen)! - 1),"activeValue":"\(active)","restart":false}}}
        """
        return try RetroStatus.parse(try RetroJSON.parse(Array(text.utf8)))
    }

    func testAPs2GameOffersNativeTo8xOfWhatTheHostListsOnlyOnAHostThatLimitsItAndSaysTheRefusal() throws {
        XCTAssertEqual(RetroResolution.offered(ps2: true), ["1x (Native)": 1, "2x": 2, "4x": 4, "8x": 8], "LRPS2 lists no 3x or 6x")
        let status = try recordedPs2Status()
        XCTAssertNil(RetroResolutionChoice.of(status, limitsPs2: false), "an older host does not limit it: nothing offered")
        let choice = try XCTUnwrap(RetroResolutionChoice.of(status, limitsPs2: true))
        XCTAssertEqual(choice.key, "pcsx2_upscale_multiplier")
        XCTAssertEqual(choice.values.map(\.value), ["1x (Native)", "2x", "4x"])
        XCTAssertEqual(choice.values.map(\.scale), [1, 2, 4])
        XCTAssertEqual(choice.selected, 2)
        XCTAssertEqual(choice.active.value, "4x")
        XCTAssertEqual(choice.note, .refused, "the host could not use the 8x saved")
    }

    func testLrps2sVrIsNeitherShownNorSentAndThePs2MenuHasNoAdvancedRow() throws {
        XCTAssertNil(RetroOptionSection.of("pcsx2_vr_mode"))
        XCTAssertNil(RetroOptionSection.of("pcsx2_vr_depth"))
        XCTAssertFalse(RetroOptionSection.sent("pcsx2_vr_mode", ps2: true))
        XCTAssertTrue(RetroOptionSection.sent("pcsx2_upscale_multiplier", ps2: true), "the menu's first page offers it")
        XCTAssertTrue(RetroOptionSection.sent("swanstation_GPU_ResolutionScale"))
        XCTAssertFalse(RetroOptionSection.sent("swanstation_GPU_ResolutionScale", ps2: true))
        XCTAssertTrue(RetroOptionSection.sent("swanstation_GPU_TextureFilter"), "the Graphics page's smooth textures sets it")
        XCTAssertFalse(RetroOptionSection.sent("swanstation_GPU_ChromaSmoothing24Bit"), "a graphics option no row sets stays held back")
        let status = try recordedPs2Status()
        let shown = RetroGameMenu.rowsFor(status, volume: 1, muted: false).compactMap { row -> RetroOptionRow? in
            if case .option(let option) = row { return option }
            return nil
        }
        XCTAssertFalse(shown.contains { $0.section == .advanced }, "with the recorded LRPS2 status nothing is under Advanced")
    }

    func testAPs1GameOffersNativeTo4x6xAnd8xAndTheValueChosenEvenWhenNotOffered() throws {
        let offered = try XCTUnwrap(RetroResolutionChoice.of(try ps1Status(chosen: "1", active: "1"), limitsPs2: false))
        XCTAssertEqual(offered.values.map(\.value), ["1", "2", "3", "4", "6", "8"], "5x, 7x and 9x to 16x are not offered")
        XCTAssertEqual(offered.values.map(\.scale), [1, 2, 3, 4, 6, 8])
        let choice = try XCTUnwrap(RetroResolutionChoice.of(try ps1Status(chosen: "7", active: "7"), limitsPs2: false))
        XCTAssertEqual(choice.values.map(\.value), ["1", "2", "3", "4", "6", "7", "8"])
        XCTAssertEqual(choice.values.map(\.scale), [1, 2, 3, 4, 6, nil, 8])
        XCTAssertEqual(choice.values[5].label, "7x", "the host's own label for a value the launcher does not offer")
        XCTAssertEqual(choice.selected, 5)
        XCTAssertEqual(choice.note, RetroGraphicsNote.none)
        XCTAssertEqual(RetroResolutionChoice.of(try ps1Status(chosen: "2", active: "1"), limitsPs2: false)?.note, .applying)
        XCTAssertEqual(RetroResolutionChoice.of(try ps1Status(chosen: "2", active: "2", pending: true), limitsPs2: false)?.note, .applying)
        XCTAssertEqual(RetroResolutionChoice.of(try ps1Status(chosen: "4", active: "2", refusal: "too large"), limitsPs2: false)?.note, .refused)
        XCTAssertNil(RetroResolutionChoice.of(try ps1Status(chosen: "1", active: "1", hardware: false), limitsPs2: false),
                     "not while the host draws without the GPU")
        XCTAssertNil(RetroResolutionChoice.of(nil, limitsPs2: true))
    }

    func testAPs2ResolutionGoesOnlyToAHostThatLimitsIt() async throws {
        XCTAssertTrue(RetroHostClient.sendsPs2Resolution("start", .object(["options": .object(["pcsx2_upscale_multiplier": .string("2x")])])))
        XCTAssertTrue(RetroHostClient.sendsPs2Resolution("option", .object(["key": .string("pcsx2_upscale_multiplier"), "value": .string("2x")])))
        XCTAssertFalse(RetroHostClient.sendsPs2Resolution("option", .object(["key": .string("swanstation_GPU_ResolutionScale"), "value": .string("2")])))
        for limits in [false, true] {
            let session = FakeRetroHostSession()
            session.limitsPs2Resolution = limits
            let game = RetroHostGame(session: session, statusEvery: .seconds(3600))
            session.greet()
            session.nextStatus = fakeStatus(ready: false)
            await game.start(RetroHostStartRequest(core: "c", disc: "d.iso", system: "s", saves: "v",
                                                   options: ["pcsx2_upscale_multiplier": "2x", "pcsx2_fastboot": "enabled"], console: RetroConsole.ps2))
            let options = session.startArgs?.objectValue?["options"]?.objectValue
            XCTAssertEqual(options?["pcsx2_upscale_multiplier"], limits ? .string("2x") : nil, "limits: \(limits)")
            XCTAssertEqual(options?["pcsx2_fastboot"], .string("enabled"))
            await game.shutdown()
        }
    }
}
