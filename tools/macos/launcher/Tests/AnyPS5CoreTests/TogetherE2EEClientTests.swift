import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AnyPS5Core

/// End-to-end encryption's calls (device keys, sealed messages and media, reports), what the
/// launcher remembers per conversation, the keys in the Keychain, and photos stripped before
/// they are sealed.
final class TogetherE2EEClientTests: TogetherSignedInCase {
    typealias E = TogetherE2EE
    typealias V = TogetherE2EETests

    var v: V.Vectors { V.vectors }

    func secrets(_ name: String) throws -> E.DeviceSecrets {
        let d = try XCTUnwrap(v.devices[name])
        return try E.DeviceSecrets(signSeed: V.hex(d.signSeed), boxSecret: V.hex(d.boxSecret))
    }

    func json(_ device: E.Device) -> [String: Any] {
        ["id": device.id, "signKey": device.signKey, "boxKey": device.boxKey, "sig": device.sig, "name": device.name ?? "Mac", "createdAt": "2026-11-06T10:00:00.000Z", "removedAt": device.removedAt ?? NSNull()]
    }

    static func message(id: String = "m1", seq: Int = 7, sealed: E.Sealed?, author: String = "u1", attachments: [[String: Any]] = []) -> [String: Any] {
        var message: [String: Any] = ["id": id, "conversationId": "c1", "seq": seq, "authorId": author, "kind": attachments.isEmpty ? "text" : "image", "text": "[encrypted message]", "caption": NSNull(),
                                      "attachments": attachments, "replyTo": NSNull(), "editedAt": NSNull(), "editCount": 0, "reactions": [], "deletedAt": NSNull(), "createdAt": "2026-11-06T10:00:00.000Z"]
        if let sealed { message["sealed"] = try! TogetherClient.json(sealed) }
        return message
    }

    // MARK: Registering

    func testADeviceRegistersOnceAndAgainOnlyWhenTheServerHasOtherKeys() async throws {
        let mac = try secrets("aliceMac")
        let alice = v.users["alice"]!
        var registered: [String: Any]?
        FakeTogether.handler = { request, body in
            switch (request.httpMethod!, request.url!.path) {
            case ("GET", "/api/v1/me/e2ee/device"):
                guard let registered else { return (404, ["code": "not_found", "title": "This device has no keys here yet", "status": 404]) }
                return (200, registered)
            case ("PUT", "/api/v1/me/e2ee/device"):
                let sent = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
                registered = sent.merging(["id": mac.deviceId, "createdAt": "2026-11-06T10:00:00.000Z", "removedAt": NSNull()]) { $1 }
                return (201, registered!)
            default: return (404, ["code": "not_found"])
            }
        }
        try await client.prepareE2EE(mac, userId: alice, name: "Utku's Mac")
        XCTAssertEqual(FakeTogether.requests.map { "\($0.0.httpMethod!) \($0.0.url!.path)" }, ["GET /api/v1/me/e2ee/device", "PUT /api/v1/me/e2ee/device"])
        let sent = try XCTUnwrap(body())
        XCTAssertEqual(Set(sent.keys), ["signKey", "boxKey", "sig", "name"], "only public keys go up")
        XCTAssertEqual(sent["signKey"] as? String, v.devices["aliceMac"]!.public.signKey)
        XCTAssertEqual(sent["boxKey"] as? String, v.devices["aliceMac"]!.public.boxKey)
        XCTAssertEqual(sent["name"] as? String, "Utku's Mac")
        XCTAssertTrue(E.verify(E.Device(id: mac.deviceId, signKey: sent["signKey"] as! String, boxKey: sent["boxKey"] as! String, sig: sent["sig"] as! String), for: alice))
        let everything = FakeTogether.requests.compactMap { $0.1 }.map { String(decoding: $0, as: UTF8.self) }.joined()
        XCTAssertFalse(everything.contains(mac.signSeed.base64EncodedString()), "the private keys never leave the Mac")
        XCTAssertFalse(everything.contains(mac.boxSecret.base64EncodedString()))

        FakeTogether.requests = []
        try await client.prepareE2EE(mac, userId: alice, name: "Utku's Mac")
        XCTAssertEqual(FakeTogether.requests.map { $0.0.httpMethod! }, ["GET"], "the same keys are there: nothing to register")
        FakeTogether.requests = []
        try await client.prepareE2EE(try secrets("alicePhone"), userId: alice, name: "Utku's Mac")
        XCTAssertEqual(FakeTogether.requests.map { $0.0.httpMethod! }, ["GET", "PUT"], "other keys: registered anew")
    }

