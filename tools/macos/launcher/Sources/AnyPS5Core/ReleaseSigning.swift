import CryptoKit
import Foundation

/// Signed releases (docs/dev/SIGNED_UPDATES.md): a release carries SHA256SUMS (the sha256 of each
/// of its files) and SHA256SUMS.sig (Ed25519 signatures of SHA256SUMS by the release keys,
/// tools/release/sign.sh). The launcher trusts the keys built into it (`ReleaseKeys`) and checks
/// the signature, then the downloaded file against the sums, before it replaces itself or
/// unpacks an engine.
public enum ReleaseSigning {
    public static let sumsName = "SHA256SUMS"
    public static let signatureName = "SHA256SUMS.sig"

    /// The last release published before releases were signed. Its engines and older ones may
    /// still be downloaded unsigned, with a warning and GitHub's sha256; every later release must
    /// be signed. Self-updates are always signed (every version newer than a signing launcher
    /// came out after signing began).
    public static let lastUnsignedRelease = "0.2.16"

    /// The sums and their signature are a few lines; anything larger is not them.
    static let largestFile = 1 << 20

    public struct Failure: Error, CustomStringConvertible, Equatable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    // MARK: Keys

    public struct Key: Equatable, Sendable {
        public let name: String
        /// The first 16 hex digits of the sha256 of the raw public key, as SHA256SUMS.sig names it.
        public let id: String
        /// The raw 32-byte Ed25519 public key.
        public let raw: Data

        public init?(name: String, raw: Data) {
            guard raw.count == 32, (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil else { return nil }
            self.name = name
            self.raw = raw
            id = ReleaseSigning.keyID(of: raw)
        }

        var publicKey: Curve25519.Signing.PublicKey? { try? Curve25519.Signing.PublicKey(rawRepresentation: raw) }
    }

    /// The keys built into this launcher: the current release key and, during a rotation, the
    /// next one.
    public static let trustedKeys: [Key] = keys(from: ReleaseKeys.list)

