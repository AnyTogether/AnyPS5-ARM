import Foundation

/// How the game's sound reaches a share play viewer, agreed per viewer.
///
/// Every host sends 16-bit stereo PCM on the "audio" data channel (5 ms StreamPacket audio,
/// ~1.5 Mbit/s) unless told otherwise. A viewer that can play an Opus audio track says so with a
/// text message on that channel once it opens (`ShareAudioHello`); a host that understands it adds
/// the game's sound to that viewer's connection as a WebRTC audio track (Opus, stereo, ~128 kbit/s,
/// with the browser's own jitter buffer, loss concealment and lip sync to the picture), offers
/// again, and stops the PCM for that viewer once the answer takes the track. Old hosts ignore the
/// hello and old viewers never send one, so either side alone keeps working on PCM.
public enum ShareAudioCodec: String, Sendable, CaseIterable {
    /// An RTP audio track on the connection, Opus stereo.
    case opus
    /// StreamPacket audio on the "audio" data channel.
    case pcm
}

/// A viewer's word on the "audio" channel: `{"type":"audio-hello","v":1,"codecs":["opus","pcm"]}`,
/// as a text message (the PCM packets are binary).
public struct ShareAudioHello: Equatable, Sendable {
    public static let type = "audio-hello"
    public static let version = 1
    public var codecs: [ShareAudioCodec]

    public init(codecs: [ShareAudioCodec]) { self.codecs = codecs }

    public var text: String {
        let list = codecs.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        return "{\"type\":\"\(Self.type)\",\"v\":\(Self.version),\"codecs\":[\(list)]}"
    }

    /// A hello from its text; unknown codecs are left out, anything else is nil.
    public init?(text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["type"] as? String == Self.type, let names = object["codecs"] as? [String] else { return nil }
        codecs = names.compactMap(ShareAudioCodec.init(rawValue:))
    }

    /// What the host sends a viewer who said this (Opus whenever they can take it).
    public var chosen: ShareAudioCodec { codecs.contains(.opus) ? .opus : .pcm }
}

/// The SDP side of the Opus track.
public enum ShareAudioSDP {
    /// What the game's sound is sent at.
    public static let kbps = 128
    /// Opus frames of 10 ms rather than WebRTC's 20: the jitter buffer can hold less.
    public static let frameMs = 10

    /// Every Opus format of `sdp` (an answer) asking for stereo, and, with `kbps`, for that average
    /// bit rate with in-band FEC and no silence suppression. A viewer applies it to its own answer
    /// (WebRTC decodes stereo only when the receiver's description asks for it); the host applies
    /// it, with the rate, to the answer before taking it (the sender encodes as the remote
    /// description asks).
    public static func stereoOpus(_ sdp: String, kbps: Int? = nil, frameMs: Int? = nil) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"a=rtpmap:(\d+) opus/48000/2"#, options: .caseInsensitive) else { return sdp }
        let whole = NSRange(sdp.startIndex..., in: sdp)
        let payloads = pattern.matches(in: sdp, range: whole).compactMap { match in Range(match.range(at: 1), in: sdp).map { String(sdp[$0]) } }
        guard !payloads.isEmpty else { return sdp }
        let newline = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: newline)
        var wanted: [(String, String)] = [("stereo", "1"), ("sprop-stereo", "1")]
        if let kbps { wanted += [("maxaveragebitrate", String(kbps * 1000)), ("useinbandfec", "1"), ("usedtx", "0")] }
        for payload in payloads {
            let prefix = "a=fmtp:\(payload) "
            if let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
                lines[index] = prefix + merge(String(lines[index].dropFirst(prefix.count)), wanted)
            } else if let rtpmap = lines.firstIndex(where: { $0.hasPrefix("a=rtpmap:\(payload) ") }) {
                lines.insert(prefix + merge("", wanted), at: rtpmap + 1)
            }
        }
        if let frameMs, let audio = lines.firstIndex(where: { $0.hasPrefix("m=audio ") }) {
            let end = lines[(audio + 1)...].firstIndex(where: { $0.hasPrefix("m=") }) ?? lines.endIndex
            if let ptime = lines[audio + 1 ..< end].firstIndex(where: { $0.hasPrefix("a=ptime:") }) {
                lines[ptime] = "a=ptime:\(frameMs)"
            } else {
                let last = lines[audio + 1 ..< end].lastIndex(where: { !$0.isEmpty }) ?? audio
                lines.insert("a=ptime:\(frameMs)", at: last + 1)
            }
        }
        return lines.joined(separator: newline)
    }

    /// Whether `sdp` has an audio section that is not turned down and carries Opus.
    public static func takesOpus(_ sdp: String) -> Bool {
        let newline = sdp.contains("\r\n") ? "\r\n" : "\n"
        var inAudio = false, opus = false, rejected = false, inactive = false
        func done() -> Bool { inAudio && opus && !rejected && !inactive }
        for line in sdp.components(separatedBy: newline) {
            if line.hasPrefix("m=") {
                if done() { return true }
                inAudio = line.hasPrefix("m=audio ")
                rejected = line.hasPrefix("m=audio 0 ")
                opus = false
                inactive = false
            } else if inAudio {
                if line.lowercased().hasPrefix("a=rtpmap:"), line.lowercased().contains(" opus/48000") { opus = true }
                if line == "a=inactive" || line == "a=sendonly" { inactive = true }
            }
        }
        return done()
    }

    private static func merge(_ existing: String, _ wanted: [(String, String)]) -> String {
        var pairs: [(String, String)] = existing.split(separator: ";").compactMap { part in
            let item = part.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { return nil }
            let bits = item.split(separator: "=", maxSplits: 1).map(String.init)
            return (bits[0], bits.count > 1 ? bits[1] : "")
        }
        for (key, value) in wanted {
            if let index = pairs.firstIndex(where: { $0.0.lowercased() == key }) { pairs[index].1 = value } else { pairs.append((key, value)) }
        }
        return pairs.map { $0.1.isEmpty ? $0.0 : "\($0.0)=\($0.1)" }.joined(separator: ";")
    }
}
