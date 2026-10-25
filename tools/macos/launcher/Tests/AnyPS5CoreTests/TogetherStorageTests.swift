import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AnyPS5Core

/// Whether a server keeps files, media in messages, the gallery and media going up.
final class TogetherStorageTests: XCTestCase {
    var folder: URL!
    var client: TogetherClient!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        FakeTogether.requests = []
        FakeTogether.delay = 0
        let store = TokenStore(file: folder.appendingPathComponent("session.json"))
        store.save(.init(accessToken: "access", accessExpiry: Date().addingTimeInterval(3600), refreshToken: "refresh",
                         user: TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)))
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: store, session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
    }

    override func tearDown() {
        FakeTogether.handler = nil
        try? FileManager.default.removeItem(at: folder)
    }

    static let media: [String: Any] = [
        "id": "0190a000-0000-7000-8000-000000000001", "kind": "image", "contentType": "image/webp", "size": 81234, "width": 1920, "height": 1080,
        "durationMs": NSNull(), "url": "https://anytogether.test/api/v1/files/media/1/file?e=1&s=x", "thumb": "https://anytogether.test/api/v1/files/media/1/thumb?e=1&s=x",
        "poster": NSNull(), "createdAt": "2026-10-25T10:00:00.000Z",
    ]

    func message(_ extra: [String: Any]) -> [String: Any] {
        ["id": "m1", "conversationId": "c1", "seq": 4, "authorId": "u2", "text": "hi", "replyTo": NSNull(), "editedAt": NSNull(), "deletedAt": NSNull(),
         "createdAt": "2026-10-25T10:00:00.000Z"].merging(extra) { _, new in new }
    }

    func decode(_ json: [String: Any]) throws -> TogetherMessage {
        try JSONDecoder.together.decode(TogetherMessage.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testAServerWithoutStorageSaysSoWithoutSigningIn() async throws {
        FakeTogether.handler = { _, _ in (200, ["enabled": false]) }
        let info = try await client.storageInfo()
        XCTAssertFalse(info.enabled)
        XCTAssertNil(FakeTogether.requests.first?.0.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(FakeTogether.requests.first?.0.url?.path, "/api/v1/storage")
    }

    func testAServerWithStorageGivesItsLimits() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["enabled": true, "quota": 104_857_600, "saveMax": 52_428_800, "saveVersions": 3, "partSize": 4_194_304,
                   "media": ["image": 10_485_760, "clip": 26_214_400, "voice": 1_048_576, "poster": 2_097_152, "voiceMs": 60000, "pixels": 40_000_000], "galleryMax": 12])
        }
        let info = try await client.storageInfo()
        XCTAssertTrue(info.enabled)
        XCTAssertEqual(info.quota, 100 * 1_048_576)
        XCTAssertEqual(info.partSize, 4 * 1_048_576)
        XCTAssertEqual(info.media.clip, 25 * 1_048_576)
        XCTAssertEqual(info.galleryMax, 12)
    }

    func testTheOverviewReadsUsageSavesAndMedia() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["enabled": true, "usage": ["used": "5242880", "limit": 104_857_600, "saves": 4_194_304, "media": 1_048_576],
                   "saves": [["id": "s1", "titleId": "PPSA01234", "game": NSNull(), "slot": "AnyPS5 saves", "updatedAt": "2026-10-25T10:00:00Z",
                              "versions": [["id": "v1", "version": 2, "size": 4_194_304, "sha256": String(repeating: "a", count: 64), "device": "Mac", "launcherVersion": "0.2.14",
                                            "createdAt": "2026-10-25T10:00:00.000Z", "download": "https://x"]]]],
                   "media": [Self.media], "next": NSNull()])
        }
        let overview = try await client.storage()
        XCTAssertEqual(overview.usage?.used, 5 * 1_048_576, "a big count may come as text")
        XCTAssertEqual(overview.usage?.fraction ?? 0, 0.05, accuracy: 0.001)
        XCTAssertEqual(overview.saves.first?.latest?.version, 2)
        XCTAssertEqual(overview.saves.first?.size, 4_194_304)
        XCTAssertEqual(overview.media.first?.kind, "image")
    }

    func testAMessageFromAServerWithoutMediaStillReads() throws {
        let plain = try decode(message([:]))
        XCTAssertNil(plain.kind)
        XCTAssertNil(plain.attachment)
        XCTAssertEqual(plain.words, "hi")
    }

    func testAPhotoMessageReadsItsAttachmentAndCaption() throws {
        let photo = try decode(message(["kind": "image", "text": "look", "caption": "look", "attachments": [Self.media]]))
        XCTAssertEqual(photo.kind, "image")
        XCTAssertEqual(photo.attachment?.media?.width, 1920)
        XCTAssertEqual(photo.attachment?.media?.still, Self.media["thumb"] as? String)
        XCTAssertEqual(photo.words, "look")
        let bare = try decode(message(["kind": "image", "text": "[photo]", "caption": NSNull(), "attachments": [Self.media]]))
        XCTAssertNil(bare.words, "the stand-in is not shown as words")
    }

    func testRemovedAndBlockedAttachmentsSaySo() throws {
        let removed = try decode(message(["kind": "clip", "text": "[clip]", "attachments": [["id": "x", "kind": "clip", "removed": true]]]))
        XCTAssertEqual(removed.attachment?.removed, true)
        XCTAssertNil(removed.attachment?.media)
        let blocked = try decode(message(["kind": "voice", "text": "[voice note]", "attachments": [["id": "y", "kind": "voice", "blocked": true]]]))
        XCTAssertEqual(blocked.attachment?.blocked, true)
    }

    func testAClipAndAVoiceNoteRead() throws {
        var clip = Self.media
        clip["kind"] = "clip"
        clip["contentType"] = "video/mp4"
        clip["durationMs"] = 30000
        clip["poster"] = "https://anytogether.test/poster"
        clip["thumb"] = NSNull()
        let message = try decode(message(["kind": "clip", "attachments": [clip]]))
        XCTAssertEqual(message.attachment?.media?.durationMs, 30000)
        XCTAssertEqual(message.attachment?.media?.still, "https://anytogether.test/poster", "a clip shows its poster")
    }

    func testSendingMediaPutsItInTheMessage() async throws {
        FakeTogether.handler = { request, _ in
            switch request.url!.path {
            case "/api/v1/me/media": return (201, ["media": Self.media, "usage": ["used": 1, "limit": 2, "saves": 0, "media": 1]])
            default: return (201, self.message(["kind": "image", "authorId": "u1", "attachments": [Self.media]]))
            }
        }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        let uploaded = try await client.uploadMedia(kind: "image", data: png, contentType: "image/png")
        XCTAssertEqual(uploaded.media.id, Self.media["id"] as? String)
        let upload = try XCTUnwrap(FakeTogether.requests.first)
        XCTAssertEqual(upload.0.url?.query, "kind=image")
        XCTAssertEqual(upload.0.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(upload.1, png)
        let sent = try await client.send(media: uploaded.media.id, caption: " gg ", in: "c1")
        XCTAssertEqual(sent.kind, "image")
        let body = try JSONSerialization.jsonObject(with: FakeTogether.requests[1].1 ?? Data()) as? [String: Any]
        XCTAssertEqual((body?["attachments"] as? [[String: String]])?.first?["mediaId"], Self.media["id"] as? String)
        XCTAssertEqual(body?["text"] as? String, "gg")
    }

    func testAPrivateGalleryIsPrivateAndAnOpenOneShows() async throws {
        FakeTogether.handler = { request, _ in
            request.url!.path.contains("/ece/") ? (403, ["code": "forbidden", "status": 403, "title": "This gallery is private"]) : (200, ["items": [Self.media]])
        }
        let closed = try await client.gallery(of: "@ece")
        XCTAssertEqual(closed, .private)
        let open = try await client.gallery(of: "mert")
        XCTAssertEqual(open.value?.count, 1)
    }

    func testPinningAddsToTheEndAndAFullGallerySaysSo() async throws {
        var pinned = ["a", "b"]
        FakeTogether.handler = { request, body in
            if request.httpMethod == "PUT", let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: [String]] { pinned = json["items"] ?? [] }
            return (200, ["items": pinned.map { id -> [String: Any] in var item = Self.media; item["id"] = id; return item }])
        }
        let added = try await client.pinToGallery("c")
        XCTAssertTrue(added)
        XCTAssertEqual(pinned, ["a", "b", "c"])
        let full = try await client.pinToGallery("d", max: 3)
        XCTAssertFalse(full)
    }

    /// The `gallery` privacy key a newer server sends does not trip the launcher's profile reading.
    func testAProfileWithTheGalleryPrivacyKeyReads() throws {
        let json: [String: Any] = ["userId": "u2", "handle": "ece", "displayName": "Ece", "avatar": NSNull(), "bio": NSNull(), "country": NSNull(), "friendship": "friends",
                                   "privacy": ["library": "friends", "trophies": "friends", "friends": "friends", "presence": "friends", "search": "everyone", "gallery": "everyone"]]
        let profile = try JSONDecoder.together.decode(TogetherProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(profile.handle, "ece")
    }

    func testTheGalleryPrivacyReadsAndDefaultsToFriends() throws {
        let with = try JSONDecoder.together.decode(TogetherOwnProfile.self, from: JSONSerialization.data(withJSONObject: [
            "handle": "utku", "displayName": "Utku", "privacy": ["library": "everyone", "gallery": "nobody", "someday": ["nested": true]],
        ]))
        XCTAssertEqual(with.privacy[.gallery], .nobody)
        XCTAssertEqual(with.privacy[.library], .everyone)
        let without = try JSONDecoder.together.decode(TogetherOwnProfile.self, from: JSONSerialization.data(withJSONObject: [
            "handle": "utku", "displayName": "Utku", "privacy": ["library": "friends"],
        ]))
        XCTAssertEqual(without.privacy[.gallery], .friends, "an older server: the default")
    }

    // MARK: Getting media ready

    func picture(width: Int, height: Int) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Noise in every pixel, so it does not compress away.
        let pixels = context.data!.bindMemory(to: UInt32.self, capacity: width * height)
        var seed: UInt32 = 0x1234_5678
        for index in 0 ..< width * height {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[index] = seed
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("shot-\(width).png")
        let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return file
    }

    func testAScreenshotThatFitsGoesAsItIs() throws {
        let file = try picture(width: 320, height: 180)
        let ready = try MediaPrep.image(file, maxBytes: 10 * 1_048_576)
        XCTAssertEqual(ready.contentType, "image/png")
        XCTAssertEqual(ready.data, try Data(contentsOf: file))
    }

    func testAScreenshotTooBigBecomesASmallerJPEG() throws {
        let file = try picture(width: 1600, height: 900)
        let size = try Data(contentsOf: file).count
        XCTAssertGreaterThan(size, 4_000_000, "the noise compressed")
        let ready = try MediaPrep.image(file, maxBytes: 1_048_576)
        XCTAssertEqual(ready.contentType, "image/jpeg")
        XCTAssertLessThanOrEqual(ready.data.count, 1_048_576)
        XCTAssertEqual(ready.data.prefix(2), Data([0xFF, 0xD8]))
    }
}
