import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Screenshots and clips made ready for AnyTogether's limits before they go up: a picture of
/// at most `maxBytes` and 40 megapixels (PNG as it is when it fits, else a JPEG), an H.264 MP4
/// clip small enough (made smaller when it is not), and a clip's poster frame.
public enum MediaPrep {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// The picture to send: the file itself when it fits, else a JPEG made smaller until it does.
    public static func image(_ file: URL, maxBytes: Int, maxPixels: Int = 40_000_000) throws -> (data: Data, contentType: String) {
        let data = try Data(contentsOf: file)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw Failure(description: "not a picture")
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let type = CGImageSourceGetType(source) as String?
        let sendable = [UTType.png.identifier, UTType.jpeg.identifier, UTType.webP.identifier].contains(type ?? "")
        if sendable, data.count <= maxBytes, width * height <= maxPixels {
            return (data, type == UTType.png.identifier ? "image/png" : type == UTType.jpeg.identifier ? "image/jpeg" : "image/webp")
        }
        var side = max(width, height)
        if width * height > maxPixels {
            side = Int(Double(side) * (Double(maxPixels) / Double(width * height)).squareRoot())
        }
        side = min(side, 3840)
        for quality in [0.88, 0.8, 0.7] {
            while side >= 320 {
                if let jpeg = jpeg(source, maxPixel: side, quality: quality), jpeg.count <= maxBytes { return (jpeg, "image/jpeg") }
                side = side * 3 / 4
            }
            side = min(max(width, height), 3840)
        }
        throw Failure(description: "the picture cannot be made small enough")
    }

    static func jpeg(_ source: CGImageSource, maxPixel: Int, quality: Double) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpeg(image, quality: quality)
    }

    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// The clip to send: the file itself when it fits, else an H.264 copy at a smaller size (in
    /// `folder`) that does. The caller removes a copy when done.
    public static func clip(_ file: URL, maxBytes: Int, in folder: URL = FileManager.default.temporaryDirectory) async throws -> URL {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if size <= maxBytes { return file }
        let asset = AVURLAsset(url: file)
        let presets = [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480]
        var smallest: URL?
        for preset in presets {
            guard let export = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let out = folder.appendingPathComponent("AnyPS5-clip-\(UUID().uuidString).mp4")
            export.outputURL = out
            export.outputFileType = .mp4
            export.shouldOptimizeForNetworkUse = true
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { done.resume() }
            }
            guard export.status == .completed else {
                try? FileManager.default.removeItem(at: out)
                continue
            }
            let made = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? .max
            if let smallest { try? FileManager.default.removeItem(at: smallest) }
            smallest = nil
            if made <= maxBytes { return out }
            smallest = out
        }
        if let smallest { try? FileManager.default.removeItem(at: smallest) }
        throw Failure(description: "the clip is too long to send")
    }

    /// A still from the clip's first second as a JPEG, at most `maxPixel` a side.
    public static func poster(_ clip: URL, maxPixel: Int = 1280) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let image = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image else { return nil }
        return jpeg(image, quality: 0.82)
    }
}
