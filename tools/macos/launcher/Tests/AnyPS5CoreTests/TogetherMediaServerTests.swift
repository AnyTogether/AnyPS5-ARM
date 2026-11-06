import XCTest
@testable import AnyPS5Core

/// The optional media server (an SFU, LiveKit) as the launcher reads it from AnyTogether: what the
/// server holds, the route of each share play and call ("mesh" when an older server does not say),
/// the room access in join answers, and the fresh tokens.
final class TogetherMediaServerTests: TogetherSignedInCase {
    static let access: [String: Any] = ["url": "wss://media.anytogether.test", "token": "jwt", "room": "share-sp1", "identity": "u1",
                                        "expiresAt": "2026-11-06T10:10:00.000Z"]

    static func share(media: Any? = nil, maxViewers: Int = 3, viewers: [[String: Any]] = []) -> [String: Any] {
        var share = TogetherSharePlayTests.share(viewers: viewers)
        share["maxViewers"] = maxViewers
        if let media { share["media"] = media }
        return share
    }

    func testTheServersLimitsNeedNoSignIn() async throws {
        FakeTogether.handler = { _, _ in (200, ["sfu": true, "maxShareViewers": 16, "maxPartySize": 24]) }
        let limits = try await client.mediaServer()
        XCTAssertEqual(last(), "GET /api/v1/media-server")
        XCTAssertNil(FakeTogether.requests.last?.0.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(limits, TogetherMediaLimits(sfu: true, maxShareViewers: 16, maxPartySize: 24))
        XCTAssertEqual(TogetherMediaLimits.mesh, TogetherMediaLimits(sfu: false, maxShareViewers: 4, maxPartySize: 8))
    }

    func testAShareWithoutMediaIsTheMesh() throws {
        let old = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONSerialization.data(withJSONObject: Self.share()))
        XCTAssertEqual(old.media, .mesh)
        let sfu = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONSerialization.data(withJSONObject: Self.share(media: "sfu", maxViewers: 12)))
        XCTAssertEqual(sfu.media, .sfu)
        XCTAssertEqual(sfu.maxViewers, 12)
        // A route this launcher does not know yet is the mesh, not a failed decode.
        let unknown = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONSerialization.data(withJSONObject: Self.share(media: "relay")))
        XCTAssertEqual(unknown.media, .mesh)
        // It survives a round trip (the share play is kept as JSON in places).
        let again = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONEncoder().encode(sfu))
        XCTAssertEqual(again.media, .sfu)
    }

    func testStartingAndJoiningCarryTheRoom() async throws {
        FakeTogether.handler = { _, _ in (201, ["sharePlay": Self.share(media: "sfu", maxViewers: 10), "iceServers": [], "expiresAt": NSNull(), "sfu": Self.access]) }
        let started = try await client.startSharePlay(titleId: "PPSA01234", title: nil, open: true, maxViewers: 10)
        XCTAssertEqual(body()?["maxViewers"] as? Int, 10)
        XCTAssertEqual(started.sharePlay.media, .sfu)
        XCTAssertEqual(started.sfu?.url, "wss://media.anytogether.test")
        XCTAssertEqual(started.sfu?.token, "jwt")
        XCTAssertEqual(started.sfu?.room, "share-sp1")
        XCTAssertEqual(started.sfu?.identity, "u1")
        XCTAssertNotNil(started.sfu?.expiresAt)
        // On the mesh, and from an older server that never says.
        FakeTogether.handler = { _, _ in (201, ["sharePlay": Self.share(), "iceServers": [], "expiresAt": NSNull(), "sfu": NSNull()]) }
        let mesh = try await client.joinSharePlay("sp1")
        XCTAssertNil(mesh.sfu)
        FakeTogether.handler = { _, _ in (201, ["sharePlay": Self.share(), "iceServers": [], "expiresAt": NSNull()]) }
        let old = try await client.joinSharePlay("sp1")
        XCTAssertNil(old.sfu)
        XCTAssertEqual(old.sharePlay.media, .mesh)
    }

    func testFreshTokens() async throws {
        FakeTogether.handler = { _, _ in (200, Self.access) }
        let share = try await client.sharePlaySfu("sp1")
        XCTAssertEqual(last(), "GET /api/v1/share-plays/sp1/sfu")
        XCTAssertEqual(share.room, "share-sp1")
        let call = try await client.callSfu("c1")
        XCTAssertEqual(last(), "GET /api/v1/calls/c1/sfu")
        XCTAssertEqual(call.token, "jwt")
    }

    func testMoreViewersThanTheServerTakes() async throws {
        FakeTogether.handler = { _, _ in
            (400, ["type": "about:blank", "status": 400, "code": "media_server_off", "title": "More than 4 viewers need a media server, and this server has none", "max": 4])
        }
        do {
            _ = try await client.updateSharePlay("sp1", maxViewers: 9)
            XCTFail("refused")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "media_server_off")
            XCTAssertEqual(problem.max, 4)
        }
    }

    func testACallsRouteTheJoinAnswerAndTheParty() throws {
        let peer: [String: Any] = ["userId": "u2", "device": "d2", "muted": false, "deafened": false]
        func call(_ media: Any?) -> [String: Any] {
            var call: [String: Any] = ["id": "c1", "kind": "party", "partyId": "p1", "startedBy": "u1", "calleeId": NSNull(), "in": [peer],
                                       "startedAt": "2026-11-06T10:00:00.000Z", "answeredAt": NSNull(), "endedAt": NSNull()]
            if let media { call["media"] = media }
            return call
        }
        let joined = try JSONDecoder.together.decode(TogetherCallJoin.self, from: JSONSerialization.data(withJSONObject: [
            "call": call("sfu"), "iceServers": [], "expiresAt": NSNull(), "sfu": Self.access,
        ]))
        XCTAssertEqual(joined.call.media, .sfu)
        XCTAssertEqual(joined.sfu?.room, "share-sp1")
        let old = try JSONDecoder.together.decode(TogetherCallJoin.self, from: JSONSerialization.data(withJSONObject: [
            "call": call(nil), "iceServers": [], "expiresAt": NSNull(),
        ]))
        XCTAssertEqual(old.call.media, .mesh)
        XCTAssertNil(old.sfu)

        var party: [String: Any] = ["id": "p1", "leaderId": "u1", "privacy": "invite", "members": [], "invited": [],
                                    "call": ["id": "c1", "in": ["u1", "u2"], "muted": [], "deafened": [], "media": "sfu"], "max": 24]
        let big = try JSONDecoder.together.decode(TogetherParty.self, from: JSONSerialization.data(withJSONObject: party))
        XCTAssertEqual(big.call?.media, .sfu)
        XCTAssertEqual(big.capacity, 24)
        party["call"] = ["id": "c1", "in": ["u1"]]
        party["max"] = nil
        let small = try JSONDecoder.together.decode(TogetherParty.self, from: JSONSerialization.data(withJSONObject: party))
        XCTAssertEqual(small.call?.media, .mesh)
        XCTAssertEqual(small.capacity, 8)
        // The copies made before the server says keep it.
        XCTAssertEqual(big.with(members: [], call: nil).capacity, 24)
        XCTAssertEqual(big.with(joinCode: nil).capacity, 24)
    }

    func testTheCallMovedEvent() throws {
        let event = TogetherSocket.Event(id: "1", type: "call.media", json: try JSONSerialization.data(withJSONObject: ["callId": "c1", "partyId": "p1", "media": "sfu"]))
        let moved = try XCTUnwrap(event.decode(TogetherCallMedia.self))
        XCTAssertEqual(moved, TogetherCallMedia(callId: "c1", partyId: "p1", media: .sfu))
    }
}

