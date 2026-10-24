import Foundation

/// Who is signed in to AnyTogether.
public struct TogetherUser: Codable, Equatable, Sendable {
    public let id: String
    public let handle: String
    public let displayName: String
    public let avatar: String?

    public init(id: String, handle: String, displayName: String, avatar: String?) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
    }
}

/// An error AnyTogether answered with: RFC 9457 problem details with a stable code.
public struct TogetherProblem: Error, Decodable, CustomStringConvertible, Sendable {
    public let status: Int
    public let code: String
    public let title: String
    /// The private part of a profile a 403 is about ("library", "trophies", "friends").
    public var section: String? = nil
    /// When a handle may change again, with "handle_cooldown".
    public var handleChangeAt: Date? = nil
    /// The theme already shared from the same file, with a 409 on sharing a theme.
    public var themeId: String? = nil
    public var description: String { title }
}

/// A sign-in that waits for someone to approve it: a hand-off to the phone or a device code.
public enum PendingSignIn: Sendable {
    case handoff(id: String, secret: String)
    case device(code: String)
}

public struct DeviceCode: Decodable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let interval: Int
}

public struct Handoff: Decodable, Sendable {
    public let handoffId: String
    public let secret: String
}

public struct TogetherMe: Decodable, Sendable {
    public struct Account: Decodable, Sendable { public let id: String; public let email: String? }
    public struct Profile: Decodable, Sendable { public let handle: String; public let displayName: String; public let bio: String?; public let avatar: String? }
    public let account: Account
    public let profile: Profile
}

/// The session kept between launches: in a file only this user can read until the launcher has a
/// stable signature (a Keychain item would ask again after every ad hoc signed update).
public final class TokenStore: @unchecked Sendable {
    struct Saved: Codable {
        var accessToken: String
        var accessExpiry: Date
        var refreshToken: String
        var user: TogetherUser
    }

    let file: URL
    private let lock = NSLock()

