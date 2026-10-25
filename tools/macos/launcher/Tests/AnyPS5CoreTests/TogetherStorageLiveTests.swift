import AVFoundation
import Foundation
import XCTest
@testable import AnyPS5Core

/// Cloud saves and media against a real AnyTogether API with storage on. Skipped unless
/// ANYTOGETHER_E2E_URL names the server and ANYTOGETHER_E2E_MAILLOG its log (MAIL_TRANSPORT=log
/// writes the sign-in codes there), e.g. a local API started with STORAGE_DIR in a temp folder.
final class TogetherStorageLiveTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["ANYTOGETHER_E2E_URL"] != nil else { throw XCTSkip("no ANYTOGETHER_E2E_URL") }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString.prefix(8))")
    }

    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// A new account on the server, signed in with the code from its log.
    func signIn(_ name: String) async throws -> TogetherClient {
        let env = ProcessInfo.processInfo.environment
        let base = URL(string: env["ANYTOGETHER_E2E_URL"]!)!
        let client = TogetherClient(base: base, store: TokenStore(file: root.appendingPathComponent("\(name).json")), clientName: "launcher-macos/0.2.99 (e2e)")
        let email = "\(name)-\(UUID().uuidString.prefix(6).lowercased())@example.com"
        try await client.startEmail(email)
        var code: String?
        for _ in 0 ..< 40 where code == nil {
            try await Task.sleep(for: .milliseconds(150))
            let log = (try? String(contentsOfFile: env["ANYTOGETHER_E2E_MAILLOG"] ?? "", encoding: .utf8)) ?? ""
            code = log.components(separatedBy: "\n").last { $0.contains("sign-in code for \(email):") }?
                .components(separatedBy: ": ").last?.prefix(6).description
        }
        _ = try await client.verifyEmail(email, code: try XCTUnwrap(code, "no code in the log"))
        return client
    }

    func game(_ mac: String) -> URL { root.appendingPathComponent("\(mac)/game") }

    func save(_ text: String, on mac: String, bytes: Int) throws {
        let file = game(mac).appendingPathComponent("_sd/savedata0/save.dat")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data((text + "\n").utf8)
        data.append(Data((0 ..< bytes).map { _ in UInt8.random(in: 0 ... 255) }))
        try data.write(to: file)
    }

    func read(on mac: String) -> String? {
        (try? Data(contentsOf: game(mac).appendingPathComponent("_sd/savedata0/save.dat"))).map { String(decoding: $0.prefix { $0 != 0x0A }, as: UTF8.self) }
    }

    func engine(_ client: TogetherClient, _ mac: String, choose: TogetherCloudSave.ConflictChoice = .notNow) -> TogetherCloudSave {
        TogetherCloudSave(client: client, game: game(mac), titleID: "PPSA01234", backups: root.appendingPathComponent("\(mac)/Backups"),
                          workspace: root.appendingPathComponent("\(mac)/Cloud"), device: "Mac \(mac)", launcherVersion: "0.2.99",
                          questions: .init(conflict: { _ in choose }, replaceLatest: { _, _ in false }))
    }

    func testSavesGoUpInPartsComeDownConflictAndRestore() async throws {
        let client = try await signIn("saves")
        let info = try await client.storageInfo()
        XCTAssertTrue(info.enabled)
        // 9 MB of saves that do not compress: three 4 MiB parts.
        try save("level 1", on: "A", bytes: 9 * 1_048_576)
        let up = try await engine(client, "A").sync()
        XCTAssertEqual(up, .uploaded(version: 1))
        let down = try await engine(client, "B").sync()
        XCTAssertEqual(down, .downloaded(version: 1, from: "Mac A"))
        XCTAssertEqual(read(on: "B"), "level 1")
        XCTAssertEqual(try Data(contentsOf: game("A").appendingPathComponent("_sd/savedata0/save.dat")),
                       try Data(contentsOf: game("B").appendingPathComponent("_sd/savedata0/save.dat")))

        // Both play on: B uploads first, A is asked and keeps its own over B's.
        try save("B level 2", on: "B", bytes: 1000)
        let bUp = try await engine(client, "B").sync()
        XCTAssertEqual(bUp, .uploaded(version: 2))
        try save("A level 3", on: "A", bytes: 1000)
        let kept = try await engine(client, "A", choose: .keepThisMac).sync()
        XCTAssertEqual(kept, .uploaded(version: 3))
        let slots = try await client.saveSlots(titleId: "PPSA01234").slots
        XCTAssertEqual(slots.first?.versions.map(\.version), [3, 2, 1])

        // Version 1 restored becomes 4 (the oldest, 1, goes to keep three) and comes down to B.
        let first = try XCTUnwrap(slots.first?.versions.last)
        let restored = try await client.restoreSaveVersion(first.id)
        XCTAssertEqual(restored.version, 4)
        let back = try await engine(client, "B", choose: .takeCloud).sync()
        XCTAssertEqual(back, .downloaded(version: 4, from: "Mac A"))
        XCTAssertEqual(read(on: "B"), "level 1")

        let overview = try await client.storage()
        XCTAssertEqual(overview.saves.first?.versions.count, 3)
        XCTAssertGreaterThan(overview.usage?.saves ?? 0, 9 * 1_048_576)
        try await client.deleteSaveSlot(try XCTUnwrap(overview.saves.first?.id))
        let after = try await client.storage()
        XCTAssertTrue(after.saves.isEmpty)
    }

    func testAScreenshotAndALauncherClipGoUpIntoAChatAndTheGallery() async throws {
        let ada = try await signIn("ada")
        let bob = try await signIn("bob")
        let bobHandle = try XCTUnwrap(bob.user?.handle)
        _ = try await ada.askFriend(bobHandle)
        try await bob.answerFriend(try XCTUnwrap(ada.user?.id), accept: true)

        // A screenshot as the launcher sends it.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let shot = root.appendingPathComponent("PPSA01234-20261025-120000.png")
        try picture(640, 360).write(to: shot)
        let ready = try MediaPrep.image(shot, maxBytes: 10 * 1_048_576)
        let photo = try await ada.uploadMedia(kind: "image", data: ready.data, contentType: ready.contentType).media
        XCTAssertEqual(photo.kind, "image")
        XCTAssertEqual(photo.contentType, "image/webp")
        let conversation = try await ada.conversation(with: try XCTUnwrap(bob.user?.id))
        let sent = try await ada.send(media: photo.id, caption: "look", in: conversation.id)
        XCTAssertEqual(sent.kind, "image")
        XCTAssertEqual(sent.caption, "look")
        let seen = try await bob.messages(in: conversation.id).messages.last
        XCTAssertEqual(seen?.attachment?.media?.id, photo.id)
        let thumb = try XCTUnwrap(seen?.attachment?.media?.thumb.flatMap(URL.init(string:)))
        let (data, response) = try await URLSession.shared.data(from: thumb)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "the signed link needs no token")
        XCTAssertGreaterThan(data.count, 100)

        // A clip as the launcher records it (H.264 and AAC), with a poster.
        let clipFile = root.appendingPathComponent("PPSA01234-20261025-120100.mp4")
        try await clip(to: clipFile)
        let clipReady = try await MediaPrep.clip(clipFile, maxBytes: 25 * 1_048_576)
        let clip = try await ada.uploadMedia(kind: "clip", data: try Data(contentsOf: clipReady), contentType: "video/mp4").media
        XCTAssertEqual(clip.kind, "clip")
        let still = await MediaPrep.poster(clipReady)
        let poster = try XCTUnwrap(still)
        let withPoster = try await ada.setPoster(clip.id, data: poster, contentType: "image/jpeg")
        XCTAssertNotNil(withPoster.poster)

        // Pinned to Ada's gallery; Bob, a friend, sees it with the default setting.
        let pinned = try await ada.pinToGallery(clip.id)
        XCTAssertTrue(pinned)
        let gallery = try await bob.gallery(of: try XCTUnwrap(ada.user?.handle))
        XCTAssertEqual(gallery.value?.map(\.id), [clip.id])
        let profile = try await ada.myProfile()
        XCTAssertEqual(profile.privacy[.gallery], .friends)
        _ = try await ada.updatePrivacy(.gallery, to: .nobody)
        let closed = try await bob.gallery(of: try XCTUnwrap(ada.user?.handle))
        XCTAssertEqual(closed, .private)

        let overview = try await ada.storage()
        XCTAssertEqual(Set(overview.media.map(\.id)), [photo.id, clip.id])
        XCTAssertGreaterThan(overview.usage?.media ?? 0, 0)
        try await ada.deleteMedia(photo.id)
        let gone = try await bob.messages(in: conversation.id).messages.last
        XCTAssertEqual(gone?.attachment?.removed, true)
    }

    func picture(_ width: Int, _ height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// Three seconds of frames and silence through the launcher's own clip encoder.
    func clip(to file: URL) async throws {
        let encoder = ClipEncoder(length: 3)
        for frame in 0 ..< 3 * 30 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 2), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            encoder.addFrame(buffer!, at: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        try await encoder.save(to: file)
    }
}