    func testAServerWithoutTheRoutesMeansNoEncryption() async throws {
        FakeTogether.handler = { _, _ in (404, ["code": "not_found", "title": "Not found", "status": 404]) }
        do {
            try await client.prepareE2EE(try secrets("aliceMac"), userId: v.users["alice"]!, name: "Mac")
            XCTFail("a server without end-to-end encryption")
        } catch {
            XCTAssertTrue(error is TogetherE2EEUnsupported, "\(error)")
        }
    }

    func testDevicesAreAskedTwentyAtATimeAndOnlyCheckedOnesCount() async throws {
        let alice = v.users["alice"]!
        let mac = v.devices["aliceMac"]!.public, phone = v.devices["alicePhone"]!.public
        var forged = phone
        forged.boxKey = v.devices["bobDesktop"]!.public.boxKey
        var removed = phone
        removed.removedAt = "2026-11-01T10:00:00.000Z"
        FakeTogether.handler = { request, _ in
            let users = request.url!.query!.replacingOccurrences(of: "users=", with: "").split(separator: ",").map(String.init)
            return (200, ["users": users.map { user in
                ["userId": user, "devices": user == alice ? [self.json(mac), self.json(forged)] : [], "removed": user == alice ? [self.json(removed)] : []]
            }])
        }
        let ids = [alice] + (1 ... 24).map { "user-\($0)" } + [alice]
        let people = try await client.e2eeDevices(of: ids)
        XCTAssertEqual(FakeTogether.requests.count, 2, "25 people: 20, then 5")
        XCTAssertEqual(FakeTogether.requests[0].0.url!.query?.split(separator: ",").count, 20)
        XCTAssertEqual(people.count, 25)
        let checked = try XCTUnwrap(people.first { $0.userId == alice }).verified
        XCTAssertEqual(checked.devices.map(\.id), [mac.id], "a device whose signature does not hold is left out")
        XCTAssertEqual(checked.removed.map(\.id), [phone.id])
        XCTAssertNotNil(checked.removed.first?.removedAt)
    }

    // MARK: Sending

    func testASealedMessageGoesWithoutTextAndIsSealedAgainWhenTheDevicesChanged() async throws {
        let mac = try secrets("aliceMac")
        let alice = v.users["alice"]!
        let all = v.devices.values.map { E.Recipient($0.public) }
        let first = all.filter { $0.id != v.devices["alicePhone"]!.public.id }
        var posts = 0
        FakeTogether.handler = { request, body in
            posts += 1
            let sent = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
            let sealed = try! JSONDecoder().decode(E.Sealed.self, from: JSONSerialization.data(withJSONObject: sent["sealed"]!))
            if sealed.keys.count < 3 {
                return (409, ["code": "e2ee_devices", "title": "The devices changed: seal it again", "status": 409, "devices": [alice: ["31a297aa4dd09c0576a7171c1f54a373", "0765916b8f2b398ceaa756abe3151f2c"]]])
            }
            return (201, Self.message(id: sent["clientId"] as! String, sealed: sealed, author: alice))
        }
        var asked: [Int] = []
        let messageId = "0190f1a2-0000-7000-8000-0000000000aa"
        let message = try await client.sendSealed(E.Payload(text: "hi"), in: "c1", messageId: messageId, replyTo: 3, from: alice, device: mac) { attempt in
            asked.append(attempt)
            return attempt == 0 ? first : all
        }
        XCTAssertEqual(asked, [0, 1], "the devices fetched again after the 409")
        XCTAssertEqual(posts, 2)
        let sent = try XCTUnwrap(body())
        XCTAssertNil(sent["text"], "a sealed message has no text")
        XCTAssertEqual(sent["clientId"] as? String, messageId)
        XCTAssertEqual(sent["replyTo"] as? Int, 3)
        XCTAssertEqual(message.id, messageId)
        let sealed = try XCTUnwrap(message.sealed)
        // Bob's Desktop opens it: the header named this message ID.
        let opened = try E.open(sealed, E.MessageMeta(conversationId: "c1", messageId: messageId, authorId: alice), me: try secrets("bobDesktop"),
                                authorDevices: [v.devices["aliceMac"]!.public])
        XCTAssertEqual(opened.text, "hi")
    }

