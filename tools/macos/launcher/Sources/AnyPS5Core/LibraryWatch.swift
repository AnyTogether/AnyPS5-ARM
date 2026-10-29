import CoreServices
import Foundation

/// Which games a scan of the games folder found that the launcher had not seen before, for the
/// "New game" notice. The first scan after launch, or after `reset()` (a new games folder), only
/// learns what is there. Games that go away go quietly, and are not new when they come back (an
/// external drive unplugged and plugged in again); a folder renamed or moved, whose title went
/// away in the same scan, is not new either.
public struct LibraryTracker: Sendable {
    private var known: Set<String>?
    private var last: [String: String] = [:]

    public init() {}

    public mutating func reset() {
        known = nil
        last = [:]
    }

    /// Takes a scan's games and returns the new ones, in the scan's order.
    public mutating func update(_ games: [Game]) -> [Game] {
        let current = Dictionary(games.map { ($0.id, $0.titleID) }, uniquingKeysWith: { first, _ in first })
        defer {
            known = (known ?? []).union(current.keys)
            last = current
        }
        guard let known else { return [] }
        let gone = Set(last.filter { current[$0.key] == nil }.values)
        return games.filter { !known.contains($0.id) && !gone.contains($0.titleID) }
    }
}

/// Watches the games folders and everything in them (FSEvents, file by file), and scans them again
/// a moment after things stop changing there: a game copied in, in a subfolder too, shows up when
/// its copy is far enough along to be a game. A long copy is still looked at every few seconds,
/// and a dump that is not whole yet is looked at again until it is, or until it has stayed the
/// same for a while. The launcher's own store and hidden files never count, so unlocking a game
/// does not keep rescanning. A folder that is not there (its drive unplugged) is skipped and
/// reported as not connected until it is back; `refresh()` watches it again once its drive mounts.
///
/// `deliver` runs on the monitor's own queue after every scan, the first one included (whose
/// `added` is always empty).
public final class LibraryMonitor: @unchecked Sendable {
    public struct Update: Sendable {
        /// The library: every folder's games, a game in several folders once (GameLibrary.merge).
        public let games: [Game]
        /// Game ID to the folder it was found in.
        public let roots: [String: URL]
        /// Each folder, in order: there or not, and how many games it holds.
        public let folders: [GameLibrary.FolderStatus]
        /// The games no scan had found before (see `LibraryTracker`).
        public let added: [Game]
        /// Folders that look like a dump still being copied.
        public let incomplete: [URL]
        /// The first scan of this folder.
        public let first: Bool
    }

    public struct Timing: Sendable {
        /// How long FSEvents gathers events before it reports them.
        public var latency: TimeInterval = 0.5
        /// How long the folder must stay still before the scan.
        public var quiet: TimeInterval = 1
        /// The longest a scan waits while changes keep coming.
        public var maxWait: TimeInterval = 4
        /// How often a dump that is not whole is looked at again.
        public var recheck: TimeInterval = 3
        /// How long such a dump may stay the same before it is left alone.
        public var settle: TimeInterval = 90
        public init() {}
    }