/// Who goes through the media server and who keeps the direct connection, and how many the host
/// may let watch.
final class MediaRoutingTests: XCTestCase {
    typealias Viewer = TogetherSharePlay.Viewer
    static func person(_ id: String) -> TogetherPerson { TogetherPerson(userId: id, handle: id, displayName: id, avatar: nil) }
    static func viewer(_ id: String, slot: Int? = nil) -> Viewer { Viewer(user: person(id), device: "d-\(id)", slot: slot, joinedAt: nil) }
    static func share(_ media: TogetherMediaRoute, viewers: [Viewer], max: Int = 4) -> TogetherSharePlay {
        TogetherSharePlay(id: "sp1", host: person("h"), hostDevice: "mac", titleId: "PPSA01234", title: nil, open: true, maxViewers: max, viewers: viewers, media: media)
    }

    func testThePickerOffersWhatTheServerTakes() {
        XCTAssertEqual(SharePlayMedia.viewerChoices(nil), 1 ... 4)
        XCTAssertEqual(SharePlayMedia.viewerChoices(.mesh), 1 ... 4)
        XCTAssertEqual(SharePlayMedia.viewerChoices(TogetherMediaLimits(sfu: true, maxShareViewers: 16, maxPartySize: 24)), 1 ... 16)
        // A server that says it has one but no more than the mesh: still the mesh's four.
        XCTAssertEqual(SharePlayMedia.viewerChoices(TogetherMediaLimits(sfu: true, maxShareViewers: 2, maxPartySize: 8)), 1 ... 4)
        XCTAssertEqual(SharePlayMedia.viewerChoices(TogetherMediaLimits(sfu: false, maxShareViewers: 16, maxPartySize: 8)), 1 ... 4)
        // Never below who watches now; never below the share play's own limit (set elsewhere).
        XCTAssertEqual(SharePlayMedia.viewerChoices(nil, watching: 3, current: 12), 3 ... 12)
        XCTAssertEqual(SharePlayMedia.viewerChoices(nil, watching: 0, current: 2), 1 ... 4)
    }

