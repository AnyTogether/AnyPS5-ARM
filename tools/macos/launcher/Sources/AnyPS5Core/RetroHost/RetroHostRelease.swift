import CryptoKit
import Darwin
import Foundation

/// Why the emulator host cannot be used: a release check failed (anyps5-retro-host
/// docs/protocol.md "Finding and checking the host"). The launcher then does not start the host and
/// shows that the emulator needs to be downloaded again. As on Windows and Linux (AnyPS5 Desktop's
/// lib/core/retro_host/retro_host_release.dart).
public struct RetroHostReleaseFailure: Error, Equatable, CustomStringConvertible {
    public let message: String
    /// The file of the release that failed (the host, SwanStation or LRPS2), when one file did.
    public let file: String?
    /// A signed release that has no host for this system: nothing is wrong with it, it is just not
    /// for this launcher.
    public let notReleased: Bool

    public init(_ message: String, file: String? = nil, notReleased: Bool = false) {
        self.message = message
        self.file = file
        self.notReleased = notReleased
    }

    public var description: String { message }
}

/// A core that ships in a package of its own beside the host package, which the player adds as an
/// emulator of its own (protocol.md "Finding and checking the host"): today only LRPS2, the PS2
/// core. Its package is `anyps5-retro-host-<version>-<os>-<arch>-<name>.zip` with its `.files`, in
/// the same release as the host package, and unpacks into the host's folder. As on Windows and
/// Linux (AnyPS5 Desktop's `RetroHostCorePackage`).
public enum RetroHostCorePackage: String, CaseIterable, Hashable, Sendable {
    case lrps2

    /// The package's name in its file names: `lrps2`.
    public var name: String { rawValue }

    /// The core library the package holds on `system`, which its `.files` must list.
    public func library(_ system: RetroHostSystem) -> String {
        switch self {
        case .lrps2: return system.ps2Core
        }
    }

    /// The package's zip in the release of host `version` for `system`.
    public func zipName(_ version: RetroHostVersion, _ system: RetroHostSystem) -> String { "\(stem(version, system)).zip" }

    /// The package's `.files` in the release of host `version` for `system`.
    public func filesName(_ version: RetroHostVersion, _ system: RetroHostSystem) -> String { "\(stem(version, system)).files" }

    private func stem(_ version: RetroHostVersion, _ system: RetroHostSystem) -> String {
        "anyps5-retro-host-\(version)-\(system.name)-\(name)"
    }
}

/// One system a host release is built for: `<os>-<arch>` in its file names, and the names of the
/// host and SwanStation inside its host package and of LRPS2 inside its LRPS2 package, as the host
/// repository's tools/package_release.py (`SYSTEMS`) packs them: an LRPS2 package that names its
/// core otherwise is refused. A release from before LRPS2 shipped has no LRPS2 package.
public struct RetroHostSystem: Equatable, Sendable {
    public let name: String
    public let executable: String
    public let core: String
    public let ps2Core: String

    public init(name: String, executable: String, core: String, ps2Core: String) {
        self.name = name
        self.executable = executable
        self.core = core
        self.ps2Core = ps2Core
    }

    public static let windowsX64 = RetroHostSystem(name: "windows-x64", executable: "anyps5-retro-host.exe",
                                                   core: "swanstation_libretro.dll", ps2Core: "pcsx2_libretro.dll")
    public static let linuxX64 = RetroHostSystem(name: "linux-x64", executable: "anyps5-retro-host",
                                                 core: "swanstation_libretro.so", ps2Core: "pcsx2_libretro.so")
    public static let macosArm64 = RetroHostSystem(name: "macos-arm64", executable: "anyps5-retro-host",
                                                   core: "swanstation_libretro.dylib", ps2Core: "pcsx2_libretro.dylib")

    /// The system this launcher runs on: the Mac's arm64 half of the launcher; nil on an Intel Mac,
    /// for which no host is released.
    public static var current: RetroHostSystem? {
        #if arch(arm64)
        return macosArm64
        #else
        return nil
        #endif
    }
}

/// A host release's version, `<major>.<minor>.<patch>` as in `welcome`'s `hostVersion`.
public struct RetroHostVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Nil unless `text` is exactly three dot-separated decimal numbers, each without a leading
    /// zero and at most nine digits.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard (1...9).contains(part.count), part.allSatisfy({ ("0"..."9").contains($0) }),
                  part == "0" || part.first != "0", let value = Int(part) else { return nil }
            numbers.append(value)
        }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: RetroHostVersion, rhs: RetroHostVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// A release file held open for its check (protocol.md "Finding and checking the host"): a
/// close-on-exec descriptor above 3, opened without blocking (so a FIFO put in its place is refused
/// at once), and hashed from what was opened, never by its path again. On macOS the system checks
/// the code signature of the host and of SwanStation as they are loaded, so the host is started
/// by its path.
public final class RetroCheckedFile: @unchecked Sendable {
    public let path: String
    private let lock = NSLock()
    private var descriptor: Int32

