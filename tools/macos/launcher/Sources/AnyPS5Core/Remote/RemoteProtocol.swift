import Foundation

/// A game as the phone lists it. `art` changes whenever its icon or background does, so the
/// phone asks for the pictures again only then.
public struct RemoteGame: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case installed, update, locked, installing, starting, running, unavailable
    }

    public var id: String
    public var name: String
    public var state: State
    public var trophies: String?
    public var art: String
    /// The phone's pad layout saved for this game (the phone's own JSON), nil for the default.
    public var layout: String?

    public init(id: String, name: String, state: State, trophies: String?, art: String, layout: String? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.trophies = trophies
        self.art = art
        self.layout = layout
    }
}

/// What the launcher is doing with a game, for the phone to show: unlocking or updating it (the
/// installer's steps, with how far along), waiting for its turn, or starting it.
public struct RemoteActivity: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case queued, unwrap, relink, copy, bundle, finish, starting
    }

    public var id: String
    public var phase: Phase
    /// An installed game being made again for a newer engine, rather than unlocked the first time.
    public var updating: Bool
    /// How much of the whole install is done, 0 to 1; nil when how long is not known.
    public var fraction: Double?
    /// Seconds since the launcher began with the game; the phone keeps counting from it.
    public var elapsed: Double

    public init(id: String, phase: Phase, updating: Bool, fraction: Double?, elapsed: Double) {
        self.id = id
        self.phase = phase
        self.updating = updating
        self.fraction = fraction
        self.elapsed = elapsed
    }

    /// Whether the phone would show the same: the time it counts itself, and a hundredth of
    /// progress is not worth a message.
    public func looksLike(_ other: RemoteActivity) -> Bool {
        guard id == other.id, phase == other.phase, updating == other.updating else { return false }
        switch (fraction, other.fraction) {
        case (nil, nil): return true
        case let (mine?, theirs?): return abs(mine - theirs) < 0.01
        default: return false
        }
    }

    /// Whether the phone, told `told`, already shows `now`.
    public static func same(_ told: RemoteActivity?, _ now: RemoteActivity?) -> Bool {
        switch (told, now) {
        case (nil, nil): return true
        case let (told?, now?): return told.looksLike(now)
        default: return false
        }
    }
}

/// What text the game asks for, for a phone to type it: the game's keyboard (sceImeOpen) or its
/// text dialog (sceImeDialogInit), from the engine's prompt datagram (APRK).
public struct RemoteTextPrompt: Codable, Equatable, Sendable {
    /// The engine's number for this keyboard or dialog; the typed text names it.
    public var id: UInt32
    /// "keyboard" or "dialog".
    public var kind: String
    public var title: String
    public var placeholder: String
    /// The text the game starts with.
    public var text: String
    /// The most characters the game takes (UTF-16 units, as it counts them).
    public var maxLength: Int
    public var multiline: Bool
    /// The keys the console would show: text, latin, url, mail or number.
    public var keyboard: String
    /// The Enter key's label: default, send, search or go.
    public var enter: String

    public init(id: UInt32, kind: String = "dialog", title: String = "", placeholder: String = "", text: String = "", maxLength: Int = 0,
                multiline: Bool = false, keyboard: String = "text", enter: String = "default") {
        self.id = id
        self.kind = kind
        self.title = title
        self.placeholder = placeholder
        self.text = text
        self.maxLength = maxLength
        self.multiline = multiline
        self.keyboard = keyboard
        self.enter = enter
    }

    static let keyboards = ["text", "latin", "url", "mail", "number"]
    static let enters = ["default", "send", "search", "go"]
}

/// What a phone does with the text it typed: send it as the game's text so far, enter it, or
/// cancel the game's keyboard.
public enum TypedAction: String, Codable, Sendable {
    case update, submit, cancel

    var code: UInt8 {
        switch self {
        case .update: return 0
        case .submit: return 1
        case .cancel: return 2
        }
    }
}

