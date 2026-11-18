import CryptoKit
import XCTest
@testable import AnyPS5Core

/// A host release as the host repository publishes it, recorded in Fixtures/RetroHostRelease (the
/// same files as AnyPS5 Desktop's test/fixtures/retro_host_release): each system's zip and `.files`
/// and the source archive, packed from small stand-in files by that repository's
/// tools/package_release.py, SHA256SUMS from its `--sums`, and SHA256SUMS.sig written by this
/// repository's tools/release/sign.sh with the throwaway key beside them (test-release-signing.key),
/// which no launcher trusts. Nothing in it is a program; nothing here runs it.
enum RetroHostReleaseFixture {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../Fixtures/RetroHostRelease").standardized
    static let version = "1.0.0"

    /// The fixture key's public half: the only key its release passes.
    static var keys: [ReleaseSigning.Key] {
        ReleaseSigning.keys(from: (try? String(contentsOf: folder.appendingPathComponent("test-release-signing.pub"), encoding: .utf8)) ?? "")
    }

    /// The throwaway key itself, to sign changed copies of the release: the last 32 bytes of its
    /// PKCS #8 form are the Ed25519 seed.
    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        let text = try String(contentsOf: folder.appendingPathComponent("test-release-signing.key"), encoding: .utf8)
        let body = text.components(separatedBy: "-----BEGIN PRIVATE KEY-----").last?
            .components(separatedBy: "-----END PRIVATE KEY-----").first?
            .filter { !$0.isWhitespace } ?? ""
        let der = try XCTUnwrap(Data(base64Encoded: body))
        return try Curve25519.Signing.PrivateKey(rawRepresentation: der.suffix(32))
    }

    /// SHA256SUMS.sig for `sums`, signed by the fixture key.
    static func signature(_ sums: Data) throws -> Data {
        let key = try privateKey()
        let id = ReleaseSigning.keyID(of: key.publicKey.rawRepresentation)
        return Data("ed25519 \(id) \(try key.signature(for: sums).base64EncodedString())\n".utf8)
    }

    /// SHA256SUMS of `files`, as shasum writes it.
    static func sums(_ files: [String: Data]) -> Data {
        Data(files.keys.sorted().map { "\(RetroHostRelease.sha256(files[$0]!))  \($0)\n" }.joined().utf8)
    }

    /// The release's files by name, as published: those SHA256SUMS lists, SHA256SUMS and its
    /// signature. With another `version`, the same files named for it and signed again by the
    /// fixture key, as the host repository would publish a newer release of them.
    static func files(version: String = version) throws -> [String: Data] {
        let sums = try Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.sumsName))
        var files: [String: Data] = [:]
        for name in try ReleaseSigning.parseSums(sums).keys {
            files[name.replacingOccurrences(of: "anyps5-retro-host-\(Self.version)-", with: "anyps5-retro-host-\(version)-")] =
                try Data(contentsOf: folder.appendingPathComponent(name))
        }
        let signedSums = version == Self.version ? sums : Self.sums(files)
        files[ReleaseSigning.sumsName] = signedSums
        files[ReleaseSigning.signatureName] = version == Self.version
            ? try Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.signatureName)) : try signature(signedSums)
        return files
    }

    /// Writes `files` into a new folder of `parent`.
    static func write(_ files: [String: Data], in parent: URL) throws -> URL {
        let folder = parent.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: folder.appendingPathComponent(name)) }
        return folder
    }
}

/// Finding and checking the emulator host, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_host_release_test.dart): the signed release installed, the checks
/// before a start, and every way a release or an installed host is refused.
final class RetroHostReleaseTests: XCTestCase {
    private var scratch: URL!
    private let mac = RetroHostSystem.macosArm64

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-release-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private var host: URL { scratch.appendingPathComponent("host") }

    @discardableResult
    private func install(_ download: URL = RetroHostReleaseFixture.folder, tag: String = "v1.0.0") async throws -> RetroHostVersion {
        try await RetroHostRelease.install(download, into: host, tag: tag, keys: RetroHostReleaseFixture.keys, system: mac)
    }

    private func check() async throws -> RetroHostChecked {
        try await RetroHostRelease.checkBeforeStart(host, keys: RetroHostReleaseFixture.keys, system: mac)
    }

