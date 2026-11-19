import CoreGraphics
import XCTest
@testable import AnyPS5Core

/// The host's frames as a picture, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_frame_image_test.dart), from frames over memory the test holds.
@MainActor
final class RetroFramePictureTests: XCTestCase {
    /// The first pixel of `image` as red, green, blue.
    private func pixel(_ image: CGImage?) throws -> [UInt8] {
        let image = try XCTUnwrap(image)
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        bytes.initialize(repeating: 0, count: 4)
        defer { bytes.deallocate() }
        let context = try XCTUnwrap(CGContext(data: bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return [bytes[0], bytes[1], bytes[2]]
    }

    private func event(_ frame: RetroPinnedFrame?, drawn: Bool = true) -> RetroFrameEvent { RetroFrameEvent(frame: frame, drawn: drawn) }

    func testAnRgba8AndABgra8FrameComeOutAsTheSameColours() async throws {
        let picture = RetroFramePicture()
        var changes = 0
        picture.onImage = { changes += 1 }
        let rgba = FakeSlot(2, 1)
        rgba.fill([200, 100, 50, 255])
        picture.take(event(rgba.pin()))
        await settleRetro({ picture.image != nil })
        XCTAssertEqual(picture.image?.width, 2)
        XCTAssertEqual(picture.image?.height, 1)
        XCTAssertEqual(try pixel(picture.image), [200, 100, 50])
        XCTAssertEqual(changes, 1)

        let bgra = FakeSlot(1, 1)
        bgra.fill([50, 100, 200, 0])
        picture.take(event(bgra.pin(format: .bgra8)))
        await settleRetro({ picture.image?.width == 1 })
        XCTAssertEqual(try pixel(picture.image), [200, 100, 50], "blue, green, red, and alpha left out")
    }

    func testAFrameThatIsNotDrawnOrAnEmptyEventIsNeverShown() async {
        let picture = RetroFramePicture()
        let slot = FakeSlot(1, 1)
        slot.fill([1, 2, 3, 255])
        picture.take(event(slot.pin(), drawn: false))
        picture.take(event(nil))
        await yieldRetro()
        XCTAssertNil(picture.image)
        picture.accepting = false
        picture.take(event(slot.pin()))
        await yieldRetro()
        XCTAssertNil(picture.image, "nothing while it does not accept frames")
    }

    func testThePixelsAreCopiedWhenTheFrameArrives() async throws {
        let picture = RetroFramePicture()
        let slot = FakeSlot(1, 1)
        slot.fill([10, 20, 30, 255])
        picture.take(event(slot.pin()))
        slot.fill([90, 90, 90, 255])
        await settleRetro({ picture.image != nil })
        XCTAssertEqual(try pixel(picture.image), [10, 20, 30], "what the host writes after the event never shows")
    }

    func testOnlyTheNewestFrameThatCameMeanwhileIsShown() async throws {
        let picture = RetroFramePicture()
        var changes = 0
        picture.onImage = { changes += 1 }
        let first = FakeSlot(1, 1), second = FakeSlot(1, 1)
        first.fill([1, 1, 1, 255])
        second.fill([2, 2, 2, 255])
        picture.take(event(first.pin()))
        picture.take(event(second.pin()))
        await settleRetro({ picture.image != nil })
        await yieldRetro()
        XCTAssertEqual(try pixel(picture.image), [2, 2, 2])
        XCTAssertEqual(changes, 1, "the frame skipped was never made into the picture")
    }

    func testClearStopsShowingThePictureAndDropsAFrameStillOnItsWay() async {
        let picture = RetroFramePicture()
        let slot = FakeSlot(1, 1)
        slot.fill([5, 5, 5, 255])
        picture.take(event(slot.pin()))
        await settleRetro({ picture.image != nil })
        picture.take(event(slot.pin()))
        picture.clear()
        XCTAssertNil(picture.image)
        await yieldRetro()
        XCTAssertNil(picture.image, "the frame on its way was dropped")
    }
}