    private init(path: String, descriptor: Int32) {
        self.path = path
        self.descriptor = descriptor
    }

    deinit { close() }

    /// Opens `path`; throws when it is missing or is not a regular file.
    public static func open(_ path: String) throws -> RetroCheckedFile {
        var opened = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard opened >= 0 else { throw RetroHostReleaseFailure("\(path) cannot be opened: \(String(cString: strerror(errno)))") }
        var info = stat()
        guard fstat(opened, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(opened)
            throw RetroHostReleaseFailure("\(path) is not a regular file")
        }
        if opened <= 3 {
            let moved = fcntl(opened, F_DUPFD_CLOEXEC, 4)
            Darwin.close(opened)
            guard moved >= 0 else { throw RetroHostReleaseFailure("\(path) cannot be held") }
            opened = moved
        }
        return RetroCheckedFile(path: path, descriptor: opened)
    }

    public var isOpen: Bool { lock.withLock { descriptor >= 0 } }

    /// The sha256 of the file's bytes, lower-case hex.
    public func sha256Hex() throws -> String {
        let held = lock.withLock { descriptor }
        guard held >= 0 else { throw RetroHostReleaseFailure("\(path) is no longer held") }
        var hasher = SHA256()
        let chunk = 1 << 20
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var offset: off_t = 0
        while true {
            let got = pread(held, buffer, chunk, offset)
            if got < 0 {
                if errno == EINTR { continue }
                throw RetroHostReleaseFailure("\(path) could not be read")
            }
            if got == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: got))
            offset += off_t(got)
        }
        return FileDigest.hex(hasher.finalize())
    }

    /// Lets the file go. Calling it again does nothing.
    public func close() {
        let held: Int32 = lock.withLock {
            defer { descriptor = -1 }
            return descriptor
        }
        if held >= 0 { Darwin.close(held) }
    }
}

/// A host whose files were checked before a start: the client starts `executable` and calls
/// `release()` once the host has exited, since the host loads the core again for every game it
/// starts.
public final class RetroHostChecked: @unchecked Sendable {
    public let version: RetroHostVersion
    /// The host executable's path, the command's first argument.
    public let executable: String
    /// The SwanStation library the release ships: with `ps2Core`, the only cores a release
    /// launcher runs.
    public let core: String
    /// The LRPS2 library of the installed LRPS2 package, checked with the others, or nil when that
    /// package is not installed.
    public let ps2Core: String?
    private let files: [RetroCheckedFile]
    private let lock = NSLock()
    private var claimed = false

    init(version: RetroHostVersion, executable: String, core: String, ps2Core: String?, files: [RetroCheckedFile]) {
        self.version = version
        self.executable = executable
        self.core = core
        self.ps2Core = ps2Core
        self.files = files
    }

    /// The cores `start` may name for this host.
    public var cores: Set<String> { Set([core] + (ps2Core.map { [$0] } ?? [])) }

    /// Whether the checked files are still held.
    public var held: Bool { files.contains { $0.isOpen } }

    /// Takes this check for one start: false when it was released or another start took it.
    public func claim() -> Bool {
        lock.withLock {
            guard !claimed, held else { return false }
            claimed = true
            return true
        }
    }

    /// Lets the checked files go. Calling it again does nothing.
    public func release() {
        for file in files { file.close() }
    }
}

/// A release whose SHA256SUMS is signed by a trusted key, and the names of this system's files in
/// it: the host package's `zipName` and `filesName`, with their digests in `sums`, and the `cores`
/// whose packages it has for this system.
public struct RetroHostSignedRelease: Sendable {
    public let version: RetroHostVersion
    public let zipName: String
    public let filesName: String
    public let sums: ReleaseSigning.Sums
    public let cores: Set<RetroHostCorePackage>
}

/// One package of a release, checked against its signed sums: its `.files` as published, the
/// list it gives, and the zip it lists.
private struct RetroHostPackage {
    let filesName: String
    let listing: Data
    let files: [String: String]
    let zip: URL
    let zipName: String
}

/// Finding and checking the emulator host as anyps5-retro-host docs/protocol.md "Finding and
/// checking the host" asks, as on Windows and Linux: releases signed like launcher releases
/// (SHA256SUMS and SHA256SUMS.sig), each system's zip listed file by file in its `.files`.
public enum RetroHostRelease {
    /// The oldest host this launcher runs, even signed, so an old host with a known fault cannot be
    /// put back.
    public static let minimumVersion = RetroHostVersion(1, 0, 0)

    /// The file beside an installed host that keeps the tag it was published under, so the check
    /// before each start holds the signed version to it too. Its name starts with a dot, which no
    /// file of a release may (`parseFileList`).
    public static let tagName = ".release-tag"

