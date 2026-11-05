@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// A tester's feedback of 5 November 2026 on AnyPS5 Desktop, brought to the Mac: a message
/// notification and a click on a conversation open that conversation, ready to answer.
@MainActor
final class MessagesOpenTests: XCTestCase {
    static let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
    static let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
    static let sol = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)

    /// Mira's pinned conversation first (its thread read with the list), then Sol's, not read yet.
    static func inbox() -> TogetherInbox {
        let now = Date()
        var inbox = TogetherInbox(me: "u1", conversations: [
            TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, mira], lastSeq: 2, readSeq: 2, unread: 0,
                                 lastMessage: TogetherMessage(id: "m2", conversationId: "c1", seq: 2, authorId: "f1", text: "GG", createdAt: now), updatedAt: now, pinned: true),
            TogetherConversation(id: "c2", kind: "direct", title: nil, members: [robin, sol], lastSeq: 3, readSeq: 3, unread: 0,
                                 lastMessage: TogetherMessage(id: "k3", conversationId: "c2", seq: 3, authorId: "f2", text: "Party tonight?", createdAt: now), updatedAt: now.addingTimeInterval(-60)),
        ])
        inbox.threads["c1"] = [TogetherMessage(id: "m2", conversationId: "c1", seq: 2, authorId: "f1", text: "GG", createdAt: now)]
        return inbox
    }

    static func messageNote(_ conversation: String) -> TogetherNotification {
        var data = TogetherNotification.Details()
        data.conversationId = conversation
        data.text = "Party tonight?"
        return TogetherNotification(id: "n1", kind: .message, actor: sol, data: data, read: true)
    }

    func testAMessageNotificationOpensItsConversationReadyToAnswer() throws {
        let model = try LauncherFixture.model()
        model.inbox = Self.inbox()
        model.open(.notifications)
        model.openNotification(Self.messageNote("c2"))
        XCTAssertEqual(model.overlay, .messages)
        XCTAssertEqual(model.selectedConversation?.id, "c2", "Sol's, not the first in the list")
        XCTAssertTrue(model.messagesInThread)
        XCTAssertNil(model.pendingConversation)
        XCTAssertNil(model.inbox?.threads["c2"], "not an empty thread: it is being read")
        XCTAssertTrue(model.threadsLoading.contains("c2"), "its messages are asked for")
        XCTAssertEqual(model.messageFocus, AppModel.quickReplies.count, "on the field")
        XCTAssertTrue(model.handle(.select))
        XCTAssertTrue(model.composing, "✕ types the answer")
    }

    func testANotificationBeforeTheListOpensItsConversationWhenTheListArrives() throws {
        let model = try LauncherFixture.model()
        model.openNotification(Self.messageNote("c2"))
        XCTAssertEqual(model.pendingConversation, "c2")
        XCTAssertFalse(model.messagesInThread)
        model.inboxArrived(Self.inbox())
        XCTAssertEqual(model.selectedConversation?.id, "c2")
        XCTAssertTrue(model.messagesInThread)
        XCTAssertNil(model.pendingConversation)
    }

    func testClickingAConversationOpensItAndReadsItsThread() throws {
        let model = try LauncherFixture.model()
        model.inbox = Self.inbox()
        model.openMessages()
        XCTAssertEqual(model.selectedConversation?.id, "c1")
        model.openConversation(at: 1)
        XCTAssertEqual(model.selectedConversation?.id, "c2")
        XCTAssertTrue(model.messagesInThread)
        XCTAssertTrue(model.threadsLoading.contains("c2"), "the thread no one read yet is asked for, not left loading")
        // Back on the first: its thread was read with the list, nothing asked again.
        model.openConversation(at: 0)
        XCTAssertEqual(model.selectedConversation?.id, "c1")
        XCTAssertFalse(model.threadsLoading.contains("c1"))
    }

    func testTheListReadAgainKeepsTheConversationOpen() throws {
        let model = try LauncherFixture.model()
        model.inbox = Self.inbox()
        model.openMessages(conversation: "c2")
        var moved = Self.inbox()
        moved.conversations.reverse()
        model.inboxArrived(moved)
        XCTAssertEqual(model.selectedConversation?.id, "c2", "the list moved, the selection did not")
    }
}

