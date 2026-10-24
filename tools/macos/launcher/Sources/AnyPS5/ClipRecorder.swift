import AnyPS5Core
import AppKit
import CoreMedia
import ScreenCaptureKit

/// The last seconds of the game playing, picture and sound, kept to be saved as a clip after
/// the fact, as the console's Create button does. ScreenCaptureKit gives the game's window and
/// its sound, which ClipEncoder encodes and keeps.
@MainActor
final class ClipRecorder {
    enum Failure: Error, CustomStringConvertible {
        case noPermission
        case noWindow
        case nothingRecorded

        var description: String {
            switch self {
            case .noPermission: return "no screen recording permission"
            case .noWindow: return "the game's window was not found"
            case .nothingRecorded: return "nothing was recorded yet"
            }
        }
    }

    private var stream: SCStream?
    private var output: Output?
    private var watch: Task<Void, Never>?
    private(set) var recordingPid: pid_t?

    /// Whether macOS lets the launcher record the screen; asks the first time.
    static func allowed() async -> Bool {
        (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil
    }

    /// Starts keeping the last `length` seconds of the game with process `pid`.
    func start(pid: pid_t, length: Double) async throws {
        stop()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Failure.noPermission
        }
        guard let app = content.applications.first(where: { $0.processID == pid }),
              let window = ClipRecorder.mainWindow(of: pid, in: content),
              let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else { throw Failure.noWindow }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let configure = { (window: SCWindow, display: SCDisplay, scale: CGFloat) in
            ClipRecorder.configuration(window: window, display: display, scale: scale, maxWidth: .max, maxHeight: .max, queueDepth: 6)
        }
        let configuration = configure(window, display, CGFloat(filter.pointPixelScale))
        let output = Output(length: length)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
        self.output = output
        recordingPid = pid
        watch = ClipRecorder.follow(stream, pid: pid, app: app, window: window, display: display, configure: configure)
    }

    /// Follows the game's window while `stream` captures it: resized, made full screen or moved
    /// to another display, the capture changes with it (checked every second).
    static func follow(_ stream: SCStream, pid: pid_t, app: SCRunningApplication, window: SCWindow, display: SCDisplay,
                       configure: @escaping (SCWindow, SCDisplay, CGFloat) -> SCStreamConfiguration) -> Task<Void, Never> {
        Task { [weak stream] in
            var frame = window.frame
            var screen = display.displayID
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let stream, !Task.isCancelled,
                      let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                      let current = ClipRecorder.mainWindow(of: pid, in: content), current.frame != frame,
                      let display = content.displays.first(where: { $0.frame.intersects(current.frame) }) ?? content.displays.first else { continue }
                frame = current.frame
                let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                if display.displayID != screen {
                    screen = display.displayID
                    try? await stream.updateContentFilter(filter)
                }
                try? await stream.updateConfiguration(configure(current, display, CGFloat(filter.pointPixelScale)))
            }
        }
    }

    func stop() {
        watch?.cancel()
        watch = nil
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        output = nil
        recordingPid = nil
    }

    /// Writes what is kept to `file`, an MP4.
    func save(to file: URL) async throws {
        guard let output else { throw Failure.nothingRecorded }
        try await output.encoder.save(to: file)
    }

    static func mainWindow(of pid: pid_t, in content: SCShareableContent) -> SCWindow? {
        content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.height > 200 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// A standard window's title bar, as the engine's windowed game has one.
    static var titleBar: CGFloat {
        NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled]).height - 100
    }

    /// What to capture of the game's window: the game, without its title bar.
    static func area(of window: SCWindow, on display: SCDisplay) -> CGRect {
        GameWindowArea.capture(window: window.frame, display: display.frame, titleBar: titleBar)
    }

    /// The game's area of `window` in pixels (`scale` a point) up to `maxWidth` x `maxHeight`, 60
    /// frames a second, and its sound.
    static func configuration(window: SCWindow, display: SCDisplay, scale: CGFloat, maxWidth: Int, maxHeight: Int, queueDepth: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let area = ClipRecorder.area(of: window, on: display)
        configuration.sourceRect = area
        let size = GameWindowArea.outputSize(area: area.size, scale: scale, maxWidth: maxWidth, maxHeight: maxHeight)
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = queueDepth
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        return configuration
    }

    /// Receives the window's frames and sound on its own queue and hands them to the encoder.
    final class Output: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "org.anyps5.clips", qos: .userInitiated)
        let encoder: ClipEncoder

        init(length: Double) {
            encoder = ClipEncoder(length: length)
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
            guard sample.isValid else { return }
            switch type {
            case .audio:
                encoder.addAudio(sample)
            case .screen:
                // Only complete frames carry a picture; idle and blank ones repeat the last.
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                      let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
                encoder.addFrame(pixels, at: CMSampleBufferGetPresentationTimeStamp(sample))
            default:
                break
            }
        }
    }
}