    func testTheDevicesChangingOverAndOverStopsAfterThreeTries() async throws {
        FakeTogether.handler = { _, _ in (409, ["code": "e2ee_devices", "title": "The devices changed", "status": 409, "devices": "not a map"]) }
        do {
            _ = try await client.sendSealed(E.Payload(text: "hi"), in: "c1", messageId: "m", from: v.users["alice"]!, device: try secrets("aliceMac")) { _ in
                self.v.devices.values.map { E.Recipient($0.public) }
            }
            XCTFail("it gives up")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "e2ee_devices", "a devices list in another shape still reads as the problem")
            XCTAssertEqual(problem.devices?.byUser, [:])
        }
        XCTAssertEqual(FakeTogether.requests.count, 3)
    }

    func testAnEditIsANewSealOfTheSameMessage() async throws {
        FakeTogether.handler = { request, body in
            let sent = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
            let sealed = try! JSONDecoder().decode(E.Sealed.self, from: JSONSerialization.data(withJSONObject: sent["sealed"]!))
            return (200, Self.message(id: "m9", seq: 9, sealed: sealed))
        }
        _ = try await client.sendSealed(E.Payload(text: "said again"), in: "c1", messageId: "m9", edit: 9, from: v.users["alice"]!, device: try secrets("aliceMac")) { _ in
            self.v.devices.values.map { E.Recipient($0.public) }
        }
        XCTAssertEqual(last(), "PATCH /api/v1/conversations/c1/messages/9")
        XCTAssertEqual(Set(try XCTUnwrap(body()).keys), ["sealed"])
    }

    func testTheProblemListsTheDevicesByPerson() throws {
        let data = try JSONSerialization.data(withJSONObject: ["status": 409, "code": "e2ee_devices", "title": "x", "devices": ["u1": ["a", "b"], "u2": []]])
        let problem = try JSONDecoder.together.decode(TogetherProblem.self, from: data)
        XCTAssertEqual(problem.devices?.byUser, ["u1": ["a", "b"], "u2": []])
    }

    // MARK: Media

    func testSealedMediaGoesUpAsCiphertextAndComesBackOpened() async throws {
        let photo = Data("a photo, already re-encoded".utf8)
        let poster = Data("a poster".utf8)
        var stored: [String: Data] = [:]
        FakeTogether.handler = { request, body in
            switch (request.httpMethod!, request.url!.path) {
            case ("POST", "/api/v1/me/media/sealed"):
                XCTAssertEqual(request.url!.query, "kind=clip")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
                stored["file"] = body
                return (201, ["media": ["id": "md1", "kind": "clip", "contentType": "application/octet-stream", "size": body!.count, "url": "https://files.test/md1", "thumb": NSNull(),
                                        "poster": NSNull(), "sealed": true, "createdAt": "2026-11-06T10:00:00.000Z"], "usage": ["used": 10, "limit": 100, "saves": 0, "media": 10]])
            case ("PUT", "/api/v1/me/media/md1/poster"):
                stored["poster"] = body
                return (200, ["media": ["id": "md1", "kind": "clip", "size": 1, "url": "https://files.test/md1", "poster": "https://files.test/md1-poster", "sealed": true]])
            case ("GET", "/md1"): return (200, FakeTogether.Raw(data: stored["file"]!))
            case ("GET", "/md1-poster"): return (200, FakeTogether.Raw(data: stored["poster"]!))
            default: return (404, ["code": "not_found"])
            }
        }
        let attachment = try await client.uploadSealed(kind: "clip", data: photo, contentType: "video/mp4", width: 1280, height: 720, durationMs: 4200, poster: (poster, "image/jpeg"))
        XCTAssertNotEqual(stored["file"], photo)
        XCTAssertEqual(stored["file"]?.count, photo.count + 16)
        XCTAssertFalse(String(decoding: stored["file"]!, as: UTF8.self).contains("photo"))
        XCTAssertEqual(attachment.mediaId, "md1")
        XCTAssertEqual(attachment.type, "video/mp4")
        XCTAssertEqual(attachment.size, photo.count)
        XCTAssertEqual(attachment.durationMs, 4200)
        XCTAssertEqual(attachment.poster?.type, "image/jpeg")
        XCTAssertNotEqual(attachment.key, attachment.poster?.key, "a key of its own for the poster")

        let media = TogetherMedia(id: "md1", kind: "clip", url: "https://files.test/md1", poster: "https://files.test/md1-poster", sealed: true)
        let opened = try await client.openSealed(attachment, media: media)
        XCTAssertEqual(opened.file, photo)
        XCTAssertEqual(opened.poster, poster)
        let other = TogetherMedia(id: "md2", kind: "clip", url: "https://files.test/md1", sealed: true)
        await XCTAssertThrowsAsync(try await self.client.openSealed(attachment, media: other), "media other than the seal names")
    }

    func testAReportOfASealedMessageCarriesItsContentKey() async throws {
        FakeTogether.handler = { _, _ in (201, ["id": "r1"]) }
        try await client.reportMessage("m1", reason: "harassment", contentKey: Data(repeating: 7, count: 32))
        XCTAssertEqual(last(), "POST /api/v1/reports")
        XCTAssertEqual(body()?["targetKind"] as? String, "message")
        XCTAssertEqual(body()?["targetId"] as? String, "m1")
        XCTAssertEqual(body()?["reason"] as? String, "harassment")
        XCTAssertEqual(body()?["contentKey"] as? String, Data(repeating: 7, count: 32).base64EncodedString())
        try await client.reportMessage("m2", reason: "spam")
        XCTAssertNil(body()?["contentKey"], "a plain message has none")
    }

    // MARK: Decoding

    func testSealedMessagesConversationsAndMediaDecode() throws {
        let m = v.messages[0]
        let message: TogetherMessage = TogetherMessagesTests.decoded(Self.message(sealed: m.sealed))
        XCTAssertEqual(message.sealed, m.sealed)
        var weird = Self.message(sealed: nil)
        weird["sealed"] = ["v": 2, "something": "else"]
        XCTAssertEqual((TogetherMessagesTests.decoded(weird) as TogetherMessage).sealed, .unreadable, "a seal of another shape is still not shown as its stand-in")
        XCTAssertNil((TogetherMessagesTests.decoded(Self.message(sealed: nil)) as TogetherMessage).sealed)
        let conversation: TogetherConversation = TogetherMessagesTests.decoded(TogetherChatTests.conversation(extra: ["encrypted": true]))
        XCTAssertTrue(conversation.encrypted)
        XCTAssertFalse((TogetherMessagesTests.decoded(TogetherChatTests.conversation()) as TogetherConversation).encrypted, "an older server")
        let media = try JSONDecoder.together.decode(TogetherMedia.self, from: JSONSerialization.data(withJSONObject: ["id": "x", "kind": "image", "size": 3, "url": "u", "sealed": true]))
        XCTAssertTrue(media.sealed)
        let note = try JSONDecoder.together.decode(TogetherNotification.self, from: JSONSerialization.data(withJSONObject: [
            "id": "n1", "kind": "message", "actor": ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull()], "subjectId": "c1",
            "data": ["conversationId": "c1", "text": "", "sealed": true], "read": false, "createdAt": "2026-11-06T10:00:00.000Z",
        ]))
        XCTAssertEqual(note.data.sealed, true)
    }
}

