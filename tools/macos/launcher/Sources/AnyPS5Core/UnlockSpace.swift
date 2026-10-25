import Foundation

/// What an unlock will write on the games folder's drive, worked out before it starts, so a
/// full drive is said up front instead of after gigabytes were written and thrown away.
///
/// The figure is a safe estimate, not exact: the unwrapped executable and modules can each be up
/// to twice the dump's files (a SELF holds its segments compressed or sparse), the relinker's
/// output as much again; a drive that clones (APFS) copies them into the bundle for nothing, any
/// other drive pays for that copy too. Then what is copied rather than cloned or linked (the
/// toolkit's libraries from another drive, the game's files where they cannot be linked), and a
/// margin for the bundle's small files and the system.
public struct UnlockSpace: Equatable, Sendable {
    /// Room left over beyond the estimate.
    public static let margin: Int64 = 512 << 20

    /// The dump's eboot.bin and modules, as they are in the dump.
    public var executables: Int64
    /// The toolkit's files the bundle gets as copies (0 when they are cloned).
    public var libraries: Int64
    /// The game's files copied into the bundle (0 when they are cloned or linked).
    public var copied: Int64
    /// The games folder's drive clones files (APFS): copies inside it take no room.
    public var clones: Bool
    /// The size of the relinker's kept output this unlock reuses, nil when it relinks.
    public var keptRelink: Int64?

    public init(executables: Int64, libraries: Int64 = 0, copied: Int64 = 0, clones: Bool, keptRelink: Int64? = nil) {
        self.executables = executables
        self.libraries = libraries
        self.copied = copied
        self.clones = clones
        self.keptRelink = keptRelink
    }

    /// Part of the room is the game's files, copied.
    public var copies: Bool { copied > 0 }

    /// The bytes the drive must have free.
    public var needed: Int64 {
        let binaries: Int64
        if let keptRelink {
            binaries = clones ? 0 : keptRelink
        } else {
            let unwrapped = executables * 2
            let relinked = executables * 2
            binaries = unwrapped + relinked + (clones ? 0 : relinked)
        }
        return binaries + libraries + copied + UnlockSpace.margin
    }

    /// What stops the unlock, nil when `free` is enough or not known: a drive that does not say
    /// never blocks, the unlock then reports a full disk itself as before.
    public func shortage(free: Int64?, volume: String) -> SpaceShortage? {
        guard let free, free < needed else { return nil }
        return SpaceShortage(needed: needed, free: free, volume: volume, copying: copies)
    }
}

/// An unlock that was not started for want of room.
public struct SpaceShortage: LocalizedError, Equatable, Sendable {
    public let needed: Int64
    public let free: Int64
    /// The drive's name.
    public let volume: String
    /// Part of the room is the game's files, which must be copied.
    public let copying: Bool

    public init(needed: Int64, free: Int64, volume: String, copying: Bool) {
        self.needed = needed
        self.free = free
        self.volume = volume
        self.copying = copying
    }

    public var missing: Int64 { max(0, needed - free) }

    public var errorDescription: String? {
        let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        return "not enough space on \(volume): the unlock needs \(format(needed)), \(format(free)) is free" + (copying ? " (the game's files must be copied)" : "")
    }
}

/// The free space where the games are.
public enum FreeSpace {
    /// The bytes free for this user where `url` is, or would be (its nearest existing folder):
    /// the room macOS can make for something the user asked for (purgeable files count), else
    /// the plain free space; nil when the drive does not say.
    public static func available(at url: URL) -> Int64? {
        guard let folder = existing(url) else { return nil }
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        if let plain = values?.volumeAvailableCapacity { return Int64(plain) }
        return nil
    }

    /// The drive's name as Finder shows it, else the folder's.
    public static func volumeName(at url: URL) -> String {
        let folder = existing(url) ?? url
        if let name = (try? folder.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName, !name.isEmpty { return name }
        return folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent
    }

    static func existing(_ url: URL) -> URL? {
        var folder = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: folder.path) {
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { return nil }
            folder = parent
        }
        return folder
    }
}