/// Settings' search field: what it finds, in the language the launcher speaks, and how the pad
/// and the arrows get to it and back.
@MainActor
final class SettingsSearchTests: XCTestCase {
    func testTheSearchFindsTitlesAndDescriptionsWhateverTheCase() throws {
        let rows = [PanelRow(id: "a", title: "Interface Sounds", kind: .info("")), PanelRow(id: "b", title: "Clips", detail: "Keeps the last 30 seconds", kind: .info("")),
                    PanelRow(id: "c", title: "", kind: .info("1.0"))]
        let categories = [PanelCategory(id: "one", title: "Behaviour", symbol: "x", rows: rows), PanelCategory(id: "two", title: "Power", symbol: "y", rows: [PanelRow(id: "d", title: "Frame cap", kind: .info(""))])]
        XCTAssertEqual(AppModel.searchSettings(categories, for: "  ", language: "en").map(\.id), ["one", "two"], "nothing typed: everything")
        XCTAssertEqual(AppModel.searchSettings(categories, for: "sounds", language: "en").flatMap(\.rows).map(\.id), ["a"])
        XCTAssertEqual(AppModel.searchSettings(categories, for: "SECONDS", language: "en").flatMap(\.rows).map(\.id), ["b"], "a description counts")
        XCTAssertEqual(AppModel.searchSettings(categories, for: "power frame", language: "en").flatMap(\.rows).map(\.id), ["d"], "every word, the category's name too")
        XCTAssertTrue(AppModel.searchSettings(categories, for: "zzz", language: "en").isEmpty)
        let turkish = [PanelCategory(id: "t", title: "Davranış", symbol: "x", rows: [PanelRow(id: "s", title: "Arayüz sesleri", kind: .info("")), PanelRow(id: "i", title: "İndirme klasörü", kind: .info(""))])]
        XCTAssertEqual(AppModel.searchSettings(turkish, for: "arayuz", language: "tr").flatMap(\.rows).map(\.id), ["s"], "accents aside")
        XCTAssertEqual(AppModel.searchSettings(turkish, for: "indirme", language: "tr").flatMap(\.rows).map(\.id), ["i"], "Turkish capitals")
    }