    /// Refuses a release whose signed `version` is not the one its `tag` gives: the launcher picks
    /// a release by its tag, so an older signed host published again under a higher tag would
    /// otherwise be taken for an update.
    public static func checkTag(_ tag: String, _ version: RetroHostVersion) throws {
        guard tag == "v\(version)" else { throw RetroHostReleaseFailure("the release tagged \(tag) is signed as host \(version)") }
    }

    /// The checks before each start: the signature, the tag kept on install against the signed
    /// version, the host package's `.files` and the `.files` of every core package installed beside
    /// it against SHA256SUMS, and the host executable, SwanStation and each installed core
    /// package's core (LRPS2) against those `.files`, each hashed from a `RetroCheckedFile`. The
    /// host's file stays held in the result; the cores are checked by path, as macOS checks their
    /// code signature when the host loads them. LRPS2 is checked for a PS1 game too, since one host
    /// plays the next game, PS1 or PS2, on the cores checked when it started. A core package counts
    /// as installed when its `.files` is in `folder` and SHA256SUMS lists it; a core library no
    /// checked `.files` lists is never given.
    public static func checkBeforeStart(_ folder: URL, keys: [ReleaseSigning.Key]? = nil, system: RetroHostSystem? = nil,
                                        minimum: RetroHostVersion = minimumVersion) async throws -> RetroHostChecked {
        let target = try system ?? currentSystem()
        let sums = try verify(try readSmall(folder.appendingPathComponent(ReleaseSigning.sumsName)),
                              try readSmall(folder.appendingPathComponent(ReleaseSigning.signatureName)), keys)
        let release = try releaseOf(sums, target, minimum)
        try checkTag(try readTag(folder), release.version)
        let files = try signedList(folder, release.filesName, sums)
        var toCheck = [(target.executable, release.filesName, files), (target.core, release.filesName, files)]
        var installedCores = Set<RetroHostCorePackage>()
        for core in RetroHostCorePackage.allCases where release.cores.contains(core) {
            let filesName = core.filesName(release.version, target)
            guard GameLibrary.isFile(folder.appendingPathComponent(filesName).path) else { continue }
            toCheck.append((core.library(target), filesName, try signedList(folder, filesName, sums)))
            installedCores.insert(core)
        }
        let ps2 = installedCores.contains(.lrps2)
        var held: [RetroCheckedFile] = []
        do {
            for (name, listName, listed) in toCheck {
                guard let expected = listed[name] else {
                    throw RetroHostReleaseFailure("\(listName) does not list \(name)", file: name)
                }
                let file: RetroCheckedFile
                do {
                    file = try RetroCheckedFile.open(folder.appendingPathComponent(name).path)
                } catch {
                    throw RetroHostReleaseFailure("\(name) is missing or not a file", file: name)
                }
                held.append(file)
                guard try file.sha256Hex() == expected else {
                    throw RetroHostReleaseFailure("\(name) does not match the signed release", file: name)
                }
            }
        } catch {
            for file in held { file.close() }
            throw error
        }
        for core in held.dropFirst() { core.close() }
        return RetroHostChecked(version: release.version, executable: folder.appendingPathComponent(target.executable).path,
                                core: folder.appendingPathComponent(target.core).path,
                                ps2Core: ps2 ? folder.appendingPathComponent(target.ps2Core).path : nil, files: held)
    }

