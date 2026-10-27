import Darwin
import XCTest
@testable import AnyPS5Core

/// Discord's side of its local socket, for the tests: it reads frames and answers each one.
final class FakeDiscord: @unchecked Sendable {
    let directory: URL
    private let listener: Int32
    private let lock = NSLock()
    private var received: [(UInt32, [String: Any])] = []

    init() throws {
        directory = URL(fileURLWithPath: "/tmp/anyps5-discord-\(UInt32.random(in: 0...UInt32.max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = directory.appendingPathComponent("discord-ipc-0").path
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            _ = path.utf8CString.withUnsafeBytes { raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(raw.count))) }
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(listener, 1) == 0 else { throw URLError(.cannotOpenFile) }
        Thread.detachNewThread { [self] in serve() }
    }

    deinit {
        close(listener)
        try? FileManager.default.removeItem(at: directory)
    }

    var frames: [(UInt32, [String: Any])] { lock.withLock { received } }

    private func serve() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            talk(client)
        }
    }

    private func talk(_ client: Int32) {
        while true {
            var header = [UInt8](repeating: 0, count: 8)
            guard recv(client, &header, 8, MSG_WAITALL) == 8 else { break }
            let op = UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24
            let length = Int(UInt32(header[4]) | UInt32(header[5]) << 8 | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
            var body = [UInt8](repeating: 0, count: length)
            guard recv(client, &body, length, MSG_WAITALL) == length else { break }
            let json = (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any] ?? [:]
            lock.withLock { received.append((op, json)) }
            let answer = op == 0 ? #"{"cmd":"DISPATCH","evt":"READY","data":{}}"# : #"{"cmd":"SET_ACTIVITY","evt":null,"data":{}}"#
            let frame = DiscordFrame.encode(op: 1, json: Data(answer.utf8))
            _ = frame.withUnsafeBytes { send(client, $0.baseAddress, frame.count, 0) }
        }
        close(client)
    }

    func waitFor(_ count: Int) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if frames.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }
}

