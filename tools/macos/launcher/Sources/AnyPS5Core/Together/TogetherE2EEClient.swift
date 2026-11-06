import Foundation

/// One person's device keys as GET /e2ee/devices lists them: the active ones, and the removed
/// ones kept to check their old messages.
public struct TogetherE2EEPerson: Decodable, Equatable, Sendable {
    public let userId: String
    public var devices: [TogetherE2EE.Device]
    public var removed: [TogetherE2EE.Device]

    public init(userId: String, devices: [TogetherE2EE.Device], removed: [TogetherE2EE.Device] = []) {
        self.userId = userId
        self.devices = devices
        self.removed = removed
    }

    enum CodingKeys: String, CodingKey { case userId, devices, removed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        devices = c.lenient([TogetherE2EE.Device].self, .devices) ?? []
        removed = c.lenient([TogetherE2EE.Device].self, .removed) ?? []
    }

    /// Only the devices whose keys say they are this person's (TogetherE2EE.verify): one that
    /// fails is left out, as if the server had not listed it.
    public var verified: TogetherE2EEPerson {
        TogetherE2EEPerson(userId: userId, devices: devices.filter { TogetherE2EE.verify($0, for: userId) },
                           removed: removed.filter { TogetherE2EE.verify($0, for: userId) })
    }
}

/// The server has no end-to-end encryption (no /me/e2ee routes): everything works as before.
public struct TogetherE2EEUnsupported: Error, Equatable, Sendable {}

extension TogetherClient {
    // MARK: Devices

    /// This session's device as the server has it; nil while it has none.
    public func e2eeDevice() async throws -> TogetherE2EE.Device? {
        do {
            return try JSONDecoder.together.decode(TogetherE2EE.Device.self, from: try await authorized("GET", "me/e2ee/device", nil))
        } catch let problem as TogetherProblem where problem.status == 404 {
            return nil
        }
    }

    /// This session's keys (201 new, 200 again). A 404 means the server has no such route.
    @discardableResult
    public func registerE2EEDevice(_ device: TogetherE2EE.Device, name: String) async throws -> TogetherE2EE.Device {
        let body = ["signKey": device.signKey, "boxKey": device.boxKey, "sig": device.sig, "name": String(name.prefix(80))]
        do {
            return try JSONDecoder.together.decode(TogetherE2EE.Device.self, from: try await authorized("PUT", "me/e2ee/device", body))
        } catch let problem as TogetherProblem where problem.status == 404 {
            throw TogetherE2EEUnsupported()
        }
    }

    /// Makes sure the server has this device's keys for this session: asks first, and registers
    /// them when it has none or other ones. Throws TogetherE2EEUnsupported from a server without
    /// end-to-end encryption.
    public func prepareE2EE(_ secrets: TogetherE2EE.DeviceSecrets, userId: String, name: String) async throws {
        let mine = try secrets.publicDevice(for: userId)
        if let kept = try await e2eeDevice(), kept.id == mine.id, kept.signKey == mine.signKey, kept.boxKey == mine.boxKey, kept.removedAt == nil, kept.name == String(name.prefix(80)) {
            return
        }
        try await registerE2EEDevice(mine, name: name)
    }

    public func removeE2EEDevice(_ id: String) async throws {
        _ = try await authorized("DELETE", "me/e2ee/devices/\(id)", nil)
    }

