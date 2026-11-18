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

/// One system a host release is built for: `<os>-<arch>` in its file names, and the names of the
/// host, of SwanStation and of LRPS2 inside its zip, as the host repository's
/// tools/package_release.py (`SYSTEMS`) packs them. A release whose LRPS2 is named otherwise is
/// taken for one without LRPS2.
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
    /// The LRPS2 library the release ships, checked with the others, or nil when its `.files` lists
    /// none: a release without PS2.
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
/// it: `zipName` and `filesName`, with their digests in `sums`.
public struct RetroHostSignedRelease: Sendable {
    public let version: RetroHostVersion
    public let zipName: String
    public let filesName: String
    public let sums: ReleaseSigning.Sums
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
    /// version, the `.files` against SHA256SUMS, and the host executable, SwanStation and, when the
    /// `.files` lists it, LRPS2 against the `.files`, each hashed from a `RetroCheckedFile`. The
    /// host's file stays held in the result; the cores are checked by path, as macOS checks their
    /// code signature when the host loads them.
    public static func checkBeforeStart(_ folder: URL, keys: [ReleaseSigning.Key]? = nil, system: RetroHostSystem? = nil,
                                        minimum: RetroHostVersion = minimumVersion) async throws -> RetroHostChecked {
        let target = try system ?? currentSystem()
        let sums = try verify(try readSmall(folder.appendingPathComponent(ReleaseSigning.sumsName)),
                              try readSmall(folder.appendingPathComponent(ReleaseSigning.signatureName)), keys)
        let release = try releaseOf(sums, target, minimum)
        try checkTag(try readTag(folder), release.version)
        let listing = try readSmall(folder.appendingPathComponent(release.filesName))
        guard sha256(listing) == sums.digest(for: release.filesName) else {
            throw RetroHostReleaseFailure("\(release.filesName) does not match the signed release")
        }
        let files = try parseFileList(listing)
        let ps2 = files[target.ps2Core] != nil
        var held: [RetroCheckedFile] = []
        do {
            for name in [target.executable, target.core] + (ps2 ? [target.ps2Core] : []) {
                guard let expected = files[name] else {
                    throw RetroHostReleaseFailure("\(release.filesName) does not list \(name)", file: name)
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
    /// with SHA256SUMS, SHA256SUMS.sig, the `.files` and the tag (`tagName`) beside it. The new host
    /// is written into `<into>.new` first, and only the two renames that put it in place touch the
    /// old one. Gives the version installed.
    public static func install(_ download: URL, into: URL, tag: String, keys: [ReleaseSigning.Key]? = nil,
                               system: RetroHostSystem? = nil, minimum: RetroHostVersion = minimumVersion) async throws -> RetroHostVersion {
        let target = try system ?? currentSystem()
        let staging = URL(fileURLWithPath: into.path + ".new")
        let version = try stage(download, staging, tag: tag, keys: keys, system: target, minimum: minimum)
        do {
            try replace(into, with: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return version
    }

    private static func stage(_ download: URL, _ staging: URL, tag: String, keys: [ReleaseSigning.Key]?,
                              system: RetroHostSystem, minimum: RetroHostVersion) throws -> RetroHostVersion {
        let sumsBytes = try readSmall(download.appendingPathComponent(ReleaseSigning.sumsName))
        let signatureBytes = try readSmall(download.appendingPathComponent(ReleaseSigning.signatureName))
        let release = try signed(sums: sumsBytes, signature: signatureBytes, tag: tag, keys: keys, system: system, minimum: minimum)
        let listing = try readSmall(download.appendingPathComponent(release.filesName))
        guard sha256(listing) == release.sums.digest(for: release.filesName) else {
            throw RetroHostReleaseFailure("\(release.filesName) does not match the signed release")
        }
        let zip = download.appendingPathComponent(release.zipName)
        guard GameLibrary.isFile(zip.path) else { throw RetroHostReleaseFailure("\(release.zipName) is missing") }
        guard (try? FileDigest.sha256(zip)) == release.sums.digest(for: release.zipName) else {
            throw RetroHostReleaseFailure("\(release.zipName) does not match the signed release")
        }
        let files = try parseFileList(listing)
        for name in [system.executable, system.core] where files[name] == nil {
            throw RetroHostReleaseFailure("\(release.filesName) does not list \(name)")
        }
        let manager = FileManager.default
        if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try unpack(zip, files: files, zipName: release.zipName, into: staging)
            try sumsBytes.write(to: staging.appendingPathComponent(ReleaseSigning.sumsName))
            try signatureBytes.write(to: staging.appendingPathComponent(ReleaseSigning.signatureName))
            try listing.write(to: staging.appendingPathComponent(release.filesName))
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
        return RetroHostSignedRelease(version: release.version, zipName: release.zipName, filesName: release.filesName, sums: checked)
    }

    /// The version of the host in `folder` as its SHA256SUMS names it, read without any check, for
    /// showing; nil when the folder holds no host release for `system`. Before a start
    /// `checkBeforeStart` checks it.
    public static func installedVersion(_ folder: URL, system: RetroHostSystem? = RetroHostSystem.current) -> RetroHostVersion? {
        installedFiles(folder, system).flatMap { RetroHostVersion($0.version) }
    }

    /// Whether the installed release's `.files` lists LRPS2, as `checkBeforeStart` decides it: a
    /// `pcsx2_libretro` file in `folder` that the `.files` does not list is not the release's LRPS2.
    public static func installedHasPs2Core(_ folder: URL, system: RetroHostSystem? = RetroHostSystem.current) -> Bool {
        guard let target = system, let match = installedFiles(folder, target),
              let listing = try? Data(contentsOf: folder.appendingPathComponent(match.name)),
              let files = try? parseFileList(listing) else { return false }
        return files[target.ps2Core] != nil
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

    private static func releaseOf(_ sums: ReleaseSigning.Sums, _ system: RetroHostSystem,
                                  _ minimum: RetroHostVersion) throws -> (version: RetroHostVersion, zipName: String, filesName: String) {
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
        return (version, "anyps5-retro-host-\(versionText)-\(system.name).zip", filesName)
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