    /// The checks on download, then the unpacking: the signature, the signed version against `tag`,
    /// the zip and the `.files` against SHA256SUMS, and every file of the zip against the `.files`.
    /// `download` holds the files as published under `tag`; `into` is replaced by the unpacked zip
    /// with SHA256SUMS, SHA256SUMS.sig, the `.files` and the tag (`tagName`) beside it. Each of
    /// `cores` the release has a package of is checked the same way and unpacked into the same
    /// folder in the same step, with its `.files`; one the release lacks is not there afterwards, so
    /// a core package moves with the host or goes. The new host is written into `<into>.new` first,
    /// and only the two renames that put it in place touch the old one. Gives the version
    /// installed.
    public static func install(_ download: URL, into: URL, tag: String, keys: [ReleaseSigning.Key]? = nil,
                               system: RetroHostSystem? = nil, minimum: RetroHostVersion = minimumVersion,
                               cores: Set<RetroHostCorePackage> = []) async throws -> RetroHostVersion {
        let target = try system ?? currentSystem()
        let staging = URL(fileURLWithPath: into.path + ".new")
        let version = try stage(download, staging, tag: tag, keys: keys, system: target, minimum: minimum, cores: cores)
        do {
            try replace(into, with: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return version
    }

    private static func stage(_ download: URL, _ staging: URL, tag: String, keys: [ReleaseSigning.Key]?,
                              system: RetroHostSystem, minimum: RetroHostVersion, cores: Set<RetroHostCorePackage>) throws -> RetroHostVersion {
        let sumsBytes = try readSmall(download.appendingPathComponent(ReleaseSigning.sumsName))
        let signatureBytes = try readSmall(download.appendingPathComponent(ReleaseSigning.signatureName))
        let release = try signed(sums: sumsBytes, signature: signatureBytes, tag: tag, keys: keys, system: system, minimum: minimum)
        var packages = [try checkedPackage(download, release.filesName, release.zipName, release.sums, required: [system.executable, system.core])]
        for core in RetroHostCorePackage.allCases where cores.contains(core) && release.cores.contains(core) {
            let package = try checkedPackage(download, core.filesName(release.version, system), core.zipName(release.version, system),
                                             release.sums, required: [core.library(system)])
            try checkApart(packages.map(\.files), package)
            packages.append(package)
        }
        let manager = FileManager.default
        if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for package in packages {
                try unpack(package.zip, files: package.files, zipName: package.zipName, into: staging)
                try writeList(package, into: staging)
            }
            try sumsBytes.write(to: staging.appendingPathComponent(ReleaseSigning.sumsName))
            try signatureBytes.write(to: staging.appendingPathComponent(ReleaseSigning.signatureName))
            try Data(tag.utf8).write(to: staging.appendingPathComponent(tagName))
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.appendingPathComponent(system.executable).path)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
        return release.version
    }

    /// Writes every file of the zip into `folder`, each checked against the `.files` as it is
    /// written: a file the list does not name, one twice, a link, or anything but a file or a
    /// folder is refused, and so is a file of the list the zip does not hold. Only names the list
    /// gives, which `parseFileList` checked, are written.
    private static func unpack(_ zip: URL, files: [String: String], zipName: String, into folder: URL) throws {
        let reader: ZipReader
        do {
            reader = try ZipReader(zip)
        } catch {
            throw RetroHostReleaseFailure("\(zipName) cannot be read")
        }
        var written = Set<String>()
        while true {
            let next: ZipReader.Entry?
            do {
                next = try reader.next()
            } catch {
                throw RetroHostReleaseFailure("\(zipName) cannot be read")
            }
            guard let entry = next else { break }
            if entry.kind == .directory { continue }
            guard entry.kind == .file, entry.readable, let expected = files[entry.name], !written.contains(entry.name) else {
                throw RetroHostReleaseFailure("\(zipName) holds \(entry.name), which its file list does not")
            }
            let target = entry.name.split(separator: "/").reduce(folder) { $0.appendingPathComponent(String($1)) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: target.path, contents: nil),
                  let output = FileHandle(forWritingAtPath: target.path) else {
                throw RetroHostReleaseFailure("\(entry.name) could not be written")
            }
            var hasher = SHA256()
            do {
                defer { try? output.close() }
                try reader.readData { chunk in
                    hasher.update(bufferPointer: chunk)
                    try output.write(contentsOf: Data(chunk))
                }
                try output.synchronize()
            } catch let failure as RetroHostReleaseFailure {
                throw failure
            } catch {
                throw RetroHostReleaseFailure("\(entry.name) in \(zipName) could not be unpacked")
            }
            guard FileDigest.hex(hasher.finalize()) == expected else {
                throw RetroHostReleaseFailure("\(entry.name) in \(zipName) does not match its file list")
            }
            written.insert(entry.name)
        }
        for name in files.keys where !written.contains(name) {
            throw RetroHostReleaseFailure("\(zipName) does not hold \(name)")
        }
    }

    /// Adds `core`'s package to the host installed in `into`, from `download`, which holds that
    /// package's zip and `.files` as published in the installed host's release. The package is
    /// checked as on download, against the SHA256SUMS kept beside the installed host, whose
    /// signature and tag are checked again first, so only a package of the installed release is
    /// taken. None of its names may be one the host package or another installed core package has,
    /// ignoring case. It is unpacked and checked in `<into>.<core>.new` first, so nothing is written
    /// beside the host until every check passed; its files are then moved into `into`, and its
    /// `.files` last, so a package stopped halfway is not installed (`installedCores`) and its files
    /// are never given to the host. Stop the host first.
    public static func addCore(_ download: URL, into: URL, _ core: RetroHostCorePackage, keys: [ReleaseSigning.Key]? = nil,
                               system: RetroHostSystem? = nil, minimum: RetroHostVersion = minimumVersion) async throws {
        let target = try system ?? currentSystem()
        let release = try installedRelease(into, keys: keys, system: target, minimum: minimum)
        let sums = release.sums
        guard release.cores.contains(core) else {
            throw RetroHostReleaseFailure("the installed host \(release.version) has no \(core.name) package", notReleased: true)
        }
        let filesName = core.filesName(release.version, target)
        var installed = [try signedList(into, release.filesName, sums)]
        for other in RetroHostCorePackage.allCases where other != core && release.cores.contains(other) {
            let name = other.filesName(release.version, target)
            if GameLibrary.isFile(into.appendingPathComponent(name).path) {
                installed.append(try signedList(into, name, sums))
            }
        }
        let package = try checkedPackage(download, filesName, core.zipName(release.version, target), sums, required: [core.library(target)])
        try checkApart(installed, package)
        let manager = FileManager.default
        let staging = URL(fileURLWithPath: into.path + ".\(core.name).new")
        if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        try unpack(package.zip, files: package.files, zipName: package.zipName, into: staging)
        let listing = into.appendingPathComponent(filesName)
        if manager.fileExists(atPath: listing.path) { try manager.removeItem(at: listing) }
        for name in package.files.keys.sorted() {
            let from = staging.appendingPathComponent(name)
            let to = into.appendingPathComponent(name)
            try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: to.path) { try manager.removeItem(at: to) }
            try manager.moveItem(at: from, to: to)
        }
        try writeList(package, into: into)
    }