    private func failure(_ body: () async throws -> Any) async -> RetroHostReleaseFailure? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error as? RetroHostReleaseFailure
        }
    }

    // MARK: Installing and checking

    func testTheSignedReleaseInstallsWithItsSumsSignatureListAndTagBesideIt() async throws {
        let version = try await install()
        XCTAssertEqual(version, RetroHostVersion(1, 0, 0))
        let manager = FileManager.default
        for name in ["anyps5-retro-host", "swanstation_libretro.dylib", "SOURCE.txt", "licenses/swanstation-dep/xxhash-LICENSE",
                     ReleaseSigning.sumsName, ReleaseSigning.signatureName, "anyps5-retro-host-1.0.0-macos-arm64.files"] {
            XCTAssertTrue(manager.fileExists(atPath: host.appendingPathComponent(name).path), name)
        }
        XCTAssertEqual(try String(contentsOf: host.appendingPathComponent(RetroHostRelease.tagName), encoding: .utf8), "v1.0.0")
        let mode = try manager.attributesOfItem(atPath: host.appendingPathComponent("anyps5-retro-host").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o755)
        XCTAssertFalse(manager.fileExists(atPath: host.path + ".new"))
        XCTAssertFalse(manager.fileExists(atPath: host.path + ".old"))
        XCTAssertFalse(manager.fileExists(atPath: host.appendingPathComponent("anyps5-retro-host.exe").path), "only this system's zip")
        XCTAssertEqual(RetroHostRelease.installedVersion(host, system: mac), RetroHostVersion(1, 0, 0))
        XCTAssertFalse(RetroHostRelease.installedHasPs2Core(host, system: mac), "this release ships no LRPS2")
    }

    func testTheCheckBeforeAStartHoldsTheHostForOneStart() async throws {
        try await install()
        let checked = try await check()
        XCTAssertEqual(checked.version, RetroHostVersion(1, 0, 0))
        XCTAssertEqual(checked.executable, host.appendingPathComponent("anyps5-retro-host").path)
        XCTAssertEqual(checked.core, host.appendingPathComponent("swanstation_libretro.dylib").path)
        XCTAssertNil(checked.ps2Core)
        XCTAssertEqual(checked.cores, [checked.core])
        XCTAssertTrue(checked.held)
        XCTAssertTrue(checked.claim())
        XCTAssertFalse(checked.claim(), "a check is good for one start")
        checked.release()
        XCTAssertFalse(checked.held)
        checked.release()
        let again = try await check()
        again.release()
        XCTAssertFalse(again.claim(), "a check let go cannot start a host")
    }

    func testAChangedHostOrCoreFailsItsCheckAndNamesTheFile() async throws {
        for name in ["anyps5-retro-host", "swanstation_libretro.dylib"] {
            try await install()
            try Data("changed".utf8).write(to: host.appendingPathComponent(name))
            let failed = await failure { try await self.check() }
            XCTAssertEqual(failed?.file, name)
            XCTAssertEqual(failed?.message, "\(name) does not match the signed release")
        }
        try await install()
        try FileManager.default.removeItem(at: host.appendingPathComponent("swanstation_libretro.dylib"))
        let missing = await failure { try await self.check() }
        XCTAssertEqual(missing?.message, "swanstation_libretro.dylib is missing or not a file")
        try await install()
        let core = host.appendingPathComponent("swanstation_libretro.dylib")
        try FileManager.default.removeItem(at: core)
        XCTAssertEqual(mkfifo(core.path, 0o600), 0)
        let fifo = await failure { try await self.check() }
        XCTAssertEqual(fifo?.file, "swanstation_libretro.dylib", "a FIFO in its place is refused at once, not read")
    }

    func testTheTagKeptBesideTheHostMustBeTheSignedVersion() async throws {
        try await install()
        try Data("v1.0.1".utf8).write(to: host.appendingPathComponent(RetroHostRelease.tagName))
        let other = await failure { try await self.check() }
        XCTAssertEqual(other?.message, "the release tagged v1.0.1 is signed as host 1.0.0")
        try FileManager.default.removeItem(at: host.appendingPathComponent(RetroHostRelease.tagName))
        let none = await failure { try await self.check() }
        XCTAssertEqual(none?.message, "\(RetroHostRelease.tagName) is missing")
    }

    func testAChangedFileListOrSignatureFails() async throws {
        try await install()
        let list = host.appendingPathComponent("anyps5-retro-host-1.0.0-macos-arm64.files")
        try (try Data(contentsOf: list) + Data("\n".utf8)).write(to: list)
        let changed = await failure { try await self.check() }
        XCTAssertEqual(changed?.message, "anyps5-retro-host-1.0.0-macos-arm64.files does not match the signed release")

        try await install()
        let builtIn = await failure { try await RetroHostRelease.checkBeforeStart(self.host, system: self.mac) }
        XCTAssertNotNil(builtIn, "the fixture key is no launcher's key")
        let sums = host.appendingPathComponent(ReleaseSigning.sumsName)
        try (try Data(contentsOf: sums) + Data("0000000000000000000000000000000000000000000000000000000000000000  extra\n".utf8)).write(to: sums)
        let forged = await failure { try await self.check() }
        XCTAssertEqual(forged?.message, "the release's signature does not match its SHA256SUMS")
    }

    func testAReleaseIsRefusedUnderAnotherTagOrBelowTheMinimum() async throws {
        let failed = await failure { try await self.install(tag: "v1.0.1") }
        XCTAssertEqual(failed?.message, "the release tagged v1.0.1 is signed as host 1.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: host.path), "nothing was put in place")

        let files = try RetroHostReleaseFixture.files()
        let old = await failure {
            try RetroHostRelease.signed(sums: files[ReleaseSigning.sumsName]!, signature: files[ReleaseSigning.signatureName]!, tag: "v1.0.0",
                                        keys: RetroHostReleaseFixture.keys, system: self.mac, minimum: RetroHostVersion(1, 0, 1))
        }
        XCTAssertEqual(old?.message, "the host 1.0.0 is older than 1.0.1, the oldest this launcher runs")

        let other = RetroHostSystem(name: "freebsd-x64", executable: "h", core: "c", ps2Core: "p")
        let notReleased = await failure {
            try RetroHostRelease.signed(sums: files[ReleaseSigning.sumsName]!, signature: files[ReleaseSigning.signatureName]!, tag: "v1.0.0",
                                        keys: RetroHostReleaseFixture.keys, system: other)
        }
        XCTAssertEqual(notReleased?.notReleased, true, "a signed release without this system is just not for it")
    }

    func testANewerReleaseReplacesTheInstalledHostWhole() async throws {
        try await install()
        let newer = try RetroHostReleaseFixture.write(try RetroHostReleaseFixture.files(version: "1.2.0"), in: scratch)
        let version = try await install(newer, tag: "v1.2.0")
        XCTAssertEqual(version, RetroHostVersion(1, 2, 0))
        XCTAssertEqual(RetroHostRelease.installedVersion(host, system: mac), RetroHostVersion(1, 2, 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: host.appendingPathComponent("anyps5-retro-host-1.0.0-macos-arm64.files").path))
        let checked = try await check()
        XCTAssertEqual(checked.version, RetroHostVersion(1, 2, 0))
        checked.release()
    }

    func testAHostLeftAsideBetweenTheTwoRenamesIsPutBack() async throws {
        try await install()
        try FileManager.default.moveItem(at: host, to: URL(fileURLWithPath: host.path + ".old"))
        let store = RetroHostStore(root: scratch, keys: RetroHostReleaseFixture.keys, system: mac)
        let installed = try XCTUnwrap(store.installed())
        XCTAssertTrue(installed.checked)
        XCTAssertEqual(installed.host, host.appendingPathComponent("anyps5-retro-host").path)
        XCTAssertNil(installed.ps2Core)
        XCTAssertEqual(store.version, RetroHostVersion(1, 0, 0))
        let checked = try await store.check()
        checked.release()
    }

    // MARK: What a release may hold

    /// The fixture's release for this system with its zip packed again from `members` (name and
    /// bytes, a link as `->target`), its `.files` from `listed`, signed again.
    private func repacked(members: [(String, String)], listed: [(String, String)]) throws -> URL {
        let tree = scratch.appendingPathComponent("tree-\(UUID().uuidString)")
        for (name, body) in members {
            let file = tree.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if body.hasPrefix("->") {
                try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: String(body.dropFirst(2)))
            } else {
                try Data(body.utf8).write(to: file)
            }
        }
        let zip = scratch.appendingPathComponent("anyps5-retro-host-1.0.0-macos-arm64.zip")
        try? FileManager.default.removeItem(at: zip)
        let pack = Process()
        pack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        pack.arguments = ["-c", "-k", "--norsrc", "--noextattr", tree.path, zip.path]
        try pack.run()
        pack.waitUntilExit()
        XCTAssertEqual(pack.terminationStatus, 0)
        let list = Data(listed.map { "\(RetroHostRelease.sha256(Data($0.1.utf8)))  \($0.0)\n" }.joined().utf8)
        let files = ["anyps5-retro-host-1.0.0-macos-arm64.zip": try Data(contentsOf: zip), "anyps5-retro-host-1.0.0-macos-arm64.files": list]
        let sums = RetroHostReleaseFixture.sums(files)
        return try RetroHostReleaseFixture.write(files.merging([ReleaseSigning.sumsName: sums,
                                                                ReleaseSigning.signatureName: try RetroHostReleaseFixture.signature(sums)]) { a, _ in a },
                                                 in: scratch)
    }

    func testAZipWithAnExtraMissingChangedOrLinkedFileIsRefused() async throws {
        let base = [("anyps5-retro-host", "host"), ("swanstation_libretro.dylib", "core")]
        let good = try repacked(members: base, listed: base)
        try await install(good)
        XCTAssertTrue(FileManager.default.fileExists(atPath: host.appendingPathComponent("anyps5-retro-host").path), "a repacked release passes")
        try FileManager.default.removeItem(at: host)

        let cases: [(members: [(String, String)], listed: [(String, String)], message: String)] = [
            (base + [("extra.txt", "x")], base, "anyps5-retro-host-1.0.0-macos-arm64.zip holds extra.txt, which its file list does not"),
            (base, base + [("licence.txt", "x")], "anyps5-retro-host-1.0.0-macos-arm64.zip does not hold licence.txt"),
            ([("anyps5-retro-host", "other"), ("swanstation_libretro.dylib", "core")], base,
             "anyps5-retro-host in anyps5-retro-host-1.0.0-macos-arm64.zip does not match its file list"),
            (base + [("link", "->anyps5-retro-host")], base + [("link", "anyps5-retro-host")],
             "anyps5-retro-host-1.0.0-macos-arm64.zip holds link, which its file list does not"),
            ([("swanstation_libretro.dylib", "core")], [("swanstation_libretro.dylib", "core")],
             "anyps5-retro-host-1.0.0-macos-arm64.files does not list anyps5-retro-host"),
        ]
        for item in cases {
            let release = try repacked(members: item.members, listed: item.listed)
            let failed = await failure { try await self.install(release) }
            XCTAssertEqual(failed?.message, item.message)
            XCTAssertFalse(FileManager.default.fileExists(atPath: host.path), "nothing was put in place: \(item.message)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: host.path + ".new"), "the half-written host is gone")
        }
    }

    func testTheFileListRefusesNamesThatCouldLeaveTheirFolder() throws {
        let digest = String(repeating: "a", count: 64)
        func list(_ names: String...) -> Data { Data(names.map { "\(digest)  \($0)\n" }.joined().utf8) }
        XCTAssertEqual(try RetroHostRelease.parseFileList(list("a/b.txt", "c-d_e+f.1")).keys.sorted(), ["a/b.txt", "c-d_e+f.1"])
        for bad in ["../x", "a/../b", ".hidden", "trailing.", "/root", "a//b", "con", "NUL.txt", "com1", "lpt9.log", "sp ace", "ü"] {
            XCTAssertThrowsError(try RetroHostRelease.parseFileList(list(bad)), bad)
        }
        XCTAssertThrowsError(try RetroHostRelease.parseFileList(list("Host", "host")), "names that differ only in case")
        XCTAssertThrowsError(try RetroHostRelease.parseFileList(list("a", "a/b")), "a file and a folder")
        XCTAssertThrowsError(try RetroHostRelease.parseFileList(list("a/b", "A")), "a folder and a file")
        XCTAssertThrowsError(try RetroHostRelease.parseFileList(Data("\(digest) one-space\n".utf8)))
        XCTAssertThrowsError(try RetroHostRelease.parseFileList(Data()))
        XCTAssertNotNil(try? RetroHostRelease.parseFileList(list("com10", "console", "lpt")), "only the device names themselves")
    }

    func testVersionsAreExactlyThreeNumbers() {
        XCTAssertEqual(RetroHostVersion("1.2.3"), RetroHostVersion(1, 2, 3))
        XCTAssertEqual(RetroHostVersion("0.0.0"), RetroHostVersion(0, 0, 0))
        for bad in ["1.2", "1.2.3.4", "01.2.3", "1.2.x", "", "1..3", "-1.2.3", "1234567890.0.0"] {
            XCTAssertNil(RetroHostVersion(bad), bad)
        }
        XCTAssertLessThan(RetroHostVersion(1, 9, 9), RetroHostVersion(1, 10, 0))
        XCTAssertEqual(RetroHostSystem.macosArm64.core, "swanstation_libretro.dylib")
    }

    // MARK: The unchecked host of a debug build

    func testADebugBuildFindsTheNamedHostWithSwanStationBesideIt() throws {
        let program = scratch.appendingPathComponent("anyps5-retro-host")
        try Data("#!/bin/sh\n".utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        let environment = [RetroHostInstall.variable: program.path]
        XCTAssertNil(RetroHostInstall.locate(environment: environment), "no SwanStation beside it")
        try Data().write(to: scratch.appendingPathComponent("swanstation_libretro.dylib"))
        let found = try XCTUnwrap(RetroHostInstall.locate(environment: environment), "swift test is a debug build")
        XCTAssertEqual(found, RetroHostInstall(host: program.path, core: scratch.appendingPathComponent("swanstation_libretro.dylib").path))
        XCTAssertFalse(found.checked)
        try Data().write(to: scratch.appendingPathComponent("pcsx2_libretro.dylib"))
        XCTAssertEqual(RetroHostInstall.locate(environment: environment)?.ps2Core, scratch.appendingPathComponent("pcsx2_libretro.dylib").path)
        XCTAssertNil(RetroHostInstall.locate(environment: [:]))
    }
}
