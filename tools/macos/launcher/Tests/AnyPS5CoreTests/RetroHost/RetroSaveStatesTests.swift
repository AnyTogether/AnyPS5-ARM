import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import AnyPS5Core

/// What a host built from the save states branch sent (capability `saveStates`), the same recording
/// as AnyPS5 Desktop's test/fixtures/retro_host_save_states_recording.json, read as Desktop's
/// test/support/save_states_host_recording.dart reads it: every message each way as its exact text,
/// by scenario, frames left out, and the files its states folder held after each scenario. It ran on
/// Windows with the host repository's fake core, so its paths are Windows ones (`C:\retro-host-test`).
struct RetroSaveStatesRecording {
    typealias Message = (from: String, message: [String: RetroJSON])
    typealias Exchange = (call: [String: RetroJSON], reply: [String: RetroJSON])

    static let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/retro-host-save-states-recording.json")

    /// The scenarios in the order they were recorded.
    let order: [String]
    private let scenarios: [String: [Message]]
    private let folders: [String: [String]]

    static func load() throws -> RetroSaveStatesRecording {
        let file = try RetroJSON.parse(Data(contentsOf: url))
        let scenarios = try XCTUnwrap(file.objectValue?["scenarios"], "the recording has no scenarios")
        var read: [String: [Message]] = [:]
        for name in scenarios.objectKeys ?? [] {
            read[name] = try (scenarios.objectValue?[name]?.arrayValue ?? []).map { entry -> Message in
                let raw = try XCTUnwrap(entry.objectValue?["raw"]?.stringValue)
                let message = try XCTUnwrap(try RetroJSON.parse(Array(raw.utf8)).objectValue)
                return (entry.objectValue?["from"]?.stringValue ?? "", message)
            }
        }
        var folders: [String: [String]] = [:]
        for (name, list) in file.objectValue?["files"]?.objectValue ?? [:] {
            folders[name] = list.arrayValue?.compactMap(\.stringValue) ?? []
        }
        return RetroSaveStatesRecording(order: scenarios.objectKeys ?? [], scenarios: read, folders: folders)
    }

    /// Every message of `scenario`, in the order they went.
    func messages(_ scenario: String) -> [Message] { scenarios[scenario] ?? [] }

    /// The names in the states folder once `scenario` was over.
    func files(_ scenario: String) -> [String] { folders[scenario] ?? [] }

    /// The host's `welcome` in `scenario`.
    func welcome(_ scenario: String) -> [String: RetroJSON] {
        messages(scenario).first { $0.from == "host" && $0.message["type"] == .string("welcome") }?.message ?? [:]
    }

    /// Each `call` of `method` the launcher sent in `scenario`, with the host's reply to it.
    func calls(_ scenario: String, _ method: String) -> [Exchange] {
        let all = messages(scenario)
        return all.compactMap { sent -> Exchange? in
            guard sent.from == "launcher", sent.message["type"] == .string("call"), sent.message["method"] == .string(method) else { return nil }
            guard let reply = all.first(where: { $0.from == "host" && $0.message["type"] == .string("reply") && $0.message["id"] == sent.message["id"] })
            else { return nil }
            return (sent.message, reply.message)
        }
    }

    /// Every `saveState` and `loadState` of every scenario with its reply: scenario by scenario, its
    /// saves and then its loads.
    func stateCalls() -> [(scenario: String, call: [String: RetroJSON], reply: [String: RetroJSON])] {
        var all: [(scenario: String, call: [String: RetroJSON], reply: [String: RetroJSON])] = []
        for scenario in order {
            for method in ["saveState", "loadState"] {
                for exchange in calls(scenario, method) { all.append((scenario: scenario, call: exchange.call, reply: exchange.reply)) }
            }
        }
        return all
    }

    /// The first error reply with `code` to a state call.
    func error(_ code: String) throws -> RetroCallError {
        let error = try XCTUnwrap(stateCalls().compactMap { $0.reply["error"]?.objectValue }.first { $0["code"] == .string(code) }, "no \(code)")
        return RetroCallError(code: code, message: error["message"]?.stringValue ?? "")
    }
}

