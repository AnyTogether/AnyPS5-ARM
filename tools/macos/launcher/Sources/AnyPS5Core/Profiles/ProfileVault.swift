import Foundation
import Security

/// Where secrets are kept, one item per account name.
public protocol SecretVault: AnyObject, Sendable {
    func read(_ account: String) -> Data?
    /// Keeps `data` for `account`, nil forgets it; false when the vault refused.
    @discardableResult
    func write(_ data: Data?, for account: String) -> Bool
}

/// Kept for this run only (tests, previews).
public final class MemoryVault: SecretVault, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()
    /// Every write fails (a test of a vault that says no).
    public var refuses = false

    public init() {}

    public func read(_ account: String) -> Data? { lock.withLock { items[account] } }

    public func write(_ data: Data?, for account: String) -> Bool {
        lock.withLock {
            guard !refuses else { return false }
            items[account] = data
            return true
        }
    }
}

/// Generic passwords in the Keychain, one per profile. The launcher is signed ad hoc, so each
/// update is another app to the Keychain: an item only the app that made it may read would ask
/// for the Mac's password after every update. Each item's decrypt rule therefore lets any app of
/// this user read it, as the file only this user could read did before, while the secret itself
/// is sealed in the login keychain and locked with it.
public final class KeychainVault: SecretVault, @unchecked Sendable {
    public let service: String
    /// A keychain file of its own (tests); nil is the user's default keychain.
    private let keychain: SecKeychain?

    public init(service: String = "AnyPS5 AnyTogether", keychain: SecKeychain? = nil) {
        self.service = service
        self.keychain = keychain
    }

    private func query(_ account: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let keychain { query[kSecMatchSearchList as String] = [keychain] }
        return query
    }

    public func read(_ account: String) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func write(_ data: Data?, for account: String) -> Bool {
        guard let data else {
            let status = SecItemDelete(query(account) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                   kSecAttrLabel as String: service, kSecValueData as String: data]
        if let keychain { item[kSecUseKeychain as String] = keychain }
        if let access = Self.anyAppReads(label: service) { item[kSecAttrAccess as String] = access }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// An access whose decrypt rule names no app: any app of this user reads the item without a
    /// prompt (changing the rules themselves still asks).
    private static func anyAppReads(label: String) -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, [] as CFArray, &access) == errSecSuccess, let access else { return nil }
        var list: CFArray?
        guard SecAccessCopyACLList(access, &list) == errSecSuccess, let acls = list as? [SecACL] else { return nil }
        for acl in acls {
            let authorizations = SecACLCopyAuthorizations(acl) as? [String] ?? []
            guard authorizations.contains(kSecACLAuthorizationDecrypt as String) else { continue }
            var applications: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector()
            guard SecACLCopyContents(acl, &applications, &description, &prompt) == errSecSuccess else { return nil }
            guard SecACLSetContents(acl, nil, description ?? (label as CFString), prompt) == errSecSuccess else { return nil }
        }
        return access
    }
}

/// The AnyTogether session of each profile, in the vault by profile.
public enum ProfileSessions {
    public static func account(for profile: String) -> String { "session.\(profile)" }

    public static func store(for profile: String, in vault: SecretVault) -> TokenStore {
        TokenStore(vault: vault, account: account(for: profile))
    }

    /// The tokens of every profile, for a crash report to take out wherever they appear.
    public static func secrets(in vault: SecretVault, accounts: [String]) -> [String] {
        accounts.flatMap { TokenStore(vault: vault, account: $0).secrets }
    }
}
