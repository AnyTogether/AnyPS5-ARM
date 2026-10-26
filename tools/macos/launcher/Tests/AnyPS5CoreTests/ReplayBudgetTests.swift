import XCTest
@testable import AnyPS5Core

final class ReplayBudgetTests: XCTestCase {
    func testTheLengthsOnOffer() {
        XCTAssertEqual(ReplayBudget.lengths, [30, 60, 180, 300])
        XCTAssertEqual(ReplayBudget.length(nil), 30)
    }

    /// A length saved before the choices (15 to 120 s) is the nearest choice now.
    func testAnOldLengthIsTheNearestChoice() {
        XCTAssertEqual(ReplayBudget.length(15), 30)
        XCTAssertEqual(ReplayBudget.length(45), 30)
        XCTAssertEqual(ReplayBudget.length(60), 60)
        // Halfway between two goes to the shorter.
        XCTAssertEqual(ReplayBudget.length(120), 60)
        XCTAssertEqual(ReplayBudget.length(300), 300)
        XCTAssertEqual(ReplayBudget.length(900), 300)
    }

    /// Up to a minute is recorded at the clip quality, as before.
    func testShortLengthsKeepTheClipQuality() {
        let quality = Int(1920.0 * 1080 * 60 * 0.15)
        XCTAssertEqual(ReplayBudget.bitRate(width: 1920, height: 1080, seconds: 30), quality)
        XCTAssertEqual(ReplayBudget.bitRate(width: 1920, height: 1080, seconds: 60), quality)
    }

    /// Three and five minutes fit the picture within the budget.
    func testLongLengthsFitTheBudget() {
        for seconds in [180, 300] {
            let rate = ReplayBudget.bitRate(width: 2560, height: 1600, seconds: seconds)
            XCTAssertLessThanOrEqual(rate / 8 * seconds, ReplayBudget.videoBudget)
            XCTAssertGreaterThan(rate, 5_000_000, "a five minute clip still looks like the game")
        }
    }

    func testTheMemoryLineCountsPictureAndSound() {
        XCTAssertEqual(ReplayBudget.megabytes(width: 1920, height: 1080, seconds: 30), 78)
        XCTAssertLessThanOrEqual(ReplayBudget.megabytes(width: 3840, height: 2160, seconds: 300), 256 + 116)
    }

    /// A small window never drops below a megabit.
    func testATinyPictureHasAFloor() {
        XCTAssertEqual(ReplayBudget.bitRate(width: 64, height: 64, seconds: 300), 1_000_000)
    }
}

/// The replay buffer keeps the window it is given, however long, and lets go of the rest.
final class ReplayTrimTests: XCTestCase {
    private func recorded(seconds: Double, keep: Double) -> ClipBuffer<Int> {
        var buffer = ClipBuffer<Int>(length: keep)
        var frame = 0
        while Double(frame) / 60 < seconds {
            buffer.addVideo(frame, at: Double(frame) / 60, key: frame % 60 == 0)
            frame += 1
        }
        var chunk = 0
        while Double(chunk) / 100 < seconds {
            buffer.addAudio(chunk, at: Double(chunk) / 100)
            chunk += 1
        }
        return buffer
    }

    func testFiveMinutesAreKeptWhole() throws {
        let clip = try XCTUnwrap(recorded(seconds: 400, keep: 300).clip())
        let start = try XCTUnwrap(clip.video.first?.time)
        let end = try XCTUnwrap(clip.video.last?.time)
        XCTAssertGreaterThanOrEqual(end - start, 300 - 0.02)
        XCTAssertLessThanOrEqual(end - start, 301.02)
        XCTAssertEqual(clip.video.first?.key, true)
    }

    func testOlderThanTheWindowIsLetGo() {
        for keep in [30.0, 60, 180, 300] {
            let buffer = recorded(seconds: keep * 2 + 10, keep: keep)
            XCTAssertLessThanOrEqual(Double(buffer.videoCount), (keep + 2.1) * 60, "\(keep) s keeps too many frames")
            XCTAssertLessThanOrEqual(Double(buffer.audioCount), (keep + 3.1) * 100, "\(keep) s keeps too much sound")
        }
    }

    /// Less recorded than the window: all of it, from the first key frame.
    func testAShortRecordingWithALongWindowIsAllKept() throws {
        let clip = try XCTUnwrap(recorded(seconds: 20, keep: 300).clip())
        XCTAssertEqual(clip.video.first?.payload, 0)
        XCTAssertEqual(clip.video.count, 1200)
    }
}

final class GamePauseTests: XCTestCase {
    func testThePressGoesWhenNobodyHoldsPlayerOne() {
        XCTAssertEqual(GamePause.route(enabled: true, controllers: 0, phonePlayers: [], channelFree: true), .send)
        XCTAssertEqual(GamePause.route(enabled: true, controllers: 0, phonePlayers: [2], channelFree: true), .send)
    }

    func testOffSendsNothing() {
        XCTAssertEqual(GamePause.route(enabled: false, controllers: 0, phonePlayers: [], channelFree: true), .off)
    }

    /// A controller or a phone as player 1: the press would sign in a second player instead.
    func testATakenFirstPlayerSendsNothing() {
        XCTAssertEqual(GamePause.route(enabled: true, controllers: 1, phonePlayers: [], channelFree: true), .playerOneTaken)
        XCTAssertEqual(GamePause.route(enabled: true, controllers: 0, phonePlayers: [1], channelFree: true), .playerOneTaken)
    }

    func testNoChannelSendsNothing() {
        XCTAssertEqual(GamePause.route(enabled: true, controllers: 0, phonePlayers: [], channelFree: false), .noChannel)
    }

    /// One press: Options down in the first packets, up in the last, in sequence, the engine's format.
    func testThePacketsAreOnePressOfOptions() {
        let packets = GamePause.packets(session: 42, firstSequence: 7)
        XCTAssertEqual(packets.count, GamePause.press.count)
        for (index, packet) in packets.enumerated() {
            XCTAssertEqual(RemotePacket.inputSession(packet), 42)
            let sequence: UInt32 = RemotePacket.read(packet, at: 8)
            XCTAssertEqual(sequence, 7 + UInt32(index))
            let buttons: UInt32 = RemotePacket.read(packet, at: 32)
            XCTAssertEqual(buttons, GamePause.press[index].down ? SharePadState.Button.options : 0)
            // No seat asked for: the engine gives the lowest free one.
            XCTAssertEqual(packet[packet.startIndex + 13], 0)
        }
        XCTAssertTrue(GamePause.press.first!.down)
        XCTAssertFalse(GamePause.press.last!.down)
        let held = GamePause.press.first { !$0.down }!.at
        XCTAssertGreaterThanOrEqual(held, 0.1, "a press shorter than a few frames may be missed")
        XCTAssertLessThan(held, RemotePadSilence, "the engine would read a gap as letting go")
    }

    private let RemotePadSilence = 0.5
}

final class WindowStartTests: XCTestCase {
    func testTheFirstLaunchIsFullScreenThenAsLeft() {
        XCTAssertTrue(WindowStart.fullScreen(saved: nil, steamFullScreen: false))
        XCTAssertFalse(WindowStart.fullScreen(saved: false, steamFullScreen: false))
        XCTAssertTrue(WindowStart.fullScreen(saved: true, steamFullScreen: false))
        XCTAssertTrue(WindowStart.fullScreen(saved: false, steamFullScreen: true))
    }
}