    /// Each person's devices (oneself, friends and direct-conversation partners; the server leaves
    /// anyone else out), asked 20 at a time. Not yet checked: see TogetherE2EEPerson.verified.
    public func e2eeDevices(of users: [String]) async throws -> [TogetherE2EEPerson] {
        struct List: Decodable { let users: [TogetherE2EEPerson] }
        var unique: [String] = []
        for user in users where !unique.contains(user) { unique.append(user) }
        var found: [TogetherE2EEPerson] = []
        for start in stride(from: 0, to: unique.count, by: 20) {
            let ids = unique[start ..< min(unique.count, start + 20)].joined(separator: ",")
            found += try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "e2ee/devices?users=\(ids)", nil)).users
        }
        return found
    }

    // MARK: Sealed messages

    /// A sealed message (no text): `messageId` is its client ID, which its header names too.
    public func send(sealed: TogetherE2EE.Sealed, messageId: String, in conversationId: String, replyTo: Int? = nil, mediaId: String? = nil) async throws -> TogetherMessage {
        var body: [String: Any] = ["clientId": messageId, "sealed": try Self.json(sealed)]
        if let replyTo { body["replyTo"] = replyTo }
        if let mediaId { body["attachments"] = [["mediaId": mediaId]] }
        return try JSONDecoder.together.decode(TogetherMessage.self, from: try await authorized("POST", "conversations/\(conversationId)/messages", body))
    }

    /// A sealed message said again: a new seal of the same message ID.
    public func edit(_ seq: Int, in conversationId: String, sealed: TogetherE2EE.Sealed) async throws -> TogetherMessage {
        try JSONDecoder.together.decode(TogetherMessage.self, from: try await authorized("PATCH", "conversations/\(conversationId)/messages/\(seq)", ["sealed": try Self.json(sealed)]))
    }

    static func json(_ sealed: TogetherE2EE.Sealed) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(sealed))
    }

    /// Seals `payload` for the devices `recipients` names and sends it; when the server says the
    /// devices changed (409 e2ee_devices) it asks `recipients` again (attempt 1, 2, …: fetch them
    /// anew) and seals again, at most `tries` times in all. `seq` edits that message instead.
    public func sendSealed(_ payload: TogetherE2EE.Payload, in conversationId: String, messageId: String, replyTo: Int? = nil, mediaId: String? = nil, edit seq: Int? = nil,
                           from userId: String, device: TogetherE2EE.DeviceSecrets, tries: Int = 3,
                           recipients: (_ attempt: Int) async throws -> [TogetherE2EE.Recipient]) async throws -> TogetherMessage {
        var attempt = 0
        while true {
            let sealed = try TogetherE2EE.seal(payload, conversationId: conversationId, messageId: messageId, senderUserId: userId, sender: device,
                                               recipients: try await recipients(attempt)).sealed
            do {
                if let seq { return try await edit(seq, in: conversationId, sealed: sealed) }
                return try await send(sealed: sealed, messageId: messageId, in: conversationId, replyTo: replyTo, mediaId: mediaId)
            } catch let problem as TogetherProblem where problem.code == "e2ee_devices" && attempt + 1 < tries {
                attempt += 1
            }
        }
    }

    // MARK: Sealed media

    /// A photo, clip or voice note's ciphertext going up (POST /me/media/sealed?kind=).
    public func uploadSealedMedia(kind: String, ciphertext: Data) async throws -> (media: TogetherMedia, usage: TogetherStorageUsage?) {
        struct Answer: Decodable { let media: TogetherMedia; let usage: TogetherStorageUsage? }
        let answer = try JSONDecoder.together.decode(Answer.self, from: try await authorized("POST", "me/media/sealed?kind=\(kind)", TogetherRawBody(data: ciphertext, contentType: "application/octet-stream")))
        return (answer.media, answer.usage)
    }

    /// A sealed clip's poster, sealed with its own key.
    @discardableResult
    public func setSealedPoster(_ mediaId: String, ciphertext: Data) async throws -> TogetherMedia {
        try await setPoster(mediaId, data: ciphertext, contentType: "application/octet-stream")
    }

    /// Seals a file (and a clip's poster) on this Mac and uploads the ciphertext: what the
    /// message's payload says about it, keys included. Photos come re-encoded already
    /// (MediaPrep.sealableImage), so nothing of where or how they were taken goes along.
    public func uploadSealed(kind: String, data: Data, contentType: String, width: Int? = nil, height: Int? = nil, durationMs: Int? = nil,
                             poster: (data: Data, contentType: String)? = nil) async throws -> TogetherE2EE.Attachment {
        let file = try TogetherE2EE.sealFile(data, part: .file)
        let media = try await uploadSealedMedia(kind: kind, ciphertext: file.ciphertext).media
        var attachment = TogetherE2EE.Attachment(mediaId: media.id, kind: kind, type: contentType, size: data.count, key: file.key, nonce: file.nonce,
                                                 width: width, height: height, durationMs: durationMs)
        if let poster {
            let sealed = try TogetherE2EE.sealFile(poster.data, part: .poster)
            // A poster that does not go up leaves the clip without one, as for a plain clip.
            if (try? await setSealedPoster(media.id, ciphertext: sealed.ciphertext)) != nil {
                attachment.poster = .init(key: sealed.key, nonce: sealed.nonce, type: poster.contentType)
            }
        }
        return attachment
    }

    /// A signed link's bytes (sealed media's ciphertext).
    public func download(_ link: String) async throws -> Data {
        guard let url = URL(string: link) else { throw TogetherProblem(status: 400, code: "bad_request", title: "Not a link") }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw TogetherProblem(status: status, code: status == 403 ? "link_expired" : "internal", title: "AnyTogether answered \(status)") }
        return data
    }

    /// A sealed attachment downloaded and opened: the file and, for a clip, its poster. The
    /// media must be the one the seal names.
    public func openSealed(_ attachment: TogetherE2EE.Attachment, media: TogetherMedia) async throws -> (file: Data, poster: Data?) {
        guard media.id == attachment.mediaId, let url = media.url else { throw TogetherE2EE.Failure.badMessage }
        let file = try TogetherE2EE.openFile(try await download(url), part: .file, key: attachment.key, nonce: attachment.nonce)
        var poster: Data?
        if let key = attachment.poster, let link = media.poster, let ciphertext = try? await download(link) {
            poster = try? TogetherE2EE.openFile(ciphertext, part: .poster, key: key.key, nonce: key.nonce)
        }
        return (file, poster)
    }

    // MARK: Reports

    /// Reports a message to the moderators. A sealed one sends its content key, so they can read
    /// it (and only it); the server checks the author's signature with it.
    public func reportMessage(_ messageId: String, reason: String, contentKey: Data? = nil) async throws {
        var body: [String: Any] = ["targetKind": "message", "targetId": messageId, "reason": reason]
        if let contentKey { body["contentKey"] = contentKey.base64EncodedString() }
        _ = try await authorized("POST", "reports", body)
    }
}
