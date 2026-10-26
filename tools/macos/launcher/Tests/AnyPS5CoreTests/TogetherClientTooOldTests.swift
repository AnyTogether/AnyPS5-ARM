import Foundation
import XCTest

@testable import AnyPS5Core

/// Retired launchers: AnyTogether answers 426 "client_too_old" with the minimum version and where
/// to update; every call hands it to the launcher, which shows Update Required.
final class TogetherClientTooOldTests: TogetherSignedInCase {
    static let tooOld: [String: Any] = ["code": "client_too_old", "status": 426, "title": "This version is too old. Update to 0.3.0 or newer.",
                                        "client": "launcher-macos", "current": "0.2.13", "minimum": "0.3.0", "downloadUrl": "https://anytogether.test/download"]

    func testTheAnswerSaysTheMinimumAndWhereToUpdate() throws {
        let problem = try JSONDecoder.together.decode(TogetherProblem.self, from: JSONSerialization.data(withJSONObject: Self.tooOld))
        XCTAssertEqual(problem.clientTooOld, TogetherClientTooOld(minimum: "0.3.0", current: "0.2.13", downloadUrl: URL(string: "https://anytogether.test/download")))
        let other = try JSONDecoder.together.decode(TogetherProblem.self, from: JSONSerialization.data(withJSONObject: ["code": "conflict", "status": 409, "title": "x"]))
        XCTAssertNil(other.clientTooOld)
    }

    func testAnyCallThatIsRefusedTellsTheLauncher() async throws {
        let heard = Heard()
        client.onClientTooOld = { heard.add($0) }
        FakeTogether.handler = { _, _ in (426, Self.tooOld) }
        do {
            _ = try await client.friends()
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "client_too_old")
        }
        XCTAssertEqual(heard.all.map(\.minimum), ["0.3.0"])
        // Signed-out calls too (the sign-in screen).
        do { try await client.startEmail("u@example.com") } catch {}
        XCTAssertEqual(heard.all.count, 2)
        // Other refusals are not an update.
        FakeTogether.handler = { _, _ in (409, ["code": "conflict", "status": 409, "title": "x"]) }
        do { _ = try await client.friends() } catch {}
        XCTAssertEqual(heard.all.count, 2)
    }
}

private final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TogetherClientTooOld] = []
    func add(_ item: TogetherClientTooOld) { lock.withLock { items.append(item) } }
    var all: [TogetherClientTooOld] { lock.withLock { items } }
}