    /// Removes `core`'s package from the host installed in `into`: its `.files` first, so it is no
    /// longer installed, then every file that `.files` lists and the folders left empty. The list is
    /// only trusted when it matches the installed release's signed SHA256SUMS; otherwise only the
    /// `.files` and the core library are deleted, by their exact names. A name the host package's
    /// `.files` lists too, in any case, is left, so the host is never damaged on a file system that
    /// ignores case. Stop the host first. Nothing happens when the package is not installed.
    public static func removeCore(_ into: URL, _ core: RetroHostCorePackage, keys: [ReleaseSigning.Key]? = nil,
                                  system: RetroHostSystem? = nil) throws {
        let target = try system ?? currentSystem()
        guard let listing = installedCoreFiles(into, target, core) else { return }
        var files: [String: String]
        do {
            let release = try installedRelease(into, keys: keys, system: target)
            files = try signedList(into, listing.lastPathComponent, release.sums)
        } catch {
            files = [core.library(target): ""]
        }
        let kept: Set<String>
        if let host = installedFiles(into, target) {
            guard let bytes = try? Data(contentsOf: into.appendingPathComponent(host.name)),
                  let names = try? parseFileList(bytes) else {
                throw RetroHostReleaseFailure("the host package beside \(core.name) cannot be read")
            }
            kept = Set(names.keys.map { $0.lowercased() })
        } else {
            kept = []
        }
        let manager = FileManager.default
        try manager.removeItem(at: listing)
        let root = into.standardizedFileURL.path
        for name in files.keys.sorted() where !kept.contains(name.lowercased()) {
            let file = name.split(separator: "/").reduce(into) { $0.appendingPathComponent(String($1)) }
            if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
            var folder = file.deletingLastPathComponent().standardizedFileURL
            while folder.path.hasPrefix(root + "/"), let left = try? manager.contentsOfDirectory(atPath: folder.path), left.isEmpty {
                try manager.removeItem(at: folder)
                folder = folder.deletingLastPathComponent().standardizedFileURL
            }
        }
    }

    /// Puts the host back after a launcher stopped between `replace`'s two renames: `into` is
    /// missing and `<into>.old` is there. Every start checks the host put back all the same.
    public static func restore(_ into: URL) {
        let manager = FileManager.default
        let old = URL(fileURLWithPath: into.path + ".old")
        guard !manager.fileExists(atPath: into.path), manager.fileExists(atPath: old.path) else { return }
        // Left for the next look or install when it cannot be moved.
        try? manager.moveItem(at: old, to: into)
    }

    /// Puts `staging` in the place of `into` whole or not at all: `into` is first moved aside to
    /// `<into>.old`, then `staging` takes its place, and the old folder is removed afterwards. A
    /// launcher stopped between the two renames leaves only `<into>.old`, which `restore` puts back.
    private static func replace(_ into: URL, with staging: URL) throws {
        let manager = FileManager.default
        restore(into)
        let old = URL(fileURLWithPath: into.path + ".old")
        if manager.fileExists(atPath: old.path) {
            do {
                try manager.removeItem(at: old)
            } catch {
                throw RetroHostReleaseFailure("an older host is still in use; close it and try again")
            }
        }
        if manager.fileExists(atPath: into.path) {
            do {
                try manager.moveItem(at: into, to: old)
            } catch {
                throw RetroHostReleaseFailure("the host is in use; close it and try again")
            }
        }
        do {
            try manager.moveItem(at: staging, to: into)
        } catch {
            if manager.fileExists(atPath: old.path) { try? manager.moveItem(at: old, to: into) }
            throw RetroHostReleaseFailure("the new host could not be put in place")
        }
        // Removed by the next install when it cannot be now.
        if manager.fileExists(atPath: old.path) { try? manager.removeItem(at: old) }
    }

