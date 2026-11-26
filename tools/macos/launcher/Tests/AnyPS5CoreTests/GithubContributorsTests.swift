import XCTest
@testable import AnyPS5Core

/// Answers every request with the status and body set for the test, or fails it as a Mac with no
/// network does.
final class ContributorsStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var offline = false
    nonisolated(unsafe) static var asked: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        ContributorsStub.asked.append(request.url!)
        if ContributorsStub.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: ContributorsStub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ContributorsStub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Settings › About's credits as GitHub's contributors API gives them: people in its order, bots
/// left out, and no one for anything but a list of people (an error status, other JSON, no
/// network). AnyPS5 Desktop's github_contributors_test.dart.
final class GithubContributorsTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContributorsStub.self]
        session = URLSession(configuration: configuration)
        ContributorsStub.status = 200
        ContributorsStub.body = Data("[]".utf8)
        ContributorsStub.offline = false
        ContributorsStub.asked = []
    }

    func person(_ login: String, _ contributions: Int) -> [String: Any] {
        ["login": login, "avatar_url": "https://avatars.githubusercontent.com/\(login)", "html_url": "https://github.com/\(login)",
         "contributions": contributions, "type": login.hasSuffix("[bot]") ? "Bot" : "User"]
    }

    func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }

    func testThePeopleInGitHubsOrderWithoutBotsOrNamelessEntries() async {
        ContributorsStub.body = json([
            person("utkuhalis", 856), person("dependabot[bot]", 40), person("B-Howell", 119),
            ["avatar_url": "https://avatars.githubusercontent.com/x", "contributions": 3], "not a person",
            person("Lenny4250gh", 72), person("github-actions[bot]", 1),
        ])
        let people = await GithubContributors.fetch(session: session)
        XCTAssertEqual(people.map(\.login), ["utkuhalis", "B-Howell", "Lenny4250gh"])
        XCTAssertEqual(people.last, GithubContributors.Person(login: "Lenny4250gh", avatar: "https://avatars.githubusercontent.com/Lenny4250gh",
                                                              page: URL(string: "https://github.com/Lenny4250gh")!, contributions: 72))
        let asked = ContributorsStub.asked.first
        XCTAssertEqual(asked?.path, "/repos/AnyTogether/AnyPS5-Desktop/contributors", "the launcher's people, as on Windows and Linux")
        XCTAssertEqual(asked?.query, "per_page=30")
    }

    func testAnErrorStatusIsNoOne() async {
        ContributorsStub.status = 403
        ContributorsStub.body = json([person("utkuhalis", 856)])
        let forbidden = await GithubContributors.fetch(session: session)
        XCTAssertEqual(forbidden, [])
        ContributorsStub.status = 404
        let missing = await GithubContributors.fetch(session: session)
        XCTAssertEqual(missing, [])
    }

    func testJSONThatIsNoListOfPeopleIsNoOne() async {
        ContributorsStub.body = json(["message": "API rate limit exceeded"])
        let limited = await GithubContributors.fetch(session: session)
        XCTAssertEqual(limited, [])
        ContributorsStub.body = Data("not JSON at all".utf8)
        let garbled = await GithubContributors.fetch(session: session)
        XCTAssertEqual(garbled, [])
    }

    func testNoNetworkIsNoOne() async {
        ContributorsStub.offline = true
        let offline = await GithubContributors.fetch(session: session)
        XCTAssertEqual(offline, [])
    }
}
