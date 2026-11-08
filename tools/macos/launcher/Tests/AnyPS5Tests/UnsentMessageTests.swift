@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// A message that did not get there stays as a bubble, sent again with its own id, as on Windows
/// and Linux.
@MainActor
final class UnsentMessageTests: XCTestCase {
    let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
    let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)

    func message(_ seq: Int, in conversation: String = "c1", text: String? = "hi") -> TogetherMessage {
        TogetherMessage(id: "m\(seq)", conversationId: conversation, seq: seq, authorId: "u1", text: text, createdAt: Date())
    }

    private var answers: [Result<TogetherMessage, Error>] = []
    private var sent: [UnsentMessage] = []

    /// A conversation in Messages; what the server answers comes from `answers`.
    func model() throws -> AppModel {
        let model = try LauncherFixture.model()
        model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let direct = TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, mira], lastSeq: 0, readSeq: 0, unread: 0, lastMessage: nil, updatedAt: Date())
        model.previewMessages(TogetherInbox(me: "u1", conversations: [direct]), index: 0, inThread: true)
        model.sendText = { [unowned self] message in
            sent.append(message)
            return try (answers.isEmpty ? .failure(URLError(.notConnectedToInternet)) : answers.removeFirst()).get()
        }
        return model
    }

    func settle(_ model: AppModel, until done: @MainActor () -> Bool = { false }) async {
        for _ in 0..<40 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testAMessageThatDoesNotGoStaysAsABubble() async throws {
        let model = try model()
        model.sendMessage("are you there?")
        await settle(model) { !model.unsentMessages.isEmpty }
        XCTAssertEqual(model.unsentMessages.map(\.text), ["are you there?"])
        XCTAssertEqual(model.messageDraft, "", "no longer in the field: the bubble keeps it")
        XCTAssertNotNil(model.toast, "said once as before")
    }

    func testTryingAgainUsesItsOwnIdAndTheBubbleLeaves() async throws {
        let model = try model()
        answers = [.failure(URLError(.timedOut))]
        model.sendMessage("hello")
        await settle(model) { !model.unsentMessages.isEmpty }
        let id = try XCTUnwrap(model.unsentMessages.first?.id)
        answers = [.success(message(1, text: "hello"))]
        // Enter on the empty field: the newest one goes again.
        model.sendMessage("")
        XCTAssertEqual(model.unsentMessages.first?.sending, true, "a try is on its way")
        await settle(model) { model.unsentMessages.isEmpty }
        XCTAssertEqual(sent.map(\.id), [id, id], "the server keeps one message per id")
        XCTAssertTrue(model.unsentMessages.isEmpty)
    }

    func testAFailedTryStaysToBeTriedAgain() async throws {
        let model = try model()
        answers = [.failure(URLError(.timedOut))]
        model.sendMessage("hello")
        await settle(model) { !model.unsentMessages.isEmpty }
        answers = [.failure(URLError(.timedOut))]
        model.retryMessage(try XCTUnwrap(model.unsentMessages.first))
        await settle(model) { model.unsentMessages.first?.sending == false && self.sent.count == 2 }
        XCTAssertEqual(model.unsentMessages.first?.sending, false)
        XCTAssertEqual(sent.count, 2)
    }

    func testPickingABubbleWithTheControllerSendsItAgain() async throws {
        let model = try model()
        model.sendMessage("hello")
        await settle(model) { !model.unsentMessages.isEmpty }
        XCTAssertTrue(model.pickMessage(-1))
        XCTAssertEqual(model.messageActions.picked, AppModel.unsentSeq(at: 0))
        answers = [.success(message(1, text: "hello"))]
        model.pickedCommand(.select)
        XCTAssertEqual(sent.count, 2)
        XCTAssertNil(model.messageActions.picked)
    }

    func testAWordsFieldThatIsNotEmptySendsThemNotTheBubble() async throws {
        let model = try model()
        model.sendMessage("first")
        await settle(model) { !model.unsentMessages.isEmpty }
        model.messageDraft = "something else"
        XCTAssertFalse(model.retryNewestUnsent())
        XCTAssertEqual(sent.count, 1)
    }

    func testSigningOutForgetsThem() async throws {
        let model = try model()
        model.sendMessage("hello")
        await settle(model) { !model.unsentMessages.isEmpty }
        model.disconnectTogether()
        XCTAssertTrue(model.unsentMessages.isEmpty)
    }
}

/// Small rows as on Windows and Linux: Copy Report, Copy the unlock error, Check family settings
/// now, Reduce transparency.
@MainActor
final class DesktopRowParityTests: XCTestCase {
    func testTheCrashReportHasCopyReport() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        let report = SessionReport(gameName: game.name, titleID: game.titleID, gameVersion: "1.00", settings: GameSettings(), system: .current(displayHz: nil),
                                   launcherVersion: "test", session: "started\nended\n", privacy: .current())
        model.overlay = .crashReport
        model.previewSessionReport(report, sharing: false)
        let row = try XCTUnwrap(model.crashReportRows().first { $0.id == "copy" })
        XCTAssertEqual(row.title, "Copy report")
        guard case .action = row.kind else { return XCTFail("an action row") }
        XCTAssertTrue(report.text().contains("AnyPS5 crash report"), "what the row copies")
    }

    func testAFailedUnlockShowsItsErrorAndCopiesIt() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        XCTAssertNil(model.failureText(game))
        model.previewFailure(game, "first line\nsecond line\nout of space")
        model.overlay = .gameSettings
        let row = try XCTUnwrap(model.panelCategories().flatMap(\.rows).first { $0.id == "unlockError" })
        XCTAssertEqual(row.title, "Unlock error")
        XCTAssertEqual(row.detail, "second line · out of space · Select to copy the whole error.")
        guard case .action = row.kind else { return XCTFail("an action row") }
        XCTAssertEqual(model.panelCategories().flatMap(\.rows).first?.id, "unlockError", "the first row")
        XCTAssertTrue(try XCTUnwrap(model.failureText(game)).hasPrefix("first line\nsecond line\nout of space"))
    }

    func testFamilySettingsCanBeCheckedNowBySomeoneWithLimits() throws {
        let model = try LauncherFixture.model()
        model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        XCTAssertFalse(model.familyRows().contains { $0.id == "family-refresh" }, "no limits, nothing to check")
        model.family = .locked
        let row = try XCTUnwrap(model.familyRows().first { $0.id == "family-refresh" })
        XCTAssertEqual(row.title, "Check family settings now")
        model.togetherUser = nil
        XCTAssertFalse(model.familyRows().contains { $0.id == "family-refresh" }, "signed out it cannot")
    }

    func testReduceTransparencyIsGlasssOwnRowAndTakesTheStepperAway() throws {
        let model = try LauncherFixture.model { $0.theme = .glass }
        model.overlay = .settings
        let appearance = { model.panelCategories().first { $0.id == "appearance" }?.rows ?? [] }
        let row = try XCTUnwrap(appearance().first { $0.id == "transparency" })
        XCTAssertEqual(row.title, "Reduce transparency")
        XCTAssertTrue(appearance().contains { $0.id == "glassTransparency" })
        guard case .toggle(let on, let set) = row.kind else { return XCTFail("a switch") }
        XCTAssertFalse(on)
        set(true)
        XCTAssertEqual(model.preferences.reduceTransparency, true)
        XCTAssertFalse(appearance().contains { $0.id == "glassTransparency" }, "nothing left to set")
        model.preferences.theme = .cosmic
        XCTAssertFalse(appearance().contains { $0.id == "transparency" }, "only Glass has any")
    }
}