    /// The signature of a release and the names it gives this `system`'s files: `sums`
    /// (SHA256SUMS) and `signature` (SHA256SUMS.sig) as downloaded from the release tagged `tag`,
    /// whose version must be the signed one (`checkTag`). The first check on download, before
    /// anything else of the release is fetched.
    public static func signed(sums: Data, signature: Data, tag: String, keys: [ReleaseSigning.Key]? = nil,
                              system: RetroHostSystem? = nil, minimum: RetroHostVersion = minimumVersion) throws -> RetroHostSignedRelease {
        let checked = try verify(sums, signature, keys)
        let release = try releaseOf(checked, try system ?? currentSystem(), minimum)
        try checkTag(tag, release.version)
        return RetroHostSignedRelease(version: release.version, zipName: release.zipName, filesName: release.filesName, sums: checked,
                                      cores: release.cores)
    }

    /// The release of the host installed in `folder`, from the SHA256SUMS, its signature and the tag
    /// kept beside it, checked as `signed` checks a download: the digests a core package added to it
    /// must match (`addCore`).
    public static func installedRelease(_ folder: URL, keys: [ReleaseSigning.Key]? = nil, system: RetroHostSystem? = nil,
                                        minimum: RetroHostVersion = minimumVersion) throws -> RetroHostSignedRelease {
        try signed(sums: try readSmall(folder.appendingPathComponent(ReleaseSigning.sumsName)),
                   signature: try readSmall(folder.appendingPathComponent(ReleaseSigning.signatureName)),
                   tag: try readTag(folder), keys: keys, system: system, minimum: minimum)
    }

    /// The version of the host in `folder` as its SHA256SUMS names it, read without any check, for
    /// showing; nil when the folder holds no host release for `system`. Before a start
    /// `checkBeforeStart` checks it.
    public static func installedVersion(_ folder: URL, system: RetroHostSystem? = RetroHostSystem.current) -> RetroHostVersion? {
        installedFiles(folder, system).flatMap { RetroHostVersion($0.version) }
    }

    /// Whether the installed LRPS2 package's `.files` lists LRPS2, as `checkBeforeStart` decides it:
    /// a `pcsx2_libretro` file in `folder` that no installed `.files` lists is not the release's
    /// LRPS2, nor is one the host package lists. Not checked: a listed LRPS2 is checked before each
    /// start.
    public static func installedHasPs2Core(_ folder: URL, system: RetroHostSystem? = RetroHostSystem.current) -> Bool {
        guard let target = system, let listing = installedCoreFiles(folder, target, .lrps2),
              let bytes = try? Data(contentsOf: listing), let files = try? parseFileList(bytes) else { return false }
        return files[target.ps2Core] != nil
    }

    /// The core packages installed beside the host in `folder`: those whose `.files`, named for the
    /// installed host's version, is there and listed in its SHA256SUMS, as `checkBeforeStart` finds
    /// them. Not checked.
    public static func installedCores(_ folder: URL, system: RetroHostSystem? = RetroHostSystem.current) -> Set<RetroHostCorePackage> {
        guard let target = system else { return [] }
        return Set(RetroHostCorePackage.allCases.filter { installedCoreFiles(folder, target, $0) != nil })
    }

