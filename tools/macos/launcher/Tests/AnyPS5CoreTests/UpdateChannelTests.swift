import XCTest
@testable import AnyPS5Core

final class UpdateChannelTests: XCTestCase {
    func v(_ text: String) -> Updates.Version { Updates.Version(text)! }

    /// The order the scheme promises: a release, builds past it, its next release's nightlies by
    /// day and count, then that release.
    func testNightliesSortBetweenTheReleases() {
        let ordered = ["v0.2.16-arm", "0.2.16-arm-766-gee1fab911", "v0.2.17-arm-nightly.20261025.1", "0.2.17-arm-nightly.20261025.1-3-gabc1234",
                       "v0.2.17-arm-nightly.20261025.2", "v0.2.17-arm-nightly.20261026.1", "v0.2.17-arm", "v0.2.18-arm-nightly.20261101.1", "v0.3.0-arm"]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(v(a), v(b), "\(a) should come before \(b)")
            XCTAssertTrue(Updates.isNewer(b, than: a))
            XCTAssertFalse(Updates.isNewer(a, than: b))
        }
    }

    func testTheNightlyPartIsReadAndShown() {
        let nightly = v("v0.2.17-arm-nightly.20261025.1")
        XCTAssertEqual(nightly.numbers, [0, 2, 17])
        XCTAssertEqual(nightly.nightly?.day, 20261025)
        XCTAssertEqual(nightly.nightly?.count, 1)
        XCTAssertEqual(nightly.description, "0.2.17-nightly.20261025.1")
        XCTAssertTrue(nightly.isNightly)
        XCTAssertEqual(v("v0.2.16-arm").description, "0.2.16")
        XCTAssertFalse(v("0.2.16-arm-766-gee1fab911").isNightly)
        XCTAssertEqual(v("0.2.17-arm-nightly.20261025.1-3-gabc1234").build, 3)
    }

    func testAMalformedNightlyIsNoVersion() {
        XCTAssertNil(Updates.Version("v0.2.17-arm-nightly.2026"))
        XCTAssertNil(Updates.Version("v0.2.17-arm-nightly.x.1"))
        XCTAssertNil(Updates.Version("nightly"))
        XCTAssertFalse(Updates.isNewer("v0.2.17-arm-nightly.oops", than: "0.2.16-arm"))
    }

    /// A list as GitHub sends it: newest created first, a draft, a nightly, a release without the
    /// app, and an older release.
    static func list(_ releases: [(tag: String, pre: Bool, draft: Bool, app: Bool, published: String)]) -> Data {
        let items: [[String: Any]] = releases.map { item in
            ["tag_name": item.tag, "html_url": "https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/\(item.tag)", "draft": item.draft, "prerelease": item.pre,
             "published_at": item.published,
             "assets": item.app ? [["name": "AnyPS5-macOS.zip", "browser_download_url": "https://example.com/\(item.tag).zip", "size": 1]] : []]
        }
        return try! JSONSerialization.data(withJSONObject: items)
    }

    static let github = list([
        ("v0.2.18-arm", false, true, true, "2026-10-26T10:00:00Z"),
        ("v0.2.17-arm-nightly.20261025.2", true, false, true, "2026-10-25T20:00:00Z"),
        ("v0.2.17-arm-nightly.20261025.1", true, false, true, "2026-10-25T08:00:00Z"),
        ("v0.2.17-arm-nightly.20261026.1", true, false, false, "2026-10-26T08:00:00Z"),
        ("v0.2.16-arm", false, false, true, "2026-10-24T12:00:00Z"),
        ("v0.2.15-arm", false, false, true, "2026-10-23T12:00:00Z"),
    ])

    func testEachChannelOffersItsNewestRelease() throws {
        let releases = try XCTUnwrap(Updates.releases(from: Self.github))
        XCTAssertFalse(releases.contains { $0.tag == "v0.2.18-arm" }, "a draft was listed")
        XCTAssertEqual(Updates.newest(releases, channel: .stable)?.tag, "v0.2.16-arm")
        let nightly = try XCTUnwrap(Updates.newest(releases, channel: .nightly))
        // The 26th's nightly has no app yet: the 25th's second one is the newest to install.
        XCTAssertEqual(nightly.tag, "v0.2.17-arm-nightly.20261025.2")
        XCTAssertEqual(nightly.version, "0.2.17-nightly.20261025.2")
        XCTAssertTrue(nightly.prerelease)
        XCTAssertNotNil(nightly.published)
    }

    /// A list in another order than the versions' still gives the highest version.
    func testTheNewestIsByVersionNotByPlaceInTheList() throws {
        let data = Self.list([
            ("v0.2.15-arm", false, false, true, "2026-10-26T12:00:00Z"),
            ("v0.2.17-arm-nightly.20261025.1", true, false, true, "2026-10-25T08:00:00Z"),
            ("v0.2.17-arm", false, false, true, "2026-10-25T12:00:00Z"),
        ])
        let releases = try XCTUnwrap(Updates.releases(from: data))
        XCTAssertEqual(Updates.newest(releases, channel: .nightly)?.tag, "v0.2.17-arm", "the release outranks its own nightlies")
        XCTAssertEqual(Updates.newest(releases, channel: .stable)?.tag, "v0.2.17-arm")
    }

    func testTheEnginePickerListsNightlyToolkitsOnlyOnNightly() {
        func entry(_ release: String, _ pre: Bool) -> EngineCatalogue.Entry {
            EngineCatalogue.Entry(release: release, tag: "v" + release, title: release, summary: "", date: nil, page: URL(string: "https://x")!,
                                  download: URL(string: "https://x/\(release).zip")!, size: nil, digest: nil, prerelease: pre)
        }
        let entries = [entry("0.2.17-arm-nightly.20261025.1", true), entry("0.2.16-arm", false)]
        XCTAssertEqual(EngineCatalogue.offered(entries, channel: .stable).map(\.release), ["0.2.16-arm"])
        XCTAssertEqual(EngineCatalogue.offered(entries, channel: .nightly).map(\.release), ["0.2.17-arm-nightly.20261025.1", "0.2.16-arm"])
    }
}

