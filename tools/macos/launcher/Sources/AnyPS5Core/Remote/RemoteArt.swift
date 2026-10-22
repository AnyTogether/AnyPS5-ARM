import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A game's icon and background as the phone gets them: small JPEGs in base64, so a whole
/// library fits through the control channel in a moment.
public enum RemoteArt {
    public static let iconSide = 256
    public static let backgroundSide = 1280

    /// The picture with its longest side at most `longestSide` pixels, nil when there is none.
    public static func jpeg(_ url: URL?, longestSide: Int, quality: Double = 0.72) -> String? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data).base64EncodedString()
    }

    /// Changes when either picture is replaced or edited.
    public static func tag(icon: URL?, background: URL?) -> String {
        let parts = [icon, background].map { url -> String in
            guard let url else { return "-" }
            // Read from the file system each time: a URL keeps the values it read once.
            let date = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(url.path)@\(Int(date))"
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "|").utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(hash, radix: 36)
    }
}
