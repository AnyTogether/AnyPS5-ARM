import AppKit
import XCTest
@testable import AnyPS5Core

final class RemoteArtTests: XCTestCase {
    func picture(width: Int, height: Int) throws -> URL {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("art-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: file)
        return file
    }

    func testABigPictureIsShrunkToAJPEG() throws {
        let file = try picture(width: 3840, height: 2160)
        defer { try? FileManager.default.removeItem(at: file) }
        let text = try XCTUnwrap(RemoteArt.jpeg(file, longestSide: 1280))
        let data = try XCTUnwrap(Data(base64Encoded: text))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(image.pixelsWide, 1280)
        XCTAssertEqual(image.pixelsHigh, 720)
    }

    func testNoPictureIsNil() {
        XCTAssertNil(RemoteArt.jpeg(nil, longestSide: 256))
        XCTAssertNil(RemoteArt.jpeg(URL(fileURLWithPath: "/nonexistent.png"), longestSide: 256))
    }

    func testTheTagFollowsThePictures() throws {
        let file = try picture(width: 8, height: 8)
        defer { try? FileManager.default.removeItem(at: file) }
        let tag = RemoteArt.tag(icon: file, background: nil)
        XCTAssertEqual(tag, RemoteArt.tag(icon: file, background: nil))
        XCTAssertNotEqual(tag, RemoteArt.tag(icon: nil, background: file))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 5)], ofItemAtPath: file.path)
        XCTAssertNotEqual(tag, RemoteArt.tag(icon: file, background: nil))
    }
}