/// A message on the phone's control channel: one JSON object per WebSocket text frame, told
/// apart by its `type`.
public enum RemoteMessage: Codable, Equatable, Sendable {
    /// The phone introduces itself; `key` is the one a previous pairing gave it.
    case hello(protocol: Int, deviceID: String, deviceName: String, key: String?)
    /// The Mac is asking its user to allow the phone; both show `code`.
    case pairing(code: String)
    /// The phone may send pad packets with `session` to `udpPort`; `key` lets it in next time.
    /// togetherServer: the AnyTogether server the launcher uses, so the phone can say when it is
    /// not its own; older launchers leave it out.
    case welcome(session: UInt64, udpPort: UInt16, macName: String, key: String, togetherServer: String? = nil)
    case rejected(reason: String)
    /// The phone's measured latency, every two seconds.
    case latency(milliseconds: Double)
    /// The launcher's games as it shows them, with the one selected, the one playing and the
    /// language, sent again whenever any of it changes.
    case library(games: [RemoteGame], selected: String?, running: String?, language: String)
    /// A game's pictures as base64 JPEG, after the phone asked with `wantArt`.
    case art(id: String, icon: String?, background: String?)
    case wantArt(id: String)
    /// A move on the launcher's screen: left, right, up, down, select, back or options.
    case command(name: String)
    case select(id: String)
    /// What Play does for the game; another game playing is stopped first.
    case launch(id: String)
    /// Stops the game playing.
    case close
    /// The PS button: the launcher comes in front of the game.
    case home
    /// The phone's pad layout for a game, kept with the game's settings; nil goes back to the default.
    case saveLayout(id: String, layout: String?)
    /// A trophy just earned in the game playing: its name, description, grade (platinum, gold,
    /// silver or bronze) and icon as base64 PNG.
    case trophy(name: String, detail: String, grade: String, icon: String?)
    /// What the launcher is doing with a game, sent as it changes; nil once it is done.
    case activity(RemoteActivity?)
    /// The launcher's theme for the phone to wear: its deep and middle tones and its accent, #RRGGBB.
    case look(deep: String, middle: String, accent: String)
    /// Remote Play: the phone wants the game's picture and sound at about this size, or no more.
    case stream(on: Bool, width: Int, height: Int)
    /// The phone lost part of the picture and waits for a key frame.
    case keyFrame
    /// How Remote Play is going for the phone: on, off, noPermission (screen recording) or noGame.
    case streaming(state: String)
    /// Whether the game is being broadcast (Twitch, YouTube, RTMP), for the phone's Go live button;
    /// the phone starts and stops it with the commands broadcastStart and broadcastStop.
    case broadcast(on: Bool)
    /// AnyTogether: either side asks the other, already signed in, to sign it in. The id is the
    /// hand-off the asker started with the server; deviceName is shown before approving.
    case togetherHandoff(id: String, deviceName: String)
    /// The answer: approved on the server, or turned down.
    case togetherHandoffAnswer(id: String, approved: Bool)
    /// The game asks for text, or (nil) no longer does: the phone shows its own keyboard with the
    /// game's prompt. A phone that does not know this message ignores it.
    case textInput(RemoteTextPrompt?)
    /// The text a phone typed for a prompt (its id), replacing the game's, and what to do with it.
    case typed(prompt: UInt32, text: String, action: TypedAction)

    public static let protocolVersion = 1

