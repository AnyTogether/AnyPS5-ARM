import AppKit

/// Gatekeeper runs an app downloaded from the release from a randomized, read-only copy (app
/// translocation) until it is moved. The launcher offers to move itself to Applications, clear the
/// download's quarantine flag on the moved copy and reopen from there.
enum AppLocation {
    private typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    private static let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)

    static var isTranslocated: Bool {
        let bundle = Bundle.main.bundleURL
        if bundle.path.contains("/AppTranslocation/") { return true }
        guard let symbol = dlsym(security, "SecTranslocateIsTranslocatedURL") else { return false }
        var translocated = DarwinBoolean(false)
        _ = unsafeBitCast(symbol, to: IsTranslocated.self)(bundle as CFURL, &translocated, nil)
        return translocated.boolValue
    }

    /// Where the user's copy of the app is (in Downloads, usually).
    static var original: URL? {
        guard let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL"),
              let url = unsafeBitCast(symbol, to: OriginalPath.self)(Bundle.main.bundleURL as CFURL, nil)?.takeRetainedValue() else { return nil }
        return url as URL
    }

    /// Copies the app to /Applications (or ~/Applications), clears its quarantine flag and reopens it.
    static func moveToApplications() -> Bool {
        let fileManager = FileManager.default
        guard let source = original ?? Optional(Bundle.main.bundleURL) else { return false }
        let candidates = [URL(fileURLWithPath: "/Applications"), fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for folder in candidates {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("AnyPS5.app")
            do {
                if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
                try fileManager.copyItem(at: source, to: target)
            } catch {
                continue
            }
            let clear = Process()
            clear.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            clear.arguments = ["-dr", "com.apple.quarantine", target.path]
            try? clear.run()
            clear.waitUntilExit()
            if source.path != target.path { try? fileManager.trashItem(at: source, resultingItemURL: nil) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return true
        }
        return false
    }
}