func XCTAssertThrowsAsync<T>(_ work: @autoclosure () async throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await work()
        XCTFail("no error: \(message)", file: file, line: line)
    } catch {}
}

/// What the launcher keeps per conversation, and opening messages with it.
final class TogetherE2EEBookTests: XCTestCase {
    typealias E = TogetherE2EE
    typealias V = TogetherE2EETests

    var v: V.Vectors { V.vectors }
    var alice: String { v.users["alice"]! }
    var bob: String { v.users["bob"]! }

    func secrets(_ name: String) throws -> E.DeviceSecrets {
        let d = try XCTUnwrap(v.devices[name])
        return try E.DeviceSecrets(signSeed: V.hex(d.signSeed), boxSecret: V.hex(d.boxSecret))
    }

    func person(_ user: String, _ names: [String], removed: [String] = []) -> TogetherE2EEPerson {
        TogetherE2EEPerson(userId: user, devices: names.map { v.devices[$0]!.public }, removed: removed.map { v.devices[$0]!.public })
    }

    func conversation(kind: String = "direct", encrypted: Bool = false) -> TogetherConversation {
        TogetherConversation(id: v.conversationId, kind: kind, title: nil, members: [TogetherPerson(userId: alice, handle: "alice", displayName: "Alice", avatar: nil),
                                                                                    TogetherPerson(userId: bob, handle: "bob", displayName: "Bob", avatar: nil)],
                             lastSeq: 2, readSeq: 2, unread: 0, lastMessage: nil, updatedAt: Date(), encrypted: encrypted)
    }