    enum CodingKeys: String, CodingKey {
        case type, `protocol`, deviceID, deviceName, key, code, session, udpPort, macName, reason, milliseconds, togetherServer
        case games, selected, running, language, id, icon, background, name, layout, detail, grade, activity, deep, middle, accent, on, width, height, state, approved
        case prompt, text, action
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(protocol: try values.decode(Int.self, forKey: .protocol), deviceID: try values.decode(String.self, forKey: .deviceID),
                          deviceName: try values.decode(String.self, forKey: .deviceName), key: try values.decodeIfPresent(String.self, forKey: .key))
        case "pairing":
            self = .pairing(code: try values.decode(String.self, forKey: .code))
        case "welcome":
            let text = try values.decode(String.self, forKey: .session)
            guard let session = UInt64(text) else {
                throw DecodingError.dataCorruptedError(forKey: .session, in: values, debugDescription: "session is not a decimal UInt64")
            }
            self = .welcome(session: session, udpPort: try values.decode(UInt16.self, forKey: .udpPort), macName: try values.decode(String.self, forKey: .macName),
                            key: try values.decode(String.self, forKey: .key), togetherServer: try? values.decodeIfPresent(String.self, forKey: .togetherServer))
        case "rejected":
            self = .rejected(reason: try values.decode(String.self, forKey: .reason))
        case "latency":
            self = .latency(milliseconds: try values.decode(Double.self, forKey: .milliseconds))
        case "library":
            self = .library(games: try values.decode([RemoteGame].self, forKey: .games), selected: try values.decodeIfPresent(String.self, forKey: .selected),
                            running: try values.decodeIfPresent(String.self, forKey: .running), language: try values.decode(String.self, forKey: .language))
        case "art":
            self = .art(id: try values.decode(String.self, forKey: .id), icon: try values.decodeIfPresent(String.self, forKey: .icon),
                        background: try values.decodeIfPresent(String.self, forKey: .background))
        case "wantArt":
            self = .wantArt(id: try values.decode(String.self, forKey: .id))
        case "command":
            self = .command(name: try values.decode(String.self, forKey: .name))
        case "select":
            self = .select(id: try values.decode(String.self, forKey: .id))
        case "launch":
            self = .launch(id: try values.decode(String.self, forKey: .id))
        case "close":
            self = .close
        case "home":
            self = .home
        case "saveLayout":
            self = .saveLayout(id: try values.decode(String.self, forKey: .id), layout: try values.decodeIfPresent(String.self, forKey: .layout))
        case "trophy":
            self = .trophy(name: try values.decode(String.self, forKey: .name), detail: try values.decode(String.self, forKey: .detail),
                           grade: try values.decode(String.self, forKey: .grade), icon: try values.decodeIfPresent(String.self, forKey: .icon))
        case "activity":
            self = .activity(try values.decodeIfPresent(RemoteActivity.self, forKey: .activity))
        case "stream":
            self = .stream(on: try values.decode(Bool.self, forKey: .on), width: try values.decodeIfPresent(Int.self, forKey: .width) ?? 0,
                           height: try values.decodeIfPresent(Int.self, forKey: .height) ?? 0)
        case "keyFrame":
            self = .keyFrame
        case "streaming":
            self = .streaming(state: try values.decode(String.self, forKey: .state))
        case "broadcast":
            self = .broadcast(on: try values.decode(Bool.self, forKey: .on))
        case "look":
            self = .look(deep: try values.decode(String.self, forKey: .deep), middle: try values.decode(String.self, forKey: .middle), accent: try values.decode(String.self, forKey: .accent))
        case "togetherHandoff":
            self = .togetherHandoff(id: try values.decode(String.self, forKey: .id), deviceName: try values.decode(String.self, forKey: .deviceName))
        case "togetherHandoffAnswer":
            self = .togetherHandoffAnswer(id: try values.decode(String.self, forKey: .id), approved: try values.decode(Bool.self, forKey: .approved))
        case "textInput":
            self = .textInput(try values.decodeIfPresent(RemoteTextPrompt.self, forKey: .prompt))
        case "typed":
            self = .typed(prompt: try values.decode(UInt32.self, forKey: .prompt), text: try values.decode(String.self, forKey: .text),
                          action: try values.decode(TypedAction.self, forKey: .action))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "unknown message type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let version, let deviceID, let deviceName, let key):
            try values.encode("hello", forKey: .type)
            try values.encode(version, forKey: .protocol)
            try values.encode(deviceID, forKey: .deviceID)
            try values.encode(deviceName, forKey: .deviceName)
            try values.encode(key, forKey: .key)
        case .pairing(let code):
            try values.encode("pairing", forKey: .type)
            try values.encode(code, forKey: .code)
        case .welcome(let session, let udpPort, let macName, let key, let togetherServer):
            try values.encode("welcome", forKey: .type)
            try values.encode(String(session), forKey: .session)
            try values.encode(udpPort, forKey: .udpPort)
            try values.encode(macName, forKey: .macName)
            try values.encode(key, forKey: .key)
            try values.encodeIfPresent(togetherServer, forKey: .togetherServer)
        case .rejected(let reason):
            try values.encode("rejected", forKey: .type)
            try values.encode(reason, forKey: .reason)
        case .latency(let milliseconds):
            try values.encode("latency", forKey: .type)
            try values.encode(milliseconds, forKey: .milliseconds)
        case .library(let games, let selected, let running, let language):
            try values.encode("library", forKey: .type)
            try values.encode(games, forKey: .games)
            try values.encode(selected, forKey: .selected)
            try values.encode(running, forKey: .running)
            try values.encode(language, forKey: .language)
        case .art(let id, let icon, let background):
            try values.encode("art", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(icon, forKey: .icon)
            try values.encode(background, forKey: .background)
        case .wantArt(let id):
            try values.encode("wantArt", forKey: .type)
            try values.encode(id, forKey: .id)
        case .command(let name):
            try values.encode("command", forKey: .type)
            try values.encode(name, forKey: .name)
        case .select(let id):
            try values.encode("select", forKey: .type)
            try values.encode(id, forKey: .id)
        case .launch(let id):
            try values.encode("launch", forKey: .type)
            try values.encode(id, forKey: .id)
        case .close:
            try values.encode("close", forKey: .type)
        case .home:
            try values.encode("home", forKey: .type)
        case .saveLayout(let id, let layout):
            try values.encode("saveLayout", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(layout, forKey: .layout)
        case .trophy(let name, let detail, let grade, let icon):
            try values.encode("trophy", forKey: .type)
            try values.encode(name, forKey: .name)
            try values.encode(detail, forKey: .detail)
            try values.encode(grade, forKey: .grade)
            try values.encode(icon, forKey: .icon)
        case .activity(let activity):
            try values.encode("activity", forKey: .type)
            try values.encode(activity, forKey: .activity)
        case .stream(let on, let width, let height):
            try values.encode("stream", forKey: .type)
            try values.encode(on, forKey: .on)
            try values.encode(width, forKey: .width)
            try values.encode(height, forKey: .height)
        case .keyFrame:
            try values.encode("keyFrame", forKey: .type)
        case .streaming(let state):
            try values.encode("streaming", forKey: .type)
            try values.encode(state, forKey: .state)
        case .broadcast(let on):
            try values.encode("broadcast", forKey: .type)
            try values.encode(on, forKey: .on)
        case .look(let deep, let middle, let accent):
            try values.encode("look", forKey: .type)
            try values.encode(deep, forKey: .deep)
            try values.encode(middle, forKey: .middle)
            try values.encode(accent, forKey: .accent)
        case .togetherHandoff(let id, let deviceName):
            try values.encode("togetherHandoff", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(deviceName, forKey: .deviceName)
        case .togetherHandoffAnswer(let id, let approved):
            try values.encode("togetherHandoffAnswer", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(approved, forKey: .approved)
        case .textInput(let prompt):
            try values.encode("textInput", forKey: .type)
            try values.encode(prompt, forKey: .prompt)
        case .typed(let prompt, let text, let action):
            try values.encode("typed", forKey: .type)
            try values.encode(prompt, forKey: .prompt)
            try values.encode(text, forKey: .text)
            try values.encode(action, forKey: .action)
        }
    }

    /// The message's type, as its JSON names it.
    public var kind: String {
        switch self {
        case .hello: return "hello"
        case .pairing: return "pairing"
        case .welcome: return "welcome"
        case .rejected(let reason): return "rejected(\(reason))"
        case .latency: return "latency"
        case .library(let games, _, let running, let language): return "library(\(games.count) games, running \(running != nil), \(language))"
        case .art(_, let icon, let background): return "art(icon \(icon?.count ?? 0), background \(background?.count ?? 0))"
        case .wantArt: return "wantArt"
        case .command(let name): return "command(\(name))"
        case .select: return "select"
        case .launch: return "launch"
        case .close: return "close"
        case .home: return "home"
        case .saveLayout(_, let layout): return "saveLayout(\(layout?.count ?? 0) bytes)"
        case .trophy(let name, _, let grade, _): return "trophy(\(grade), \(name))"
        case .look(_, _, let accent): return "look(\(accent))"
        case .stream(let on, let width, let height): return "stream(\(on) \(width)x\(height))"
        case .keyFrame: return "keyFrame"
        case .streaming(let state): return "streaming(\(state))"
        case .broadcast(let on): return "broadcast(\(on))"
        case .togetherHandoff: return "togetherHandoff"
        case .togetherHandoffAnswer(_, let approved): return "togetherHandoffAnswer(\(approved))"
        case .textInput(let prompt): return "textInput(\(prompt.map { "\($0.id) \($0.kind)" } ?? "none"))"
        case .typed(let prompt, let text, let action): return "typed(\(prompt), \(text.count) characters, \(action.rawValue))"
        case .activity(let activity): return "activity(\(activity.map { "\($0.phase.rawValue) \($0.fraction.map { String(format: "%.2f", $0) } ?? "-")" } ?? "none"))"
        }
    }

    /// The message as the text of one WebSocket frame.
    public var text: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// The pad datagrams the launcher relays between the phone and the game, the engine's
/// RemotePad wire format: little-endian, with a magic, a version and a size up front.
public enum RemotePacket {
    public static let inputMagic: UInt32 = 0x4952_5041
    public static let outputMagic: UInt32 = 0x4F52_5041
    public static let helloMagic: UInt32 = 0x4852_5041
    public static let pressMagic: UInt32 = 0x5052_5041
    public static let promptMagic: UInt32 = 0x4B52_5041
    public static let textMagic: UInt32 = 0x5452_5041
    public static let assistMagic: UInt32 = 0x4152_5041
    public static let assistSize = 16
    /// Byte 13 of an input: 1 marks a device that helps the first player (assist).
    public static let seatByte = 13
    public static let assistSeat: UInt8 = 1
    /// The assist datagram's flag: the Mac's other controllers help the first player.
    public static let assistControllers: UInt32 = 1
    public static let version: UInt16 = 1
    public static let promptHeaderSize = 24
    public static let textHeaderSize = 20
    /// The largest prompt or text datagram (the engine's LargestTextDatagram).
    public static let largestText = 8192
    public static let inputSize = 80
    public static let outputSize = 32
    public static let helloSize = 16
    public static let pressSize = 24

    /// The session of a well-formed input packet, nil for anything else.
    public static func inputSession(_ data: Data) -> UInt64? {
        guard header(data, magic: inputMagic, size: inputSize) else { return nil }
        return read(data, at: 24)
    }

    public static func isOutput(_ data: Data) -> Bool { header(data, magic: outputMagic, size: outputSize) }

    public static func isHello(_ data: Data) -> Bool { header(data, magic: helloMagic, size: helloSize) }

    /// The player a game's hello says its bridge's phone is, from 1; nil while it is none.
    public static func helloPlayer(_ data: Data) -> Int? {
        guard isHello(data) else { return nil }
        let player = data[data.startIndex + 8]
        return player == 0 ? nil : Int(player)
    }

    /// Whether a game's hello says its engine takes presses (bit 0 of byte 9).
    public static func helloTakesPresses(_ data: Data) -> Bool {
        isHello(data) && data[data.startIndex + 9] & 1 != 0
    }

    /// Whether a game's hello says its engine tells what text the game asks for and takes the
    /// text typed for it (bit 1 of byte 9).
    public static func helloTakesText(_ data: Data) -> Bool {
        isHello(data) && data[data.startIndex + 9] & 2 != 0
    }

    /// Whether a game's hello says its engine takes assist (bit 2 of byte 9): the assist datagram
    /// and inputs marked as helping the first player.
    public static func helloTakesAssist(_ data: Data) -> Bool {
        isHello(data) && data[data.startIndex + 9] & 4 != 0
    }

    /// The assist datagram (APRA): whether the Mac's controllers after the first player's help
    /// the first player instead of being players of their own.
    public static func assist(controllers: Bool) -> Data {
        var bytes = [UInt8](repeating: 0, count: assistSize)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(assistMagic, at: 0)
        put(version, at: 4)
        put(UInt16(assistSize), at: 6)
        put(controllers ? assistControllers : 0, at: 8)
        return Data(bytes)
    }

    /// An input packet marked as helping the first player (byte 13 = 1); anything else unchanged.
    public static func helping(_ data: Data) -> Data {
        guard inputSession(data) != nil else { return data }
        var marked = data
        marked[marked.startIndex + seatByte] = assistSeat
        return marked
    }

    /// A game's prompt (APRK): `.some(nil)` when it says no text is asked for any more, nil for
    /// anything that is not a well-formed prompt.
    public static func prompt(_ data: Data) -> RemoteTextPrompt?? {
        guard data.count >= promptHeaderSize, data.count <= largestText, read(data, at: 0) as UInt32 == promptMagic,
              read(data, at: 4) as UInt16 == version, Int(read(data, at: 6) as UInt16) == data.count else { return nil }
        let bytes = [UInt8](data)
        guard bytes[12] <= 2 else { return nil }
        let lengths = [Int(read(data, at: 18) as UInt16), Int(read(data, at: 20) as UInt16), Int(read(data, at: 22) as UInt16)]
        guard promptHeaderSize + lengths.reduce(0, +) == data.count else { return nil }
        let id: UInt32 = read(data, at: 8)
        guard id != 0, bytes[12] != 0 else { return .some(nil) }
        var strings: [String] = []
        var at = promptHeaderSize
        for length in lengths {
            strings.append(String(decoding: bytes[at..<(at + length)], as: UTF8.self))
            at += length
        }
        let keyboard = Int(bytes[14]) < RemoteTextPrompt.keyboards.count ? RemoteTextPrompt.keyboards[Int(bytes[14])] : "text"
        let enter = Int(bytes[15]) < RemoteTextPrompt.enters.count ? RemoteTextPrompt.enters[Int(bytes[15])] : "default"
        return .some(RemoteTextPrompt(id: id, kind: bytes[12] == 1 ? "keyboard" : "dialog", title: strings[0], placeholder: strings[1], text: strings[2],
                                      maxLength: Int(read(data, at: 16) as UInt16), multiline: bytes[13] & 1 != 0, keyboard: keyboard, enter: enter))
    }

    /// A prompt as the engine sends it, nil for none (a stand-in game in the tests).
    public static func promptPacket(_ prompt: RemoteTextPrompt?) -> Data {
        let parts = [prompt?.title ?? "", prompt?.placeholder ?? "", prompt?.text ?? ""].map { [UInt8]($0.utf8) }
        var bytes = [UInt8](repeating: 0, count: promptHeaderSize)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(promptMagic, at: 0)
        put(version, at: 4)
        put(UInt16(promptHeaderSize + parts.map(\.count).reduce(0, +)), at: 6)
        put(prompt?.id ?? 0, at: 8)
        if let prompt {
            bytes[12] = prompt.kind == "keyboard" ? 1 : 2
            bytes[13] = prompt.multiline ? 1 : 0
            bytes[14] = UInt8(RemoteTextPrompt.keyboards.firstIndex(of: prompt.keyboard) ?? 0)
            bytes[15] = UInt8(RemoteTextPrompt.enters.firstIndex(of: prompt.enter) ?? 0)
            put(UInt16(clamping: prompt.maxLength), at: 16)
        }
        for (index, part) in parts.enumerated() { put(UInt16(part.count), at: 18 + index * 2) }
        return Data(bytes + parts.joined())
    }

    /// The text a phone typed (APRT), for the engine: the whole text, replacing the game's, then
    /// the action. `id` tells copies apart; the text is cut on a character to fit one datagram.
    public static func text(prompt: UInt32, id: UInt32, action: TypedAction, text: String) -> Data {
        var utf8: [UInt8] = []
        for character in text {
            let encoded = [UInt8](String(character).utf8)
            if textHeaderSize + utf8.count + encoded.count > largestText { break }
            utf8 += encoded
        }
        var bytes = [UInt8](repeating: 0, count: textHeaderSize)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(textMagic, at: 0)
        put(version, at: 4)
        put(UInt16(textHeaderSize + utf8.count), at: 6)
        put(prompt, at: 8)
        put(id, at: 12)
        bytes[16] = action.code
        put(UInt16(utf8.count), at: 18)
        return Data(bytes + utf8)
    }

    /// A press (APRP): `buttons` held on the game's first player's pad for `holdMillis`, whoever
    /// drives it, without taking a seat. A copy with the same `id` counts once.
    public static func press(id: UInt32, buttons: UInt32, holdMillis: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: pressSize)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(pressMagic, at: 0)
        put(version, at: 4)
        put(UInt16(pressSize), at: 6)
        put(id, at: 8)
        put(buttons, at: 12)
        put(holdMillis, at: 16)
        return Data(bytes)
    }

    static func header(_ data: Data, magic: UInt32, size: Int) -> Bool {
        data.count == size && read(data, at: 0) as UInt32 == magic && read(data, at: 4) as UInt16 == version && Int(read(data, at: 6) as UInt16) == size
    }

    static func read<T: FixedWidthInteger>(_ data: Data, at offset: Int) -> T {
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { target in
            data.withUnsafeBytes { source in
                target.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[(source.startIndex + offset)..<(source.startIndex + offset + MemoryLayout<T>.size)]))
            }
        }
        return T(littleEndian: value)
    }
}
