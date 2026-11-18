import Foundation

/// The values and message rules of the emulator host's protocol, version 1 (anyps5-retro-host
/// docs/protocol.md), as the launcher's client checks them. As on Windows and Linux (AnyPS5
/// Desktop's lib/core/retro_host/retro_host_protocol.dart), written from the protocol alone.
public enum RetroProtocol {
    /// The protocol version this launcher speaks.
    public static let version = 1
    /// The capability every method of version 1 needs.
    public static let ps1Capability = "ps1"
    /// The capability that plays PS2 games on LRPS2: `start.console` and `status.console`
    /// (protocol.md "Capabilities", anyps5-retro-host docs/ps2.md).
    public static let ps2Capability = "ps2"
    /// The largest call and ping id.
    public static let maxID = 2_147_483_647
    public static let maxUInt32 = 4_294_967_295
    /// The longest message body, and the shortest.
    public static let maxBody = 1_048_576
    public static let minBody = 2
}

/// The other side broke a rule that protocol.md "Protocol errors" lists. The launcher kills the
/// host and handles it as a host failure.
public struct RetroProtocolError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "RetroProtocolError: \(message)" }
}

/// A call's `error` reply (protocol.md "call and reply"). `code` is what programs act on; a code
/// this launcher does not know is a failure without a known cause.
public struct RetroCallError: Error, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String

    public static let unknownMethod = "unknownMethod"
    public static let argument = "argument"
    public static let busy = "busy"
    public static let start = "start"
    public static let tooLarge = "tooLarge"

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "RetroCallError(\(code)): \(message)" }
}

/// The frame pixel formats version 1 defines, and their codes in the ring header.
public enum RetroPixelFormat: String, CaseIterable, Sendable {
    case rgba8, bgra8

    public var code: UInt32 { self == .rgba8 ? 1 : 2 }
}

/// The `errorCode` values a `status` can carry, and the two the client reports itself after a host
/// failure (protocol.md "Host failure").
public enum RetroErrorCode {
    public static let none = ""
    public static let bios = "bios"
    public static let disc = "disc"
    public static let core = "core"
    public static let stalled = "stalled"
    public static let didNotStart = "didNotStart"
    public static let frameTooLarge = "frameTooLarge"
    public static let other = "other"
    public static let hostExited = "hostExited"
    public static let hostHung = "hostHung"
}

/// Reads the fields of a received object, throwing `RetroProtocolError` when one is missing, has
/// the wrong type or is out of its range. Fields it is not asked for are ignored.
struct RetroFields {
    let map: [String: RetroJSON]
    let place: String

    init(_ map: [String: RetroJSON], _ place: String) {
        self.map = map
        self.place = place
    }

    init(_ value: RetroJSON, _ place: String) throws {
        guard let map = value.objectValue else { throw RetroProtocolError("\(place) must be an object.") }
        self.init(map, place)
    }

    private func bad(_ key: String, _ rule: String) -> RetroProtocolError {
        RetroProtocolError("\(place).\(key) \(rule).")
    }

    func has(_ key: String) -> Bool { map[key] != nil }

    func integer(_ key: String, _ range: ClosedRange<Int>) throws -> Int {
        guard let value = map[key]?.intValue else { throw bad(key, "must be an integer") }
        guard range.contains(value) else { throw bad(key, "must be from \(range.lowerBound) to \(range.upperBound)") }
        return value
    }

    func number(_ key: String, above: Double? = nil, atMost: Double? = nil) throws -> Double {
        guard case .number(let value)? = map[key] else { throw bad(key, "must be a number") }
        if let above, !(value > above) { throw bad(key, "must be greater than \(above)") }
        if let atMost, value > atMost { throw bad(key, "must be at most \(atMost)") }
        return value
    }

    func string(_ key: String) throws -> String {
        guard let value = map[key]?.stringValue else { throw bad(key, "must be a string") }
        return value
    }

    func stringOrNull(_ key: String) throws -> String? {
        guard let value = map[key] else { throw bad(key, "is missing") }
        if value.isNull { return nil }
        guard let text = value.stringValue else { throw bad(key, "must be a string or null") }
        return text
    }

