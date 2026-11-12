import Foundation
import XCTest
@testable import AnyPS5Core

/// The head of a game's launch script on a games folder macOS guards (an external drive): the
/// script reads one of the game's files before the engine starts and waits while it cannot. A
/// file without read permission stands in for the read macOS holds back until the player answers.
final class LaunchScriptTests: XCTestCase {
    var scratch: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("launch-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let probe { chmod(probe.path, 0o644) }
        try? fm.removeItem(at: scratch)
    }

    var probe: URL?

    /// A bundle as the installer lays it out, its script ending where the engine would start: it
    /// prints the folder the game starts in.
    func bundle(waitTries: Int) throws -> URL {
        let contents = scratch.appendingPathComponent("Game.app/Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let system = contents.appendingPathComponent("Resources/game/app0/sce_sys")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: system, withIntermediateDirectories: true)
        let param = system.appendingPathComponent("param.json")
        try Data("{}".utf8).write(to: param)
        probe = param
        let launch = macOS.appendingPathComponent("launch")
        try (Installer.launchHead(identifier: "org.anyps5.test", waitTries: waitTries) + "pwd\n").write(to: launch, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launch.path)
        return launch
    }

    /// Runs the script as macOS starts a bundle (its own path, through its #! line) and gives
    /// what it printed and how long it took.
    func run(_ launch: URL) throws -> (output: String, seconds: TimeInterval) {
        let process = Process()
        process.executableURL = launch
        process.environment = ["HOME": scratch.path, "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        process.standardOutput = out
        let start = Date()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return (String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), Date().timeIntervalSince(start))
    }

    func skipAsRoot() throws {
        try XCTSkipIf(getuid() == 0, "root reads a file without read permission")
    }

    func testAReadableGameStartsAtOnceInItsGameFolder() throws {
        let (output, seconds) = try run(try bundle(waitTries: Installer.readWaitTries))
        XCTAssertTrue(output.hasSuffix("/Game.app/Contents/Resources/game"), output)
        XCTAssertLessThan(seconds, 5)
    }

    func testTheEngineWaitsUntilTheGameCanBeRead() throws {
        try skipAsRoot()
        let launch = try bundle(waitTries: Installer.readWaitTries)
        let param = try XCTUnwrap(probe)
        XCTAssertEqual(chmod(param.path, 0), 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { chmod(param.path, 0o644) }
        let (output, seconds) = try run(launch)
        XCTAssertTrue(output.hasSuffix("/Game.app/Contents/Resources/game"), output)
        XCTAssertGreaterThanOrEqual(seconds, 1.0, "the engine started before the read went through")
        XCTAssertLessThan(seconds, 30)
    }

    func testAReadThatNeverGetsThroughStillStartsTheGameAfterTheWait() throws {
        try skipAsRoot()
        let launch = try bundle(waitTries: 3)
        XCTAssertEqual(chmod(try XCTUnwrap(probe).path, 0), 0)
        let (output, seconds) = try run(launch)
        XCTAssertTrue(output.hasSuffix("/Game.app/Contents/Resources/game"), output)
        XCTAssertGreaterThanOrEqual(seconds, 0.5)
        XCTAssertLessThan(seconds, 30)
    }

    func testTheReadComesBeforeAnyStepIntoTheGameFolder() {
        let script = Installer.launchHead(identifier: "x")
        let probe = script.range(of: "until { true < \"$probe\"; }")
        let firstStep = script.range(of: "cd ")
        XCTAssertNotNil(probe)
        XCTAssertNotNil(firstStep)
        if let probe, let firstStep { XCTAssertLessThan(probe.lowerBound, firstStep.lowerBound) }
        XCTAssertTrue(script.contains("-ge \(Installer.readWaitTries) ]"))
    }
}