/// Something a flag a task sets, read by the test.
final class RetroFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var value: Bool { lock.withLock { on } }
    func set() { lock.withLock { on = true } }
}

/// Save states in the emulator host, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_state_slots_test.dart and test/ui/retro_host/retro_save_states_test.dart):
/// the slots of a game's states folder and their pictures, the game's `saveState` and `loadState`
/// with every reply the recorded host sent, the rule that no other call goes out while one runs,
/// and a save's picture.
@MainActor
final class RetroSaveStatesTests: XCTestCase {
    private var games: [RetroHostGame] = []
    private var folders: [URL] = []
    private var keep: [RetroSaveStates] = []

    override func tearDown() async throws {
        for states in keep { states.dispose() }
        for game in games { game.dispose() }
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        keep = []
        games = []
        folders = []
    }

    private func recording() throws -> RetroSaveStatesRecording { try RetroSaveStatesRecording.load() }

    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retro-states-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    private func write(_ bytes: [UInt8], _ path: String, modified: Date? = nil) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path) }
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    private func request(_ root: URL) -> RetroHostStartRequest {
        RetroHostStartRequest(core: "/cores/swanstation_libretro.dylib", disc: root.appendingPathComponent("games/Night Racer.cue").path,
                              system: root.appendingPathComponent("system").path, saves: root.appendingPathComponent("saves").path,
                              states: root.appendingPathComponent("states").path)
    }

    /// A game started with a states folder on a host that lists `saveStates` (unless `lists` is
    /// false), its first frame shown.
    private func started(lists: Bool = true) async throws -> (FakeRetroHostSession, RetroHostGame, URL) {
        let root = try temp()
        let session = FakeRetroHostSession()
        session.canSaveStates = lists
        let game = RetroHostGame(session: session, statusEvery: .seconds(3600))
        games.append(game)
        session.greet()
        session.nextStatus = fakeStatus()
        await game.start(request(root))
        return (session, game, root)
    }

    private func saveStates(_ game: RetroHostGame, _ root: URL, picture: RetroSaveStates.PictureMaker? = nil) -> RetroSaveStates {
        let states = RetroSaveStates(game: game, folder: RetroStateFolder(folder: root.appendingPathComponent("states").path, disc: request(root).disc),
                                     picture: picture)
        keep.append(states)
        return states
    }

    /// The host writes a state's file as it saves it, as the recorded host did.
    private func hostWritesStates(_ session: FakeRetroHostSession, _ folder: RetroStateFolder) {
        session.onCall = { method, args in
            guard method == "saveState", let slot = args.objectValue?["slot"]?.intValue else { return }
            let path = folder.statePath(slot)
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
        }
    }

    private func saved() throws -> RetroJSON { try XCTUnwrap(try recording().calls("slots", "saveState").first?.reply["result"]) }
    private func loaded() throws -> RetroJSON { try XCTUnwrap(try recording().calls("slots", "loadState")[1].reply["result"]) }

    // MARK: The states folder

    func testADiscsNameIsTheHostsTheLastPartAfterASeparatorWithoutItsExtension() {
        XCTAssertEqual(RetroStateFolder.discName(#"C:\Games\Spyro (USA).cue"#, windows: true), "Spyro (USA)")
        XCTAssertEqual(RetroStateFolder.discName("C:/Games/Final Fantasy VII.m3u", windows: true), "Final Fantasy VII")
        XCTAssertEqual(RetroStateFolder.discName("/games/Jak.and.Daxter.iso"), "Jak.and.Daxter")
        XCTAssertEqual(RetroStateFolder.discName("/games/.hidden"), ".hidden", "a first dot is no extension")
        XCTAssertEqual(RetroStateFolder.discName("/games/noextension"), "noextension")
        XCTAssertEqual(RetroStateFolder.discName(#"/games/a\b.cue"#), #"a\b"#, #"\ is a letter on macOS"#)
    }

    func testTheRecordedHostNamedEachSlotItSavedAsTheLauncherReadsIt() throws {
        let recording = try recording()
        // Recorded on Windows, so its paths are read as the host read them there.
        let start = try XCTUnwrap(recording.calls("slots", "start").first?.call["args"]?.objectValue)
        let name = RetroStateFolder.discName(try XCTUnwrap(start["disc"]?.stringValue), windows: true)
        var saved: [Int] = []
        for exchange in recording.calls("slots", "saveState") where exchange.reply["result"]?.objectValue != nil {
            if let slot = exchange.call["args"]?.objectValue?["slot"]?.intValue, !saved.contains(slot) { saved.append(slot) }
        }
        XCTAssertEqual(saved, [0, 3])
        XCTAssertEqual(recording.files("slots"), saved.map { "\(name).\($0).state" })
        XCTAssertEqual((RetroStateFolder(folder: "/retro/states", disc: "/games/game.cue").statePath(3) as NSString).lastPathComponent, "game.3.state")

        let ps2 = try XCTUnwrap(recording.calls("ps2-slot", "start").first?.call["args"]?.objectValue)
        let ps2Name = RetroStateFolder.discName(try XCTUnwrap(ps2["disc"]?.stringValue), windows: true)
        XCTAssertEqual(recording.files("ps2-slot"), ["\(ps2Name).1.state"])
    }

    func testTheRecordedHostListsSaveStatesAndTookTheLaunchersStartWithItsStatesFolder() throws {
        let recording = try recording()
        XCTAssertEqual(recording.welcome("welcome")["capabilities"]?.arrayValue?.contains(.string(RetroProtocol.saveStatesCapability)), true)
        func text(_ map: [String: RetroJSON], _ key: String) throws -> String { try XCTUnwrap(map[key]?.stringValue, key) }
        let start = try XCTUnwrap(recording.calls("slots", "start").first?.call["args"]?.objectValue)
        let ours = RetroHostStartRequest(core: try text(start, "core"), disc: try text(start, "disc"), system: try text(start, "system"),
                                         saves: try text(start, "saves"), states: try text(start, "states"))
        XCTAssertEqual(ours.args, .object(start))
        var without = start
        without["states"] = nil
        XCTAssertEqual(ours.withoutStates().args, .object(without))
        let ps2 = try XCTUnwrap(recording.calls("ps2-slot", "start").first?.call["args"]?.objectValue)
        XCTAssertEqual(RetroHostStartRequest(core: try text(ps2, "core"), disc: try text(ps2, "disc"), system: try text(ps2, "system"),
                                             saves: try text(ps2, "saves"), console: RetroConsole.ps2, states: try text(ps2, "states")).args,
                       .object(ps2))
    }

    func testEveryErrorCodeTheRecordedHostGaveHasItsOutcome() throws {
        let codes = Set(try recording().stateCalls().compactMap { $0.reply["error"]?.objectValue?["code"]?.stringValue })
        XCTAssertEqual(codes, [RetroCallError.argument, RetroCallError.noState, RetroCallError.badState, RetroCallError.otherGame,
                               RetroCallError.otherCore, RetroCallError.coreRefused, RetroCallError.fileError])
        let outcomes = Dictionary(uniqueKeysWithValues: codes.map { ($0, RetroStateOutcome(errorCode: $0)) })
        XCTAssertEqual(outcomes, [
            RetroCallError.argument: .failed, RetroCallError.noState: .noState, RetroCallError.badState: .badState,
            RetroCallError.otherGame: .otherGame, RetroCallError.otherCore: .otherCore, RetroCallError.coreRefused: .coreRefused,
            RetroCallError.fileError: .fileError,
        ])
        XCTAssertEqual(RetroStateOutcome(errorCode: "aCodeOfALaterHost"), .failed)
    }

    func testTheSlotsEmptyWithoutAFileSavedAtItsTimeWithThePictureKeptBesideIt() throws {
        let root = try temp()
        let folder = RetroStateFolder(folder: root.path, disc: "games/Night Racer.cue")
        XCTAssertEqual(folder.read().map(\.empty), Array(repeating: true, count: RetroStateFolder.slots))

        let at = Date(timeIntervalSince1970: 1_795_010_580)
        try write([1, 2, 3], folder.statePath(2), modified: at)
        try write([4], folder.statePath(5))
        try FileManager.default.createDirectory(atPath: folder.statePath(6), withIntermediateDirectories: true)
        try write([5], root.appendingPathComponent("Other Game.1.state").path)
        let png = Data([137, 80, 78, 71])
        try folder.keepPicture(2, png)
        try FileManager.default.setAttributes([.modificationDate: at.addingTimeInterval(1)], ofItemAtPath: folder.picturePath(2))
        try Data(count: RetroStateFolder.pictureLimit + 1).write(to: URL(fileURLWithPath: folder.picturePath(5)))

        let slots = folder.read()
        XCTAssertEqual(slots.map(\.slot), Array(0..<8))
        XCTAssertEqual(slots.filter { !$0.empty }.map(\.slot), [2, 5], "a folder is no state")
        XCTAssertEqual(slots[2].savedAt, at)
        XCTAssertEqual(slots[2].picture, png)
        XCTAssertNil(slots[5].picture, "a picture far larger than one the launcher writes is left out")
        XCTAssertEqual((folder.statePath(2) as NSString).lastPathComponent, "Night Racer.2.state")
        XCTAssertEqual((folder.picturePath(2) as NSString).lastPathComponent, "Night Racer.2.png")
    }

    func testAPictureOlderThanItsStateIsOfAStateBeforeAndIsNotShown() throws {
        let root = try temp()
        let folder = RetroStateFolder(folder: root.path, disc: "game.cue")
        try write([9], folder.picturePath(3), modified: Date(timeIntervalSince1970: 1_793_000_000))
        try write([1], folder.statePath(3), modified: Date(timeIntervalSince1970: 1_793_086_400))
        let slot = folder.read()[3]
        XCTAssertFalse(slot.empty)
        XCTAssertNil(slot.picture, "a picture a failed save could not take away stays out of sight")
    }

    func testAPictureIsPutInPlaceWholeAndASaveWithoutOneTakesTheOldOneAway() throws {
        let root = try temp()
        let folder = RetroStateFolder(folder: root.path, disc: "game.cue")
        try folder.keepPicture(0, Data([1]))
        try folder.keepPicture(0, Data([2, 2]))
        XCTAssertEqual(FileManager.default.contents(atPath: folder.picturePath(0)), Data([2, 2]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["game.0.png"], "nothing left beside it")
        try folder.keepPicture(0, nil)
        XCTAssertFalse(exists(folder.picturePath(0)))
        try folder.keepPicture(1, nil)
    }

    func testAPictureThatCannotBeWrittenLeavesNoneBehind() throws {
        let root = try temp()
        let folder = RetroStateFolder(folder: root.appendingPathComponent("missing").path, disc: "game.cue")
        XCTAssertThrowsError(try folder.keepPicture(0, Data([1])))
        XCTAssertFalse(exists(folder.picturePath(0)))
        XCTAssertFalse(exists(folder.picturePath(0) + ".writing"))
    }

    func testASlotsPictureIs240PixelsWideAtTheGamesAspect() throws {
        let slot = FakeSlot(4, 4)
        slot.fill([10, 20, 30, 255])
        let image = try XCTUnwrap(RetroFramePicture.image(of: slot.pin()))
        let png = try XCTUnwrap(RetroStatePicture.png(image, aspect: 4.0 / 3.0))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let read = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(read.width, 240)
        XCTAssertEqual(read.height, 180)
        XCTAssertEqual(Array(png.prefix(4)), [137, 80, 78, 71])
        XCTAssertNil(RetroStatePicture.png(image, aspect: 0))
    }

    // MARK: The game's saveState and loadState

    func testAGameStartedWithAStatesFolderOnAHostThatListsSaveStatesSendsItAndSavesStates() async throws {
        let (session, game, root) = try await started()
        XCTAssertEqual(session.startArgs?.objectValue?["states"], .string(root.appendingPathComponent("states").path))
        XCTAssertTrue(game.savesStates)
    }

    func testOnAHostWithoutSaveStatesTheFolderIsLeftOutAndTheGameHasNoSaveStates() async throws {
        let (session, game, _) = try await started(lists: false)
        XCTAssertNil(session.startArgs?.objectValue?["states"])
        XCTAssertFalse(game.savesStates)
        let outcome = await game.saveState(0)
        XCTAssertEqual(outcome, .notNow)
        XCTAssertFalse(session.methods.contains("saveState"))
    }

    func testEverySaveStateAndLoadStateReplyTheRecordedHostSentIsTheOutcomeTheMenuActsOn() async throws {
        let (session, game, _) = try await started()
        var seen = Set<RetroStateOutcome>()
        for exchange in try recording().stateCalls() {
            let method = exchange.call["method"]?.stringValue ?? ""
            guard let slot = exchange.call["args"]?.objectValue?["slot"]?.intValue else { continue }
            session.callResults = [:]
            session.callErrors = [:]
            let expected: RetroStateOutcome
            if let error = exchange.reply["error"]?.objectValue {
                let code = error["code"]?.stringValue ?? ""
                session.callErrors[method] = RetroCallError(code: code, message: error["message"]?.stringValue ?? "")
                expected = RetroStateOutcome(errorCode: code)
            } else {
                let result = try XCTUnwrap(exchange.reply["result"])
                session.callResults[method] = result
                expected = result.objectValue != nil ? .done : .notNow
            }
            let outcome: RetroStateOutcome
            if method == "saveState" {
                outcome = await game.saveState(slot)
            } else {
                outcome = await game.loadState(slot)
            }
            XCTAssertEqual(outcome, expected, "\(exchange.scenario): \(method) \(slot)")
            XCTAssertEqual(session.calls.last?.0, method)
            XCTAssertEqual(session.calls.last?.1, .object(["slot": .int(slot)]))
            seen.insert(outcome)
        }
        XCTAssertEqual(seen, Set(RetroStateOutcome.allCases), "the recording has every outcome")
        let count = session.calls.count
        let outside = await game.saveState(8)
        XCTAssertEqual(outside, .failed, "there is no ninth slot")
        XCTAssertEqual(session.calls.count, count)
    }

    func testNoOtherCallIsSentAfterASaveStateOrLoadStateUntilItsReply() async throws {
        let (session, game, _) = try await started()
        session.callResults["saveState"] = try saved()
        session.callResults["option"] = .bool(true)
        let gate = RetroGate()
        session.callGate = gate
        let saving = Task { await game.saveState(1) }
        await settleRetro({ session.methods.contains("saveState") })
        session.callGate = nil
        let refreshed = RetroFlag()
        let waiting = [
            Task { await game.pause(true) },
            Task {
                await game.refresh()
                refreshed.set()
            },
            Task { _ = await game.setOption(key: "k", value: "v") },
            Task { await game.setVolume(level: 0) },
        ]
        let loading = Task { await game.loadState(1) }
        await yieldRetro()
        XCTAssertEqual(session.methods.last, "saveState", "everything else waits for its reply")
        XCTAssertFalse(refreshed.value, "status waits too")
        gate.open()
        let outcome = await saving.value
        XCTAssertEqual(outcome, .done)
        for task in waiting { await task.value }
        _ = await loading.value
        let after = Set(session.methods.drop(while: { $0 != "saveState" }).dropFirst())
        XCTAssertTrue(["pause", "option", "volume", "loadState"].allSatisfy { after.contains($0) }, "\(after)")
        XCTAssertTrue(refreshed.value)
    }

    func testACallAskedBehindASecondStateCallWaitsForThatOneToo() async throws {
        let (session, game, _) = try await started()
        session.callResults["saveState"] = try saved()
        session.callResults["loadState"] = try loaded()
        session.callResults["option"] = .bool(true)
        let first = RetroGate()
        session.callGate = first
        let saving = Task { await game.saveState(1) }
        await settleRetro({ session.methods.contains("saveState") })
        let loading = Task { await game.loadState(2) }
        await yieldRetro()
        let option = Task { await game.setOption(key: "k", value: "v") }
        await yieldRetro()
        let second = RetroGate()
        session.onCall = { [unowned session] method, _ in
            if method == "loadState" { session.callGate = second }
        }
        first.open()
        let savedOutcome = await saving.value
        XCTAssertEqual(savedOutcome, .done)
        await settleRetro({ session.methods.last == "loadState" })
        await yieldRetro()
        XCTAssertEqual(session.methods.last, "loadState", "the option waits for the load it was asked behind")
        second.open()
        let loadedOutcome = await loading.value
        XCTAssertEqual(loadedOutcome, .done)
        let taken = await option.value
        XCTAssertTrue(taken)
        XCTAssertEqual(Array(session.methods.suffix(3)), ["saveState", "loadState", "option"])
    }

    func testAStateCallAskedOnceStopHasBegunIsNotNowWithoutACall() async throws {
        let (session, game, _) = try await started()
        let gate = RetroGate()
        session.callGate = gate
        let stopping = Task { await game.stop() }
        await settleRetro({ session.methods.contains("release") })
        let save = await game.saveState(0)
        let load = await game.loadState(0)
        XCTAssertEqual(save, .notNow)
        XCTAssertEqual(load, .notNow)
        gate.open()
        _ = await stopping.value
        XCTAssertFalse(session.methods.contains("saveState"))
        XCTAssertFalse(session.methods.contains("loadState"))
    }

    func testALoadAnsweredFalseCountsUntilAStatusAskedAfterItsReplySaysTheGamePlaysOn() async throws {
        let (session, game, root) = try await started()
        let states = saveStates(game, root)
        session.callResults["loadState"] = .bool(false)
        var outcome = await states.load(1)
        XCTAssertEqual(outcome, .notNow)
        XCTAssertTrue(states.loadAnsweredFalse, "the status before the load says nothing of it")
        await game.refresh()
        XCTAssertFalse(states.loadAnsweredFalse, "a status asked after the reply says the game plays on")

        let gate = RetroGate()
        session.callGate = gate
        let loading = Task { await states.load(1) }
        await settleRetro({ session.methods.filter { $0 == "loadState" }.count == 2 })
        session.callGate = nil
        let polled = Task { await game.refresh() }
        await yieldRetro()
        gate.open()
        outcome = await loading.value
        XCTAssertEqual(outcome, .notNow)
        await polled.value
        XCTAssertFalse(states.loadAnsweredFalse, "a status held behind the load is asked after its reply")

        outcome = await states.load(1)
        XCTAssertEqual(outcome, .notNow)
        XCTAssertTrue(states.loadAnsweredFalse, "a later load answered false counts again")
        session.nextStatus = fakeStatus(ended: true, errorCode: RetroErrorCode.other)
        await game.refresh()
        XCTAssertEqual(game.phase, .ended)
        XCTAssertTrue(states.loadAnsweredFalse, "the load ended the game")
    }

    func testNoGameLoadedIsNotNowWithoutACall() async {
        let session = FakeRetroHostSession()
        session.canSaveStates = true
        let game = RetroHostGame(session: session, statusEvery: .seconds(3600))
        games.append(game)
        let outcome = await game.saveState(0)
        XCTAssertEqual(outcome, .notNow)
        XCTAssertTrue(session.calls.isEmpty)
    }

    // MARK: A game's save states

    func testASaveKeepsThePictureItIsGivenBesideTheStateAndTheSlotsAreReadAgain() async throws {
        let (session, game, root) = try await started()
        let states = saveStates(game, root, picture: { _, _ in Data([7, 7, 7]) })
        XCTAssertTrue(states.available)
        XCTAssertFalse(states.anySaved)
        session.callResults["saveState"] = try saved()
        hostWritesStates(session, states.folder)
        var outcome = await states.save(4)
        XCTAssertEqual(outcome, .done)
        XCTAssertFalse(states.slot(4).empty)
        XCTAssertNil(states.slot(4).picture, "no frame was shown, so no picture was kept")
        XCTAssertFalse(exists(states.folder.picturePath(4)))
        XCTAssertTrue(states.anySaved)

        let frame = FakeSlot(4, 4)
        frame.fill([10, 20, 30, 255])
        session.send(frame.pin())
        await settleRetro({ game.picture.image != nil })
        outcome = await states.save(5)
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(states.slot(5).picture, Data([7, 7, 7]), "the frame shown is kept beside the state")
        withExtendedLifetime(frame) {}
    }

    func testASaveThatDidNotWorkTakesThePictureAwayUnlessTheCoreRefusedIt() async throws {
        let (session, game, root) = try await started()
        let states = saveStates(game, root)
        try write([1], states.folder.statePath(2))
        try write([9], states.folder.picturePath(2))
        let recording = try recording()

        session.callErrors["saveState"] = try recording.error(RetroCallError.coreRefused)
        var outcome = await states.save(2)
        XCTAssertEqual(outcome, .coreRefused)
        XCTAssertEqual(FileManager.default.contents(atPath: states.folder.picturePath(2)), Data([9]), "the core gave no state: the slot is as it was")

        session.callErrors["saveState"] = try recording.error(RetroCallError.fileError)
        outcome = await states.save(2)
        XCTAssertEqual(outcome, .fileError)
        XCTAssertFalse(exists(states.folder.picturePath(2)), "a late write may still put the new state in the slot")
        XCTAssertFalse(states.slot(2).empty)

        try write([9], states.folder.picturePath(2))
        session.callErrors = [:]
        session.callResults["saveState"] = .bool(false)
        let path = states.folder.statePath(2)
        session.onCall = { _, _ in try? Data([2]).write(to: URL(fileURLWithPath: path)) }
        outcome = await states.save(2)
        XCTAssertEqual(outcome, .notNow)
        XCTAssertFalse(exists(states.folder.picturePath(2)),
                       "a host that wrote the state and went away answers false, as the client reports a host failure")
    }

    func testAGameClosedWhileItsPictureIsMadeWritesNoPicture() async throws {
        let (session, game, root) = try await started()
        let drawing = RetroLatch<Data?>()
        let states = saveStates(game, root, picture: { _, _ in await drawing.wait() })
        session.callResults["saveState"] = try saved()
        hostWritesStates(session, states.folder)
        let frame = FakeSlot(4, 4)
        frame.fill([10, 20, 30, 255])
        session.send(frame.pin())
        await settleRetro({ game.picture.image != nil })
        let saving = Task { await states.save(0) }
        await settleRetro({ FileManager.default.fileExists(atPath: states.folder.statePath(0)) })
        await yieldRetro()
        states.dispose()
        drawing.complete(Data([7]))
        let outcome = await saving.value
        XCTAssertEqual(outcome, .done)
        XCTAssertFalse(exists(states.folder.picturePath(0)))
        withExtendedLifetime(frame) {}
    }

    func testOneSaveOrLoadAtATimeAndASlotFoundEmptyIsReadAgain() async throws {
        let (session, game, root) = try await started()
        let states = saveStates(game, root)
        try write([1], states.folder.statePath(1))
        await states.refresh()
        XCTAssertFalse(states.slot(1).empty)

        let gate = RetroGate()
        session.callGate = gate
        session.callResults["loadState"] = try loaded()
        let first = Task { await states.load(1) }
        await settleRetro({ states.busy })
        let second = await states.save(2)
        XCTAssertEqual(second, .notNow, "one at a time")
        XCTAssertEqual(states.running?.slot, 1)
        XCTAssertEqual(states.running?.saving, false)
        gate.open()
        let outcome = await first.value
        XCTAssertEqual(outcome, .done)
        XCTAssertFalse(states.busy)

        session.callGate = nil
        try FileManager.default.removeItem(atPath: states.folder.statePath(1))
        session.callErrors["loadState"] = try recording().error(RetroCallError.noState)
        let empty = await states.load(1)
        XCTAssertEqual(empty, .noState)
        XCTAssertTrue(states.slot(1).empty)
    }
}
