import Foundation

/// What the browser pad page says on its WebSocket, one small JSON object per text frame
/// (BrowserPad/index.html speaks the other side):
///
/// - `{"t":"pad","b":bits,"s":[lx,ly,rx,ry],"l2":0-255,"r2":0-255,"tp":[[id,x,y]]}`: the whole pad,
///   sent on every change and again every 200 ms while nothing changes;
/// - `{"t":"btn","n":"ps"|"create"}`: the PS and Create buttons, which are the launcher's, not
///   the game's (the phone app sends them the same way);
/// - `{"t":"ping","at":ms}`, answered with a pong; `{"t":"lat","ms":ms}`, the latency it measured;
/// - `{"t":"type","id":prompt,"text":"...","a":"update"|"submit"|"cancel"}`: the text typed for the
///   game's keyboard (`{"t":"ime",...}`), replacing the game's.
public enum BrowserPadMessage: Equatable, Sendable {
    case pad(SharePadState)
    case button(String)
    case ping(Double)
    case latency(Double)
    case typed(prompt: UInt32, text: String, action: TypedAction)

    /// The pad buttons a page may hold: every libScePad bit the phone app sends, nothing else.
    public static let buttonMask: UInt32 = 0x0002 | 0x0004 | 0x0008 | 0x00F0 | 0x0F00 | 0xF000 | 0x100000
    /// A text frame longer than this is not one of the page's (a typed text is the longest).
    public static let maxLength = 4096

    public static func parse(_ text: String) -> BrowserPadMessage? {
        guard text.utf8.count <= maxLength, let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["t"] as? String else { return nil }
        switch type {
        case "pad":
            return pad(object).map(BrowserPadMessage.pad)
        case "btn":
            guard let name = object["n"] as? String, ["ps", "create"].contains(name) else { return nil }
            return .button(name)
        case "ping":
            guard let at = number(object["at"]) else { return nil }
            return .ping(at)
        case "lat":
            guard let ms = number(object["ms"]), ms >= 0, ms < 10_000 else { return nil }
            return .latency(ms)
        case "type":
            guard let id = number(object["id"]), id >= 1, id <= Double(UInt32.max), let text = object["text"] as? String,
                  let action = TypedAction(rawValue: object["a"] as? String ?? "") else { return nil }
            return .typed(prompt: UInt32(id), text: text, action: action)
        default:
            return nil
        }
    }

    /// The pad from a `pad` message: buttons kept to the pad's own bits, every value clamped;
    /// a trigger pulled shows as its button and a trigger's button as a full pull.
    static func pad(_ object: [String: Any]) -> SharePadState? {
        guard let bits = number(object["b"]), bits >= 0, bits <= Double(UInt32.max) else { return nil }
        var state = SharePadState()
        state.buttons = UInt32(bits) & buttonMask
        if let sticks = object["s"] {
            guard let axes = sticks as? [Any], axes.count == 4 else { return nil }
            var values: [UInt8] = []
            for axis in axes {
                guard let value = number(axis) else { return nil }
                values.append(byte(value))
            }
            state.sticks = values
        }
        state.l2 = byte(number(object["l2"]) ?? 0)
        state.r2 = byte(number(object["r2"]) ?? 0)
        for (bit, keyPath) in [(SharePadState.Button.l2, \SharePadState.l2), (SharePadState.Button.r2, \SharePadState.r2)] {
            if state[keyPath: keyPath] > 0 { state.buttons |= bit } else if state.buttons & bit != 0 { state[keyPath: keyPath] = 255 }
        }
        if let points = object["tp"] as? [Any] {
            for point in points.prefix(2) {
                guard let values = point as? [Any], values.count == 3, let id = number(values[0]), let x = number(values[1]), let y = number(values[2]) else { continue }
                state.touches.append(.init(id: UInt8(max(0, min(255, id))), x: UInt16(max(0, min(1919, x))), y: UInt16(max(0, min(1079, y)))))
            }
        }
        return state
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
}

/// What the launcher tells the page, as the JSON text it sends.
public enum BrowserPadReply: Equatable, Sendable {
    /// Waiting for the launcher's phone server.
    case wait
    /// The launcher asks its user to allow this browser; both screens show `code`.
    case pairing(code: String)
    case welcome(host: String)
    /// Every seat is taken, or another device is being asked about: the page waits.
    case busy
    case rejected(reason: String)
    /// The game's vibration (0-255 each) and light bar for this pad.
    case output(large: UInt8, small: UInt8, light: (UInt8, UInt8, UInt8)?)
    /// The player this pad is in the game, from 1; 0 while it is none.
    case player(Int)
    case look(deep: String, middle: String, accent: String)
    case pong(Double)
    /// The game asks for text (the page shows a keyboard), or no longer does (nil).
    case ime(RemoteTextPrompt?)

    public static func == (left: BrowserPadReply, right: BrowserPadReply) -> Bool { left.text == right.text }

    public var text: String {
        let object: [String: Any]
        switch self {
        case .wait: object = ["t": "wait"]
        case .pairing(let code): object = ["t": "pairing", "code": code]
        case .welcome(let host): object = ["t": "welcome", "host": host]
        case .busy: object = ["t": "busy"]
        case .rejected(let reason): object = ["t": "rejected", "reason": reason]
        case .output(let large, let small, let light):
            var values: [String: Any] = ["t": "out", "big": Int(large), "small": Int(small)]
            if let light { values["rgb"] = String(format: "#%02x%02x%02x", light.0, light.1, light.2) }
            object = values
        case .player(let number): object = ["t": "player", "n": number]
        case .look(let deep, let middle, let accent): object = ["t": "look", "deep": deep, "middle": middle, "accent": accent]
        case .pong(let at): object = ["t": "pong", "at": at]
        case .ime(let prompt):
            if let prompt {
                object = ["t": "ime", "id": Int(prompt.id), "kind": prompt.kind, "title": prompt.title, "placeholder": prompt.placeholder, "text": prompt.text,
                          "max": prompt.maxLength, "multi": prompt.multiline, "kb": prompt.keyboard, "enter": prompt.enter]
            } else {
                object = ["t": "ime", "id": 0]
            }
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The game's answer packet (RemotePacket output) as the page hears it; nil for anything else.
    public static func output(_ packet: Data) -> BrowserPadReply? {
        guard RemotePacket.isOutput(packet) else { return nil }
        let bytes = [UInt8](packet)
        return .output(large: bytes[24], small: bytes[25], light: bytes[26] != 0 ? (bytes[27], bytes[28], bytes[29]) : nil)
    }
}