final class DiscordPresenceTests: XCTestCase {
    func testFrameRoundTrip() {
        let frame = DiscordFrame.encode(op: 1, json: Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(Array(frame.prefix(8)), [1, 0, 0, 0, 7, 0, 0, 0])
        XCTAssertEqual(DiscordFrame.decode(frame)?.op, 1)
        XCTAssertEqual(DiscordFrame.decode(frame).map { String(decoding: $0.json, as: UTF8.self) }, #"{"a":1}"#)
        XCTAssertNil(DiscordFrame.decode(frame.prefix(9)))
    }

    func testHandshakeThenActivity() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        presence.playing("Hollow Knight: Silksong", since: started)
        XCTAssertTrue(discord.waitFor(2))
        let (handshakeOp, handshake) = discord.frames[0]
        XCTAssertEqual(handshakeOp, 0)
        XCTAssertEqual(handshake["client_id"] as? String, "1234")
        XCTAssertEqual(handshake["v"] as? Int, 1)
        let (activityOp, command) = discord.frames[1]
        XCTAssertEqual(activityOp, 1)
        XCTAssertEqual(command["cmd"] as? String, "SET_ACTIVITY")
        let arguments = command["args"] as? [String: Any]
        XCTAssertEqual(arguments?["pid"] as? Int, Int(ProcessInfo.processInfo.processIdentifier))
        let activity = arguments?["activity"] as? [String: Any]
        XCTAssertEqual(activity?["details"] as? String, "Hollow Knight: Silksong")
        XCTAssertEqual((activity?["timestamps"] as? [String: Any])?["start"] as? Int, 1_800_000_000)
        XCTAssertEqual(activity?["state"] as? String, "AnyPS5 · Mac")
        XCTAssertNil(activity?["assets"], "Discord shows the application's own icon when no image is named")
        presence.close()
    }

    func testClearRemovesTheActivity() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory)
        presence.playing("Stray", since: Date())
        presence.clear()
        XCTAssertTrue(discord.waitFor(3))
        let arguments = discord.frames[2].1["args"] as? [String: Any]
        XCTAssertEqual(discord.frames[2].1["cmd"] as? String, "SET_ACTIVITY")
        XCTAssertTrue(arguments?["activity"] is NSNull)
        XCTAssertEqual(discord.frames.filter { $0.0 == 0 }.count, 1, "one handshake per connection")
        presence.close()
    }

    static let catalog = DiscordGames(json: Data(#"[{"id":"1413176957381771337","name":"Hollow Knight: Silksong","aliases":[]},{"id":"1431009382950506536","name":"Plants vs. Zombies: Replanted","aliases":["PvZ Replanted"]}]"#.utf8))

    func testGamesMatchByNameWithoutMarks() {
        XCTAssertEqual(Self.catalog.applicationID(for: "Hollow Knight: Silksong"), "1413176957381771337")
        XCTAssertEqual(Self.catalog.applicationID(for: "Plants vs. Zombies™: Replanted"), "1431009382950506536")
        XCTAssertEqual(Self.catalog.applicationID(for: "pvz replanted"), "1431009382950506536")
        XCTAssertNil(Self.catalog.applicationID(for: "Dreaming Sarah"))
        XCTAssertNil(DiscordGames(json: Data("not json".utf8)).applicationID(for: "Hollow Knight: Silksong"))
    }

    func testAKnownGameShowsAsItself() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory, games: Self.catalog)
        presence.playing("Hollow Knight: Silksong", since: Date())
        XCTAssertTrue(discord.waitFor(2))
        XCTAssertEqual(discord.frames[0].1["client_id"] as? String, "1413176957381771337")
        let activity = (discord.frames[1].1["args"] as? [String: Any])?["activity"] as? [String: Any]
        XCTAssertEqual(activity?["details"] as? String, "AnyPS5 Launcher · Mac")
        XCTAssertNil(activity?["state"])
        presence.close()
    }

    func testAnUnknownGameShowsUnderAnyPS5() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory, games: Self.catalog)
        presence.playing("Dreaming Sarah", since: Date())
        XCTAssertTrue(discord.waitFor(2))
        XCTAssertEqual(discord.frames[0].1["client_id"] as? String, "1234")
        let activity = (discord.frames[1].1["args"] as? [String: Any])?["activity"] as? [String: Any]
        XCTAssertEqual(activity?["details"] as? String, "Dreaming Sarah")
        XCTAssertEqual(activity?["state"] as? String, "AnyPS5 · Mac")
        presence.close()
    }

    func testAnotherGameConnectsAgainAsThatGame() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory, games: Self.catalog)
        presence.playing("Dreaming Sarah", since: Date())
        presence.clear()
        presence.playing("Hollow Knight: Silksong", since: Date())
        XCTAssertTrue(discord.waitFor(5))
        let handshakes = discord.frames.filter { $0.0 == 0 }.map { $0.1["client_id"] as? String }
        XCTAssertEqual(handshakes, ["1234", "1413176957381771337"])
        presence.close()
    }

    func testWithoutDiscordNothingHappens() {
        let empty = URL(fileURLWithPath: "/tmp/anyps5-no-discord-\(UInt32.random(in: 0...UInt32.max))")
        let presence = DiscordPresence(applicationID: "1234", directory: empty)
        presence.playing("Stray", since: Date())
        presence.clear()
        presence.close()
    }

    func testTheApplicationIDCanComeFromTheEnvironment() {
        XCTAssertEqual(DiscordPresence.applicationID(environment: [:]), DiscordPresence.anyps5ApplicationID)
        XCTAssertEqual(DiscordPresence.applicationID(environment: ["ANYPS5_DISCORD_APP_ID": " 987654321 "]), "987654321")
        XCTAssertEqual(DiscordPresence.applicationID(environment: ["ANYPS5_DISCORD_APP_ID": ""]), "", "set and empty turns the presence off")
    }

    func testDiscordIsLookedForWhereItsSocketsLive() {
        let folders = DiscordPresence.socketDirectories(environment: ["XDG_RUNTIME_DIR": "/run/user/501", "TMPDIR": "/var/folders/ab/T/"])
        XCTAssertEqual(folders.map(\.path), ["/run/user/501", "/var/folders/ab/T", "/tmp"])
        XCTAssertEqual(DiscordPresence.socketDirectories(environment: ["TMPDIR": "/tmp/"]).map(\.path), ["/tmp"], "each folder once")
    }

    func testASocketInALaterFolderIsFound() throws {
        let discord = try FakeDiscord()
        let empty = URL(fileURLWithPath: "/tmp/anyps5-no-discord-\(UInt32.random(in: 0...UInt32.max))")
        let presence = DiscordPresence(applicationID: "1234", directories: [empty, discord.directory])
        presence.playing("Stray", since: Date())
        XCTAssertTrue(discord.waitFor(2))
        XCTAssertEqual(discord.frames[0].1["client_id"] as? String, "1234")
        presence.close()
    }

    func testNoApplicationIDIsOff() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "", directory: discord.directory)
        presence.playing("Stray", since: Date())
        XCTAssertFalse(discord.waitFor(1))
        presence.close()
    }
    // MARK: The activity, with a party and a Join button

    static let join = DiscordActivity.Button(label: "Join on AnyTogether", url: "https://anytogether.net/join/K7QM3XPA")

    func testAGameAloneHasNoButtonsAndNoParty() throws {
        let activity = try XCTUnwrap(DiscordActivity(game: "Stray", since: Date(timeIntervalSince1970: 1_800_000_000), partyText: "In a party").json(knownGame: false))
        XCTAssertEqual(activity["details"] as? String, "Stray")
        XCTAssertEqual(activity["state"] as? String, "AnyPS5 · Mac")
        XCTAssertEqual((activity["timestamps"] as? [String: Any])?["start"] as? Int, 1_800_000_000)
        XCTAssertEqual(activity["type"] as? Int, 0)
        XCTAssertNil(activity["buttons"])
        XCTAssertNil(activity["party"])
    }

    func testAJoinButtonGoesWithTheActivity() throws {
        let activity = try XCTUnwrap(DiscordActivity(game: "Stray", since: Date(), button: Self.join, partyText: "In a party").json(knownGame: false))
        let buttons = try XCTUnwrap(activity["buttons"] as? [[String: String]])
        XCTAssertEqual(buttons, [["label": "Join on AnyTogether", "url": "https://anytogether.net/join/K7QM3XPA"]])
    }

    func testAButtonKeepsToDiscordsLimits() throws {
        let long = DiscordActivity.Button(label: String(repeating: "a", count: 40), url: Self.join.url)
        let clipped = try XCTUnwrap(DiscordActivity(game: "Stray", since: Date(), button: long, partyText: "x").json(knownGame: false)?["buttons"] as? [[String: String]])
        XCTAssertEqual(clipped.first?["label"]?.count, 32, "labels are 32 characters at most")
        let plain = DiscordActivity.Button(label: "Join", url: "http://anytogether.net/join/K7QM3XPA")
        XCTAssertNil(DiscordActivity(game: "Stray", since: Date(), button: plain, partyText: "x").json(knownGame: false)?["buttons"], "https only")
        let huge = DiscordActivity.Button(label: "Join", url: "https://anytogether.net/join/" + String(repeating: "A", count: 500))
        XCTAssertNil(DiscordActivity(game: "Stray", since: Date(), button: huge, partyText: "x").json(knownGame: false)?["buttons"], "512 characters at most")
        let empty = DiscordActivity.Button(label: "  ", url: Self.join.url)
        XCTAssertNil(DiscordActivity(game: "Stray", since: Date(), button: empty, partyText: "x").json(knownGame: false)?["buttons"])
        XCTAssertEqual(DiscordActivity.Button.maxLabel, 32)
        XCTAssertEqual(DiscordActivity.Button.maxURL, 512)
    }

    func testInAPartyWithoutAGame() throws {
        let party = DiscordActivity.Party(id: "p1", size: 3, max: 8)
        let activity = try XCTUnwrap(DiscordActivity(party: party, button: Self.join, partyText: "In a party").json(knownGame: false))
        XCTAssertEqual(activity["details"] as? String, "In a party")
        XCTAssertEqual(activity["state"] as? String, "AnyPS5 · Mac")
        let shown = try XCTUnwrap(activity["party"] as? [String: Any])
        XCTAssertEqual(shown["id"] as? String, "p1")
        XCTAssertEqual(shown["size"] as? [Int], [3, 8])
        XCTAssertNotNil(activity["buttons"])
        XCTAssertNil(activity["timestamps"], "no time without a start")
    }

    func testAKnownGameInAPartySaysSoUnderIt() throws {
        let activity = try XCTUnwrap(DiscordActivity(game: "Hollow Knight: Silksong", since: Date(), party: .init(id: "p1", size: 2, max: 8), partyText: "In a party").json(knownGame: true))
        XCTAssertEqual(activity["details"] as? String, "AnyPS5 Launcher · Mac")
        XCTAssertEqual(activity["state"] as? String, "In a party", "the size shows next to the state")
        XCTAssertEqual((activity["party"] as? [String: Any])?["size"] as? [Int], [2, 8])
    }

    func testAPartySizeIsAlwaysOneOfMax() throws {
        let odd = try XCTUnwrap(DiscordActivity(party: .init(id: "p1", size: 0, max: 0), partyText: "x").json(knownGame: false)?["party"] as? [String: Any])
        XCTAssertEqual(odd["size"] as? [Int], [1, 1])
    }

    func testNothingToShowClears() {
        XCTAssertNil(DiscordActivity(button: Self.join, partyText: "In a party").json(knownGame: false), "a button alone is nothing")
    }

    func testShowSendsTheWholeActivity() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory, games: Self.catalog)
        presence.show(DiscordActivity(party: .init(id: "p1", size: 2, max: 8), button: Self.join, partyText: "In a party"))
        XCTAssertTrue(discord.waitFor(2))
        XCTAssertEqual(discord.frames[0].1["client_id"] as? String, "1234")
        let activity = (discord.frames[1].1["args"] as? [String: Any])?["activity"] as? [String: Any]
        XCTAssertEqual((activity?["buttons"] as? [[String: String]])?.first?["label"], "Join on AnyTogether")
        presence.show(nil)
        XCTAssertTrue(discord.waitFor(3))
        XCTAssertTrue((discord.frames[2].1["args"] as? [String: Any])?["activity"] is NSNull, "nil clears")
        presence.close()
    }

    func testAKnownGameWithAButtonShowsAsItself() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory, games: Self.catalog)
        presence.show(DiscordActivity(game: "Hollow Knight: Silksong", since: Date(), button: Self.join, partyText: "In a party"))
        XCTAssertTrue(discord.waitFor(2))
        XCTAssertEqual(discord.frames[0].1["client_id"] as? String, "1413176957381771337")
        presence.close()
    }

    // MARK: Which code the Join button uses

    static func code(_ code: String, expires: TimeInterval = 3600) -> TogetherJoinCode {
        TogetherJoinCode(code: code, url: "https://anytogether.net/join/\(code)", expiresAt: Date().addingTimeInterval(expires))
    }

    func testTheButtonUsesACodeThatWorks() {
        let party = DiscordJoin.Source(id: "p1", code: Self.code("PPPPPPPP"), mine: false, mayMake: false)
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: party), .button("https://anytogether.net/join/PPPPPPPP"))
        let share = DiscordJoin.Source(id: "s1", code: Self.code("SSSSSSSS"), mine: true, mayMake: true)
        XCTAssertEqual(DiscordJoin.plan(share: share, party: party), .button("https://anytogether.net/join/SSSSSSSS"), "the share play first")
        let ranOut = DiscordJoin.Source(id: "s1", code: Self.code("SSSSSSSS", expires: -10), mine: false, mayMake: false)
        XCTAssertEqual(DiscordJoin.plan(share: ranOut, party: party), .button("https://anytogether.net/join/PPPPPPPP"))
    }

    func testTheLeaderGetsACodeMadeForTheButton() {
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: .init(id: "p1", code: nil, mine: true, mayMake: true)), .makeParty("p1"))
        XCTAssertEqual(DiscordJoin.plan(share: .init(id: "s1", code: nil, mine: true, mayMake: true), party: .init(id: "p1", code: nil, mine: true, mayMake: true)), .makeShare("s1"))
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: .init(id: "p1", code: Self.code("PPPPPPPP", expires: -1), mine: true, mayMake: true)), .makeParty("p1"), "one that ran out is made again")
    }

    func testNoButtonWhenTheUserStoppedTheCodeOrIsNotTheLeader() {
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: .init(id: "p1", code: nil, mine: true, mayMake: false)), .none, "stopped by the user this session")
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: .init(id: "p1", code: nil, mine: false, mayMake: true)), .none, "a member never makes one")
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: nil), .none)
    }

    func testTheButtonIsLookedAtAgainWhenTheSoonestCodeRunsOut() {
        let now = Date()
        let party = DiscordJoin.Source(id: "p1", code: Self.code("PPPPPPPP", expires: 3600), mine: true, mayMake: true)
        let share = DiscordJoin.Source(id: "s1", code: Self.code("SSSSSSSS", expires: 600), mine: true, mayMake: true)
        XCTAssertEqual(DiscordJoin.refresh(share: share, party: party, now: now), share.code?.expiresAt)
        XCTAssertEqual(DiscordJoin.refresh(share: nil, party: party, now: now), party.code?.expiresAt)
        let ranOut = DiscordJoin.Source(id: "s1", code: Self.code("SSSSSSSS", expires: -10), mine: true, mayMake: true)
        XCTAssertEqual(DiscordJoin.refresh(share: ranOut, party: party, now: now), party.code?.expiresAt, "one that ran out already is no reason to wait")
        XCTAssertNil(DiscordJoin.refresh(share: ranOut, party: nil, now: now))
        XCTAssertNil(DiscordJoin.refresh(share: nil, party: .init(id: "p1", code: nil, mine: true, mayMake: true), now: now))
        XCTAssertNil(DiscordJoin.refresh(share: nil, party: nil, now: now))
    }

    func testWhenTheCodeRunsOutTheButtonGetsANewOneOrGoes() throws {
        // The leader's code: until it runs out the button opens it, then a new one is made for it.
        let led = DiscordJoin.Source(id: "p1", code: Self.code("PPPPPPPP", expires: 900), mine: true, mayMake: true)
        let end = try XCTUnwrap(DiscordJoin.refresh(share: nil, party: led))
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: led, now: end.addingTimeInterval(-1)), .button("https://anytogether.net/join/PPPPPPPP"))
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: led, now: end), .makeParty("p1"))
        // A member's button goes; so does the leader's once they stopped making codes for it.
        let member = DiscordJoin.Source(id: "p1", code: led.code, mine: false, mayMake: false)
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: member, now: end), .none)
        let stopped = DiscordJoin.Source(id: "p1", code: led.code, mine: true, mayMake: false)
        XCTAssertEqual(DiscordJoin.plan(share: nil, party: stopped, now: end), .none)
        // The share play's code running out falls back to the party's, which still works.
        let share = DiscordJoin.Source(id: "s1", code: Self.code("SSSSSSSS", expires: 60), mine: true, mayMake: false)
        let party = DiscordJoin.Source(id: "p1", code: Self.code("PPPPPPPP", expires: 3600), mine: false, mayMake: false)
        let shareEnd = try XCTUnwrap(DiscordJoin.refresh(share: share, party: party))
        XCTAssertEqual(DiscordJoin.plan(share: share, party: party, now: shareEnd), .button("https://anytogether.net/join/PPPPPPPP"))
    }
}
