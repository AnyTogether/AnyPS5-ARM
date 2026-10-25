import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AnyPS5Core

final class ProfilePictureTests: XCTestCase {
    /// A picture, the left half red and the right half blue, as PNG or JPEG.
    static func picture(width: Int, height: Int, jpeg: Bool = false) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The colour at a point of a picture, from the top left.
    func pixel(_ data: Data, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let image = ProfilePicture.read(data)!
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (bytes[0], bytes[1], bytes[2])
    }

    func testZoomOneIsTheLargestSquareInTheMiddle() {
        XCTAssertEqual(ProfilePicture.crop(width: 400, height: 200, zoom: 1, offset: .zero), CGRect(x: 100, y: 0, width: 200, height: 200))
        XCTAssertEqual(ProfilePicture.crop(width: 200, height: 400, zoom: 1, offset: .zero), CGRect(x: 0, y: 100, width: 200, height: 200))
    }

    func testZoomAndOffsetMoveASmallerSquare() {
        XCTAssertEqual(ProfilePicture.crop(width: 400, height: 200, zoom: 2, offset: .zero), CGRect(x: 150, y: 50, width: 100, height: 100))
        XCTAssertEqual(ProfilePicture.crop(width: 400, height: 200, zoom: 2, offset: CGPoint(x: -1, y: 1)), CGRect(x: 0, y: 100, width: 100, height: 100))
        // Past the edge stays at the edge, and zoom never goes below 1.
        XCTAssertEqual(ProfilePicture.crop(width: 400, height: 200, zoom: 2, offset: CGPoint(x: 5, y: -5)), CGRect(x: 300, y: 0, width: 100, height: 100))
        XCTAssertEqual(ProfilePicture.crop(width: 400, height: 200, zoom: 0.2, offset: .zero), CGRect(x: 100, y: 0, width: 200, height: 200))
    }

    /// Dragging the picture right shows more of its left: the square moves left.
    func testDraggingMovesTheSquareTheOtherWay() {
        let moved = ProfilePicture.offset(.zero, movedBy: CGSize(width: 50, height: 0), width: 400, height: 200, zoom: 1)
        XCTAssertEqual(moved.x, -0.5, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0)
        XCTAssertEqual(ProfilePicture.crop(width: 400, height: 200, zoom: 1, offset: moved).minX, 50, accuracy: 0.0001)
        let far = ProfilePicture.offset(.zero, movedBy: CGSize(width: -1000, height: 0), width: 400, height: 200, zoom: 1)
        XCTAssertEqual(far.x, 1)
    }

    func testTheCropIsA512PixelPNGOfTheChosenSquare() throws {
        let source = try XCTUnwrap(ProfilePicture.read(Self.picture(width: 400, height: 200)))
        let left = try XCTUnwrap(ProfilePicture.png(source, crop: ProfilePicture.crop(width: 400, height: 200, zoom: 1, offset: CGPoint(x: -1, y: 0))))
        let image = try XCTUnwrap(ProfilePicture.read(left))
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertEqual(CGImageSourceGetType(CGImageSourceCreateWithData(left as CFData, nil)!) as String?, UTType.png.identifier)
        XCTAssertGreaterThan(pixel(left, x: 256, y: 256).r, 200, "the left square is red")
        let right = try XCTUnwrap(ProfilePicture.png(source, crop: ProfilePicture.crop(width: 400, height: 200, zoom: 1, offset: CGPoint(x: 1, y: 0))))
        XCTAssertGreaterThan(pixel(right, x: 256, y: 256).b, 200, "the right square is blue")
        let middle = try XCTUnwrap(ProfilePicture.png(source, crop: ProfilePicture.crop(width: 400, height: 200, zoom: 1, offset: .zero)))
        XCTAssertGreaterThan(pixel(middle, x: 40, y: 256).r, 200)
        XCTAssertGreaterThan(pixel(middle, x: 470, y: 256).b, 200)
    }

    func testANonPictureIsNotRead() {
        XCTAssertNil(ProfilePicture.read(Data("not a picture".utf8)))
    }

    /// The server's limits, checked before sending.
    func testWhatAnyTogetherWouldRefuse() {
        XCTAssertNil(ProfilePicture.uploadProblem(Self.picture(width: 512, height: 512)))
        XCTAssertNil(ProfilePicture.uploadProblem(Self.picture(width: 64, height: 40, jpeg: true)))
        XCTAssertEqual(ProfilePicture.uploadProblem(Self.picture(width: 31, height: 200)), .tooSmall)
        XCTAssertEqual(ProfilePicture.uploadProblem(Data("GIF89a".utf8)), .notPNGOrJPEG)
        XCTAssertEqual(ProfilePicture.contentType(Self.picture(width: 40, height: 40, jpeg: true)), "image/jpeg")
        XCTAssertEqual(ProfilePicture.contentType(Self.picture(width: 40, height: 40)), "image/png")
    }
}

final class TogetherAvatarTests: TogetherSignedInCase {
    func testTheAvatarGoesUpAsItIsAndTheUserKeepsItsAddress() async throws {
        let png = ProfilePictureTests.picture(width: 64, height: 64)
        FakeTogether.handler = { _, _ in (200, ["avatar": "https://anytogether.test/api/v1/avatars/0123456789abcdef0123456789abcdef.jpg"]) }
        let address = try await client.uploadAvatar(png)
        XCTAssertEqual(last(), "PUT /api/v1/me/avatar")
        let request = try XCTUnwrap(FakeTogether.requests.last)
        XCTAssertEqual(request.0.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(request.1, png)
        XCTAssertEqual(address, "https://anytogether.test/api/v1/avatars/0123456789abcdef0123456789abcdef.jpg")
        XCTAssertEqual(client.user?.avatar, address)
    }

    func testARefusedAvatarIsAProblem() async {
        FakeTogether.handler = { _, _ in (413, ["status": 413, "code": "payload_too_large", "title": "An avatar is at most 5 MB"]) }
        do {
            _ = try await client.uploadAvatar(Data([0xFF, 0xD8, 0xFF, 0xE0]))
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.status, 413)
            XCTAssertEqual(FakeTogether.requests.last?.0.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        } catch {
            XCTFail("\(error)")
        }
    }
}