    /// The keys of release-signing.pub's lines, "ed25519 <base64> <name>"; other lines are skipped.
    public static func keys(from text: String) -> [Key] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count == 3, fields[0] == "ed25519", let raw = Data(base64Encoded: String(fields[1])) else { return nil }
            return Key(name: String(fields[2]), raw: raw)
        }
    }

    public static func keyID(of raw: Data) -> String {
        SHA256.hash(data: raw).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Checking

    /// SHA256SUMS once its signature has been checked: the sha256 (lower-case hex) of each file
    /// by its name.
    public struct Sums: Equatable, Sendable {
        public let digests: [String: String]
        /// The name of the key whose signature was good.
        public let signer: String

        public func digest(for name: String) -> String? { digests[name] }

        /// Fails unless `file` is the one the sums list as `name`.
        public func check(_ file: URL, as name: String) throws {
            guard let expected = digests[name] else { throw Failure("the signed release does not list \(name)") }
            guard try FileDigest.sha256(file) == expected else { throw Failure("\(name) does not match the signed release (sha256)") }
        }
    }

    /// The files and digests of SHA256SUMS as shasum writes it: "<64 hex digits>  <name>" a line
    /// (a "*" before the name, binary mode, is allowed). Anything else in it is refused.
    public static func parseSums(_ data: Data) throws -> [String: String] {
        guard data.count <= largestFile, let text = String(data: data, encoding: .utf8) else { throw Failure("SHA256SUMS cannot be read") }
        var digests: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.count > 66, line.prefix(64).allSatisfy(\.isHexDigit), line.dropFirst(64).first == " " else { throw Failure("SHA256SUMS has a line it cannot read") }
            var name = line.dropFirst(65)
            if name.first == " " || name.first == "*" { name = name.dropFirst() }
            guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != "..", digests[String(name)] == nil else {
                throw Failure("SHA256SUMS names a file it cannot")
            }
            digests[String(name)] = line.prefix(64).lowercased()
        }
        guard !digests.isEmpty else { throw Failure("SHA256SUMS lists no file") }
        return digests
    }

    /// Checks `signature` (SHA256SUMS.sig: "ed25519 <key ID> <base64 signature>" a line) over
    /// `sums` with `keys`; one good signature by one of them is enough.
    public static func verify(sums: Data, signature: Data, keys: [Key] = trustedKeys) throws -> Sums {
        guard signature.count <= largestFile, let text = String(data: signature, encoding: .utf8) else { throw Failure("SHA256SUMS.sig cannot be read") }
        var unknown: [String] = []
        var known = false
        var seen = false
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            guard fields.count == 3, fields[0] == "ed25519" else { continue }
            seen = true
            let id = String(fields[1])
            let matching = keys.filter { $0.id == id }
            if matching.isEmpty { unknown.append(id); continue }
            known = true
            guard let bytes = Data(base64Encoded: String(fields[2])), bytes.count == 64 else { continue }
            for key in matching where key.publicKey?.isValidSignature(bytes, for: sums) == true {
                return Sums(digests: try parseSums(sums), signer: key.name)
            }
        }
        guard seen else { throw Failure("SHA256SUMS.sig holds no signature") }
        if !known { throw Failure("the release is signed with a key this launcher does not trust (\(unknown.joined(separator: ", ")))") }
        throw Failure("the release's signature does not match its SHA256SUMS")
    }

    // MARK: Releases

    /// Where a release's SHA256SUMS and SHA256SUMS.sig are.
    public struct Assets: Codable, Equatable, Sendable {
        public var sums: URL
        public var signature: URL

        public init(sums: URL, signature: URL) {
            self.sums = sums
            self.signature = signature
        }
    }

    /// The signature files among a release's assets as GitHub lists them; nil for a release
    /// without both (one published before signing began, or one whose signature is missing).
    public static func assets(in list: [[String: Any]]) -> Assets? {
        func url(_ name: String) -> URL? {
            list.first { $0["name"] as? String == name }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        }
        guard let sums = url(sumsName), let signature = url(signatureName) else { return nil }
        return Assets(sums: sums, signature: signature)
    }

    /// Downloads a release's sums and signature and checks them.
    public static func fetch(_ assets: Assets, keys: [Key] = trustedKeys, session: URLSession = .shared) async throws -> Sums {
        func get(_ url: URL, _ name: String) async throws -> Data {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure("\(name) could not be downloaded")
            }
            guard data.count <= largestFile else { throw Failure("\(name) is too large") }
            return data
        }
        let sums = try await get(assets.sums, sumsName)
        let signature = try await get(assets.signature, signatureName)
        return try verify(sums: sums, signature: signature, keys: keys)
    }

    /// How far an engine of a release can be trusted.
    public enum Trust: String, Codable, Sendable {
        /// The release is signed: the download is checked against its signed sums.
        case signed
        /// Published before signing began: only GitHub's sha256 checks it, and the launcher
        /// says so before downloading it.
        case unsignedOlder
        /// Published after signing began but without a signature: refused.
        case unsignedRefused
    }

    public static func trust(release: String, signed: Bool) -> Trust {
        if signed { return .signed }
        return isAfterSigningBegan(release) ? .unsignedRefused : .unsignedOlder
    }

    /// Whether a release (0.2.17-arm, v0.2.17-arm-nightly.20261025.1) is numbered past
    /// `lastUnsignedRelease`; a version that cannot be read counts as past it.
    static func isAfterSigningBegan(_ release: String) -> Bool {
        func numbers(_ text: String) -> [Int]? {
            let text = text.hasPrefix("v") ? String(text.dropFirst()) : text
            let head = text.prefix { $0.isNumber || $0 == "." }
            let parts = head.split(separator: ".", omittingEmptySubsequences: false)
            let values = parts.compactMap { Int($0) }
            guard !values.isEmpty, values.count == parts.count else { return nil }
            return values + Array(repeating: 0, count: max(0, 3 - values.count))
        }
        guard let offered = numbers(release), let last = numbers(lastUnsignedRelease) else { return true }
        return last.lexicographicallyPrecedes(offered)
    }
}