    func testTheSavedChoiceIsKeptWithinWhatTheServerTakes() {
        XCTAssertEqual(SharePlayMedia.clampViewers(12, nil), 4)
        XCTAssertEqual(SharePlayMedia.clampViewers(12, TogetherMediaLimits(sfu: true, maxShareViewers: 16, maxPartySize: 24)), 12)
        XCTAssertEqual(SharePlayMedia.clampViewers(40, TogetherMediaLimits(sfu: true, maxShareViewers: 16, maxPartySize: 24)), 16)
        XCTAssertEqual(SharePlayMedia.clampViewers(0, nil), 1)
    }

    func testOnTheMeshEveryViewerIsCalled() {
        let share = Self.share(.mesh, viewers: [Self.viewer("a"), Self.viewer("b", slot: 2)])
        XCTAssertEqual(SharePlayMedia.meshViewers(share, asked: []).map(\.user.userId), ["a", "b"])
        XCTAssertTrue(SharePlayMedia.servesAsk(share, from: "a", meshPeers: 4))
    }

    func testThroughTheMediaServerOnlyPadHoldersGetTheDirectConnection() {
        let share = Self.share(.sfu, viewers: [Self.viewer("a"), Self.viewer("b", slot: 2), Self.viewer("c"), Self.viewer("d", slot: 4)], max: 12)
        XCTAssertEqual(SharePlayMedia.meshViewers(share, asked: []).map(\.user.userId), ["b", "d"])
        // An older viewer app without a pad that asked for an offer stays on the mesh.
        XCTAssertEqual(SharePlayMedia.meshViewers(share, asked: ["c"]).map(\.user.userId), ["b", "c", "d"])
        // Someone who left is not kept for having asked.
        XCTAssertEqual(SharePlayMedia.meshViewers(share, asked: ["gone"]).map(\.user.userId), ["b", "d"])
    }