    func book(as device: String = "bobDesktop", me: String? = nil) throws -> TogetherE2EEBook {
        var book = TogetherE2EEBook(me: me ?? bob, device: try secrets(device))
        book.availability = .on
        return book
    }

    func message(_ index: Int, at date: Date = Date(timeIntervalSince1970: 1_800_000_000), attachments: [TogetherAttachment]? = nil) -> TogetherMessage {
        let m = v.messages[index]
        let media = m.payload.contains("attachment") ? [TogetherAttachment(id: "0190f1a2-0000-7000-8000-00000000f11e", kind: "clip")] : nil
        return TogetherMessage(id: m.messageId, conversationId: v.conversationId, seq: index + 1, authorId: m.authorId, text: "[encrypted message]", createdAt: date,
                               attachments: attachments ?? media, sealed: m.sealed)
    }

    func testTheLockState() throws {
        var book = try book()
        XCTAssertNil(book.lock(conversation(kind: "group")), "groups stay as they are")
        book.availability = .unknown
        XCTAssertNil(book.lock(conversation()), "nothing known and never encrypted: as today")
        XCTAssertEqual(book.lock(conversation(encrypted: true)), .waiting)
        book.availability = .off
        XCTAssertNil(book.lock(conversation()), "a server without end-to-end encryption")
        book.availability = .on
        XCTAssertEqual(book.lock(conversation()), .waiting, "the devices not fetched yet")
        book.learn([person(alice, ["aliceMac", "alicePhone"]), person(bob, ["bobDesktop"])])
        XCTAssertEqual(book.lock(conversation()), .on)
        XCTAssertEqual(Set(book.recipients(conversation())?.map(\.id) ?? []), Set(v.devices.values.map(\.public.id)), "every device of both people, this one included")
        book.learn([person(alice, [])])
        XCTAssertEqual(book.lock(conversation()), .off, "the other person has no device and it was never encrypted")
        XCTAssertNil(book.recipients(conversation()))
        XCTAssertEqual(book.lock(conversation(encrypted: true)), .noDevice)
        book.sawEncrypted(v.conversationId)
        XCTAssertEqual(book.lock(conversation()), .noDevice, "seen encrypted here: never plain again")
        book.learn([person(alice, ["aliceMac"]), person(bob, [])])
        XCTAssertEqual(book.lock(conversation()), .waiting, "this device is not among the user's own yet")
    }