/// The channels against a fake GitHub.
final class UpdateChannelLookupTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChannelStub.self]
        session = URLSession(configuration: configuration)
        ChannelStub.asked = []
        ChannelStub.latest = Data(#"{"tag_name":"v0.2.16-arm","html_url":"https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.16-arm","draft":false,"prerelease":false,"assets":[{"name":"AnyPS5-macOS.zip","browser_download_url":"https://example.com/a.zip","size":1}]}"#.utf8)
        ChannelStub.list = UpdateChannelTests.github
    }

    /// Switching to Nightly finds the newest nightly at once.
    func testNightlyOffersTheNewestNightly() async {
        let found = await Updates.lookup(current: "0.2.16-arm", channel: .nightly, session: session)
        guard case .newer(let release) = found else { return XCTFail("no nightly offered: \(found)") }
        XCTAssertEqual(release.tag, "v0.2.17-arm-nightly.20261025.2")
        XCTAssertEqual(ChannelStub.asked, ["/repos/AnyTogether/AnyPS5-ARM/releases"])
    }

    /// Stable keeps asking for the latest release, as before the channels.
    func testStableAsksForTheLatestRelease() async {
        let found = await Updates.lookup(current: "0.2.15-arm", channel: .stable, session: session)
        guard case .newer(let release) = found else { return XCTFail("no release offered: \(found)") }
        XCTAssertEqual(release.tag, "v0.2.16-arm")
        XCTAssertEqual(ChannelStub.asked, ["/repos/AnyTogether/AnyPS5-ARM/releases/latest"])
    }

    /// Back on Stable from a nightly: the older stable release is never offered...
    func testBackOnStableNeverGoesBack() async {
        let found = await Updates.lookup(current: "0.2.17-arm-nightly.20261025.2", channel: .stable, session: session)
        XCTAssertEqual(found, .current)
    }

    /// ...but the release the nightly led to is.
    func testBackOnStableTakesTheNewerRelease() async {
        ChannelStub.latest = Data(#"{"tag_name":"v0.2.17-arm","html_url":"https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.17-arm","draft":false,"prerelease":false,"assets":[{"name":"AnyPS5-macOS.zip","browser_download_url":"https://example.com/a.zip","size":1}]}"#.utf8)
        let found = await Updates.lookup(current: "0.2.17-arm-nightly.20261025.2", channel: .stable, session: session)
        guard case .newer(let release) = found else { return XCTFail("the release was not offered: \(found)") }
        XCTAssertEqual(release.version, "0.2.17")
    }

    func testTheNewestNightlyRunningIsUpToDate() async {
        let found = await Updates.lookup(current: "0.2.17-arm-nightly.20261025.2", channel: .nightly, session: session)
        XCTAssertEqual(found, .current)
    }

    func testAListThatIsNoListIsAFailure() async {
        ChannelStub.list = Data(#"{"message":"API rate limit exceeded"}"#.utf8)
        let found = await Updates.lookup(current: "0.2.16-arm", channel: .nightly, session: session)
        XCTAssertEqual(found, .failed)
    }
}

/// Answers /releases/latest and /releases with the bodies set for the test.
final class ChannelStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var latest = Data()
    nonisolated(unsafe) static var list = Data()
    nonisolated(unsafe) static var asked: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        ChannelStub.asked.append(path)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: path.hasSuffix("/latest") ? ChannelStub.latest : ChannelStub.list)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