    func testSettingsSearchesInTheLanguageShown() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        model.settingsQuery = T.text(.sounds)
        let found = model.panelCategories()
        XCTAssertTrue(found.flatMap(\.rows).contains { $0.id == "sounds" })
        XCTAssertLessThan(found.flatMap(\.rows).count, 6)
        XCTAssertEqual(model.panelCategory, 0)
        XCTAssertFalse(model.panelInRows)
    }

    func testThePadReachesTheFieldAndComesBack() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        XCTAssertFalse(model.settingsSearchFocused)
        XCTAssertTrue(model.handle(.up), "up from the first category")
        XCTAssertTrue(model.settingsSearchFocused)
        XCTAssertTrue(model.handle(.select))
        XCTAssertTrue(model.settingsTyping, "✕ or Return types in it")
        model.settingsQuery = "vibration"
        model.leaveSettingsSearch(intoRows: true)
        XCTAssertFalse(model.settingsSearchFocused)
        XCTAssertFalse(model.settingsTyping)
        XCTAssertTrue(model.panelInRows, "Return goes to the first setting found")
        let rows = try XCTUnwrap(model.panelCategories().first?.rows)
        XCTAssertEqual(rows[model.focusedRow(in: rows)].id, "vibration")
        // ○ goes back to the categories found, then clears the search.
        XCTAssertTrue(model.handle(.back))
        XCTAssertFalse(model.panelInRows)
        XCTAssertTrue(model.handle(.back))
        XCTAssertEqual(model.settingsQuery, "")
        XCTAssertTrue(model.settingsSearchFocused)
        XCTAssertEqual(model.overlay, .settings)
        XCTAssertTrue(model.handle(.down))
        XCTAssertFalse(model.settingsSearchFocused)
        XCTAssertEqual(model.panelCategory, 0)
    }

    func testNothingFoundLeavesOnlyTheField() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        model.settingsQuery = "qwxzv"
        XCTAssertTrue(model.panelCategories().isEmpty)
        XCTAssertTrue(model.handle(.down), "the command is taken")
        XCTAssertTrue(model.handle(.up))
        XCTAssertTrue(model.settingsSearchFocused)
        XCTAssertTrue(model.handle(.down), "nothing to go down to")
        XCTAssertTrue(model.settingsSearchFocused)
        XCTAssertTrue(model.handle(.back))
        XCTAssertEqual(model.settingsQuery, "")
        XCTAssertTrue(model.handle(.back))
        XCTAssertNil(model.overlay, "○ on an empty field closes Settings")
    }

    func testOpeningSettingsAgainStartsWithoutASearch() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        model.settingsQuery = "clips"
        model.startSettingsSearch()
        model.closeOverlay()
        model.open(.settings)
        XCTAssertEqual(model.settingsQuery, "")
        XCTAssertFalse(model.settingsSearchFocused)
        XCTAssertFalse(model.settingsTyping)
    }

    func testTheSearchTextsAreTranslated() {
        XCTAssertNotEqual(T.string("settingsSearch"), "settingsSearch")
        XCTAssertTrue(T.format(.settingsSearchNone, "abc").contains("abc"))
    }
}

/// The launcher's own sounds: a volume in percent, Off at 0, kept with the preferences and given
/// to the sounds at once.
@MainActor
final class InterfaceSoundVolumeTests: XCTestCase {
    func stepper(_ model: AppModel) throws -> (value: Int, format: (Int) -> String, set: (Int) -> Void) {
        model.open(.settings)
        let row = try XCTUnwrap(model.panelCategories().flatMap(\.rows).first { $0.id == "sounds" })
        guard case .stepper(let value, let range, let step, let format, let set) = row.kind else { throw XCTSkip("not a stepper") }
        XCTAssertEqual(range, 0...100)
        XCTAssertEqual(step, 10)
        return (value, format, set)
    }

    func testTheVolumeIsAPercentWithOffAtZero() throws {
        let model = try LauncherFixture.model()
        let sounds = try stepper(model)
        XCTAssertEqual(sounds.value, 0, "the fixture has its sounds off")
        XCTAssertEqual(sounds.format(0), T.text(.off))
        XCTAssertEqual(sounds.format(40), "40%")
        sounds.set(40)
        XCTAssertTrue(model.preferences.sounds)
        XCTAssertEqual(model.preferences.soundVolume, 40)
        XCTAssertTrue(Sounds.shared.enabled)
        XCTAssertEqual(Sounds.shared.volume, 0.4, accuracy: 0.001, "the sounds play at it at once")
        XCTAssertEqual(try stepper(model).value, 40)
        try stepper(model).set(0)
        XCTAssertFalse(model.preferences.sounds, "0% is muted")
        XCTAssertFalse(Sounds.shared.enabled)
        XCTAssertEqual(try stepper(model).value, 0)
    }

    func testTheVolumeIsKept() throws {
        var preferences = Preferences()
        preferences.sounds = true
        preferences.soundVolume = 30
        let saved = try JSONEncoder().encode(preferences)
        let read = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertEqual(read.soundVolume, 30)
        XCTAssertTrue(read.sounds)
    }
}