    func boolean(_ key: String) throws -> Bool {
        guard let value = map[key]?.boolValue else { throw bad(key, "must be a boolean") }
        return value
    }

    func strings(_ key: String) throws -> [String] {
        guard let items = map[key]?.arrayValue else { throw bad(key, "must be an array of strings") }
        return try items.map { item in
            guard let text = item.stringValue else { throw bad(key, "must be an array of strings") }
            return text
        }
    }

    func object(_ key: String) throws -> RetroFields {
        guard let value = map[key]?.objectValue else { throw bad(key, "must be an object") }
        return RetroFields(value, "\(place).\(key)")
    }
}

/// One core option a `status` lists (protocol.md "status").
public struct RetroOption: Equatable, Sendable {
    public let key: String
    public let title: String
    public let values: [String]
    public let labels: [String]
    public let selected: Int
    public let activeValue: String
    public let restart: Bool

    var json: RetroJSON {
        .object([
            "title": .string(title), "values": .array(values.map { .string($0) }),
            "labels": .array(labels.map { .string($0) }), "selected": .int(selected),
            "activeValue": .string(activeValue), "restart": .bool(restart),
        ])
    }
}

/// The consoles `start.console` names and `status.console` gives (capability `ps2`).
public enum RetroConsole {
    public static let ps1 = "ps1"
    public static let ps2 = "ps2"

    public static let all: Set<String> = [ps1, ps2]
}

/// The discs of a multi-disc game.
public struct RetroDiscs: Equatable, Sendable {
    public let labels: [String]
    /// The inserted disc; nil while the tray is open, or when the core inserted a disc past the 128th.
    public let inserted: Int?
    public let insertedDiscPath: String?
    public let playedDiscPath: String
    public let busy: Bool
    public let failed: Bool

    var json: RetroJSON {
        .object([
            "labels": .array(labels.map { .string($0) }), "inserted": inserted.map(RetroJSON.int) ?? RetroJSON.null,
            "insertedDiscPath": insertedDiscPath.map(RetroJSON.string) ?? RetroJSON.null,
            "playedDiscPath": .string(playedDiscPath), "busy": .bool(busy), "failed": .bool(failed),
        ])
    }
}

/// A loaded game's state, from `status`, or the shorter form the client gives after a host failure.
public struct RetroStatus: Equatable, Sendable {
    public var ready: Bool
    public var ended: Bool
    public var error: String
    public var errorCode: String
    public var aspect: Double = 4.0 / 3.0
    public var hardware = false
    public var resolutionError = ""
    public var graphicsPending = false
    public var progressLabel: String?
    public var progressPercent: Int?
    public var options: [String: RetroOption] = [:]
    /// Memory card 1's file is there but the host could not read it as a card, so it is left as it is
    /// and this game's saves are not written anywhere. False from a status without the field.
    public var cardUnreadable = false
    public var discs: RetroDiscs?
    /// The console the game was started as (`RetroConsole`); nil from a host without the `ps2`
    /// capability.
    public var console: String?

    /// The most discs `status.discs.labels` may list.
    public static let maxDiscs = 128

    /// What the client reports from a host failure until the UI calls `release`.
    public static func failed(error: String, errorCode: String) -> RetroStatus {
        RetroStatus(ready: false, ended: true, error: error, errorCode: errorCode)
    }

    /// The four fields protocol.md "Host failure" gives for a status the client made.
    public var failureJSON: RetroJSON {
        .object(["ready": .bool(ready), "ended": .bool(ended), "error": .string(error), "errorCode": .string(errorCode)])
    }

    /// The status as protocol.md "status" writes it.
    public var json: RetroJSON {
        var map = failureJSON.objectValue!
        map["aspect"] = .number(aspect)
        map["hardware"] = .bool(hardware)
        map["resolutionError"] = .string(resolutionError)
        map["graphicsPending"] = .bool(graphicsPending)
        map["progressLabel"] = progressLabel.map(RetroJSON.string) ?? RetroJSON.null
        map["progressPercent"] = progressPercent.map(RetroJSON.int) ?? RetroJSON.null
        map["options"] = .object(options.mapValues(\.json))
        map["cardUnreadable"] = .bool(cardUnreadable)
        if let discs { map["discs"] = discs.json }
        if let console { map["console"] = .string(console) }
        return .object(map)
    }

