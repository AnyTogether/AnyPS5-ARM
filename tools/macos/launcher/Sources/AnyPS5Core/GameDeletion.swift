import Foundation

/// Why Delete game will not touch a game's files.
public enum DeletionRefusal: Error, Equatable, Sendable {
    /// The game's folder is a games folder itself, or holds one: deleting it would take the
    /// library's own folder (and whatever else is in it).
    case libraryFolder
    /// The game's folder is a link, or is reached through one that leads out of its games folder:
    /// the files live somewhere the library does not own.
    case linkedElsewhere
    /// Another game of the library keeps its files inside this game's folder.
    case sharedFolder
}

/// What Delete game takes from the disk: the game's own folder first, then what belongs to it and
/// to no other game (its update, its add-ons, and the archives those folders were unpacked from).
public struct DeletionPlan: Equatable, Sendable {
    public let game: Game
    /// The games folder the game was found in.
    public let root: URL
    /// The folders and files that go, the game's folder first. Never a link.
    public let items: [URL]

    public init(game: Game, root: URL, items: [URL]) {
        self.game = game
        self.root = root
        self.items = items
    }

    /// The game's own folder.
    public var folder: URL { items[0] }
    /// What goes with the game's folder.
    public var extras: [URL] { Array(items.dropFirst()) }
}

/// How one item left the disk.
public enum TrashResult: Equatable, Sendable {
    /// In the Trash, where it can be put back from.
    case trashed
    /// There is no Trash for it where it is (a drive without one, a network share): nothing was
    /// touched.
    case noTrash
    /// It could not be moved (in use, no permission): nothing was touched.
    case failed(String)
}

/// How a deletion ended.
public enum DeletionOutcome: Equatable, Sendable {
    /// The game's folder is gone. `left` could not follow it.
    case deleted(left: [URL])
    /// The game's folder cannot go to the Trash where it is; nothing was touched.
    case needsPermanent
    /// The game's folder could not be removed; nothing was touched.
    case failed(String)
}

/// Delete game: the game's own files off the disk, into the Trash. What it may take is decided
/// here, away from the interface, so it can be tested without one. The same rules as AnyPS5
/// Desktop's game_deletion.dart.
public enum GameDeletion {
    /// The archives a game is dropped into a games folder as (GameArchives).
    static let archiveExtensions = ["zip", "ffpfsc"]

    /// What deleting `game` takes. `root` is the games folder it was found in, `roots` all the
    /// games folders and `games` the library.
    ///
    /// Only the game's own root ever goes: the folder that holds its eboot.bin and sce_sys. Never
    /// a games folder (a dump kept loose in one shares it with the store and with other games),
    /// never a link or a folder reached through a link that leads out of the games folder, never a
    /// folder another game lives in. Its update and add-ons go with it unless another game uses
    /// them too, and so does the archive a folder was unpacked from: left behind, the update would
    /// show as a game of its own and the archive would be offered for unpacking again.
    public static func plan(_ game: Game, root: URL, roots: [URL], games: [Game]) throws -> DeletionPlan {
        let folder = game.folder
        if isLink(folder) { throw DeletionRefusal.linkedElsewhere }
        let everyRoot = [root] + roots
        for other in everyRoot where same(other, folder) || inside(folder, other) { throw DeletionRefusal.libraryFolder }
        let realRoot = real(root), realFolder = real(folder)
        if realRoot == realFolder { throw DeletionRefusal.libraryFolder }
        guard isWithin(realRoot, realFolder) else { throw DeletionRefusal.linkedElsewhere }
        for other in roots {
            let path = real(other)
            if path == realFolder || isWithin(realFolder, path) { throw DeletionRefusal.libraryFolder }
        }
        // What the other games own: their folders, updates and add-ons.
        let taken = games.filter { $0.id != game.id }.flatMap { other -> [URL] in
            [other.folder] + (other.update.map { [$0.folder] } ?? []) + other.addons.map(\.folder)
        }
        if taken.contains(where: { same(folder, $0) || inside(folder, $0) }) { throw DeletionRefusal.sharedFolder }
        var items = [folder]
        func add(_ url: URL) {
            if items.contains(where: { same($0, url) || inside($0, url) }) { return }
            guard isDirectory(url), isWithin(realRoot, real(url)) else { return }
            if everyRoot.contains(where: { same($0, url) || inside(url, $0) }) { return }
            // Another game's too (two dumps of one title share an update): it stays.
            if taken.contains(where: { same($0, url) || inside(url, $0) || inside($0, url) }) { return }
            items.append(url)
        }
        if let update = game.update { add(update.folder) }
        for addon in game.addons {
            // "<game>-DLC" holds nothing but this game's add-ons: the whole folder goes.
            let parent = addon.folder.deletingLastPathComponent()
            let own = GameAddons.addonSuffixes.contains { parent.lastPathComponent.lowercased().hasSuffix($0) }
            add(own && !same(parent, folder.deletingLastPathComponent()) ? parent : addon.folder)
        }
        // The archive a folder was unpacked from, beside it under the same name.
        for item in items {
            for ending in archiveExtensions {
                let archive = item.deletingLastPathComponent().appendingPathComponent(item.lastPathComponent + "." + ending)
                if isFile(archive) { items.append(archive) }
            }
        }
        return DeletionPlan(game: game, root: root, items: items)
    }

