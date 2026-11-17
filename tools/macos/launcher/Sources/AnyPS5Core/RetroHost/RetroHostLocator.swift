import Foundation

/// Which emulator host the launcher may run (anyps5-retro-host docs/protocol.md "Finding and
/// checking the host"), as on Windows and Linux, where a debug build (`kDebugMode`) may run the host
/// `ANYPS5_RETRO_HOST` names.
///
/// A release only ever runs a signed host release it ships with or downloads, after the checks the
/// protocol lists, and ignores `ANYPS5_RETRO_HOST`. Those checks come with signed distribution, so
/// until then a release finds no host at all. A debug build may run any host it is pointed at,
/// unchecked. Which of the two a build is gets decided when it is compiled (`#if DEBUG`, set by
/// `swift build` and `swift test` and never by `swift build -c release`), not by a setting, file,
/// argument or environment variable of the running launcher, so a release build can never find an
/// unchecked host: it does not even hold the variable's name.
public enum RetroHostLocator {
    /// Whether this build may run a host it has not checked: true only in a debug build.
    public static var runsUncheckedHosts: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// The host this build runs: in a debug build the executable `ANYPS5_RETRO_HOST` names, when it
    /// is an absolute path to an executable file; nil in a release build, and when the variable is
    /// unset or names no such file.
    public static func host(environment: [String: String] = ProcessInfo.processInfo.environment,
                            fileManager: FileManager = .default) -> URL? {
        #if DEBUG
        guard let path = environment["ANYPS5_RETRO_HOST"], path.hasPrefix("/") else { return nil }
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue,
              fileManager.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
        #else
        return nil
        #endif
    }
}
