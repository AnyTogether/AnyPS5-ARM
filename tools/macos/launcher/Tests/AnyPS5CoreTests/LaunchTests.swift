import XCTest
@testable import AnyPS5Core

final class LaunchTests: XCTestCase {
    func testLaunchRunsTheBundleScriptDirectly() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("launch-\(UUID().uuidString).app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let out = bundle.appendingPathComponent("out.txt")
        let script = "#!/bin/sh\necho \"$ANYPS5_TEST $(basename \"$0\") $PPID\" > \"\(out.path)\"\n"
        try script.write(to: macOS.appendingPathComponent("launch"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent("launch").path)

        let pid = try Installer.launch(bundle: bundle, environment: ["ANYPS5_TEST": "hello"])
        XCTAssertGreaterThan(pid, 0)
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: out.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let words = try String(contentsOf: out, encoding: .utf8).split(separator: " ").map(String.init)
        XCTAssertEqual(words.first, "hello", "the game gets the launcher's environment for it")
        XCTAssertEqual(words.dropFirst().first, "launch")
        XCTAssertEqual(words.last?.trimmingCharacters(in: .whitespacesAndNewlines), String(ProcessInfo.processInfo.processIdentifier), "a child of the launcher, not of LaunchServices")
    }

    func testTheGameDoesNotInheritTheLaunchersIdentity() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString).app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let out = bundle.appendingPathComponent("out.txt")
        try "#!/bin/sh\necho \"[${__CFBundleIdentifier}][${XPC_SERVICE_NAME}]\" > \"\(out.path)\"\n".write(to: macOS.appendingPathComponent("launch"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent("launch").path)
        setenv("__CFBundleIdentifier", "org.anyps5.launcher", 1)
        setenv("XPC_SERVICE_NAME", "application.org.anyps5.launcher", 1)
        defer {
            unsetenv("__CFBundleIdentifier")
            unsetenv("XPC_SERVICE_NAME")
        }
        _ = try Installer.launch(bundle: bundle, environment: [:])
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: out.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "[][]\n")
    }

    func testLaunchFailsWithoutAScript() {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).app")
        XCTAssertThrowsError(try Installer.launch(bundle: bundle, environment: [:]))
    }
}