    public init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Together/session.json")) {
        self.file = file
    }

    func load() -> Saved? {
        lock.withLock { (try? Data(contentsOf: file)).flatMap { try? JSONDecoder.together.decode(Saved.self, from: $0) } }
    }

    /// The tokens kept now, for a crash report to take out wherever they appear.
    public var secrets: [String] {
        load().map { [$0.accessToken, $0.refreshToken] } ?? []
    }

    /// Changes the kept user (a new handle or name), keeping the tokens.
    func update(_ change: (inout TogetherUser) -> Void) {
        guard var saved = load() else { return }
        change(&saved.user)
        save(saved)
    }

    func save(_ saved: Saved?) {
        lock.withLock {
            guard let saved else {
                try? FileManager.default.removeItem(at: file)
                return
            }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard let data = try? JSONEncoder.together.encode(saved) else { return }
            FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
}

/// The launcher's side of AnyTogether's API: signing in (email code, phone hand-off, device code),
/// keeping the session, and calls that refresh an expired access token by themselves.
public final class TogetherClient: @unchecked Sendable {
    public let base: URL
    let store: TokenStore
    let session: URLSession
    public let clientName: String
    private let refresher = Refresher()

    public init(base: URL, store: TokenStore = TokenStore(), session: URLSession = .shared, clientName: String) {
        self.base = base
        self.store = store
        self.session = session
        self.clientName = clientName
    }

    public var user: TogetherUser? { store.load()?.user }

    // MARK: Signing in

    public func startEmail(_ email: String) async throws {
        _ = try await send("POST", "auth/email/start", ["email": email])
    }

    public func verifyEmail(_ email: String, code: String) async throws -> TogetherUser {
        try keep(try await send("POST", "auth/email/verify", ["email": email, "code": code]))
    }

    /// For the phone to approve: the launcher hands the ID to its paired phone.
    public func startHandoff(deviceName: String) async throws -> Handoff {
        try JSONDecoder.together.decode(Handoff.self, from: try await send("POST", "auth/handoff/start", ["deviceName": deviceName]))
    }

    /// For a browser to approve: show `userCode` and open `verificationUri`.
    /// Signs in the device that started this hand-off (the phone, or another launcher) as us.
    public func approveHandoff(_ id: String) async throws {
        _ = try await authorized("POST", "auth/handoff/\(id)/approve", nil)
    }

    public func startDeviceCode(deviceName: String) async throws -> DeviceCode {
        try JSONDecoder.together.decode(DeviceCode.self, from: try await send("POST", "auth/device", ["deviceName": deviceName]))
    }

    public func waitForApproval(_ handoff: Handoff, every interval: Duration = .seconds(2), until deadline: Date = Date().addingTimeInterval(300)) async throws -> TogetherUser {
        try await waitForApproval(.handoff(id: handoff.handoffId, secret: handoff.secret), every: interval, until: deadline)
    }

    public func waitForApproval(_ device: DeviceCode, every interval: Duration? = nil, until deadline: Date = Date().addingTimeInterval(600)) async throws -> TogetherUser {
        try await waitForApproval(.device(code: device.deviceCode), every: interval ?? .seconds(device.interval), until: deadline)
    }

    /// Asks until the sign-in is approved, refused or out of time.
    public func waitForApproval(_ pending: PendingSignIn, every interval: Duration, until deadline: Date) async throws -> TogetherUser {
        let grant: [String: String]
        switch pending {
        case .handoff(let id, let secret): grant = ["grantType": "handoff", "handoffId": id, "secret": secret]
        case .device(let code): grant = ["grantType": "device_code", "deviceCode": code]
        }
        var wait = interval
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                return try keep(try await send("POST", "auth/token", grant))
            } catch let problem as TogetherProblem where problem.code == "authorization_pending" || problem.code == "slow_down" {
                if problem.code == "slow_down" { wait += .seconds(5) }
                try await Task.sleep(for: wait)
            }
        }
        throw TogetherProblem(status: 400, code: "expired_token", title: "The sign-in was not approved in time")
    }

    /// Forgets the session here only (it ended elsewhere).
    public func forget() {
        store.save(nil)
    }

    public func signOut() async {
        _ = try? await authorized("POST", "auth/logout", nil)
        store.save(nil)
    }

    // MARK: Calls

    public func me() async throws -> TogetherMe {
        try JSONDecoder.together.decode(TogetherMe.self, from: try await authorized("GET", "me", nil))
    }

    /// The current access token, refreshed first if it is about to expire.
    public func accessToken() async throws -> String {
        guard let saved = store.load() else { throw TogetherProblem(status: 401, code: "unauthorized", title: "Not signed in") }
        if saved.accessExpiry.timeIntervalSinceNow > 30 { return saved.accessToken }
        return try await refresh(from: saved.refreshToken)
    }

    /// A call with the access token; a 401 refreshes it once and calls again.
    func authorized(_ method: String, _ path: String, _ body: Any?) async throws -> Data {
        let token = try await accessToken()
        do {
            return try await send(method, path, body, token: token)
        } catch let problem as TogetherProblem where problem.status == 401 {
            guard let saved = store.load() else { throw problem }
            let fresh = try await refresh(from: saved.refreshToken)
            return try await send(method, path, body, token: fresh)
        }
    }

    /// One refresh at a time: calls that fail together share it.
    private func refresh(from refreshToken: String) async throws -> String {
        try await refresher.run {
            if let saved = self.store.load(), saved.refreshToken != refreshToken { return saved.accessToken }
            do {
                let data = try await self.send("POST", "auth/token", ["grantType": "refresh_token", "refreshToken": refreshToken])
                _ = try self.keep(data)
                return self.store.load()?.accessToken ?? ""
            } catch let problem as TogetherProblem where problem.status == 401 || problem.status == 400 {
                self.store.save(nil)
                throw problem
            }
        }
    }

    private func keep(_ data: Data) throws -> TogetherUser {
        struct Tokens: Decodable {
            let accessToken: String
            let expiresIn: Int
            let refreshToken: String
            let user: TogetherUser
        }
        let tokens = try JSONDecoder.together.decode(Tokens.self, from: data)
        store.save(.init(accessToken: tokens.accessToken, accessExpiry: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)), refreshToken: tokens.refreshToken, user: tokens.user))
        return tokens.user
    }

    func send(_ method: String, _ path: String, _ body: Any?, token: String? = nil) async throws -> Data {
        // A path may carry a query ("users/search?q=…"), which appendingPathComponent would escape.
        var request = URLRequest(url: URL(string: base.appendingPathComponent("api/v1").absoluteString + "/" + path)!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(clientName, forHTTPHeaderField: "AnyTogether-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let raw = body as? TogetherRawBody {
            // A file going up (a theme): its own type, and time to send it.
            request.setValue(raw.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = raw.data
            request.timeoutInterval = 180
        } else if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw (try? JSONDecoder.together.decode(TogetherProblem.self, from: data)) ?? TogetherProblem(status: status, code: "internal", title: "AnyTogether answered \(status)")
        }
        return data
    }
}

/// Runs one refresh at a time; callers that arrive meanwhile wait for the same result.
private actor Refresher {
    private var running: Task<String, Error>?

    func run(_ work: @escaping @Sendable () async throws -> String) async throws -> String {
        if let running { return try await running.value }
        let task = Task { try await work() }
        running = task
        defer { running = nil }
        return try await task.value
    }
}

extension JSONDecoder {
    /// ISO 8601 dates with or without milliseconds: the server sends them with.
    static let together: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let together: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