    /// Moves the plan's items to the Trash (`trash`), or with `permanent` deletes them for good
    /// (`remove`). The game's folder goes first: when it cannot go, nothing else is touched. Slow
    /// for a big game on another volume; never on the main thread.
    public static func run(_ plan: DeletionPlan, permanent: Bool = false,
                           trash: (URL) -> TrashResult = GameDeletion.systemTrash,
                           remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) -> DeletionOutcome {
        var left: [URL] = []
        for (index, item) in plan.items.enumerated() {
            let first = index == 0
            // Changed into a link since it was planned: never followed.
            if isLink(item) {
                if first { return .failed("the folder became a link") }
                left.append(item)
                continue
            }
            guard isDirectory(item) || isFile(item) else {
                if first { return .failed("the folder is not there") }
                continue
            }
            let result: TrashResult
            if permanent {
                do {
                    try remove(item)
                    result = .trashed
                } catch {
                    result = .failed(error.localizedDescription)
                }
            } else {
                result = trash(item)
            }
            switch result {
            case .trashed: break
            case .noTrash:
                if first { return .needsPermanent }
                left.append(item)
            case .failed(let message):
                if first { return .failed(message) }
                left.append(item)
            }
        }
        return .deleted(left: left)
    }

    /// The Mac's Trash. A volume without one (a network share, some external formats) answers
    /// `noTrash`, and nothing is deleted.
    public static func systemTrash(_ url: URL) -> TrashResult {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .trashed
        } catch {
            let problem = error as NSError
            if problem.domain == NSCocoaErrorDomain, problem.code == NSFeatureUnsupportedError { return .noTrash }
            return .failed(error.localizedDescription)
        }
    }

    /// The bytes the plan's items take, files and folders alike.
    public static func size(of items: [URL]) -> Int64 {
        items.reduce(Int64(0)) { (total: Int64, item: URL) -> Int64 in
            if isDirectory(item) { return total + GameLibrary.size(of: item) }
            let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return total + Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
    }

    // MARK: Paths

    static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// A real folder, not a link to one.
    static func isDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }

    /// A real file, not a link to one.
    static func isFile(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular
    }

    /// `url`'s path with every link in it followed.
    static func real(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isWithin(_ parent: String, _ child: String) -> Bool {
        child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    /// The same place, as the paths are written or once their links are followed.
    static func same(_ left: URL, _ right: URL) -> Bool {
        left.standardizedFileURL.path == right.standardizedFileURL.path || real(left) == real(right)
    }

    /// Whether `child` is inside `parent`, as the paths are written or once their links are
    /// followed.
    static func inside(_ parent: URL, _ child: URL) -> Bool {
        isWithin(parent.standardizedFileURL.path, child.standardizedFileURL.path) || isWithin(real(parent), real(child))
    }
}
