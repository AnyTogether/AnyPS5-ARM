import XCTest
@testable import AnyPS5Core

/// Answers every request with the status and body set for the test.
final class ReleaseStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var cachePolicies: [URLRequest.CachePolicy] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        ReleaseStub.cachePolicies.append(request.cachePolicy)
        let response = HTTPURLResponse(url: request.url!, statusCode: ReleaseStub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ReleaseStub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UpdateLookupTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStub.self]
        session = URLSession(configuration: configuration)
        ReleaseStub.cachePolicies = []
    }

    func latest(_ tag: String) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/\#(tag)","draft":false,"prerelease":false,"assets":[{"name":"AnyPS5-macOS.zip","browser_download_url":"https://example.com/a.zip","size":1}]}"#.utf8)
    }

    func testANewerReleaseIsFound() async {
        ReleaseStub.status = 200
        ReleaseStub.body = latest("v0.2.10-arm")
        let result = await Updates.lookup(current: "0.2.9-arm", session: session)
        guard case .newer(let release) = result else { return XCTFail("no newer release: \(result)") }
        XCTAssertEqual(release.version, "0.2.10")
        XCTAssertEqual(ReleaseStub.cachePolicies, [.reloadIgnoringLocalCacheData], "a check asked a cache instead of GitHub")
    }

    func testTheSameReleaseIsUpToDate() async {
        ReleaseStub.status = 200
        ReleaseStub.body = latest("v0.2.10-arm")
        let result = await Updates.lookup(current: "0.2.10-arm", session: session)
        XCTAssertEqual(result, .current)
    }

    func testAnAnswerThatIsNoReleaseIsAFailure() async {
        ReleaseStub.status = 403
        ReleaseStub.body = Data(#"{"message":"rate limited"}"#.utf8)
        let result = await Updates.lookup(current: "0.2.9-arm", session: session)
        XCTAssertEqual(result, .failed)
    }
}
