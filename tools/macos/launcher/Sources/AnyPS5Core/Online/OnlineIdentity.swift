import CryptoKit
import Foundation

/// Who an AnyTogether user is to a game: the same account number and virtual address on every
/// Mac and in every session, worked out from the user ID alone, so no server has to hand them
/// out and every launcher in a session agrees without asking.
public enum OnlineIdentity {
    /// The platform's longest online ID.
    public static let onlineIdLength = 16

    /// The first 8 bytes of SHA-256 of the user ID, never 0 (0 means "nobody" to a game).
    public static func accountId(forUser userId: String) -> UInt64 {
        let number = digest(userId).prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return number == 0 ? 1 : number
    }

    /// The handle cut to the platform's 16 letters ("player" for an empty one).
    public static func onlineId(handle: String) -> String {
        let cut = String(handle.prefix(onlineIdLength))
        return cut.isEmpty ? "player" : cut
    }

    /// Each player's address in 198.18.0.0/15, from bytes 8 to 10 of the same digest. A last
    /// octet of 0 or 255 is skipped (some games treat them as network or broadcast addresses),
    /// and when two players land on one address the one with the smaller user ID keeps it and the
    /// other moves up, so the result depends only on who is in the session, not on join order:
    /// someone leaving never moves anyone else.
    public static func addresses(for userIds: [String]) -> [String: UInt32] {
        var taken = Set<UInt32>()
        var result: [String: UInt32] = [:]
        for userId in Set(userIds).sorted() {
            let bytes = Array(digest(userId).dropFirst(8).prefix(3))
            var host = (UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])) & ~OnlineWire.virtualMask
            while true {
                host &= ~OnlineWire.virtualMask
                let low = host & 0xFF
                if low != 0, low != 0xFF, !taken.contains(host) { break }
                host += 1
            }
            taken.insert(host)
            result[userId] = OnlineWire.virtualNetwork | host
        }
        return result
    }

    private static func digest(_ userId: String) -> SHA256.Digest { SHA256.hash(data: Data(userId.utf8)) }
}
