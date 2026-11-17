import Darwin
import XCTest
@testable import AnyPS5Core

/// The programs that end with the launcher, as on Windows and Linux: an engine build's tools
/// and what they started, never a program left to finish.
final class ChildProcessesTests: XCTestCase {
    override func tearDown() {
        ChildProcesses.endAll(grace: 0.1)
        super.tearDown()
    }

    /// A shell that starts a sleep of its own and prints its number.
    private func shellWithChild() throws -> (Process, pid_t) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/bin/sleep 60 & echo $!; wait"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        var line = Data()
        while !line.contains(0x0A) {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            line.append(data)
        }
        let child = try XCTUnwrap(pid_t(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        return (process, child)
    }

    private func gone(_ pid: pid_t) -> Bool {
        for _ in 0..<100 {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            usleep(20_000)
        }
        return false
    }

    private func ended(_ process: Process) -> Bool {
        for _ in 0..<100 where process.isRunning { usleep(20_000) }
        return !process.isRunning
    }

    func testTheDescendantsComeFromTheTableOfParents() {
        // 10 started 11 and 14, 11 started 12; 13 is another program's.
        let parents: [pid_t: pid_t] = [1: 0, 10: 1, 11: 10, 12: 11, 13: 1, 14: 10, 0: 0]
        XCTAssertEqual(ChildProcesses.descendants(of: 10, parents: parents), [11, 14, 12])
        XCTAssertEqual(ChildProcesses.descendants(of: 13, parents: parents), [])
        XCTAssertEqual(ChildProcesses.descendants(of: 0, parents: parents), [], "never the kernel's")
        // A loop in a table read while processes come and go ends.
        XCTAssertEqual(ChildProcesses.descendants(of: 20, parents: [20: 21, 21: 20]), [21])
    }

    func testTheProcessTableHasThisProcessAndItsParent() {
        XCTAssertEqual(ChildProcesses.parents()[getpid()], getppid())
    }

    func testEndAllEndsARememberedProgramAndTheProgramItStarted() throws {
        let (shell, child) = try shellWithChild()
        ChildProcesses.remember(shell)
        XCTAssertEqual(ChildProcesses.count, 1)
        ChildProcesses.endAll()
        XCTAssertEqual(ChildProcesses.count, 0)
        XCTAssertTrue(ended(shell))
        XCTAssertTrue(gone(child), "the sleep the shell started ends too")
    }

    func testAForgottenProgramIsLeftRunning() throws {
        let (shell, child) = try shellWithChild()
        ChildProcesses.remember(shell)
        ChildProcesses.forget(shell)
        XCTAssertEqual(ChildProcesses.count, 0)
        ChildProcesses.endAll()
        XCTAssertTrue(shell.isRunning)
        kill(child, SIGKILL)
        shell.terminate()
        XCTAssertTrue(ended(shell))
    }

    func testEndAllWithNothingRememberedDoesNothing() {
        ChildProcesses.endAll()
        XCTAssertEqual(ChildProcesses.count, 0)
    }

    func testAnEngineBuildsCommandEndsWithTheLauncherAndAnInstallDoesNot() throws {
        let root = FileManager.default.temporaryDirectory
        for ends in [true, false] {
            let finished = expectation(description: "the command returned")
            let runner = SystemCommands(endsWithLauncher: ends)
            DispatchQueue.global().async {
                _ = try? runner.run(URL(fileURLWithPath: "/bin/sleep"), ["2"], in: root, environment: [:], cancel: nil) { _ in }
                finished.fulfill()
            }
            // The command starts and is remembered only when it ends with the launcher.
            if ends {
                for _ in 0..<50 where ChildProcesses.count == 0 { usleep(20_000) }
            } else {
                usleep(300_000)
            }
            XCTAssertEqual(ChildProcesses.count, ends ? 1 : 0)
            ChildProcesses.endAll()
            wait(for: [finished], timeout: ends ? 1.5 : 5)
            XCTAssertEqual(ChildProcesses.count, 0, "forgotten once it returned")
        }
    }
}
