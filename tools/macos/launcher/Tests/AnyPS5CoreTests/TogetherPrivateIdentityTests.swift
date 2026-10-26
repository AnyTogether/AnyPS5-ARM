import Foundation
import XCTest
@testable import AnyPS5Core

/// The friends-only name and picture: shown when there, the public ones when not, the handle always.
final class TogetherPrivateIdentityTests: XCTestCase {
    var folder: URL!
    var client: TogetherClient!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("private-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        FakeTogether.requests = []
        let store = TokenStore(file: folder.appendingPathComponent("s.json"))
        store.save(.init(accessToken: "access", accessExpiry: Date().addingTimeInterval(600), refreshToken: "refresh",
                         user: TogetherUser(id: "me", handle: "utku", displayName: "Utku", avatar: nil)))
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: store, session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
    }

    override func tearDown() {
        FakeTogether.handler = nil
        try? FileManager.default.removeItem(at: folder)
    }

    func decode<T: Decodable>(_ type: T.Type, _ json: Any) throws -> T {
        try JSONDecoder.together.decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testAFriendsPrivateNameAndPictureAreShownWithTheHandle() throws {
        let friend = try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "avatar": "https://x/pub.jpg",
                                                       "privateName": "Selin Kaya", "privateAvatar": "https://x/api/v1/avatars/private/h.jpg?e=1&s=2"])
        let shown = TogetherIdentity.shown(friend, book: TogetherIdentityBook())
        XCTAssertEqual(shown.name, "Selin Kaya")
        XCTAssertEqual(shown.avatar, "https://x/api/v1/avatars/private/h.jpg?e=1&s=2")
        XCTAssertEqual(shown.handle, "selin", "the handle stays next to a private name")
        XCTAssertTrue(shown.isPrivate)
        XCTAssertEqual(shown.publicName, "Night Owl")
    }

    func testAFriendWithoutThemFallsBackToThePublicOnes() throws {
        let unset = try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "avatar": "https://x/pub.jpg",
                                                      "privateName": NSNull(), "privateAvatar": NSNull()])
        let stranger = try decode(TogetherPerson.self, ["userId": "u3", "handle": "deniz", "displayName": "Deniz", "avatar": NSNull()])
        XCTAssertEqual(TogetherIdentity.shown(unset, book: TogetherIdentityBook()).name, "Night Owl", "null: not set")
        XCTAssertEqual(TogetherIdentity.shown(unset, book: TogetherIdentityBook()).avatar, "https://x/pub.jpg")
        XCTAssertFalse(TogetherIdentity.shown(unset, book: TogetherIdentityBook()).isPrivate)
        XCTAssertEqual(TogetherIdentity.shown(stranger, book: TogetherIdentityBook()).name, "Deniz", "left out: may not see")
        XCTAssertNil(TogetherIdentity.shown(stranger, book: TogetherIdentityBook()).avatar)
    }

    func testABlankPrivateNameCountsAsNone() throws {
        let friend = try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": "   "])
        XCTAssertEqual(TogetherIdentity.shown(friend, book: TogetherIdentityBook()).name, "Night Owl")
    }

    /// Realtime events never carry them: the values read over HTTP are kept by user ID.
    func testACardFromARealtimeEventKeepsWhatTheFriendsListSaid() throws {
        var book = TogetherIdentityBook()
        let friend = try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": "Selin Kaya", "privateAvatar": "https://x/p.jpg"])
        book.learn(friends: [friend])
        let fromEvent = try decode(TogetherPerson.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "avatar": NSNull()])
        let shown = TogetherIdentity.shown(fromEvent, book: book)
        XCTAssertEqual(shown.name, "Selin Kaya")
        XCTAssertEqual(shown.avatar, "https://x/p.jpg")
    }

    func testAnEndedFriendshipForgetsThem() throws {
        var book = TogetherIdentityBook()
        book.learn(friends: [try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": "Selin Kaya"])])
        book.learn(friends: [])
        let card = try decode(TogetherPerson.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl"])
        XCTAssertEqual(TogetherIdentity.shown(card, book: book).name, "Night Owl")
    }

    func testAFriendWhoClearedThemIsShownPublicAfterTheNextList() throws {
        var book = TogetherIdentityBook()
        book.learn(friends: [try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": "Selin Kaya"])])
        book.learn(friends: [try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": NSNull()])])
        let card = try decode(TogetherPerson.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl"])
        XCTAssertEqual(TogetherIdentity.shown(card, book: book).name, "Night Owl")
    }

    func testTheCardsOwnValuesWinOverTheBook() throws {
        var book = TogetherIdentityBook()
        book.learn(friends: [try decode(TogetherFriend.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": "Old Name"])])
        let party = try decode(TogetherPerson.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "privateName": "New Name"])
        XCTAssertEqual(TogetherIdentity.shown(party, book: book).name, "New Name", "a fresher HTTP answer")
    }

    func testTheOwnProfileHasThem() throws {
        let own = try decode(TogetherOwnProfile.self, ["handle": "utku", "displayName": "Utku", "privateName": "Utku Halis", "privateAvatar": "https://x/me.jpg"])
        XCTAssertEqual(own.privateName, "Utku Halis")
        XCTAssertEqual(own.privateAvatar, "https://x/me.jpg")
        let old = try decode(TogetherOwnProfile.self, ["handle": "utku", "displayName": "Utku"])
        XCTAssertNil(old.privateName)
    }

    func testAnotherProfileViewHasThem() throws {
        let profile = try decode(TogetherProfile.self, ["userId": "u2", "handle": "selin", "displayName": "Night Owl", "friendship": "friends", "privateName": "Selin Kaya"])
        XCTAssertEqual(profile.privateName, "Selin Kaya")
    }

    func testSettingAndClearingThePrivateName() async throws {
        FakeTogether.handler = { _, body in
            let changes = (try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]) ?? [:]
            return (200, ["handle": "utku", "displayName": "Utku", "privateName": changes["privateName"] is NSNull ? NSNull() : changes["privateName"] ?? NSNull()])
        }
        let set = try await client.setPrivateName("Utku Halis")
        XCTAssertEqual(set.privateName, "Utku Halis")
        XCTAssertEqual(FakeTogether.requests.last?.0.httpMethod, "PATCH")
        XCTAssertEqual(FakeTogether.requests.last?.0.url?.path, "/api/v1/me/profile")
        let cleared = try await client.setPrivateName("  ")
        XCTAssertNil(cleared.privateName)
        let sent = try JSONSerialization.jsonObject(with: FakeTogether.requests.last?.1 ?? Data()) as? [String: Any]
        XCTAssertTrue(sent?["privateName"] is NSNull, "a blank name clears it")
    }

    func testThePrivatePictureGoesUpAndIsRemoved() async throws {
        FakeTogether.handler = { request, _ in
            request.httpMethod == "PUT" ? (200, ["privateAvatar": "https://x/api/v1/avatars/private/h.jpg?e=1&s=2"]) : (204, [:])
        }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 64)
        let link = try await client.uploadPrivateAvatar(png)
        XCTAssertEqual(link, "https://x/api/v1/avatars/private/h.jpg?e=1&s=2")
        XCTAssertEqual(FakeTogether.requests.last?.0.url?.path, "/api/v1/me/avatar/private")
        XCTAssertEqual(FakeTogether.requests.last?.0.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertNil(client.user?.avatar, "the public picture is not touched")
        try await client.removePrivateAvatar()
        XCTAssertEqual(FakeTogether.requests.last?.0.httpMethod, "DELETE")
        XCTAssertEqual(FakeTogether.requests.last?.0.url?.path, "/api/v1/me/avatar/private")
    }

    func testAFriendsPrivateCardCanBeReported() async throws {
        FakeTogether.handler = { _, _ in (201, ["id": "r1"]) }
        try await client.reportPrivateProfile("u2", reason: "offensive")
        let sent = try JSONSerialization.jsonObject(with: FakeTogether.requests.last?.1 ?? Data()) as? [String: String]
        XCTAssertEqual(sent, ["targetKind": "private_profile", "targetId": "u2", "reason": "offensive"])
    }
}
