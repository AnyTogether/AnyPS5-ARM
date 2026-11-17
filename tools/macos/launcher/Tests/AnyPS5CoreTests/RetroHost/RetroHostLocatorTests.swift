import XCTest
@testable import AnyPS5Core

/// Finding the emulator host (protocol.md "Finding and checking the host"). `swift test` builds in
/// debug, so these see the debug build's side; a release build (`swift build -c release`) compiles
/// `host` to nil and never reads the variable.
final class RetroHostLocatorTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("retro-host-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, executable: Bool) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url
    }

    func testThisDebugBuildMayRunAnUncheckedHost() {
        #if DEBUG
        XCTAssertTrue(RetroHostLocator.runsUncheckedHosts)
        #else
        XCTAssertFalse(RetroHostLocator.runsUncheckedHosts)
        #endif
    }

    func testADebugBuildRunsTheExecutableTheVariableNames() throws {
        let host = try file("anyps5-retro-host", executable: true)
        #if DEBUG
        XCTAssertEqual(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": host.path])?.path, host.path)
        #else
        XCTAssertNil(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": host.path]))
        #endif
    }

    func testNothingIsFoundWithoutAnAbsolutePathToAnExecutableFile() throws {
        let plain = try file("not-executable", executable: false)
        XCTAssertNil(RetroHostLocator.host(environment: [:]))
        XCTAssertNil(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": ""]))
        XCTAssertNil(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": "anyps5-retro-host"]))
        XCTAssertNil(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": plain.path]))
        XCTAssertNil(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": folder.path]))
        XCTAssertNil(RetroHostLocator.host(environment: ["ANYPS5_RETRO_HOST": folder.appendingPathComponent("missing").path]))
    }
}
