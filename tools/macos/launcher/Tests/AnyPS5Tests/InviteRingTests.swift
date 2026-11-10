@testable import AnyPS5
import AnyPS5Core
import XCTest

/// A game invite, a party invite and a Play Together offer ring on the controller, as on Windows
/// and Linux; none of them on Do Not Disturb, and nothing with Controller Vibration off.
@MainActor
final class InviteRingTests: XCTestCase {
    /// The controller's motors: the patterns the launcher played.
    final class FakePad: HapticOutput {
        var played: [[HapticPulse]] = []
        func play(_ pulses: [HapticPulse]) { played.append(pulses) }
        func stop() {}
    }

    let mira: [String: Any] = ["userId": "f1", "handle": "mira", "displayName": "Mira", "avatar": NSNull()]
    var pad = FakePad()

    /// A fresh fake pad, in front and in hand (each event's ring is then its own, never the same
    /// cue twice within 30 ms).
    func usePad() {
        pad = FakePad()
        let haptics = HapticFeedback(output: pad, enabled: Feel.shared.vibration)
        haptics.launcherInFront = true
        haptics.padInUse = true
        Feel.shared.haptics = haptics
    }

    func event(_ type: String, _ data: [String: Any]) throws -> TogetherSocket.Event {
        TogetherSocket.Event(id: UUID().uuidString, type: type, json: try JSONSerialization.data(withJSONObject: data))
    }

    var invites: [(String, TogetherSocket.Event)] {
        get throws {
            let session: [String: Any] = ["id": "gs-lan", "kind": "lan", "partyId": "p1", "host": mira, "titleId": "PPSA00001",
                                          "gameVersion": "01.000", "engineBuild": "toolkit-1", "capacity": 4, "joinable": true, "players": [mira]]
            return [
                ("game invite", try event("game_session.invite", ["sessionId": "gs-mira", "from": mira, "titleId": "PPSA00001",
                                                                  "gameVersion": "01.000", "engineBuild": "toolkit-1"])),
                ("party invite", try event("party.invite", ["partyId": "p1", "from": mira, "size": 2])),
                ("Play Together offer", try event("game_session.started", ["partyId": "p1", "session": session])),
            ]
        }
    }

    func model() throws -> AppModel {
        let model = try LauncherFixture.model()
        model.previewOwnProfile(TogetherOwnProfile(handle: "robin", displayName: "Robin", bio: nil, avatar: nil, country: nil, handleChangeAt: nil, privacy: .standard))
        return model
    }

    func testEveryInviteRingsOnTheController() throws {
        let kept = Feel.shared.haptics
        defer { Feel.shared.haptics = kept }
        let model = try model()
        let ring = HapticPatterns.pulses(for: .ring)
        for (name, invite) in try invites {
            usePad()
            model.togetherEvent(invite)
            XCTAssertEqual(pad.played, [ring], "\(name): the ring, as on Windows and Linux")
        }
        XCTAssertEqual(model.gameInvites.count, 1)
        XCTAssertEqual(model.playTogetherOffers.count, 1)
    }

    func testDoNotDisturbKeepsThePadStill() throws {
        let kept = Feel.shared.haptics
        defer { Feel.shared.haptics = kept }
        let model = try model()
        model.togetherProfile?.presence = .dnd
        XCTAssertTrue(model.doNotDisturb)
        for (name, invite) in try invites {
            usePad()
            model.togetherEvent(invite)
            XCTAssertEqual(pad.played, [], "\(name) on Do Not Disturb")
        }
        XCTAssertEqual(model.gameInvites.count, 1, "the invite still comes in")
    }

    func testControllerVibrationOffKeepsThePadStill() throws {
        let kept = Feel.shared.haptics
        defer { Feel.shared.haptics = kept }
        let model = try model()
        model.preferences.controllerVibration = false
        XCTAssertFalse(Feel.shared.vibration)
        for (name, invite) in try invites {
            usePad()
            model.togetherEvent(invite)
            XCTAssertEqual(pad.played, [], "\(name) with Controller Vibration off")
        }
        model.preferences.controllerVibration = nil
        XCTAssertTrue(Feel.shared.vibration)
    }
}