    func testDevicesThatChangeRaiseANoticeAndDropTheComparedMark() throws {
        var book = try book()
        let c = conversation()
        book.learn([person(alice, ["aliceMac"]), person(bob, ["bobDesktop"])])
        XCTAssertTrue(book.noteDevices(c))
        XCTAssertNil(book.notice(c.id), "the first time it only remembers")
        let number = try XCTUnwrap(book.safetyNumber(c))
        XCTAssertEqual(number.count, 60)
        XCTAssertFalse(book.isCompared(c))
        book.markCompared(c)
        XCTAssertTrue(book.isCompared(c))
        XCTAssertFalse(book.noteDevices(c), "nothing changed")

        book.learn([person(alice, ["aliceMac", "alicePhone"])])
        XCTAssertTrue(book.noteDevices(c))
        XCTAssertEqual(book.notice(c.id), .init(mine: false, theirs: true), "Alice added her phone")
        XCTAssertFalse(book.isCompared(c), "the mark goes")
        XCTAssertNotEqual(book.safetyNumber(c), number)
        book.learn([person(alice, ["aliceMac"])])
        book.noteDevices(c)
        XCTAssertFalse(book.isCompared(c), "back to the old number, but the mark is gone for good")
        book.markCompared(c)
        XCTAssertNil(book.notice(c.id), "comparing again clears the notice")
        let bobLaptop = try E.DeviceSecrets.generate().publicDevice(for: bob)
        book.learn([TogetherE2EEPerson(userId: bob, devices: [v.devices["bobDesktop"]!.public, bobLaptop])])
        book.noteDevices(c)
        XCTAssertEqual(book.notice(c.id), .init(mine: true, theirs: false), "Bob, this user, added a laptop")
        book.dismissNotice(c.id)
        XCTAssertNil(book.notice(c.id))
        // Someone who had no device getting one is not a change to warn about.
        book.learn([person(alice, [])])
        book.noteDevices(c)
        book.dismissNotice(c.id)
        book.learn([person(alice, ["aliceMac"])])
        book.noteDevices(c)
        XCTAssertNil(book.notice(c.id))
    }

