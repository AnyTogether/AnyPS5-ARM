import XCTest
@testable import AnyPS5Core

/// The Graphics rows besides the internal resolution, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_graphics_test.dart), read from statuses the real host sent: PS1 from
/// SwanStation drawing on the GPU (Fixtures/retro-host-swanstation-status.json), PS2 from the real
/// LRPS2's options (Fixtures/retro-host-lrps2-status.json, the last status of Desktop's
/// `lrps2-no-bios-folder` recording, which ended before it drew, so `hardware` is set for the
/// settings that need the GPU).
final class RetroGraphicsTests: XCTestCase {
    static func fixture(_ name: String, ps2: Bool = false) throws -> RetroStatus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Fixtures/\(name)").standardized
        let file = try RetroJSON.parse(Array(try Data(contentsOf: url)))
        return try RetroStatus.parse(try XCTUnwrap(file.objectValue?["status"]), ps2: ps2)
    }

    static func ps1(hardware: Bool? = nil) throws -> RetroStatus {
        var status = try fixture("retro-host-swanstation-status.json")
        if let hardware { status.hardware = hardware }
        return status
    }

    static func ps2() throws -> RetroStatus {
        var status = try fixture("retro-host-lrps2-status.json", ps2: true)
        status.hardware = true
        return status
    }

    /// `status` with the option at `key` changed.
    static func edited(_ status: RetroStatus, _ key: String, values: [String]? = nil, labels: [String]? = nil, selected: Int? = nil,
                       active: String? = nil) -> RetroStatus {
        var status = status
        let option = status.options[key]!
        status.options[key] = RetroOption(key: key, title: option.title, values: values ?? option.values, labels: labels ?? option.labels,
                                          selected: selected ?? option.selected, activeValue: active ?? option.activeValue, restart: option.restart)
        return status
    }

    private func levels(_ choice: RetroGraphicsChoice) -> [String] {
        choice.values.map { value in value.offer.map { "\($0.level)" } ?? value.label }
    }

    private let filter = "swanstation_GPU_TextureFilter"
    private let pgxp = "swanstation_GPU_PGXPEnable"
    private let hack = "swanstation_GPU_WidescreenHack"
    private let aspect = "swanstation_Display_AspectRatio"

    func testPs1SmoothTexturesFixWobbly3dAndWidescreenFromTheRealSwanStationNoneOfPs2() throws {
        let status = try Self.ps1()
        let smooth = try XCTUnwrap(RetroGraphicsChoice.of(status, .smoothTextures))
        XCTAssertEqual(levels(smooth), ["off", "smooth", "extraSmooth"])
        XCTAssertEqual(smooth.values.map(\.label), ["Nearest-Neighbor", "Bilinear", "xBR"])
        XCTAssertEqual(smooth.selected, 0)
        XCTAssertEqual(smooth.note, .none)
        let wobbly = try XCTUnwrap(RetroGraphicsChoice.of(status, .fixWobbly3d))
        XCTAssertEqual(levels(wobbly), ["off", "on"])
        XCTAssertEqual(wobbly.selected, 0)
        let widescreen = try XCTUnwrap(RetroGraphicsChoice.of(status, .widescreenPs1))
        XCTAssertEqual(levels(widescreen), ["off", "on"])
        XCTAssertEqual(widescreen.selected, 0)
        XCTAssertNil(RetroGraphicsChoice.of(status, .sharperTextures), "a PS2 setting, for a host with PS2 only")
        XCTAssertNil(RetroGraphicsChoice.of(status, .widescreenPs2))
        XCTAssertNil(RetroGraphicsChoice.of(nil, .smoothTextures))
    }

    func testWithoutTheGpuOnlyWidescreenIsOfferedAndAnOptionTheHostDoesNotListHasNoRow() throws {
        let software = try Self.ps1(hardware: false)
        XCTAssertNil(RetroGraphicsChoice.of(software, .smoothTextures))
        XCTAssertNil(RetroGraphicsChoice.of(software, .fixWobbly3d))
        XCTAssertNotNil(RetroGraphicsChoice.of(software, .widescreenPs1))
        var status = try Self.ps1()
        status.options[pgxp] = nil
        XCTAssertNil(RetroGraphicsChoice.of(status, .fixWobbly3d))
    }

    func testOnlyValuesTheHostListsAreOfferedAndAChosenValueNoOfferHasShowsWithTheHostsLabel() throws {
        let fewer = Self.edited(try Self.ps1(), filter, values: ["Nearest", "Bilinear"], labels: ["Nearest-Neighbor", "Bilinear"],
                                selected: 1, active: "Bilinear")
        let choice = try XCTUnwrap(RetroGraphicsChoice.of(fewer, .smoothTextures))
        XCTAssertEqual(levels(choice), ["off", "smooth"], "the host lists no xBR")
        XCTAssertEqual(choice.selected, 1)

        let jinc = Self.edited(try Self.ps1(), filter, selected: 3, active: "JINC2")
        let other = try XCTUnwrap(RetroGraphicsChoice.of(jinc, .smoothTextures))
        XCTAssertEqual(levels(other), ["off", "smooth", "extraSmooth", "JINC2"])
        XCTAssertEqual(other.selected, 3)
        XCTAssertEqual(other.changesFor(jinc, 1), [RetroOptionValue(filter, "Bilinear")])
        XCTAssertEqual(other.changesFor(jinc, 3), [], "already chosen")
    }

    func testWidescreenSetsTheHackAndThe16To9AspectRatioTogetherItsRowFollowsTheHack() throws {
        let status = try Self.ps1()
        let off = try XCTUnwrap(RetroGraphicsChoice.of(status, .widescreenPs1))
        XCTAssertEqual(off.changesFor(status, 1), [RetroOptionValue(hack, "true"), RetroOptionValue(aspect, "16:9")])
        XCTAssertEqual(off.changesFor(status, 0), [])
        let halfway = Self.edited(status, hack, selected: 0, active: "true")
        let half = try XCTUnwrap(RetroGraphicsChoice.of(halfway, .widescreenPs1))
        XCTAssertEqual(levels(half), ["off", "on", "Enabled"], "the hack is on at 4:3: neither Off nor On")
        XCTAssertEqual(half.selected, 2)
        XCTAssertEqual(half.changesFor(halfway, 0), [RetroOptionValue(hack, "false")], "4:3 already")
        XCTAssertEqual(half.changesFor(halfway, 1), [RetroOptionValue(aspect, "16:9")], "On, set whole")
    }

    func testTheNoteSaysInAMomentWhileAChosenValueIsNotInEffectOrTheHostIsStillApplyingAGraphicsChange() throws {
        let pending = Self.edited(try Self.ps1(), pgxp, selected: 0)
        let choice = try XCTUnwrap(RetroGraphicsChoice.of(pending, .fixWobbly3d))
        XCTAssertEqual(choice.selected, 1)
        XCTAssertEqual(choice.note, .applying)
        let ratio = Self.edited(Self.edited(try Self.ps1(), hack, selected: 0, active: "true"), aspect, selected: 1)
        XCTAssertEqual(RetroGraphicsChoice.of(ratio, .widescreenPs1)?.note, .applying, "the aspect ratio is not in effect yet")
        let settled = try Self.ps1()
        XCTAssertEqual(RetroGraphicsChoice.of(settled, .fixWobbly3d)?.note, RetroGraphicsNote.none)
        var redrawing = settled
        redrawing.graphicsPending = true
        XCTAssertEqual(RetroGraphicsChoice.of(redrawing, .fixWobbly3d)?.note, .applying,
                       "in effect, but the host is still applying a graphics change")
    }

    func testPs2SharperTexturesAndWidescreenFromTheRealLrps2sOptionsThePatchAtTheNextStart() throws {
        let status = try Self.ps2()
        XCTAssertNil(RetroGraphicsChoice.of(status, .smoothTextures))
        XCTAssertNil(RetroGraphicsChoice.of(status, .widescreenPs1))
        let sharper = try XCTUnwrap(RetroGraphicsChoice.of(status, .sharperTextures))
        XCTAssertEqual(levels(sharper), ["off", "on"])
        XCTAssertEqual(sharper.selected, 0)
        XCTAssertEqual(sharper.note, .none, "LRPS2 applies it while the game runs")
        XCTAssertEqual(sharper.changesFor(status, 1), [RetroOptionValue("pcsx2_anisotropic_filtering", "16x")])
        let widescreen = try XCTUnwrap(RetroGraphicsChoice.of(status, .widescreenPs2))
        XCTAssertEqual(levels(widescreen), ["off", "on"], "16:10, 21:9 and 32:9 are not offered")
        XCTAssertEqual(widescreen.note, .changesAtNextStart, "LRPS2 patches the game at boot")
        let chosen = Self.edited(status, "pcsx2_widescreen_hint", selected: 1)
        let next = try XCTUnwrap(RetroGraphicsChoice.of(chosen, .widescreenPs2))
        XCTAssertEqual(next.selected, 1)
        XCTAssertEqual(next.note, .nextStart)
        var software = status
        software.hardware = false
        XCTAssertNil(RetroGraphicsChoice.of(software, .sharperTextures))
        XCTAssertNotNil(RetroGraphicsChoice.of(software, .widescreenPs2))
    }

    func testTheDefaultsOfTheSettingsNotChosenFixWobbly3dForPs1SharperTexturesForPs2() {
        XCTAssertEqual(RetroGraphics.defaults(kept: [:], ps2: false), [pgxp: "true", "swanstation_GPU_TrueColor": "true"])
        XCTAssertEqual(RetroGraphics.defaults(kept: ["swanstation_GPU_ResolutionScale": "4"], ps2: false), RetroGraphics.defaults(kept: [:], ps2: false),
                       "textures are not smoothed for the player at any resolution")
        XCTAssertEqual(RetroGraphics.defaults(kept: [filter: "xBR", pgxp: "false"], ps2: false), ["swanstation_GPU_TrueColor": "true"])
        XCTAssertEqual(RetroGraphics.defaults(kept: [:], ps2: true), ["pcsx2_anisotropic_filtering": "16x"])
        XCTAssertEqual(RetroGraphics.defaults(kept: ["pcsx2_anisotropic_filtering": "disabled"], ps2: true), [:])
        for ps2 in [false, true] {
            let widescreen: RetroGraphicsSetting = ps2 ? .widescreenPs2 : .widescreenPs1
            XCTAssertTrue(Set(RetroGraphics.defaults(kept: [:], ps2: ps2).keys).isDisjoint(with: widescreen.keys),
                          "widescreen is never chosen for the player")
        }
        XCTAssertNil(RetroGraphics.defaults(kept: [:], ps2: false)[filter], "no texture filter unless the player chose one")
        XCTAssertEqual(RetroGraphics.perGameKeys, [hack, aspect], "only PS1 widescreen is kept per game")
        XCTAssertEqual(RetroGraphics.keys, [filter, pgxp, hack, aspect, "pcsx2_anisotropic_filtering", "pcsx2_widescreen_hint"])
    }
}