/// The Theme Studio's − and +: each number end to end in 10 to 20 presses (the depth's ten
/// values in nine), and a held − or + keeps stepping from the value it reached.
@MainActor
final class StudioStepTests: XCTestCase {
    func testEachNumberGoesEndToEndInAFewPresses() throws {
        let model = try LauncherFixture.model()
        let neon = ThemeDesign(id: "neon", name: "Neon", author: "Robin", style: 0, deep: "#050510", middle: "#1A1040", bright: "#FF4FD8", accent: "#00E5FF")
        model.previewThemes([neon], active: neon, hub: [])
        for id in ["hue", "highlight", "depth", "accent"] {
            let row = try XCTUnwrap(model.studioRows().first { $0.id == id }, id)
            guard case .stepper(_, let range, let step, _, _) = row.kind else { return XCTFail("\(id) is not a stepper") }
            let presses = Int((Double(range.upperBound - range.lowerBound) / Double(step)).rounded(.up))
            XCTAssertTrue((9...20).contains(presses), "\(id): \(presses) presses")
        }
    }

    func testAHeldStepStepsFromTheValueItReached() throws {
        let model = try LauncherFixture.model()
        let neon = ThemeDesign(id: "neon", name: "Neon", author: "Robin", style: 0, deep: "#050510", middle: "#1A1040", bright: "#FF4FD8", accent: "#00E5FF")
        model.previewThemes([neon], active: neon, hub: [])
        model.open(.studio)
        func depth() throws -> Int {
            guard case .stepper(let value, _, _, _, _) = try XCTUnwrap(model.studioRows().first { $0.id == "depth" }).kind else { throw XCTSkip("no depth") }
            return value
        }
        let start = try depth()
        XCTAssertTrue(model.stepRow("depth", by: -1) || start == 1)
        let lower = try depth()
        XCTAssertTrue(model.stepRow("depth", by: 1))
        XCTAssertTrue(model.stepRow("depth", by: 1))
        XCTAssertEqual(try depth(), lower + 2, "each step from the value the last one left")
        while model.stepRow("depth", by: 1) {}
        XCTAssertEqual(try depth(), 10)
        XCTAssertFalse(model.stepRow("depth", by: 1), "at its end a held + stops")
    }
}

/// The phone's latency pill keeps its width: digits of one width, room for "999 ms".
final class PhoneLatencyTests: XCTestCase {
    func testTheLatencyReadsAtMostThreeDigits() {
        XCTAssertEqual(PhoneIndicator.latencyText(23.4), "23 ms")
        XCTAssertEqual(PhoneIndicator.latencyText(4200), "999 ms")
        XCTAssertEqual(PhoneIndicator.latencyText(-3), "0 ms")
    }
}

/// A phone's pad on the launcher's own screens: its Options button opens Settings (and closes
/// it), its other buttons move as a controller's; a game running takes it alone.
@MainActor
final class PhoneControlsLauncherTests: XCTestCase {
    func testThePhonesOptionsButtonOpensSettings() throws {
        let model = try LauncherFixture.model()
        model.phonePad("phone-1", PadState(pressed: [.start]), active: true)
        XCTAssertEqual(model.overlay, .settings)
        model.phonePad("phone-1", PadState(pressed: [.start]), active: true)
        XCTAssertEqual(model.overlay, .settings, "held, it does not press again")
        model.phonePad("phone-1", .idle, active: true)
        model.phonePad("phone-1", PadState(pressed: [.start]), active: true)
        XCTAssertNil(model.overlay, "pressed again in Settings: closed")
        model.phonePad("phone-1", .idle, active: true)
        XCTAssertTrue(model.phonePads.isEmpty, "a pad let go is forgotten")
    }

    func testOptionsDoesNothingWhileTheLauncherIsBehind() throws {
        let model = try LauncherFixture.model()
        model.phonePad("phone-1", PadState(pressed: [.start]), active: false)
        XCTAssertNil(model.overlay)
    }

    func testOptionsWaitsForAPairingQuestion() throws {
        let model = try LauncherFixture.model()
        model.previewPairing(PairingRequest(id: UUID(), deviceName: "Pixel 8", code: "1234"))
        model.phoneOptions(active: true)
        XCTAssertNil(model.overlay)
    }
}
