import CoreGraphics
import Foundation

/// The host's frames as a picture, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_frame_image.dart):
///
/// - Each frame marked `drawn` is copied at once, on the session's queue while its event is
///   handled: a frame "stays readable until another frame replaces it", and one that was not drawn
///   only until the next message, so nothing waits. After that, nothing the host writes can change
///   the picture, and the main thread never reads the shared memory.
/// - The copy becomes a `CGImage`: `rgba8` and `bgra8` come out as the same colours, alpha left out.
/// - It keeps up by skipping: frames that come while the main thread has not taken the last one
///   replace it, so only the newest is shown ("Frames can be skipped; only the newest frame
///   matters").
///
/// Frames not marked drawn, and events with no frame, leave the picture as it is ("the launcher
/// keeps showing what it showed before"). While `accepting` is false every frame is ignored, so a
/// game that ended never shows its last picture again.
public final class RetroFramePicture: @unchecked Sendable {
    private let lock = NSLock()
    private var accepts = true
    private var pending: CGImage?
    private var scheduled = false
    /// Counts the clears, so a picture made before one is never shown after it.
    private var generation = 0

    public init() {}

    /// The newest picture, on the main thread; nil before the first frame and after `clear()`.
    @MainActor public private(set) var image: CGImage?
    /// Called on the main thread after `image` changed.
    @MainActor public var onImage: (() -> Void)?

    /// Whether frames are taken now.
    public var accepting: Bool {
        get { lock.withLock { accepts } }
        set { lock.withLock { accepts = newValue } }
    }

    /// Drops the picture and any frame still on its way.
    @MainActor public func clear() {
        lock.withLock {
            generation += 1
            pending = nil
        }
        guard image != nil else { return }
        image = nil
        onImage?()
    }

    /// One `frame` event, on the session's queue: a drawn frame is copied there and then.
    public func take(_ event: RetroFrameEvent) {
        guard event.drawn, let frame = event.frame else { return }
        let before: Int? = lock.withLock { accepts ? generation : nil }
        guard let before, let picture = Self.image(of: frame) else { return }
        let schedule: Bool = lock.withLock {
            // A clear while the frame was copied: it belongs to what was cleared.
            guard generation == before, accepts else { return false }
            pending = picture
            defer { scheduled = true }
            return !scheduled
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.publish() }
        }
    }

    @MainActor private func publish() {
        let next: CGImage? = lock.withLock {
            scheduled = false
            defer { pending = nil }
            return accepts ? pending : nil
        }
        guard let next else { return }
        image = next
        onImage?()
    }

    /// A copy of `frame`'s rows of `width` × 4 bytes as an image.
    static func image(of frame: RetroPinnedFrame) -> CGImage? {
        let rowBytes = frame.width * 4
        guard frame.width > 0, frame.height > 0 else { return nil }
        let bytes = Data(bytes: frame.pixels, count: rowBytes * frame.height)
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        let info: CGBitmapInfo = frame.pixelFormat == .rgba8
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
