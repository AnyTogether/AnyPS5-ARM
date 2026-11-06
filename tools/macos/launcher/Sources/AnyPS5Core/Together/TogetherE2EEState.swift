import Foundation

/// This Mac's end-to-end encryption keys for one signed-in person, in the vault (the Keychain,
/// this Mac only): made once, never sent anywhere. Signing in again on the same profile finds the
/// same keys, so the same device registers under the new session.
public enum TogetherE2EEKeys {
    /// The Keychain item's service, apart from the sessions'.
    public static let service = "AnyPS5 AnyTogether E2EE"

    public static func account(profile: String, userId: String) -> String { "device.\(profile).\(userId)" }

    struct Kept: Codable {
        var v = 1
        var signSeed: String
        var boxSecret: String
    }

    public static func load(from vault: SecretVault, account: String) -> TogetherE2EE.DeviceSecrets? {
        guard let data = vault.read(account), let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.v == 1,
              let seed = try? TogetherE2EE.base64(kept.signSeed, length: 32), let secret = try? TogetherE2EE.base64(kept.boxSecret, length: 32) else { return nil }
        return try? TogetherE2EE.DeviceSecrets(signSeed: seed, boxSecret: secret)
    }

    /// The keys kept, or new ones kept now; nil when the vault will not keep them (then this Mac
    /// registers none, rather than keys it would lose).
    public static func loadOrMake(in vault: SecretVault, account: String) -> TogetherE2EE.DeviceSecrets? {
        if let kept = load(from: vault, account: account) { return kept }
        let made = TogetherE2EE.DeviceSecrets.generate()
        guard let data = try? JSONEncoder().encode(Kept(signSeed: made.signSeed.base64EncodedString(), boxSecret: made.boxSecret.base64EncodedString())),
              vault.write(data, for: account), load(from: vault, account: account) == made else { return nil }
        return made
    }
}