    public let roots: [URL]
    private let timing: Timing
    private let deliver: @Sendable (Update) -> Void
    private let queue = DispatchQueue(label: "org.anyps5.library-monitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()

    // Only touched on `queue`.
    private var stream: FSEventStreamRef?
    private var tracker = LibraryTracker()
    private var scans = 0
    private var pending: DispatchWorkItem?
    private var firstRequest: DispatchTime?
    private var incompleteSignature = ""
    private var incompleteSince = DispatchTime.now()
    private var stopped = false

    public convenience init(root: URL, timing: Timing = Timing(), deliver: @escaping @Sendable (Update) -> Void) {
        self.init(roots: [root], timing: timing, deliver: deliver)
    }

    public init(roots: [URL], timing: Timing = Timing(), deliver: @escaping @Sendable (Update) -> Void) {
        self.roots = roots
        self.timing = timing
        self.deliver = deliver
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Starts watching and scans at once.
    public func start() {
        onQueue {
            self.stopped = false
            self.startStream()
            self.request(after: 0)
        }
    }

    /// Scans again soon; several asks close together make one scan.
    public func rescan() {
        onQueue { self.request(after: 0.15) }
    }

    /// Watches again from scratch and scans: for a drive that was just mounted.
    public func refresh() {
        onQueue {
            guard !self.stopped else { return }
            self.stopStream()
            self.startStream()
            self.request(after: 0.15)
        }
    }

    public func stop() {
        onQueue {
            self.stopped = true
            self.pending?.cancel()
            self.pending = nil
            self.stopStream()
        }
    }

    /// Whether an event at `path` can change what the scan finds: anything in the folder but the
    /// launcher's store and hidden files, and the folder itself or what holds it (moved, its drive
    /// gone).
    public static func matters(_ path: String, root: String) -> Bool {
        let event = normal(path), folder = normal(root)
        if event == folder || event == "/" || folder.hasPrefix(event + "/") { return true }
        guard event.hasPrefix(folder + "/") else { return true }
        let relative = event.dropFirst(folder.count + 1)
        return !relative.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// A path as FSEvents and the settings may both write it: no trailing slash, /private/var,
    /// /private/tmp and /private/etc as /var, /tmp and /etc.
    static func normal(_ path: String) -> String {
        var value = path
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        for prefix in ["/private/var/", "/private/tmp/", "/private/etc/"] where value.hasPrefix(prefix) {
            value.removeFirst("/private".count)
        }
        if value == "/private/var" || value == "/private/tmp" { value.removeFirst("/private".count) }
        return value
    }

    /// `matters` for several folders: an event inside one (or more, when one holds another) counts
    /// when it counts for each folder holding it, so one folder's store is not another's change;
    /// an event in none of them (what holds a folder, its drive) always counts.
    public static func matters(_ path: String, roots: [String]) -> Bool {
        let event = normal(path)
        let holding = roots.filter { root in
            let folder = normal(root)
            return event == folder || event.hasPrefix(folder + "/")
        }
        return holding.isEmpty || holding.allSatisfy { matters(path, root: $0) }
    }

    // MARK: On the queue

    private func onQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true { work() } else { queue.sync(execute: work) }
    }

    private func startStream() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<LibraryMonitor>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            monitor.received(list)
        }
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, roots.map(\.path) as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), timing.latency, FSEventStreamCreateFlags(flags)) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func received(_ paths: [String]) {
        guard !stopped else { return }
        let rootPaths = roots.map(\.path)
        guard paths.isEmpty || paths.contains(where: { Self.matters($0, roots: rootPaths) }) else { return }
        request(after: timing.quiet)
    }

    /// A scan `delay` from now, but never later than `maxWait` after the first unanswered ask.
    private func request(after delay: TimeInterval) {
        guard !stopped else { return }
        let now = DispatchTime.now()
        let first = firstRequest ?? now
        firstRequest = first
        let deadline = min(now + delay, first + timing.maxWait)
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pending = work
        queue.asyncAfter(deadline: deadline, execute: work)
    }

    private func scan() {
        guard !stopped else { return }
        pending = nil
        firstRequest = nil
        let survey = GameLibrary.survey(roots: roots)
        let added = tracker.update(survey.games)
        scans += 1
        let update = Update(games: survey.games, roots: survey.roots, folders: survey.folders, added: added, incomplete: survey.incomplete, first: scans == 1)
        deliver(update)
        lookAgainAtIncomplete(survey.incomplete)
    }

    /// A dump still being copied is looked at again until it is a game or stops changing; the
    /// folder's own events usually get there first.
    private func lookAgainAtIncomplete(_ folders: [URL]) {
        guard !folders.isEmpty else {
            incompleteSignature = ""
            return
        }
        let signature = folders.map { folder -> String in
            let fileManager = FileManager.default
            func stamp(_ url: URL) -> String {
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return "-" }
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                return "\(size)@\(date)"
            }
            return [folder.path, stamp(folder), stamp(folder.appendingPathComponent("sce_sys")), stamp(folder.appendingPathComponent("sce_sys/param.json")), stamp(folder.appendingPathComponent("eboot.bin"))].joined(separator: "|")
        }.joined(separator: "\n")
        let now = DispatchTime.now()
        if signature != incompleteSignature {
            incompleteSignature = signature
            incompleteSince = now
        }
        guard pending == nil, now < incompleteSince + timing.settle else { return }
        request(after: timing.recheck)
    }
}
