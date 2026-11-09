@testable import AnyPS5
import AnyPS5Core
import XCTest

/// Settings rows the Mac launcher took over from AnyPS5 Desktop: the launcher volume, the phone
/// server's switch, menu music without a theme, the talk key, and why upstream's engine is not
/// offered here.
@MainActor
final class DesktopParityTests: XCTestCase {
    func row(_ rows: [PanelRow], _ id: String) throws -> PanelRow { try XCTUnwrap(rows.first { $0.id == id }, "no row \(id)") }

    func rows(_ model: AppModel, _ category: String) throws -> [PanelRow] {
        model.open(.settings)
        return try XCTUnwrap(model.panelCategories().first { $0.id == category }, "no category \(category)").rows
    }

    func testTheLauncherVolumeIsOverTheSoundsAndTheMusic() throws {
        let model = try LauncherFixture.model { $0.sounds = true }
        let behaviour = try rows(model, "behaviour")
        let ids = behaviour.map(\.id)
        XCTAssertEqual(Array(ids.prefix(3)), ["launcherVolume", "sounds", "music"])
        guard case .stepper(let value, let range, _, _, let set) = try row(behaviour, "launcherVolume").kind else { return XCTFail("not a stepper") }
        XCTAssertEqual(value, 100)
        XCTAssertEqual(range, 0...100)
        model.preferences.musicVolume = 60
        set(50)
        XCTAssertEqual(model.preferences.launcherVolume, 50)
        XCTAssertEqual(Sounds.shared.volume, 0.5, accuracy: 0.001)
        XCTAssertEqual(ThemeMusic.shared.volume, 0.3, accuracy: 0.001)
        set(0)
        XCTAssertFalse(Sounds.shared.enabled, "0 % is silent")
        set(100)
        XCTAssertNil(model.preferences.launcherVolume, "the default is not kept")
        XCTAssertTrue(Sounds.shared.enabled)
    }

    func testThePhoneServerCanBeTurnedOff() throws {
        let model = try LauncherFixture.model()
        let advanced = try rows(model, "advanced")
        guard case .toggle(let on, let set) = try row(advanced, "phoneServer").kind else { return XCTFail("not a toggle") }
        XCTAssertTrue(on)
        XCTAssertTrue(advanced.contains { $0.id == "browserPlay" })
        set(false)
        XCTAssertEqual(model.preferences.phoneServer, false)
        let off = try rows(model, "advanced")
        XCTAssertFalse(off.contains { $0.id == "browserPlay" }, "the browser pad needs the phone server")
        XCTAssertFalse(off.contains { $0.id == "phoneAddress" }, "no server, no address")
        model.setPhoneServer(true)
        XCTAssertNil(model.preferences.phoneServer)
    }

    func testMenuMusicNeedsNoTheme() throws {
        let model = try LauncherFixture.model()
        XCTAssertNotNil(try rows(model, "appearance").first { $0.id == "menuMusic" })
        XCTAssertFalse(try rows(model, "appearance").contains { $0.id == "menuMusicOff" })
        model.preferences.menuMusicFile = "/Music/Menu.m4a"
        let appearance = try rows(model, "appearance")
        XCTAssertEqual(try row(appearance, "menuMusic").detail, "Menu.m4a")
        guard case .action(_, let remove) = try row(appearance, "menuMusicOff").kind else { return XCTFail("not an action") }
        remove()
        XCTAssertNil(model.preferences.menuMusicFile)
    }

    func testTheTalkKeyIsChosenAndARefusedOneKeepsTheOld() throws {
        let model = try LauncherFixture.model()
        guard case .keys(let keys, false, _) = try row(model.voiceControlRows(), "voice-key").kind else { return XCTFail("not a key row") }
        XCTAssertEqual(keys, ["⌥V"])
        XCTAssertEqual(try row(model.voiceControlRows(), "voice-mic").detail, "⌥V turns the microphone on and off, in a game too.")
        model.chooseTalkKey(KeyChord(keyCode: 9, name: "V"))
        XCTAssertNil(model.preferences.talkKey, "a plain V would be taken from every app")
        model.chooseTalkKey(KeyChord(keyCode: 11, modifiers: .control, name: "B"))
        XCTAssertEqual(model.preferences.talkKey, KeyChord(keyCode: 11, modifiers: .control, name: "B"))
        XCTAssertEqual(try row(model.voiceControlRows(), "voice-mic").detail, "⌃B turns the microphone on and off, in a game too.")
        model.chooseTalkKey(TalkKey.standard)
        XCTAssertNil(model.preferences.talkKey, "back to ⌥V: nothing kept")
    }

    func testNoiseSuppressionSitsBesideTheMicrophoneOnByDefault() throws {
        let model = try LauncherFixture.model()
        let ids = model.voiceControlRows().map(\.id)
        XCTAssertEqual(try XCTUnwrap(ids.firstIndex(of: "voice-noise")), try XCTUnwrap(ids.firstIndex(of: "voice-mic")) + 1)
        guard case .toggle(true, let set) = try row(model.voiceControlRows(), "voice-noise").kind else { return XCTFail("not a switch, or not on") }
        XCTAssertEqual(try row(model.voiceControlRows(), "voice-noise").detail, "Background noise is filtered out of your microphone.")
        set(false)
        XCTAssertEqual(model.preferences.noiseSuppression, false)
        XCTAssertEqual(try row(model.voiceControlRows(), "voice-noise").detail, "Your microphone goes as it is: for music, or a quiet room.")
        XCTAssertTrue(AppModel.personalKeys.contains("noiseSuppression"))
    }

    func testThePublicProfileSwitchComesFirstInPrivacy() throws {
        let model = try LauncherFixture.model()
        model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        model.previewOwnProfile(TogetherOwnProfile(handle: "robin", displayName: "Robin", bio: nil, avatar: nil, country: nil, handleChangeAt: nil, privacy: .standard))
        let ids = model.togetherRows().map(\.id)
        let open = try XCTUnwrap(ids.firstIndex(of: "privacy-public-profile"))
        XCTAssertEqual(open, try XCTUnwrap(ids.firstIndex(of: "together-privacy")) + 1)
        guard case .toggle(false, _) = try row(model.togetherRows(), "privacy-public-profile").kind else { return XCTFail("off for a new account") }
        XCTAssertTrue(try XCTUnwrap(row(model.togetherRows(), "privacy-public-profile").detail).hasSuffix(TChat.text(.publicProfileOffNote)))
        model.togetherProfile?.publicProfile = true
        XCTAssertEqual(try row(model.togetherRows(), "privacy-public-profile").detail, TChat.text(.publicProfileHint))
    }

    func testTheEnginePickerSaysWhyUpstreamIsNotOffered() throws {
        let engine = try rows(try LauncherFixture.model(), "engine")
        XCTAssertEqual(engine.map(\.id).prefix(2), ["engineDefault", "engineUpstreamNotOnMac"])
        XCTAssertEqual(try row(engine, "engineUpstreamNotOnMac").title, "Upstream's own engine isn't offered here")
    }
}