    func testAnAskWithoutAPadIsServedWhileTheMeshHasRoom() {
        let share = Self.share(.sfu, viewers: [Self.viewer("a"), Self.viewer("b", slot: 2)], max: 12)
        XCTAssertTrue(SharePlayMedia.servesAsk(share, from: "b", meshPeers: 9))
        XCTAssertTrue(SharePlayMedia.servesAsk(share, from: "a", meshPeers: 3))
        XCTAssertFalse(SharePlayMedia.servesAsk(share, from: "a", meshPeers: 4))
        // Not a viewer at all: never.
        XCTAssertFalse(SharePlayMedia.servesAsk(share, from: "z", meshPeers: 0))
    }

    func testTheViewersRouteFollowsTheirPad() {
        let me = "a"
        XCTAssertEqual(SharePlayMedia.viewerRoute(Self.share(.mesh, viewers: [Self.viewer(me)]), me: me), .mesh)
        XCTAssertEqual(SharePlayMedia.viewerRoute(Self.share(.sfu, viewers: [Self.viewer(me)]), me: me), .sfu)
        XCTAssertEqual(SharePlayMedia.viewerRoute(Self.share(.sfu, viewers: [Self.viewer(me, slot: 3)]), me: me), .mesh)
    }

    func testACallUsesTheMediaServerFromAnyOfItsSignals() {
        XCTAssertEqual(PartyMedia.route(join: .mesh, party: nil, event: nil), .mesh)
        XCTAssertEqual(PartyMedia.route(join: .sfu, party: nil, event: nil), .sfu)
        XCTAssertEqual(PartyMedia.route(join: .mesh, party: .sfu, event: nil), .sfu)
        XCTAssertEqual(PartyMedia.route(join: .mesh, party: .mesh, event: .sfu), .sfu)
        // Once there, it stays.
        XCTAssertEqual(PartyMedia.route(join: .sfu, party: .mesh, event: nil), .sfu)
    }
}

/// LiveKit's client has one audio engine per app: either without a device (the host's game sound
/// fed in by hand) or on the Mac's microphone and speakers (party voice, watching).
final class SfuAudioPlanTests: XCTestCase {
    func testNothingThroughTheMediaServerLeavesTheEngineAlone() {
        XCTAssertEqual(SfuAudioPlan.mode(gameSound: false, voice: false, watching: false), SfuAudioPlan(deviceless: false, gameSound: false))
    }

    func testTheHostsGameSoundAloneRunsWithoutADevice() {
        XCTAssertEqual(SfuAudioPlan.mode(gameSound: true, voice: false, watching: false), SfuAudioPlan(deviceless: true, gameSound: true))
    }

    func testVoiceOrWatchingNeedsTheDeviceAndTheGameSoundWaits() {
        XCTAssertEqual(SfuAudioPlan.mode(gameSound: true, voice: true, watching: false), SfuAudioPlan(deviceless: false, gameSound: false))
        XCTAssertEqual(SfuAudioPlan.mode(gameSound: true, voice: false, watching: true), SfuAudioPlan(deviceless: false, gameSound: false))
        XCTAssertEqual(SfuAudioPlan.mode(gameSound: false, voice: true, watching: true), SfuAudioPlan(deviceless: false, gameSound: false))
    }
}

/// The game's sound as StreamPacket audio, gathered into 20 ms blocks for the media server.
final class SfuSoundBlocksTests: XCTestCase {
    func testFiveMillisecondPacketsMakeTwentyMillisecondBlocks() {
        var blocks = SfuSoundBlocks(frames: 960)
        let packet = [Int16](repeating: 7, count: 240 * 2)
        XCTAssertTrue(blocks.add(packet).isEmpty)
        XCTAssertTrue(blocks.add(packet).isEmpty)
        XCTAssertTrue(blocks.add(packet).isEmpty)
        let full = blocks.add(packet)
        XCTAssertEqual(full.count, 1)
        XCTAssertEqual(full.first?.count, 960 * 2)
        // A larger piece fills one and keeps the rest.
        let two = blocks.add([Int16](repeating: 1, count: 1200 * 2))
        XCTAssertEqual(two.count, 1)
        XCTAssertEqual(blocks.pending, 240)
    }
}
