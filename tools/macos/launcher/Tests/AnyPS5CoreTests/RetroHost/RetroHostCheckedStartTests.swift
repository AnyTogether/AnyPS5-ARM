import XCTest
@testable import AnyPS5Core

/// A checked host's start, as on Windows and Linux (AnyPS5 Desktop's retro_host_client.dart
/// `start(checked:)`): the check is good for one start of its own executable, its files are let go
/// once the host has exited, and the host is given only the release's cores. The "host" here is
/// /usr/bin/true, which exits at once without a word of the protocol.
final class RetroHostCheckedStartTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-checked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func checked(executable: String) throws -> RetroHostChecked {
        let file = scratch.appendingPathComponent("held-\(UUID().uuidString)")
        try Data("x".utf8).write(to: file)
        return RetroHostChecked(version: RetroHostVersion(1, 0, 0), executable: executable, core: "/release/swanstation_libretro.dylib",
                                ps2Core: nil, files: [try RetroCheckedFile.open(file.path)])
    }

    func testACommandOfAnotherProgramIsRefusedAndTheCheckLetGo() async throws {
        let check = try checked(executable: "/release/anyps5-retro-host")
        do {
            _ = try await RetroHostClient.start(command: ["/usr/bin/true"], checked: check)
            XCTFail("another program was started with the check")
        } catch {
            XCTAssertEqual(error as? RetroHostClientError, .notTheCheckedHost)
        }
        XCTAssertFalse(check.held)
        do {
            _ = try await RetroHostClient.start(command: ["/release/anyps5-retro-host"], checked: check)
            XCTFail("a check let go started a host")
        } catch {
            XCTAssertEqual(error as? RetroHostClientError, .checkNotHeld)
        }
    }

    func testTheCheckIsHeldUntilTheHostExitedAndOnlyTheReleasesCoreStarts() async throws {
        let check = try checked(executable: "/usr/bin/true")
        let client = try await RetroHostClient.start(command: ["/usr/bin/true"], checked: check)
        do {
            _ = try await client.call("start", .object(["core": .string("/elsewhere/other_libretro.dylib"), "disc": .string("/d.cue"),
                                                         "system": .string("/s"), "saves": .string("/v")]))
            XCTFail("another core was sent to a checked host")
        } catch {
            XCTAssertEqual((error as? RetroCallError)?.code, RetroCallError.argument)
        }
        _ = await client.exited()
        XCTAssertFalse(check.held, "the files are let go once the host has exited")
        await client.close()
    }
}
