import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// What saving or loading a state came to (anyps5-retro-host docs/protocol.md "saveState and
/// loadState"), as on Windows and Linux (AnyPS5 Desktop's lib/core/retro_host/retro_state_slots.dart).
public enum RetroStateOutcome: String, CaseIterable, Sendable {
    /// The host saved the state, or loaded it into the game.
    case done
    /// The call returned `false`: no game is loaded, it has not shown its first frame, it has ended,
    /// or the game's thread did not get to the call in time.
    case notNow
    /// `noState`: the slot holds no state.
    case noState
    /// `badState`: the file is not a state this host reads, or it is damaged.
    case badState
    /// `otherGame`: the state was saved from another game.
    case otherGame
    /// `otherCore`: the state was saved by another core or core build, so the host refuses it
    /// rather than give the core data it may misread.
    case otherCore
    /// `coreRefused`: the core gave no state, or refused the one in the file; the game runs on.
    case coreRefused
    /// `fileError`: the file could not be written or read in time.
    case fileError
    /// Any other error: an `argument` error, a code this launcher does not know, or a host that
    /// went away.
    case failed

    /// The outcome of an `error` reply with `code`.
    public init(errorCode code: String) {
        switch code {
        case RetroCallError.noState: self = .noState
        case RetroCallError.badState: self = .badState
        case RetroCallError.otherGame: self = .otherGame
        case RetroCallError.otherCore: self = .otherCore
        case RetroCallError.coreRefused: self = .coreRefused
        case RetroCallError.fileError: self = .fileError
        default: self = .failed
        }
    }
}

/// One save state slot of a game, as the launcher's states folder holds it: when its state was
/// saved (the file's time), and the picture the launcher kept of that moment.
public struct RetroStateSlot: Equatable, Sendable {
    /// The host's slot number, 0 to `RetroStateFolder.slots` - 1; the player sees it from 1.
    public let slot: Int
    /// When the state in it was saved; nil for an empty slot.
    public let savedAt: Date?
    /// A PNG of the game's picture when it was saved; nil when none was kept.
    public let picture: Data?

    public init(_ slot: Int, savedAt: Date? = nil, picture: Data? = nil) {
        self.slot = slot
        self.savedAt = savedAt
        self.picture = picture
    }

    public var empty: Bool { savedAt == nil }
}

/// The save states of one game in the launcher's states folder (`retro/states/<console>/<title ID>`):
/// the folder `start.states` names, so the host writes each slot there as `<disc's name without its
/// extension>.<slot>.state`, as it names the memory card `<name>.srm` in `saves`. The launcher keeps
/// each slot's picture beside it as `<name>.<slot>.png`; the host reads and writes nothing but its
/// `.state` files there.
public struct RetroStateFolder: Equatable, Sendable {
    /// How many slots a game has: the host's slots 0 to 7.
    public static let slots = 8
    /// The largest picture read back: a picture larger than this is not one the launcher wrote.
    public static let pictureLimit = 1 << 20

    /// The folder `start.states` names.
    public let folder: String
    /// The disc's name without its extension, as the host takes it (`discName`).
    public let name: String

    /// `disc` is the same string that goes into `start.disc`.
    public init(folder: String, disc: String) {
        self.folder = folder
        name = Self.discName(disc)
    }

    /// The name the host gives `disc`'s states and memory card (protocol.md "start", `saves`): the
    /// last part of the path after its last `/` (with `windows`, also `\`, as a host on Windows reads
    /// it; on macOS a `\` is a letter of a file's name), without what follows its last dot, unless
    /// that dot is its first letter.
    public static func discName(_ disc: String, windows: Bool = false) -> String {
        let base = disc.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || (windows && $0 == "\\") }).last.map(String.init) ?? disc
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex else { return base }
        return String(base[..<dot])
    }

    public func statePath(_ slot: Int) -> String { (folder as NSString).appendingPathComponent("\(name).\(slot).state") }

    public func picturePath(_ slot: Int) -> String { (folder as NSString).appendingPathComponent("\(name).\(slot).png") }

    /// When `slot`'s state file was last written; nil when there is none.
    public func written(_ slot: Int) -> Date? {
        guard let info = try? FileManager.default.attributesOfItem(atPath: statePath(slot)),
              info[.type] as? FileAttributeType == .typeRegular else { return nil }
        return info[.modificationDate] as? Date
    }

    /// Every slot as the folder holds it now. A slot whose state cannot be read is empty. A picture is
    /// left out when it cannot be read, is far larger than one the launcher writes, or is older than
    /// its state: the launcher writes a slot's picture only after its state was saved, so an older one
    /// is of a state before (one a failed save could not take away), not of the one there now.
    public func read() -> [RetroStateSlot] { (0..<Self.slots).map(read) }

    private func read(_ slot: Int) -> RetroStateSlot {
        guard let savedAt = written(slot) else { return RetroStateSlot(slot) }
        var picture: Data?
        let path = picturePath(slot)
        if let info = try? FileManager.default.attributesOfItem(atPath: path), info[.type] as? FileAttributeType == .typeRegular,
           let kept = info[.modificationDate] as? Date, kept >= savedAt,
           let size = (info[.size] as? NSNumber)?.intValue, size <= Self.pictureLimit {
            picture = FileManager.default.contents(atPath: path)
        }
        return RetroStateSlot(slot, savedAt: savedAt, picture: picture)
    }

    /// Keeps `png` as `slot`'s picture: written beside it, flushed, then renamed over it, so a
    /// picture is whole or not there. With `png` nil, the picture of the state the slot held before
    /// goes. A picture that cannot be written leaves none behind, and throws.
    public func keepPicture(_ slot: Int, _ png: Data?) throws {
        let path = picturePath(slot)
        guard let png else { return Self.remove(path) }
        let writing = path + ".writing"
        do {
            guard FileManager.default.createFile(atPath: writing, contents: nil) else { throw POSIXError(.ENOENT) }
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: writing))
            do {
                try handle.write(contentsOf: png)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard Darwin.rename(writing, path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            Self.remove(writing)
            Self.remove(path)
            throw error
        }
    }

    private static func remove(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// A small PNG of a game's picture for its save state slot: `width` pixels wide, at the game's
/// display `aspect`, as its picture is shown. Nil when the image could not be drawn or encoded.
public enum RetroStatePicture {
    public static func png(_ image: CGImage, aspect: Double, width: Int = 240) -> Data? {
        guard aspect > 0, aspect.isFinite else { return nil }
        let height = min(max(Int((Double(width) / aspect).rounded()), 1), width * 4)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, small, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