    func testWhatIsRememberedSurvivesARestart() throws {
        var book = try book()
        let c = conversation()
        book.learn([person(alice, ["aliceMac"]), person(bob, ["bobDesktop"])])
        book.noteDevices(c)
        book.markCompared(c)
        book.sawEncrypted("other")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("e2ee-\(UUID().uuidString)/u.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        book.remembered.save(file)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains(try secrets("bobDesktop").boxSecret.base64EncodedString()), "no keys in it")
        XCTAssertEqual(TogetherE2EEBook.Remembered.load(file), book.remembered)
        XCTAssertEqual(TogetherE2EEBook.Remembered.load(file.appendingPathExtension("missing")), .init())
    }

    func testMessagesOpenOrSayWhyNot() throws {
        var book = try book()
        XCTAssertNil(book.open(message(0)), "the author's devices are not known yet")
        XCTAssertEqual(book.waitingAuthors([message(0), message(1)]), [alice, bob])
        book.learn([person(alice, ["aliceMac", "alicePhone"]), person(bob, ["bobDesktop"])])
        XCTAssertEqual(book.open(message(0)), .payload(E.Payload(text: "Merhaba Bob 👋 GG?")))
        guard case .payload(let clip) = book.open(message(1)) else { return XCTFail("the clip opens") }
        XCTAssertEqual(clip.attachment?.mediaId, "0190f1a2-0000-7000-8000-00000000f11e")
        XCTAssertEqual(book.waitingAuthors([message(0), message(1)]), [])
        XCTAssertNotNil(book.opened(message(0)))
        XCTAssertEqual(book.contentKey(message(0))?.base64EncodedString(), v.messages[0].random.contentKey, "for a report")

        XCTAssertEqual(book.open(message(1, attachments: [TogetherAttachment(id: "another", kind: "clip")])), .undecryptable, "the seal names other media")
        XCTAssertEqual(book.open(message(1, attachments: [])), .undecryptable, "media in the seal but none on the message")

        var later = TogetherE2EEBook(me: bob, device: E.DeviceSecrets.generate())
        later.availability = .on
        later.learn([person(alice, ["aliceMac"])])
        XCTAssertEqual(later.open(message(0)), .beforeDevice)

        var tampered = message(0)
        let flipped = V.flip(tampered.sealed!.body)
        tampered.sealed?.body = flipped
        XCTAssertEqual(book.open(tampered), .undecryptable)
        var unreadable = message(0)
        unreadable.sealed = .unreadable
        XCTAssertEqual(book.open(unreadable), .undecryptable)
    }

    func testAnUnknownSendingDeviceIsFetchedForOnceThenRefused() throws {
        var book = try book()
        let sent = Date(timeIntervalSince1970: 1_800_000_000)
        book.learn([person(alice, ["alicePhone"])], at: sent.addingTimeInterval(-3600))
        XCTAssertNil(book.open(message(0, at: sent)), "fetched before it was sent: fetch again")
        book.learn([person(alice, ["alicePhone"])], at: sent.addingTimeInterval(3600))
        XCTAssertEqual(book.open(message(0, at: sent)), .undecryptable, "fetched after and still not there: not the author's")
        var removed = try self.book()
        removed.learn([person(alice, ["alicePhone"], removed: ["aliceMac"])])
        XCTAssertEqual(removed.open(message(0)), .payload(E.Payload(text: "Merhaba Bob 👋 GG?")), "a removed device's old messages still verify")
    }

    // MARK: Keys

    func testKeysAreMadeOnceAndKeptOnlyWhereTheVaultKeepsThem() throws {
        let vault = MemoryVault()
        let account = TogetherE2EEKeys.account(profile: "p1", userId: "u1")
        XCTAssertNil(TogetherE2EEKeys.load(from: vault, account: account))
        let made = try XCTUnwrap(TogetherE2EEKeys.loadOrMake(in: vault, account: account))
        XCTAssertEqual(TogetherE2EEKeys.loadOrMake(in: vault, account: account), made, "the same keys next time")
        XCTAssertNotEqual(TogetherE2EEKeys.loadOrMake(in: vault, account: TogetherE2EEKeys.account(profile: "p2", userId: "u1")), made, "another profile, other keys")
        let refusing = MemoryVault()
        refusing.refuses = true
        XCTAssertNil(TogetherE2EEKeys.loadOrMake(in: refusing, account: account), "no keys that would be lost")
        vault.write(Data("not keys".utf8), for: "broken")
        XCTAssertNil(TogetherE2EEKeys.load(from: vault, account: "broken"))
    }

    /// The real Keychain, in a keychain file of the test's own: an item for this Mac only, never
    /// synchronised.
    func testTheKeychainKeepsDeviceKeysForThisMacOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("e2ee-keychain-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var keychain: SecKeychain?
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        guard SecKeychainCreate(folder.appendingPathComponent("test.keychain").path, 4, "test", false, nil, &keychain) == errSecSuccess, let keychain else { throw XCTSkip("no keychain can be made here") }
        defer { SecKeychainDelete(keychain) }
        let service = "AnyPS5 test e2ee \(UUID().uuidString)"
        let vault = KeychainVault(service: service, keychain: keychain, thisDeviceOnly: true)
        let made = try XCTUnwrap(TogetherE2EEKeys.loadOrMake(in: vault, account: "device.p.u"))
        XCTAssertEqual(TogetherE2EEKeys.load(from: vault, account: "device.p.u"), made)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device.p.u",
                                    kSecMatchSearchList as String: [keychain], kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertNotEqual(attributes[kSecAttrSynchronizable as String] as? Bool, true, "not synchronised to iCloud Keychain")
        XCTAssertTrue(vault.write(nil, for: "device.p.u"))
        XCTAssertNil(TogetherE2EEKeys.load(from: vault, account: "device.p.u"))
    }

    // MARK: Photos

    func testAPhotoIsDrawnAgainWithoutItsLocationOrCamera() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("e2ee-photo-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("shot.jpg")
        // Noise, so the PNG is big and a smaller limit takes a JPEG.
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var generator = SystemRandomNumberGenerator()
        for y in 0 ..< 300 {
            for x in 0 ..< 400 {
                context.setFillColor(red: .random(in: 0 ... 1, using: &generator), green: .random(in: 0 ... 1, using: &generator), blue: .random(in: 0 ... 1, using: &generator), alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0082, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 28.9784, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Secret Camera Co", kCGImagePropertyTIFFModel: "Model X"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "at home", kCGImagePropertyExifLensModel: "Lens 1"],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let before = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(file as CFURL, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary], "the test picture has a location to lose")

        let ready = try MediaPrep.sealableImage(file, maxBytes: 10 * 1_048_576)
        XCTAssertEqual(ready.contentType, "image/png")
        XCTAssertEqual(ready.width, 400)
        XCTAssertEqual(ready.height, 300)
        let after = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(ready.data as CFData, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertNil(after[kCGImagePropertyGPSDictionary])
        // ImageIO describes any PNG with an Exif part of its own (colour space, size): nothing of the camera's.
        let exif = after[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifUserComment])
        XCTAssertNil(exif[kCGImagePropertyExifLensModel])
        XCTAssertNil((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake])
        let bytes = String(decoding: ready.data, as: UTF8.self)
        XCTAssertFalse(bytes.contains("Secret Camera"))
        XCTAssertFalse(bytes.contains("at home"))

        XCTAssertGreaterThan(ready.data.count, 200_000)
        let small = try MediaPrep.sealableImage(file, maxBytes: 200_000)
        XCTAssertEqual(small.contentType, "image/jpeg", "too big as a PNG: a JPEG")
        let smallAfter = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(small.data as CFData, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertNil(smallAfter[kCGImagePropertyGPSDictionary])
        XCTAssertNil((smallAfter[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
        XCTAssertNil((smallAfter[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel])
        XCTAssertFalse(String(decoding: small.data, as: UTF8.self).contains("Secret Camera"))
    }

    /// A picture file of the user's own (Messages › Send a photo) of a kind the server does not
    /// take, a TIFF here, goes as a PNG drawn from its pixels, its location left behind.
    func testAPictureOfAnotherKindGoesAsAPNGWithoutItsLocation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("e2ee-tiff-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("scan.tiff")
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0082, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 28.9784, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Secret Camera Co"],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let before = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(file as CFURL, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary], "the test picture has a location to lose")

        let ready = try MediaPrep.sealableImage(file, maxBytes: 10 * 1_048_576)
        XCTAssertEqual(ready.contentType, "image/png")
        XCTAssertEqual(ready.width, 64)
        XCTAssertEqual(ready.height, 48)
        let after = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(ready.data as CFData, nil)!, 0, nil) as! [CFString: Any]
        XCTAssertNil(after[kCGImagePropertyGPSDictionary])
        XCTAssertFalse(String(decoding: ready.data, as: UTF8.self).contains("Secret Camera"))
    }
}
