import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The profile picture: a square cut from a picture the user chose, kept as a 512 px PNG in
/// Application Support/AnyPS5/profile.png and shown on the top bar; it can go up to AnyTogether
/// as the account's avatar.
public enum ProfilePicture {
    public static let side = 512
    public static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AnyPS5/profile.png")

    /// AnyTogether's limits for PUT /me/avatar.
    public static let uploadMaxBytes = 5 * 1024 * 1024
    public static let uploadMinSide = 32
    public static let uploadMaxPixels = 25_000_000

    /// Pictures larger than this are read smaller: a crop needs no more.
    static let readMaxSide = 4096

    /// A picture file read upright (its EXIF orientation applied), at most 4096 px on a side; nil
    /// when it is no picture.
    public static func read(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: readMaxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The square of a `width` × `height` picture the crop keeps, in its pixels from the top left.
    /// Zoom 1 is the largest square in the middle; more zoom a smaller one. The offset (-1...1 on
    /// each axis) moves the square within the room around it, 0 being the middle.
    public static func crop(width: Int, height: Int, zoom: Double, offset: CGPoint) -> CGRect {
        let side = Double(min(width, height)) / min(max(zoom, 1), 8)
        let roomX = (Double(width) - side) / 2
        let roomY = (Double(height) - side) / 2
        let x = roomX + min(max(Double(offset.x), -1), 1) * roomX
        let y = roomY + min(max(Double(offset.y), -1), 1) * roomY
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The offset that moves the crop by `pixels` of the picture: dragging the picture right
    /// by d moves the square left by d.
    public static func offset(_ offset: CGPoint, movedBy pixels: CGSize, width: Int, height: Int, zoom: Double) -> CGPoint {
        let side = Double(min(width, height)) / min(max(zoom, 1), 8)
        let roomX = (Double(width) - side) / 2
        let roomY = (Double(height) - side) / 2
        func moved(_ value: CGFloat, _ by: CGFloat, _ room: Double) -> CGFloat {
            room < 0.5 ? 0 : min(max(value - by / CGFloat(room), -1), 1)
        }
        return CGPoint(x: moved(offset.x, pixels.width, roomX), y: moved(offset.y, pixels.height, roomY))
    }

    /// The square `crop` of `image` drawn `side` px wide, as PNG.
    public static func png(_ image: CGImage, crop: CGRect, side: Int = side) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // CoreGraphics counts from the bottom left; the crop from the top left.
        let scale = Double(side) / crop.width
        let drawn = CGRect(x: -crop.minX * scale, y: -(Double(image.height) - crop.maxY) * scale,
                           width: Double(image.width) * scale, height: Double(image.height) * scale)
        context.draw(image, in: drawn)
        guard let square = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, square, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A picture the server already made square (an AnyTogether avatar), as the 512 px PNG.
    public static func png(fromSquare data: Data) -> Data? {
        guard let image = read(data) else { return nil }
        return png(image, crop: crop(width: image.width, height: image.height, zoom: 1, offset: .zero))
    }

    public enum UploadProblem: Equatable, Sendable {
        case notPNGOrJPEG, tooLarge, tooSmall, tooManyPixels
    }

    /// What AnyTogether would refuse in the picture: PNG or JPEG only, at most 5 MB, at least
    /// 32 px on a side and at most 25 megapixels. nil when it would take it.
    public static func uploadProblem(_ data: Data) -> UploadProblem? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) as String?,
              type == UTType.png.identifier || type == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return .notPNGOrJPEG }
        if data.count > uploadMaxBytes { return .tooLarge }
        if min(width, height) < uploadMinSide { return .tooSmall }
        if width * height > uploadMaxPixels { return .tooManyPixels }
        return nil
    }

    /// The content type to send the picture with.
    public static func contentType(_ data: Data) -> String {
        data.starts(with: [0xFF, 0xD8, 0xFF]) ? "image/jpeg" : "image/png"
    }
}