    /// Whether `value` is the client's own failure report rather than a host's status, which always
    /// has every field.
    static func isFailureReport(_ value: RetroJSON) -> Bool {
        guard let map = value.objectValue, map.count == 4, let code = map["errorCode"]?.stringValue else { return false }
        return code == RetroErrorCode.hostExited || code == RetroErrorCode.hostHung
    }

    /// Reads a `status` result, throwing `RetroProtocolError` for a field outside what protocol.md
    /// allows. Unknown fields are ignored. A host's `errorCode` of `hostExited` or `hostHung`, which
    /// only the client may report, is read as `other` (protocol.md "status"). A host that lists the
    /// `ps2` capability (`ps2`) sends `console` in every status, `"ps1"` or `"ps2"`; any other host's
    /// `console` is ignored.
    public static func parse(_ value: RetroJSON, ps2: Bool = false) throws -> RetroStatus {
        let f = try RetroFields(value, "status")
        var options: [String: RetroOption] = [:]
        let optionFields = try f.object("options")
        for key in optionFields.map.keys {
            let o = try optionFields.object(key)
            let values = try o.strings("values")
            let labels = try o.strings("labels")
            guard labels.count == values.count else { throw RetroProtocolError("status.options.\(key).labels must match values.") }
            guard !values.isEmpty else { throw RetroProtocolError("status.options.\(key).values is empty.") }
            options[key] = RetroOption(
                key: key, title: try o.string("title"), values: values, labels: labels,
                selected: try o.integer("selected", 0...(values.count - 1)), activeValue: try o.string("activeValue"),
                restart: try o.boolean("restart"))
        }
        var discs: RetroDiscs?
        if f.has("discs") {
            let d = try f.object("discs")
            let labels = try d.strings("labels")
            guard labels.count <= maxDiscs else { throw RetroProtocolError("status.discs.labels has more than 128 discs.") }
            guard let insertedValue = d.map["inserted"] else { throw RetroProtocolError("status.discs.inserted is missing.") }
            var inserted: Int?
            if !insertedValue.isNull {
                guard let index = insertedValue.intValue, index >= 0, index < labels.count else {
                    throw RetroProtocolError("status.discs.inserted must be a disc index or null.")
                }
                inserted = index
            }
            discs = RetroDiscs(
                labels: labels, inserted: inserted, insertedDiscPath: try d.stringOrNull("insertedDiscPath"),
                playedDiscPath: try d.string("playedDiscPath"), busy: try d.boolean("busy"), failed: try d.boolean("failed"))
        }
        guard let percentValue = f.map["progressPercent"] else { throw RetroProtocolError("status.progressPercent is missing.") }
        var percent: Int?
        if !percentValue.isNull {
            guard let value = percentValue.intValue, (0...100).contains(value) else {
                throw RetroProtocolError("status.progressPercent must be an integer from 0 to 100 or null.")
            }
            percent = value
        }
        let code = try f.string("errorCode")
        var status = RetroStatus(
            ready: try f.boolean("ready"), ended: try f.boolean("ended"), error: try f.string("error"),
            errorCode: code == RetroErrorCode.hostExited || code == RetroErrorCode.hostHung ? RetroErrorCode.other : code)
        status.aspect = try f.number("aspect", above: 0, atMost: 10)
        status.hardware = try f.boolean("hardware")
        status.resolutionError = try f.string("resolutionError")
        status.graphicsPending = try f.boolean("graphicsPending")
        status.progressLabel = try f.stringOrNull("progressLabel")
        status.progressPercent = percent
        status.options = options
        status.cardUnreadable = try f.has("cardUnreadable") ? f.boolean("cardUnreadable") : false
        status.discs = discs
        if ps2 {
            let console = try f.string("console")
            guard RetroConsole.all.contains(console) else { throw RetroProtocolError("status.console \(console) is unknown.") }
            status.console = console
        }
        return status
    }
}
