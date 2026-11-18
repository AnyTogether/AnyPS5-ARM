import Foundation

/// The emulator host and the SwanStation library it loads for a PS1 game: the signed release the
/// launcher downloaded (`RetroHostStore.installed()`), checked before each start, or in a debug
/// build (`RetroHostLocator`) the host `ANYPS5_RETRO_HOST` names (`locate`), which is not. As on
/// Windows and Linux (AnyPS5 Desktop's lib/core/retro_host/retro_host_install.dart). The core is
/// the SwanStation library beside the host, as a host release's zip holds the two. A host release
/// with the `ps2` capability has LRPS2 beside them too, and so may an unchecked host: `ps2Core`.
public struct RetroHostInstall: Equatable, Sendable {
    /// The environment variable that names the host in a debug build.
    public static let variable = "ANYPS5_RETRO_HOST"

    /// The host executable.
    public let host: String
    /// The SwanStation library, given to the host in `start`.
    public let core: String
    /// The LRPS2 library a PS2 game is started with, or nil when this host has none beside it.
    public let ps2Core: String?
    /// A signed release's host: its files are checked before each start and held until the host
    /// has exited (`RetroHostStore.check()`, `RetroHostClient.start(checked:)`). False for the host
    /// of a debug build.
    public let checked: Bool

    public init(host: String, core: String, ps2Core: String? = nil, checked: Bool = false) {
        self.host = host
        self.core = core
        self.ps2Core = ps2Core
        self.checked = checked
    }

    /// The host `environment` names and the SwanStation library beside it, in a debug build that
    /// runs an unchecked host, when both files are there; nil otherwise, and always in a release,
    /// which is compiled without the lookup (`RetroHostLocator.host`). LRPS2 is its `ps2Core` when
    /// it is beside them too, unchecked like them.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                              system: RetroHostSystem = .macosArm64) -> RetroHostInstall? {
        guard let host = RetroHostLocator.host(environment: environment) else { return nil }
        let folder = host.deletingLastPathComponent()
        let core = folder.appendingPathComponent(system.core).path
        guard GameLibrary.isFile(core) else { return nil }
        let ps2Core = folder.appendingPathComponent(system.ps2Core).path
        return RetroHostInstall(host: host.path, core: core, ps2Core: GameLibrary.isFile(ps2Core) ? ps2Core : nil)
    }
}
