import AppKit
import Foundation

enum Phase: Int, CaseIterable, Identifiable {
    case prepare
    case relink
    case copyGame
    case bundle
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .prepare: return L.phasePrepare
        case .relink: return L.phaseRelink
        case .copyGame: return L.phaseCopy
        case .bundle: return L.phaseBundle
        case .finish: return L.phaseFinish
        }
    }
}

struct ConversionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// The converter's own copy of the tools the command line uses: Contents/Resources/toolkit holds the
// relinker, the prx libraries, and the Vulkan loader with MoltenVK and its driver manifest, whose
// library path already points into a packaged title (Contents/MacOS/libs).
struct Toolkit {
    let root: URL

    static var bundled: Toolkit? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("toolkit")
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("relinker").path) ? Toolkit(root: root) : nil
    }

    var relinker: URL { root.appendingPathComponent("relinker") }
    var libraries: URL { root.appendingPathComponent("libs") }
    var vulkan: URL { root.appendingPathComponent("vulkan") }
}

final class Converter {
    let game: GameFolder
    let destination: URL
    let toolkit: Toolkit
    let report: (Phase) -> Void
    let log: (String) -> Void

    init(game: GameFolder, destination: URL, toolkit: Toolkit, report: @escaping (Phase) -> Void, log: @escaping (String) -> Void) {
        self.game = game
        self.destination = destination
        self.toolkit = toolkit
        self.report = report
        self.log = log
    }

    var bundleURL: URL {
        destination.appendingPathComponent(Converter.safeName(game.name) + ".app")
    }

    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Game" : cleaned
    }

    func run() throws -> URL {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("AnyPS5-" + UUID().uuidString)
        defer { try? fileManager.removeItem(at: work) }

        report(.prepare)
        guard let executable = game.executable else { throw ConversionError(message: L.noExecutable) }
        let source = work.appendingPathComponent("source")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        let input = source.appendingPathComponent("eboot.bin")
        try fileManager.copyItem(at: executable, to: input)
        for module in game.modules {
            let directory = source.appendingPathComponent(module.deletingLastPathComponent().lastPathComponent)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let elf = Elf.resolve(module) else { continue }
            try fileManager.copyItem(at: elf, to: directory.appendingPathComponent(module.lastPathComponent))
            log("module " + module.lastPathComponent + (elf == module ? "" : " (from .esbak)"))
        }

        report(.relink)
        let relinked = work.appendingPathComponent("out")
        try runTool(toolkit.relinker, ["--macos", "--to-rosetta", input.path, relinked.appendingPathComponent("eboot").path])

        report(.copyGame)
        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }
        let contents = bundleURL.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        let app0 = resources.appendingPathComponent("game/app0")
        try fileManager.createDirectory(at: macOS.appendingPathComponent("libs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: app0.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: game.url, to: app0)
        try overlay(relinked.appendingPathComponent("app0"), onto: app0)

        report(.bundle)
        try fileManager.copyItem(at: relinked.appendingPathComponent("eboot"), to: macOS.appendingPathComponent("eboot"))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent("eboot").path)
        try fileManager.createSymbolicLink(atPath: macOS.appendingPathComponent("app0").path, withDestinationPath: "../Resources/game/app0")
        for library in try fileManager.contentsOfDirectory(at: toolkit.libraries, includingPropertiesForKeys: nil) where library.pathExtension == "prx" {
            try fileManager.copyItem(at: library, to: macOS.appendingPathComponent("libs").appendingPathComponent(library.lastPathComponent))
        }
        for name in ["libvulkan.1.dylib", "libMoltenVK.dylib"] {
            try fileManager.copyItem(at: toolkit.vulkan.appendingPathComponent(name), to: macOS.appendingPathComponent("libs").appendingPathComponent(name))
        }
        let icd = resources.appendingPathComponent("vulkan/icd.d")
        try fileManager.createDirectory(at: icd, withIntermediateDirectories: true)
        try fileManager.copyItem(at: toolkit.vulkan.appendingPathComponent("MoltenVK_icd.json"), to: icd.appendingPathComponent("MoltenVK_icd.json"))
        let launcher = macOS.appendingPathComponent("launch")
        try launchScript.write(to: launcher, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        report(.finish)
        let hasIcon = makeIcon(from: app0.appendingPathComponent("sce_sys/icon0.png"), into: resources)
        var info: [String: Any] = [
            "CFBundleName": game.name,
            "CFBundleDisplayName": game.name,
            "CFBundleIdentifier": game.bundleIdentifier,
            "CFBundleExecutable": "launch",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": game.version,
            "CFBundleVersion": game.version,
            "LSMinimumSystemVersion": "11.0",
            "LSApplicationCategoryType": "public.app-category.games",
            "NSHighResolutionCapable": true,
        ]
        if hasIcon { info["CFBundleIconFile"] = "AppIcon" }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        // Files copied out of a downloaded converter carry its quarantine flag; the game is made here.
        try? runTool(URL(fileURLWithPath: "/usr/bin/xattr"), ["-dr", "com.apple.quarantine", bundleURL.path], quiet: true)
        NSWorkspace.shared.noteFileSystemChanged(bundleURL.path)
        return bundleURL
    }

    private var launchScript: String {
        """
        #!/bin/sh
        # Starts the title from its game folder: AnyPS5 maps /app0 under the working directory.
        here="$(cd "$(dirname "$0")" && pwd)"
        export VK_DRIVER_FILES="${VK_DRIVER_FILES:-$here/../Resources/vulkan/icd.d/MoltenVK_icd.json}"
        export ANYPS5_SHADER_CACHE_DIR="${ANYPS5_SHADER_CACHE_DIR:-$HOME/Library/Caches/\(game.bundleIdentifier)/shader_cache}"
        mkdir -p "$ANYPS5_SHADER_CACHE_DIR" "$HOME/Library/Logs/AnyPS5"
        cd "$here/../Resources/game" || exit 1
        exec "$here/eboot" "$@" >> "$HOME/Library/Logs/AnyPS5/\(game.titleID).log" 2>&1

        """
    }

    private func overlay(_ source: URL, onto target: URL) throws {
        let fileManager = FileManager.default
        let base = source.resolvingSymlinksInPath().path
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let item as URL in enumerator {
            let path = item.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { throw ConversionError(message: "unexpected relinker output " + path) }
            let relative = path.dropFirst(base.count + 1)
            let destination = target.appendingPathComponent(String(relative))
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: item, to: destination)
        }
    }

    private func makeIcon(from png: URL, into resources: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: png.path) else { return false }
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
        defer { try? FileManager.default.removeItem(at: iconset) }
        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for size in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
                    try runTool(URL(fileURLWithPath: "/usr/bin/sips"), ["-z", "\(size * scale)", "\(size * scale)", png.path, "--out", iconset.appendingPathComponent(name).path], quiet: true)
                }
            }
            try runTool(URL(fileURLWithPath: "/usr/bin/iconutil"), ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path], quiet: true)
            return true
        } catch {
            log("icon: " + error.localizedDescription)
            return false
        }
    }

    private func runTool(_ tool: URL, _ arguments: [String], quiet: Bool = false) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if !quiet || process.terminationStatus != 0 {
            for line in output.split(separator: "\n") { log(String(line)) }
        }
        guard process.terminationStatus == 0 else {
            let last = output.split(separator: "\n").last.map(String.init) ?? ""
            throw ConversionError(message: L.toolFailed(tool.lastPathComponent, Int(process.terminationStatus), last))
        }
    }
}

enum Rosetta {
    static var installed: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func install() -> Bool {
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil && installed
    }
}
