import XCTest
@testable import AnyPS5Core

/// The LRPS2 package, a core package of its own beside the host package (anyps5-retro-host
/// protocol.md "Finding and checking the host"), as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_host_core_package_test.dart), against the release in
/// Fixtures/RetroHostReleaseLrps2, packed by host PR #22's tools/package_release.py and signed with
/// the fixture's throwaway key: added from the installed host's release, checked with the host
/// before every start, moved with the host on an update, gone with a release that lacks it, and
/// removed again. The 1.0.0 release in Fixtures/RetroHostRelease has no core package and offers
/// none.
final class RetroHostCorePackageTests: XCTestCase {
    private let system = RetroHostSystem.macosArm64
    private let keys = RetroHostReleaseFixture.keys
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-core-package-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        RetroHostFakeGitHub.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        RetroHostFakeGitHub.reset()
    }

    private var installed: URL { scratch.appendingPathComponent("RetroHost/host") }
    private var listingName: String { "anyps5-retro-host-1.1.0-macos-arm64-lrps2.files" }

    private func inHost(_ name: String) -> URL { installed.appendingPathComponent(name) }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: inHost(name).path) }

    private func installHost(addPs2: Bool = false) async throws {
        try await RetroHostReleaseFixture.installLrps2(into: installed, system: system, addPs2: addPs2)
    }

    private func addPs2(_ from: URL = RetroHostReleaseFixture.lrps2Folder) async throws {
        try await RetroHostRelease.addCore(from, into: installed, .lrps2, keys: keys, system: system)
    }

    private func check() async throws -> RetroHostChecked {
        try await RetroHostRelease.checkBeforeStart(installed, keys: keys, system: system)
    }

    private func failure(_ body: () async throws -> Void) async -> String? {
        do {
            try await body()
            return nil
        } catch let error as RetroHostReleaseFailure {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    private func installedCores() -> Set<RetroHostCorePackage> { RetroHostRelease.installedCores(installed, system: system) }
    private func offeredCores() -> Set<RetroHostCorePackage> { RetroHostRelease.offeredCores(installed, system: system) }

    func testTheRecordedReleaseIsThePackersEachSystemsTwoPackagesUnderOneSignedSums() throws {
        let folder = RetroHostReleaseFixture.lrps2Folder
        let sums = try Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.sumsName))
        let listed = Set(try ReleaseSigning.parseSums(sums).keys)
        for name in ["windows-x64", "linux-x64", "macos-arm64"] {
            for ending in [".zip", ".files", "-lrps2.zip", "-lrps2.files"] {
                XCTAssertTrue(listed.contains("anyps5-retro-host-1.1.0-\(name)\(ending)"), "\(name)\(ending)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.signatureName)), try RetroHostReleaseFixture.signature(sums))
        let host = try RetroHostRelease.parseFileList(try Data(contentsOf: folder.appendingPathComponent("anyps5-retro-host-1.1.0-macos-arm64.files")))
        XCTAssertNil(host[system.ps2Core], "LRPS2 is not in the host package")
        let package = try RetroHostRelease.parseFileList(try Data(contentsOf: folder.appendingPathComponent(listingName)))
        XCTAssertEqual(Set(package.keys), ["SOURCE-lrps2.txt", "licenses/lrps2-GPL-3.0.txt", system.ps2Core])
    }

    func testAHostInstalledAloneOffersLrps2ButHasNoneAndIsCheckedWithoutIt() async throws {
        try await installHost()
        XCTAssertEqual(offeredCores(), [.lrps2])
        XCTAssertEqual(installedCores(), [])
        XCTAssertFalse(RetroHostRelease.installedHasPs2Core(installed, system: system))
        XCTAssertFalse(exists(system.ps2Core), "never downloaded unasked")
        let checked = try await check()
        defer { checked.release() }
        XCTAssertNil(checked.ps2Core)
    }

    func testThe100ReleaseFromBeforeLrps2ShippedOffersNoCorePackage() async throws {
        _ = try await RetroHostRelease.install(RetroHostReleaseFixture.folder, into: installed, tag: "v1.0.0", keys: keys, system: system)
        XCTAssertEqual(offeredCores(), [])
        let message = await failure { try await self.addPs2() }
        XCTAssertEqual(message, "the installed host 1.0.0 has no lrps2 package")
        XCTAssertEqual(installedCores(), [])
    }

    func testLrps2AddedFromTheReleaseIsCheckedWithTheHostBeforeEveryStart() async throws {
        try await installHost()
        try await addPs2()
        XCTAssertEqual(installedCores(), [.lrps2])
        XCTAssertTrue(RetroHostRelease.installedHasPs2Core(installed, system: system))
        for name in ["SOURCE-lrps2.txt", "licenses/lrps2-GPL-3.0.txt", system.ps2Core] {
            XCTAssertTrue(exists(name), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".lrps2.new"), "its staging folder is gone")
        let checked = try await check()
        defer { checked.release() }
        XCTAssertEqual(checked.ps2Core, inHost(system.ps2Core).path)
        XCTAssertEqual(checked.cores, [checked.core, inHost(system.ps2Core).path])
    }

    func testAChangedLrps2OrAChangedLrps2FilesFailsTheCheckForAnyGame() async throws {
        try await installHost(addPs2: true)
        try Data("changed".utf8).write(to: inHost(system.ps2Core))
        do {
            try await check().release()
            XCTFail("a changed LRPS2 passed the check")
        } catch let error as RetroHostReleaseFailure {
            XCTAssertEqual(error.file, system.ps2Core)
        }

        try await installHost(addPs2: true)
        try Data("\(RetroHostRelease.sha256(Data("x".utf8)))  \(system.ps2Core)\n".utf8).write(to: inHost(listingName))
        let message = await failure { try await self.check().release() }
        XCTAssertEqual(message, "\(listingName) does not match the signed release")
    }

    func testAPcsx2LibretroNoInstalledFilesListsIsNeverGivenToTheHost() async throws {
        try await installHost()
        try Data("not the release's LRPS2".utf8).write(to: inHost(system.ps2Core))
        XCTAssertFalse(RetroHostRelease.installedHasPs2Core(installed, system: system))
        let checked = try await check()
        defer { checked.release() }
        XCTAssertNil(checked.ps2Core)
    }

    func testAPackageThatIsNotTheInstalledReleasesIsRefusedAndNothingIsAdded() async throws {
        try await installHost()
        let zipName = "anyps5-retro-host-1.1.0-macos-arm64-lrps2.zip"
        var changed = try RetroHostReleaseFixture.files(ps2: true)
        var zip = try XCTUnwrap(changed[zipName])
        zip[zip.count - 1] ^= 1
        changed[zipName] = zip
        let changedFolder = try RetroHostReleaseFixture.write(changed, in: scratch)
        var message = await failure { try await self.addPs2(changedFolder) }
        XCTAssertEqual(message, "\(zipName) does not match the signed release")

        let newer = try RetroHostReleaseFixture.write(try RetroHostReleaseFixture.files(version: "1.1.1", ps2: true), in: scratch)
        message = await failure { try await self.addPs2(newer) }
        XCTAssertTrue(message?.contains("is missing") == true, "named for another release: \(message ?? "")")

        let release = try RetroHostReleaseFixture.files(ps2: true)
        var other: [String: Data] = [:]
        for ending in ["-lrps2.files", "-lrps2.zip"] {
            other["anyps5-retro-host-1.1.0-macos-arm64\(ending)"] = release["anyps5-retro-host-1.1.0-linux-x64\(ending)"]
        }
        let otherFolder = try RetroHostReleaseFixture.write(other, in: scratch)
        message = await failure { try await self.addPs2(otherFolder) }
        XCTAssertTrue(message?.contains("does not match the signed release") == true,
                      "another package's bytes under this package's names: \(message ?? "")")
        XCTAssertEqual(installedCores(), [])
        XCTAssertFalse(exists(system.ps2Core))
    }

    func testAPackageWithANameOfTheHostPackageIsRefusedBeforeAnythingIsWritten() async throws {
        var files = try RetroHostReleaseFixture.files(ps2: true)
        let stem = "anyps5-retro-host-1.1.0-macos-arm64-lrps2"
        let contents = [system.ps2Core: "lrps2 stand-in\n", "source.txt": "over the host\n"]
        let tree = scratch.appendingPathComponent("clash-tree")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        for (name, body) in contents { try Data(body.utf8).write(to: tree.appendingPathComponent(name)) }
        let zip = scratch.appendingPathComponent("\(stem).zip")
        let pack = Process()
        pack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        pack.arguments = ["-c", "-k", "--norsrc", "--noextattr", tree.path, zip.path]
        try pack.run()
        pack.waitUntilExit()
        XCTAssertEqual(pack.terminationStatus, 0)
        files["\(stem).zip"] = try Data(contentsOf: zip)
        files["\(stem).files"] = Data(contents.keys.sorted().map { "\(RetroHostRelease.sha256(Data(contents[$0]!.utf8)))  \($0)\n" }.joined().utf8)
        let signedFiles = files.filter { $0.key.hasPrefix("anyps5-retro-host-") }
        let sums = RetroHostReleaseFixture.sums(signedFiles)
        let release = try RetroHostReleaseFixture.write(signedFiles.merging([ReleaseSigning.sumsName: sums,
                                                                             ReleaseSigning.signatureName: try RetroHostReleaseFixture.signature(sums)]) { a, _ in a },
                                                       in: scratch)
        _ = try await RetroHostRelease.install(release, into: installed, tag: "v1.1.0", keys: keys, system: system)
        let message = await failure { try await self.addPs2(release) }
        XCTAssertTrue(message?.contains("shares a name with an installed package") == true, message ?? "")
        XCTAssertFalse(exists(system.ps2Core))
        XCTAssertFalse(try String(contentsOf: inHost("SOURCE.txt"), encoding: .utf8).contains("over the host"))
    }

    func testAFilesCutShortWhileItWasWrittenIsNotInstalledAndTheNextAddWritesItWhole() async throws {
        try await installHost()
        let whole = try Data(contentsOf: RetroHostReleaseFixture.lrps2Folder.appendingPathComponent(listingName))
        try whole.prefix(whole.count / 2).write(to: inHost(listingName + ".part"))
        XCTAssertEqual(installedCores(), [])
        try await addPs2()
        XCTAssertEqual(try Data(contentsOf: inHost(listingName)), whole)
        XCTAssertFalse(exists(listingName + ".part"))
        XCTAssertEqual(installedCores(), [.lrps2])
    }

    func testRemovingLrps2DeletesItsFilesAndLeavesTheHostWhole() async throws {
        try await installHost(addPs2: true)
        try RetroHostRelease.removeCore(installed, .lrps2, keys: keys, system: system)
        XCTAssertEqual(installedCores(), [])
        for name in ["SOURCE-lrps2.txt", "licenses/lrps2-GPL-3.0.txt", system.ps2Core, listingName] {
            XCTAssertFalse(exists(name), name)
        }
        XCTAssertTrue(exists("licenses/swanstation-GPL-3.0.txt"))
        let checked = try await check()
        defer { checked.release() }
        XCTAssertNil(checked.ps2Core)
        try RetroHostRelease.removeCore(installed, .lrps2, keys: keys, system: system)
    }

    // MARK: A host update

    func testAHostUpdateInstallsTheLrps2ItHadFromTheNewReleaseInTheSameStep() async throws {
        try await installHost(addPs2: true)
        let newer = try RetroHostReleaseFixture.write(try RetroHostReleaseFixture.files(version: "1.1.1", ps2: true), in: scratch)
        _ = try await RetroHostRelease.install(newer, into: installed, tag: "v1.1.1", keys: keys, system: system, cores: [.lrps2])
        XCTAssertEqual(RetroHostRelease.installedVersion(installed, system: system), RetroHostVersion(1, 1, 1))
        XCTAssertEqual(installedCores(), [.lrps2])
        XCTAssertTrue(exists("anyps5-retro-host-1.1.1-macos-arm64-lrps2.files"))
        XCTAssertFalse(exists(listingName))
        let checked = try await check()
        defer { checked.release() }
        XCTAssertEqual(checked.ps2Core, inHost(system.ps2Core).path)
    }

    func testAHostUpdateToAReleaseWithoutLrps2RemovesIt() async throws {
        try await installHost(addPs2: true)
        let newer = try RetroHostReleaseFixture.write(try RetroHostReleaseFixture.files(version: "1.2.0"), in: scratch)
        _ = try await RetroHostRelease.install(newer, into: installed, tag: "v1.2.0", keys: keys, system: system, cores: [.lrps2])
        XCTAssertEqual(installedCores(), [])
        XCTAssertEqual(offeredCores(), [])
        XCTAssertFalse(exists(system.ps2Core))
    }

    func testAHostUpdateOfAHostWithoutLrps2DoesNotAddIt() async throws {
        try await installHost()
        let newer = try RetroHostReleaseFixture.write(try RetroHostReleaseFixture.files(version: "1.1.1", ps2: true), in: scratch)
        _ = try await RetroHostRelease.install(newer, into: installed, tag: "v1.1.1", keys: keys, system: system)
        XCTAssertEqual(installedCores(), [])
        XCTAssertEqual(offeredCores(), [.lrps2])
    }

    // MARK: From GitHub

    private func store() -> RetroHostStore {
        RetroHostStore(root: scratch.appendingPathComponent("RetroHost"), keys: keys, system: system)
    }

    private func releases() async throws -> [RetroHostUpstreamRelease] {
        try await RetroHostStore.releases(session: URLSession(configuration: RetroHostFakeGitHub.configuration),
                                          api: URL(string: "https://api.github.example")!)
    }

    private func fetchedSince(_ seen: Int) -> [String] {
        RetroHostFakeGitHub.requests.dropFirst(seen).map { URL(string: $0)?.lastPathComponent ?? $0 }
    }

    func testTheHostAloneIsFetchedThenLrps2OnlyForThisSystemAgainstTheKeptSums() async throws {
        var published = [RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(ps2: true), tag: "v1.1.0")]
        RetroHostFakeGitHub.list(published)
        let host = store()
        let configuration = RetroHostFakeGitHub.configuration
        _ = try await host.putInPlace(try await host.fetch(RetroHostStore.newest(try await releases()), configuration: configuration))
        XCTAssertTrue(fetchedSince(0).filter { $0.contains("lrps2") }.isEmpty)
        XCTAssertEqual(host.offeredCores, [.lrps2])

        var seen = RetroHostFakeGitHub.requests.count
        let release = try await releases().first
        try await host.putCoreInPlace(try await host.fetchCore(release, .lrps2, configuration: configuration), .lrps2)
        XCTAssertEqual(Set(fetchedSince(seen).filter { $0.hasPrefix("anyps5-") }),
                       ["anyps5-retro-host-1.1.0-macos-arm64-lrps2.files", "anyps5-retro-host-1.1.0-macos-arm64-lrps2.zip"])
        XCTAssertEqual(host.installedCores, [.lrps2])
        XCTAssertEqual(host.installed()?.ps2Core, inHost(system.ps2Core).path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("RetroHost/.downloads/v1.1.0-lrps2").path))

        published.insert(RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(version: "1.1.1", ps2: true), tag: "v1.1.1"), at: 0)
        RetroHostFakeGitHub.list(published)
        seen = RetroHostFakeGitHub.requests.count
        let update = try await host.fetch(RetroHostStore.newest(try await releases()), cores: host.installedCores, configuration: configuration)
        XCTAssertTrue(fetchedSince(seen).contains("anyps5-retro-host-1.1.1-macos-arm64-lrps2.zip"))
        _ = try await host.putInPlace(update, cores: host.installedCores)
        XCTAssertEqual(host.version, RetroHostVersion(1, 1, 1))
        XCTAssertEqual(host.installedCores, [.lrps2])

        try host.removeCore(.lrps2)
        XCTAssertNil(host.installed()?.ps2Core)
    }

    func testLrps2ComesOnlyFromTheInstalledHostsOwnRelease() async throws {
        RetroHostFakeGitHub.list([
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(version: "1.1.1", ps2: true), tag: "v1.1.1"),
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(ps2: true), tag: "v1.1.0"),
        ])
        let host = store()
        try await installHost()
        let listed = try await releases()
        let other = try XCTUnwrap(listed.first { $0.tag == "v1.1.1" })
        let seen = RetroHostFakeGitHub.requests.count
        do {
            _ = try await host.fetchCore(other, .lrps2, configuration: RetroHostFakeGitHub.configuration)
            XCTFail("another release's package was fetched")
        } catch let error as RetroHostDownloadError {
            XCTAssertEqual(error.kind, .notAvailable)
        }
        XCTAssertEqual(RetroHostFakeGitHub.requests.count, seen, "nothing downloaded")
        do {
            _ = try await host.fetchCore(nil, .lrps2, configuration: RetroHostFakeGitHub.configuration)
            XCTFail("no release, no package")
        } catch let error as RetroHostDownloadError {
            XCTAssertEqual(error.kind, .notAvailable)
        }
    }
}