    /// The core packages the installed host's release has for `system`, whether installed or not:
    /// both the zip and the `.files` of each, named for the installed host's version, are in the
    /// SHA256SUMS kept beside it. Empty for a release from before LRPS2 shipped, such as 1.0.0. Not
    /// checked: adding one checks the sums again (`addCore`).
    public static func offeredCores(_ folder: URL, system: RetroHostSystem? = RetroHostSystem.current) -> Set<RetroHostCorePackage> {
        guard let target = system, let version = installedVersion(folder, system: target),
              let sums = try? Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.sumsName)),
              let digests = try? ReleaseSigning.parseSums(sums) else { return [] }
        return Set(RetroHostCorePackage.allCases.filter {
            digests[$0.filesName(version, target)] != nil && digests[$0.zipName(version, target)] != nil
        })
    }

    /// `core`'s `.files` beside the installed host in `folder`, named for its version and listed in
    /// its SHA256SUMS; nil when it is not there. Not checked.
    private static func installedCoreFiles(_ folder: URL, _ target: RetroHostSystem, _ core: RetroHostCorePackage) -> URL? {
        guard let version = installedVersion(folder, system: target),
              let sums = try? Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.sumsName)),
              let digests = try? ReleaseSigning.parseSums(sums) else { return nil }
        let name = core.filesName(version, target)
        let file = folder.appendingPathComponent(name)
        return digests[name] != nil && GameLibrary.isFile(file.path) ? file : nil
    }

    /// The installed release's `.files` for `target` that SHA256SUMS lists, and the version its
    /// name gives; nil when there is none. Not checked.
    private static func installedFiles(_ folder: URL, _ target: RetroHostSystem?) -> (name: String, version: String)? {
        guard let target, let sums = try? Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.sumsName)),
              let digests = try? ReleaseSigning.parseSums(sums) else { return nil }
        for name in digests.keys.sorted() {
            if let match = releaseName(name), match.system == target.name, match.kind == "files",
               GameLibrary.isFile(folder.appendingPathComponent(name).path) {
                return (name, match.version)
            }
        }
        return nil
    }

    /// A `.files` list: `<64 hex digits>  <name>` a line, as shasum writes it, with `/` between
    /// directories. The names follow the host's `package_release.py --check`: each part is letters,
    /// digits and `._+-`, does not start or end with a dot and is no Windows device name, and no
    /// two names differ only in case, nor is one name a file and a folder of another; so no file
    /// unpacks outside its folder, or over another, on any system.
    public static func parseFileList(_ bytes: Data) throws -> [String: String] {
        guard let text = String(data: bytes, encoding: .utf8) else { throw RetroHostReleaseFailure("the file list cannot be read") }
        var files: [String: String] = [:]
        var seenFiles = Set<String>()
        var seenFolders = Set<String>()
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw[...]
            if line.isEmpty { continue }
            let digest = line.prefix(64)
            guard line.count > 66, digest.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }),
                  line.dropFirst(64).hasPrefix("  ") else {
                throw RetroHostReleaseFailure("the file list has a line it cannot read")
            }
            let name = String(line.dropFirst(66))
            let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.allSatisfy({ memberPart($0) && !deviceName($0) }) else {
                throw RetroHostReleaseFailure("the file list names a file it cannot")
            }
            let key = name.lowercased()
            let folders = (1..<max(1, parts.count)).map { parts.prefix($0).joined(separator: "/").lowercased() }
            if seenFiles.contains(key) || seenFolders.contains(key) || folders.contains(where: seenFiles.contains) {
                throw RetroHostReleaseFailure("the file list names \(name) twice, or as a file and a folder, ignoring case")
            }
            seenFiles.insert(key)
            seenFolders.formUnion(folders)
            files[name] = String(digest)
        }
        guard !files.isEmpty else { throw RetroHostReleaseFailure("the file list lists no file") }
        return files
    }

    /// One part of a name: letters, digits and `._+-`, not starting or ending with a dot.
    static func memberPart(_ part: String) -> Bool {
        func allowed(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "+" || c == "-") }
        guard let first = part.first, let last = part.last, allowed(first), allowed(last) else { return false }
        return part.allSatisfy { allowed($0) || $0 == "." }
    }

    /// `con`, `prn`, `aux`, `nul`, `com0`-`com9` and `lpt0`-`lpt9`, with or without an extension,
    /// in any case.
    static func deviceName(_ part: String) -> Bool {
        let stem = part.lowercased().split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if ["con", "prn", "aux", "nul"].contains(stem) { return true }
        guard stem.count == 4, stem.hasPrefix("com") || stem.hasPrefix("lpt"), let digit = stem.last else { return false }
        return ("0"..."9").contains(digit)
    }

    /// `anyps5-retro-host-<version>-<os>-<arch>.<zip or files>`: its version, system and kind.
    static func releaseName(_ name: String) -> (version: String, system: String, kind: String)? {
        let prefix = "anyps5-retro-host-"
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard let dot = rest.lastIndex(of: ".") else { return nil }
        let kind = String(rest[rest.index(after: dot)...])
        guard kind == "zip" || kind == "files" else { return nil }
        let parts = rest[..<dot].split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }),
              parts[1].allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }),
              parts[2].allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) else { return nil }
        return (String(parts[0]), "\(parts[1])-\(parts[2])", kind)
    }

    private static func releaseOf(_ sums: ReleaseSigning.Sums, _ system: RetroHostSystem, _ minimum: RetroHostVersion) throws
        -> (version: RetroHostVersion, zipName: String, filesName: String, cores: Set<RetroHostCorePackage>) {
        let listed = sums.digests.keys.filter { name in
            guard let match = releaseName(name) else { return false }
            return match.system == system.name && match.kind == "files"
        }
        guard let filesName = listed.first else {
            throw RetroHostReleaseFailure("the release has no host for \(system.name)", notReleased: true)
        }
        guard listed.count == 1 else { throw RetroHostReleaseFailure("the release lists more than one host for \(system.name)") }
        let versionText = releaseName(filesName)?.version ?? ""
        guard let version = RetroHostVersion(versionText) else {
            throw RetroHostReleaseFailure("the host version \(versionText) cannot be read")
        }
        guard version >= minimum else {
            throw RetroHostReleaseFailure("the host \(version) is older than \(minimum), the oldest this launcher runs")
        }
        var cores = Set<RetroHostCorePackage>()
        for core in RetroHostCorePackage.allCases {
            let zip = sums.digests[core.zipName(version, system)] != nil
            let files = sums.digests[core.filesName(version, system)] != nil
            guard zip == files else { throw RetroHostReleaseFailure("the release lists only half of the \(core.name) package") }
            if zip { cores.insert(core) }
        }
        return (version, "anyps5-retro-host-\(versionText)-\(system.name).zip", filesName, cores)
    }

    /// The `.files` `name` in `folder`, read and held to its digest in `sums`, as a file list.
    private static func signedList(_ folder: URL, _ name: String, _ sums: ReleaseSigning.Sums) throws -> [String: String] {
        let listing = try readSmall(folder.appendingPathComponent(name))
        guard sha256(listing) == sums.digest(for: name) else { throw RetroHostReleaseFailure("\(name) does not match the signed release") }
        return try parseFileList(listing)
    }

    /// One package of a release in `folder`, checked as on download: its `.files` `filesName` and
    /// zip `zipName` against `sums`, and `required` listed in it. Every file of the zip is checked
    /// against the `.files` as it is unpacked (`unpack`).
    private static func checkedPackage(_ folder: URL, _ filesName: String, _ zipName: String, _ sums: ReleaseSigning.Sums,
                                       required: [String]) throws -> RetroHostPackage {
        let listing = try readSmall(folder.appendingPathComponent(filesName))
        guard sha256(listing) == sums.digest(for: filesName) else {
            throw RetroHostReleaseFailure("\(filesName) does not match the signed release")
        }
        let zip = folder.appendingPathComponent(zipName)
        guard GameLibrary.isFile(zip.path) else { throw RetroHostReleaseFailure("\(zipName) is missing") }
        guard (try? FileDigest.sha256(zip)) == sums.digest(for: zipName) else {
            throw RetroHostReleaseFailure("\(zipName) does not match the signed release")
        }
        let files = try parseFileList(listing)
        for name in required where files[name] == nil {
            throw RetroHostReleaseFailure("\(filesName) does not list \(name)")
        }
        return RetroHostPackage(filesName: filesName, listing: listing, files: files, zip: zip, zipName: zipName)
    }

    /// Refuses `package` when one of its names is a name, or a folder, of one of `others`, ignoring
    /// case, as the host's `package_release.py --check` does across the packages of one system: they
    /// all unpack into one folder, so none may write over another's file.
    private static func checkApart(_ others: [[String: String]], _ package: RetroHostPackage) throws {
        let lines = (others + [package.files]).flatMap { list in list.map { "\($0.value)  \($0.key)\n" } }
        do {
            _ = try parseFileList(Data(lines.joined().utf8))
        } catch let failure as RetroHostReleaseFailure {
            throw RetroHostReleaseFailure("\(package.filesName) shares a name with an installed package: \(failure.message)")
        }
    }

    /// Writes `package`'s `.files` into `folder`: to `<name>.part` first, then renamed, so a
    /// launcher stopped while it writes leaves either the whole `.files` or none, and the package is
    /// installed completely or not at all.
    private static func writeList(_ package: RetroHostPackage, into folder: URL) throws {
        let part = folder.appendingPathComponent(package.filesName + ".part")
        let final = folder.appendingPathComponent(package.filesName)
        try package.listing.write(to: part)
        if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
        try FileManager.default.moveItem(at: part, to: final)
    }

    private static func verify(_ sums: Data, _ signature: Data, _ keys: [ReleaseSigning.Key]?) throws -> ReleaseSigning.Sums {
        do {
            return try ReleaseSigning.verify(sums: sums, signature: signature, keys: keys ?? ReleaseSigning.trustedKeys)
        } catch let failure as ReleaseSigning.Failure {
            throw RetroHostReleaseFailure(failure.description)
        }
    }

    private static func readSmall(_ file: URL) throws -> Data {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue
        guard let size, GameLibrary.isFile(file.path), let data = try? Data(contentsOf: file) else {
            throw RetroHostReleaseFailure("\(file.lastPathComponent) is missing")
        }
        guard size <= ReleaseSigning.largestFile, data.count <= ReleaseSigning.largestFile else {
            throw RetroHostReleaseFailure("\(file.lastPathComponent) is too large")
        }
        return data
    }

    private static func readTag(_ folder: URL) throws -> String {
        guard let tag = String(data: try readSmall(folder.appendingPathComponent(tagName)), encoding: .utf8) else {
            throw RetroHostReleaseFailure("the release tag beside the host cannot be read")
        }
        return tag
    }

    static func sha256(_ data: Data) -> String { FileDigest.hex(SHA256.hash(data: data)) }

    private static func currentSystem() throws -> RetroHostSystem {
        guard let system = RetroHostSystem.current else { throw RetroHostReleaseFailure("no emulator host is released for this system") }
        return system
    }
}
