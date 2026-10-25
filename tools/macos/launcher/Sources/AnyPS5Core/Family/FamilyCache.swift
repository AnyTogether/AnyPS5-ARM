import CryptoKit
import Foundation

/// A public key from AnyTogether's JWKS (`/.well-known/jwks.json`): Ed25519, the raw 32 bytes in
/// base64url.
public struct FamilyKey: Decodable, Equatable, Sendable {
    public let kid: String?
    public let x: String
    let kty: String?
    let crv: String?

    public init(kid: String?, x: String) {
        self.kid = kid
        self.x = x
        kty = "OKP"
        crv = "Ed25519"
    }

    var raw: Data? { FamilyJWS.base64URL(x) }

    var isEd25519: Bool { (kty ?? "OKP") == "OKP" && (crv ?? "Ed25519") == "Ed25519" && raw?.count == 32 }
}

public enum FamilyCacheError: Error, Equatable, Sendable {
    /// Not a compact JWS, or its parts do not read.
    case malformed
    /// No key of the server's made the signature.
    case signature
    /// Not a family status for its own subject.
    case claims
    /// Limits from one server are not lifted by another.
    case otherServer
    /// Older than the status kept.
    case older
}

/// A compact JWS (EdDSA) as AnyTogether signs a family status: the status in the `family` claim,
/// audience "anytogether-family", its subject the status's user.
enum FamilyJWS {
    static let audience = "anytogether-family"

    static func base64URL(_ text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        return Data(base64Encoded: base)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// The status, once the signature holds for one of `keys` and the claims are a family
    /// status's; and the key that made it.
    static func verify(_ token: String, keys: [FamilyKey]) throws -> (status: FamilyStatus, key: FamilyKey) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = base64URL(parts[0]), let payload = base64URL(parts[1]), let signature = base64URL(parts[2]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { throw FamilyCacheError.malformed }
        guard header["alg"] as? String == "EdDSA" else { throw FamilyCacheError.signature }
        let kid = header["kid"] as? String
        let candidates = keys.filter(\.isEd25519).sorted { ($0.kid == kid ? 0 : 1) < ($1.kid == kid ? 0 : 1) }
        let input = Data((parts[0] + "." + parts[1]).utf8)
        guard let key = candidates.first(where: { candidate in
            guard let raw = candidate.raw, let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
            return publicKey.isValidSignature(signature, for: input)
        }) else { throw FamilyCacheError.signature }
        guard let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], let family = claims["family"] as? [String: Any] else { throw FamilyCacheError.claims }
        let audiences = (claims["aud"] as? [String]) ?? [(claims["aud"] as? String) ?? ""]
        guard audiences.contains(audience) else { throw FamilyCacheError.claims }
        var fields = family
        // The status's own time, else the token's.
        if fields["issuedAt"] == nil, let iat = claims["iat"] as? Double {
            fields["issuedAt"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: iat))
        }
        guard let data = try? JSONSerialization.data(withJSONObject: fields), let status = try? JSONDecoder.together.decode(FamilyStatus.self, from: data) else { throw FamilyCacheError.claims }
        guard claims["sub"] as? String == status.userId else { throw FamilyCacheError.claims }
        return (status, key)
    }
}

/// Where this Mac stands with family limits: none, a status that applies (`stale` when it is
/// over a week old: still applied, the child is asked to connect), or locked because the kept
/// status was changed or lost.
public enum FamilyStanding: Equatable, Sendable {
    case free
    case limited(FamilyStatus, stale: Bool)
    case locked

    public var status: FamilyStatus? {
        if case .limited(let status, _) = self { return status }
        return nil
    }
}

/// The last family status the server signed, kept for when it cannot be reached: the signed copy
/// and the key that checks it in Application Support, and a seal over both elsewhere (the app's
/// defaults), so a changed, swapped or deleted file locks instead of lifting the limits. Signing
/// out keeps it; a parent signing in replaces it with their own status, which has no limits.
/// One status for the Mac, whoever is signed in, as the same child may play signed out.
public final class FamilyCache: @unchecked Sendable {
    struct Saved: Codable {
        var signed: String
        /// The key's x, base64url.
        var key: String
        var server: String
    }

    struct Seal: Codable {
        var digest: String
        var server: String
        var restricted: Bool
    }

    /// Over this, the status still applies but the child is asked to connect.
    public static let staleAfter: TimeInterval = 7 * 86_400
    /// Games played here are kept this long: a status is for one day.
    static let recordsKept: TimeInterval = 2 * 86_400

    let folder: URL
    let defaults: UserDefaults
    private let lock = NSLock()
    private static let sealKey = "AnyPS5.familySeal"

    public init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Family"),
                defaults: UserDefaults = .standard) {
        self.folder = folder
        self.defaults = defaults
    }

    private var file: URL { folder.appendingPathComponent("family.json") }
    private var playFile: URL { folder.appendingPathComponent("play.json") }

    static func digest(_ saved: Saved) -> String {
        SHA256.hash(data: Data("\(saved.signed)\n\(saved.key)\n\(saved.server)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var seal: Seal? {
        defaults.data(forKey: Self.sealKey).flatMap { try? JSONDecoder().decode(Seal.self, from: $0) }
    }

    /// Checks a status the server just signed and keeps it; the status comes back.
    @discardableResult
    public func accept(signed: String, keys: [FamilyKey], server: URL, now: Date = Date()) throws -> FamilyStatus {
        let (status, key) = try FamilyJWS.verify(signed, keys: keys)
        return try lock.withLock {
            let server = server.absoluteString
            if let seal, seal.restricted, seal.server != server { throw FamilyCacheError.otherServer }
            if case .limited(let kept, _) = readStanding(now: now), kept.issuedAt > status.issuedAt { throw FamilyCacheError.older }
            let saved = Saved(signed: signed, key: key.x, server: server)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(saved).write(to: file, options: .atomic)
            let seal = Seal(digest: Self.digest(saved), server: server, restricted: status.restricted)
            defaults.set(try JSONEncoder().encode(seal), forKey: Self.sealKey)
            return status
        }
    }

    /// What applies now, from what is kept.
    public func standing(now: Date = Date()) -> FamilyStanding {
        lock.withLock { readStanding(now: now) }
    }

    private func readStanding(now: Date) -> FamilyStanding {
        let seal = self.seal
        guard let data = try? Data(contentsOf: file) else {
            // Limits were kept here and the file is gone.
            return seal?.restricted == true ? .locked : .free
        }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let status = try? FamilyJWS.verify(saved.signed, keys: [FamilyKey(kid: nil, x: saved.key)]).status else { return .locked }
        if let seal, seal.digest != Self.digest(saved) { return .locked }
        guard status.restricted else { return .free }
        return .limited(status, stale: now.timeIntervalSince(status.issuedAt) > Self.staleAfter)
    }

    // MARK: Play on this Mac

    /// Games played here recently, for what the kept status does not count yet.
    public var records: [FamilyPlayRecord] {
        lock.withLock { loadRecords() }
    }

    public func record(_ record: FamilyPlayRecord, now: Date = Date()) {
        lock.withLock {
            var records = loadRecords().filter { now.timeIntervalSince($0.endedAt) < Self.recordsKept && $0.id != record.id }
            records.append(record)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let data = try? JSONEncoder.together.encode(records) { try? data.write(to: playFile, options: .atomic) }
        }
    }

    private func loadRecords() -> [FamilyPlayRecord] {
        (try? Data(contentsOf: playFile)).flatMap { try? JSONDecoder.together.decode([FamilyPlayRecord].self, from: $0) } ?? []
    }
}