/// What the launcher knows about end-to-end encryption for the signed-in person: whether the
/// server has it, everyone's checked device keys, what each sealed message opened to (in memory
/// only), and what it remembers per conversation (the devices last seen, the notice when they
/// changed, the "compared" mark, and that it was seen encrypted).
public struct TogetherE2EEBook: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        /// Not asked yet, or the server could not be reached.
        case unknown
        /// The server has no end-to-end encryption: everything works as before.
        case off
        /// This device's keys are registered.
        case on
    }

    /// A direct conversation's state, for its header and composer.
    public enum Lock: Equatable, Sendable {
        /// Both people have a device: every message is sealed.
        case on
        /// The other person has no device and it was never encrypted: plain, labelled so.
        case off
        /// Encrypted, but the other person has no device now: nothing can be sent.
        case noDevice
        /// Encrypted (or about to be), and the devices are not known yet.
        case waiting
    }

    /// What a sealed message opened to on this device.
    public enum Opened: Equatable, Sendable {
        case payload(TogetherE2EE.Payload)
        /// No key for this device: sent before it was added.
        case beforeDevice
        /// Anything else that failed: never shown as plain text.
        case undecryptable
    }

    /// The devices of a conversation's two people changed since they were last seen.
    public struct Notice: Codable, Equatable, Sendable {
        public var mine: Bool
        public var theirs: Bool

        public init(mine: Bool, theirs: Bool) {
            self.mine = mine
            self.theirs = theirs
        }
    }

    /// What is kept between launches, per signed-in person (no keys and nothing of what was said).
    public struct Remembered: Codable, Equatable, Sendable {
        public struct Seen: Codable, Equatable, Sendable {
            public var mine: [String]
            public var theirs: [String]
        }

        /// Conversations this device saw encrypted: never plain again here.
        public var encrypted: Set<String> = []
        public var devices: [String: Seen] = [:]
        public var notices: [String: Notice] = [:]
        /// The safety number each conversation was marked compared at.
        public var compared: [String: String] = [:]

        public init() {}

        public static func load(_ file: URL) -> Remembered {
            (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Remembered.self, from: $0) } ?? Remembered()
        }

        public func save(_ file: URL) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard let data = try? JSONEncoder().encode(self) else { return }
            FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }

    public var me: String
    public var availability: Availability = .unknown
    /// This device's keys; nil until they are loaded (or when the Keychain would not keep them).
    public var device: TogetherE2EE.DeviceSecrets?
    /// Everyone's devices that passed TogetherE2EE.verify, by user ID, and when they were fetched.
    public private(set) var people: [String: TogetherE2EEPerson] = [:]
    public private(set) var fetched: [String: Date] = [:]
    public var remembered = Remembered()
    /// Sealed messages opened, by message ID, the whole seal and the media it names.
    public private(set) var opened: [OpenKey: Opened] = [:]

    public struct OpenKey: Hashable, Sendable {
        let messageId: String
        let sealed: TogetherE2EE.Sealed?
        let mediaId: String?
    }

    public init(me: String, device: TogetherE2EE.DeviceSecrets? = nil, remembered: Remembered = Remembered()) {
        self.me = me
        self.device = device
        self.remembered = remembered
    }

    // MARK: Devices

    /// People's devices as fetched: each checked, and the ones that fail left out.
    public mutating func learn(_ fetchedPeople: [TogetherE2EEPerson], at now: Date = Date()) {
        for person in fetchedPeople {
            people[person.userId] = person.verified
            fetched[person.userId] = now
        }
    }

    public func devices(of userId: String) -> [TogetherE2EE.Device]? { people[userId]?.devices }

    static func other(in conversation: TogetherConversation, me: String) -> String? {
        guard conversation.kind == "direct" else { return nil }
        return conversation.others(than: me).first?.userId
    }

    /// Whether this device saw the conversation encrypted (or the server says it is).
    public func isEncrypted(_ conversation: TogetherConversation) -> Bool {
        conversation.encrypted || remembered.encrypted.contains(conversation.id)
    }

    public mutating func sawEncrypted(_ conversationId: String) {
        remembered.encrypted.insert(conversationId)
    }

    /// The lock state of a direct conversation; nil for a group, or while nothing says it is or
    /// will be encrypted (a server without end-to-end encryption, say): then it works as before.
    public func lock(_ conversation: TogetherConversation) -> Lock? {
        guard let other = Self.other(in: conversation, me: me) else { return nil }
        let encrypted = isEncrypted(conversation)
        switch availability {
        case .off:
            return encrypted ? .noDevice : nil
        case .unknown:
            return encrypted ? .waiting : nil
        case .on:
            guard let mine = people[me]?.devices, let theirs = people[other]?.devices else { return .waiting }
            if theirs.isEmpty { return encrypted ? .noDevice : .off }
            return mine.contains(where: { $0.id == device?.deviceId }) ? .on : .waiting
        }
    }

    /// Every active device of both people, the one sealing included: who a message is sealed for.
    public func recipients(_ conversation: TogetherConversation) -> [TogetherE2EE.Recipient]? {
        guard let other = Self.other(in: conversation, me: me), let mine = people[me]?.devices, let theirs = people[other]?.devices,
              !mine.isEmpty, !theirs.isEmpty else { return nil }
        return (mine + theirs).map(TogetherE2EE.Recipient.init)
    }

    /// The 60 digits of the conversation's safety number, while both people have a device.
    public func safetyNumber(_ conversation: TogetherConversation) -> String? {
        guard let other = Self.other(in: conversation, me: me), let mine = people[me]?.devices, let theirs = people[other]?.devices else { return nil }
        return TogetherE2EE.safetyNumber((me, mine.map(\.signKey)), (other, theirs.map(\.signKey)))
    }

    /// Compares both people's devices with the ones last seen in the conversation: a change
    /// raises its notice and drops the "compared" mark. The first time it only remembers, and a
    /// side that had no device before only becomes known. True when anything changed.
    @discardableResult
    public mutating func noteDevices(_ conversation: TogetherConversation) -> Bool {
        guard let other = Self.other(in: conversation, me: me), let mine = people[me]?.devices, let theirs = people[other]?.devices else { return false }
        let now = Remembered.Seen(mine: mine.map(\.id).sorted(), theirs: theirs.map(\.id).sorted())
        let before = remembered.devices[conversation.id]
        remembered.devices[conversation.id] = now
        guard let before, before != now else { return before == nil }
        let mineChanged = !before.mine.isEmpty && before.mine != now.mine
        let theirsChanged = !before.theirs.isEmpty && before.theirs != now.theirs
        if mineChanged || theirsChanged {
            var notice = remembered.notices[conversation.id] ?? Notice(mine: false, theirs: false)
            notice.mine = notice.mine || mineChanged
            notice.theirs = notice.theirs || theirsChanged
            remembered.notices[conversation.id] = notice
            remembered.compared[conversation.id] = nil
        }
        return true
    }

    public func notice(_ conversationId: String) -> Notice? { remembered.notices[conversationId] }

    public mutating func dismissNotice(_ conversationId: String) {
        remembered.notices[conversationId] = nil
    }

    /// Whether the person marked the conversation's safety number, as it is now, compared.
    public func isCompared(_ conversation: TogetherConversation) -> Bool {
        guard let number = safetyNumber(conversation) else { return false }
        return remembered.compared[conversation.id] == number
    }

    /// Marks it compared (or not): the notice goes with the mark.
    public mutating func markCompared(_ conversation: TogetherConversation, _ on: Bool = true) {
        remembered.compared[conversation.id] = on ? safetyNumber(conversation) : nil
        if on { remembered.notices[conversation.id] = nil }
    }

    // MARK: Messages

    static func key(_ message: TogetherMessage) -> OpenKey { OpenKey(messageId: message.id, sealed: message.sealed, mediaId: message.attachments?.first?.id) }

    public func opened(_ message: TogetherMessage) -> Opened? { opened[Self.key(message)] }

    /// Opens a sealed message on this device and keeps what it opened to. Nil (and nothing
    /// kept) while that cannot be told yet: the author's devices are not fetched, or not since the
    /// message was sent and its device is not among them; fetch them and open it again.
    @discardableResult
    public mutating func open(_ message: TogetherMessage) -> Opened? {
        guard let sealed = message.sealed, message.deletedAt == nil, let author = message.authorId else { return nil }
        let key = Self.key(message)
        if let known = opened[key] { return known }
        guard let device else {
            // No keys on this Mac: nothing sealed can be read here.
            return availability == .unknown ? nil : keep(.undecryptable, key)
        }
        guard sealed.v == TogetherE2EE.version else { return keep(.undecryptable, key) }
        guard sealed.keys[device.deviceId] != nil else { return keep(.beforeDevice, key) }
        guard let person = people[author] else { return nil }
        let devices = person.devices + person.removed
        if !devices.contains(where: { $0.id == sealed.device }), (fetched[author] ?? .distantPast) < message.createdAt.addingTimeInterval(120) { return nil }
        let meta = TogetherE2EE.MessageMeta(conversationId: message.conversationId, messageId: message.id, authorId: author)
        do {
            let payload = try TogetherE2EE.open(sealed, meta, me: device, authorDevices: devices)
            // The plain attachments list names the media the seal is about: they must agree.
            guard payload.attachment?.mediaId == message.attachments?.first?.id else { return keep(.undecryptable, key) }
            return keep(.payload(payload), key)
        } catch TogetherE2EE.Failure.noKey {
            return keep(.beforeDevice, key)
        } catch {
            return keep(.undecryptable, key)
        }
    }

    private mutating func keep(_ result: Opened, _ key: OpenKey) -> Opened {
        opened[key] = result
        return result
    }

    /// The authors whose devices a set of messages still waits for, to fetch at once.
    public func waitingAuthors(_ messages: [TogetherMessage]) -> Set<String> {
        Set(messages.compactMap { message in
            guard message.sealed != nil, message.deletedAt == nil, opened[Self.key(message)] == nil, let author = message.authorId else { return nil }
            return author
        })
    }

    /// The content key of a sealed message, for a report: unwrapped again with this device's key.
    public func contentKey(_ message: TogetherMessage) -> Data? {
        guard let sealed = message.sealed, let device, let author = message.authorId else { return nil }
        let context = TogetherE2EE.Context(conversationId: message.conversationId, messageId: message.id, senderUserId: author, senderDeviceId: sealed.device)
        return try? TogetherE2EE.unwrapKey(sealed, context, me: device)
    }
}
