@testable import AnyPS5
import AnyPS5Core
import XCTest

/// How a challenge's time and values read, in English and Turkish.
@MainActor
final class ChallengeTextTests: XCTestCase {
    func testTimeLeftAndValuesInBothLanguages() {
        T.texts = T.load([T.sourceFolder])
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        XCTAssertEqual(AppModel.challengeClock(.endsIn(2 * 86400 + 600)), "Ends in 2 days")
        XCTAssertEqual(AppModel.challengeClock(.startsIn(3 * 3600)), "Starts in 3 hours")
        XCTAssertEqual(AppModel.challengeClock(.endsIn(30)), "Ends in 1 minute")
        XCTAssertEqual(AppModel.challengeClock(.ended), "Ended")
        XCTAssertEqual(AppModel.challengeValue(1, metric: .trophies), "1 trophy")
        XCTAssertEqual(AppModel.challengeValue(12, metric: .trophies), "12 trophies")
        XCTAssertEqual(AppModel.challengeValue(1830, metric: .points), "1,830 pts")
        XCTAssertEqual(AppModel.challengeValue(2 * 3600 + 5 * 60, metric: .time), "2 h 5 min")
        T.language = .turkish
        // The system's unit names may be joined to the number by a no-break space.
        let plain = { (text: String) in text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(plain(AppModel.challengeClock(.endsIn(2 * 86400 + 600))), "2 gün içinde bitiyor")
        XCTAssertEqual(plain(AppModel.challengeClock(.startsIn(3 * 3600))), "3 saat sonra başlıyor")
        XCTAssertEqual(AppModel.challengeValue(12, metric: .trophies), "12 kupa")
        XCTAssertEqual(TChal.text(.title), "Meydan okumalar")
        XCTAssertEqual(TChal.format(.entrants, 4), "4 kişi katıldı")
    }

    /// Open or closed is the server's word, not this Mac's clock.
    func testAChallengeIsClosedByTheServersState() {
        let past = Date().addingTimeInterval(-86400 * 2), future = Date().addingTimeInterval(86400 * 2)
        func challenge(_ state: TogetherChallenge.State, startsAt: Date = past, endsAt: Date = future, final: Bool = false) -> TogetherChallenge {
            TogetherChallenge(id: "c", title: "Sprint", game: .init(titleId: "PPSA01234", names: [:]), metric: .points, audience: .friends, startsAt: startsAt, endsAt: endsAt, state: state, final: final)
        }
        XCTAssertTrue(challenge(.active, endsAt: past).isOpen, "the window has passed on this clock, but the server still runs it")
        XCTAssertTrue(challenge(.upcoming, startsAt: future).isOpen)
        XCTAssertFalse(challenge(.ended, endsAt: future).isOpen, "ended by the server's word, whatever this clock says")
        XCTAssertFalse(challenge(.cancelled).isOpen)
        XCTAssertFalse(challenge(.other).isOpen)
        XCTAssertTrue(challenge(.ended, endsAt: future, final: true).decided)
        XCTAssertFalse(challenge(.ended).decided, "over, not final yet")
        XCTAssertFalse(challenge(.active, endsAt: past, final: true).decided)
    }

    /// Joining or leaving refused: the server's reason in words.
    func testRefusalsReadAsTheirReason() throws {
        T.texts = T.load([T.sourceFolder])
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        let problem = { (code: String, status: Int) throws -> TogetherProblem in
            try JSONDecoder().decode(TogetherProblem.self, from: JSONSerialization.data(withJSONObject: ["status": status, "code": code, "title": ""]))
        }
        XCTAssertEqual(AppModel.challengeProblem(try problem("full", 409), leaving: false, mine: false), "This challenge is full")
        XCTAssertEqual(AppModel.challengeProblem(try problem("conflict", 409), leaving: false, mine: false), "This challenge is over")
        XCTAssertEqual(AppModel.challengeProblem(try problem("conflict", 409), leaving: true, mine: true), "You made this challenge, so you stay in it")
        XCTAssertEqual(AppModel.challengeProblem(try problem("restricted_by_family", 403), leaving: false, mine: false), "Your family settings keep challenges off")
    }
}
