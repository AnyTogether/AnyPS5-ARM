import Foundation

/// A relinker option a player can switch on for one game (Advanced → Rebuild Options), used by
/// the game's next rebuild. Only these ever reach the relinker: whatever else a settings file
/// names is ignored. An option that chooses the platform, the target or a path, or that can give
/// a broken game without saying so, does not belong here.
public enum RelinkerFlag: String, CaseIterable, Sendable {
    /// Passes each function import of the executable through libc.prx's call tracer, so that
    /// detailed logging (APS5_TRACE_CALLS) can record the game's system library calls.
    case traceImports = "--trace-imports"

    /// What the toolkit's libc.prx has to export for a game relinked with this option to start:
    /// the executable binds it without a fallback.
    var libcExport: String? {
        switch self {
        case .traceImports: return "TraceImport_nid_no_patch"
        }
    }
}

extension GameSettings {
    /// The relinker options chosen for this game that the launcher knows, in the list's order.
    public var chosenRelinkerFlags: [RelinkerFlag] {
        RelinkerFlag.allCases.filter { relinkerFlags?.contains($0.rawValue) == true }
    }

    public mutating func setRelinkerFlag(_ flag: RelinkerFlag, _ on: Bool) {
        let current = chosenRelinkerFlags
        let chosen = RelinkerFlag.allCases.filter { $0 == flag ? on : current.contains($0) }
        relinkerFlags = chosen.isEmpty ? nil : chosen.map(\.rawValue)
    }
}

extension Toolkit {
    /// Whether this toolkit can relink with `flag`: its relinker knows the option and its libc.prx
    /// has what the option needs. An engine that lacks it (an older one, upstream's) unlocks the
    /// game without it. Read from the files, once per change of them.
    public func supports(_ flag: RelinkerFlag) -> Bool {
        guard ToolkitFiles.contains(relinker, flag.rawValue) else { return false }
        guard let export = flag.libcExport else { return true }
        return ToolkitFiles.contains(libraries.appendingPathComponent("libc.prx"), export)
    }
}

private enum ToolkitFiles {
    static let lock = NSLock()
    nonisolated(unsafe) static var answers: [String: Bool] = [:]

    static func contains(_ file: URL, _ text: String) -> Bool {
        var info = stat()
        guard stat(file.path, &info) == 0 else { return false }
        let key = "\(file.path)\n\(text)\n\(info.st_size)\n\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
        if let known = lock.withLock({ answers[key] }) { return known }
        let found = (try? Data(contentsOf: file, options: .alwaysMapped)).map { $0.range(of: Data(text.utf8)) != nil } ?? false
        lock.withLock { answers[key] = found }
        return found
    }
}
