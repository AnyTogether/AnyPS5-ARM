import AnyPS5Core
import AVFoundation
import Combine
import AppKit
import CoreMedia
import ScreenCaptureKit
import SwiftUI

/// Broadcasting the game playing, as the console's Broadcast does: ScreenCaptureKit gives the
/// game's window (in pixels, following it as it changes) and its sound, the microphone comes in
/// through AVAudioEngine, and BroadcastSession encodes and publishes them. The launcher shows
/// how it goes; a LIVE badge sits over the game meanwhile.
@MainActor
final class Broadcaster: ObservableObject {
    enum Phase: Equatable {
        case off
        case starting
        case live
        case reconnecting(attempt: Int, delay: Double)
        case failed(String)

        var active: Bool {
            switch self {
            case .starting, .live, .reconnecting: return true
            case .off, .failed: return false
            }
        }
    }

    @Published var settings: BroadcastSettings {
        didSet {
            guard settings != oldValue else { return }
            if persists { settings.save() }
            session?.microphoneLevel = settings.microphone ? Float(settings.microphoneLevel) / 100 : 0
            if settings.microphone != oldValue.microphone, phase.active { settings.microphone ? startMicrophone() : stopMicrophone() }
            badge.update(self)
        }
    }
    @Published private(set) var phase = Phase.off {
        didSet { if phase.active != oldValue.active { phoneTold(phase.active) } }
    }
    @Published private(set) var stats = BroadcastSession.Stats()
    /// The game broadcast, while one is.
    @Published private(set) var game: String?
    /// The previews' running game, which has no process.
    var previewGame: String?
    let keys: BroadcastKeyStore
    let persists: Bool
    private var session: BroadcastSession?
    private var stream: SCStream?
    private var output: Output?
    private var watch: Task<Void, Never>?
    private var microphone: Microphone?
    private var timer: Timer?
    private let badge = LiveBadge()
    /// Said over the game when the state changes.
    var notice: (String, String, String) -> Void = { _, _, _ in }
    /// Tells the phone whether a broadcast is on.
    var phoneTold: (Bool) -> Void = { _ in }
    /// Passes changes on to the launcher's model.
    var relay: AnyCancellable?

    init(persists: Bool) {
        self.persists = persists
        settings = persists ? BroadcastSettings.load() : BroadcastSettings()
        keys = persists ? BroadcastKeyStore() : BroadcastKeyStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-broadcast-\(UUID().uuidString)/keys.json"))
    }

    var key: String { keys.key(for: settings.service) }

    func setKey(_ key: String) {
        keys.setKey(key, for: settings.service)
        objectWillChange.send()
    }

    /// Where the broadcast goes, or why it cannot.
    func endpoint() -> Result<RTMPEndpoint, RTMPEndpoint.Problem> {
        Result { try RTMPEndpoint.parse(url: settings.serverURL, key: key) }.mapError { $0 as? RTMPEndpoint.Problem ?? .noHost }
    }

    var serviceName: String { settings.service == .custom ? TB.text(.serviceCustom) : settings.service.name }

    // MARK: Starting and stopping

    /// Broadcasts the game with process `pid` (`name` for the badge and the notices).
    func start(pid: pid_t, game id: String) async {
        guard !phase.active else { return }
        guard case .success(let endpoint) = endpoint() else {
            if case .failure(let problem) = endpoint() { phase = .failed(problem.description) }
            return
        }
        phase = .starting
        game = id
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            fail(TB.text(.needsPermission), detail: TB.text(.needsPermissionDetail))
            return
        }
        guard phase == .starting, let app = content.applications.first(where: { $0.processID == pid }), let window = ClipRecorder.mainWindow(of: pid, in: content),
              let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else {
            if phase == .starting { fail(ClipRecorder.Failure.noWindow.description, detail: "") }
            return
        }
        let quality = settings.quality
        let session = BroadcastSession(endpoint: endpoint, quality: quality) { [weak self] state in
            Task { @MainActor in self?.changed(state) }
        }
        session.microphoneLevel = settings.microphone ? Float(settings.microphoneLevel) / 100 : 0
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        // The game's pixels at the preset's size, letterboxed when the window is another shape,
        // so the stream keeps one size while the window changes.
        let configure = { (window: SCWindow, display: SCDisplay, scale: CGFloat) -> SCStreamConfiguration in
            let configuration = ClipRecorder.configuration(window: window, display: display, scale: scale, maxWidth: quality.width, maxHeight: quality.height, queueDepth: 5)
            configuration.width = quality.width
            configuration.height = quality.height
            configuration.preservesAspectRatio = true
            configuration.scalesToFit = true
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(quality.frameRate))
            return configuration
        }
        let output = Output(session: session)
        let stream = SCStream(filter: filter, configuration: configure(window, display, CGFloat(filter.pointPixelScale)), delegate: nil)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.audioQueue)
            try await stream.startCapture()
        } catch {
            fail(TB.text(.needsPermission), detail: "\(error.localizedDescription)")
            return
        }
        guard phase == .starting else {
            try? await stream.stopCapture()
            return
        }
        self.session = session
        self.stream = stream
        self.output = output
        watch = ClipRecorder.follow(stream, pid: pid, app: app, window: window, display: display, configure: configure)
        session.start()
        if settings.microphone { startMicrophone() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        badge.update(self)
    }

    /// Ends the broadcast (the game ended, or the user stopped it).
    func stop() {
        guard phase.active || session != nil else {
            if case .failed = phase { phase = .off }
            return
        }
        let wasLive = phase == .live || stats.duration > 0
        tearDown()
        phase = .off
        game = nil
        badge.update(self)
        if wasLive { notice(TB.text(.endedNotice), TB.text(.stopped), "dot.radiowaves.left.and.right") }
    }

    private func tearDown() {
        watch?.cancel()
        watch = nil
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        output = nil
        stopMicrophone()
        session?.stop()
        session = nil
        timer?.invalidate()
        timer = nil
    }

    private func fail(_ reason: String, detail: String) {
        tearDown()
        phase = .failed(reason)
        game = nil
        badge.update(self)
        notice(TB.text(.failedNotice), detail.isEmpty ? reason : detail, "exclamationmark.triangle.fill")
    }

    private func changed(_ state: RTMPPublisher.State) {
        guard session != nil else { return }
        switch state {
        case .connecting:
            if phase != .live, !isReconnecting { phase = .starting }
        case .live:
            let first = stats.duration == 0 && !isReconnecting
            phase = .live
            if first { notice(TB.text(.startedNotice), TB.format(.startedDetail, serviceName), "dot.radiowaves.left.and.right") }
        case .reconnecting(let attempt, let delay, _):
            if attempt == 1 && phase == .live { notice(TB.text(.reconnectingNotice), TB.format(.reconnectingDetail, serviceName), "wifi.exclamationmark") }
            phase = .reconnecting(attempt: attempt, delay: delay)
        case .failed(let reason):
            fail(TB.format(.failed, reason), detail: reason)
        case .stopped:
            break
        }
        tick()
    }

    private var isReconnecting: Bool {
        if case .reconnecting = phase { return true }
        return false
    }

    private func tick() {
        guard let session else { return }
        stats = session.stats()
        badge.update(self)
    }

    // MARK: Microphone

    private func startMicrophone() {
        guard microphone == nil, let session else { return }
        Task { @MainActor in
            guard await PartyVoice.microphoneAllowed() else {
                self.notice(TB.text(.microphone), TB.text(.noMicrophone), "mic.slash")
                return
            }
            guard self.microphone == nil, self.session === session, self.settings.microphone else { return }
            let microphone = Microphone(session: session)
            if microphone.start() { self.microphone = microphone } else { self.notice(TB.text(.microphone), TB.text(.noMicrophone), "mic.slash") }
        }
    }

    private func stopMicrophone() {
        microphone?.stop()
        microphone = nil
    }

    // MARK: Previews

    func preview(_ phase: Phase, stats: BroadcastSession.Stats, game: String?) {
        self.phase = phase
        self.stats = stats
        self.game = game
        previewGame = game
    }

    // MARK: Capture

    /// The game's frames and sound, handed to the session on their own queues.
    final class Output: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "org.anyps5.broadcast.video", qos: .userInteractive)
        let audioQueue = DispatchQueue(label: "org.anyps5.broadcast.sound", qos: .userInteractive)
        private let session: BroadcastSession

        init(session: BroadcastSession) { self.session = session }

        func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
            guard sample.isValid else { return }
            switch type {
            case .screen:
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                      let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
                session.video(pixels, at: CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            case .audio:
                if let samples = Output.interleaved(sample) { session.gameAudio(samples, at: CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
            default:
                break
            }
        }

        /// ScreenCaptureKit's float sound (planar or not) as interleaved stereo.
        static func interleaved(_ sample: CMSampleBuffer) -> [Float]? {
            let buffers = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(buffers.unsafeMutablePointer) }
            var block: CMBlockBuffer?
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil, bufferListOut: buffers.unsafeMutablePointer,
                                                                          bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: 2),
                                                                          blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return nil }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let format = CMSampleBufferGetFormatDescription(sample), let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  description.mFormatFlags & kAudioFormatFlagIsFloat != 0, let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            let planar = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            let channels = max(1, Int(description.mChannelsPerFrame))
            let second = planar && buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            var samples = [Float](repeating: 0, count: frames * 2)
            for frame in 0 ..< frames {
                samples[frame * 2] = planar ? first[frame] : first[frame * channels]
                samples[frame * 2 + 1] = planar ? (second ?? first)[frame] : first[frame * channels + min(1, channels - 1)]
            }
            return samples
        }
    }

    /// The microphone through AVAudioEngine, made 48 kHz stereo for the mixer.
    final class Microphone: @unchecked Sendable {
        private let engine = AVAudioEngine()
        private let session: BroadcastSession
        private var converter: AVAudioConverter?
        private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!

        init(session: BroadcastSession) { self.session = session }

        func start() -> Bool {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0, let converter = AVAudioConverter(from: format, to: target) else { return false }
            self.converter = converter
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
                self?.convert(buffer, at: time)
            }
            do {
                try engine.start()
                return true
            } catch {
                input.removeTap(onBus: 0)
                return false
            }
        }

        func stop() {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        private func convert(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
            guard let converter else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var given = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if given {
                    status.pointee = .noDataNow
                    return nil
                }
                given = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0, let data = converted.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(converted.frameLength) * 2))
            let seconds = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : CACurrentMediaTime()
            session.microphone(samples, at: seconds)
        }
    }
}

/// The small LIVE badge over the game while it is broadcast: a borderless panel above every
/// window that never takes the keyboard or the mouse, and that the broadcast itself does not
/// capture (only the game's own windows are).
@MainActor
final class LiveBadge {
    private var panel: NSPanel?
    private let state = LiveBadgeState()

    func update(_ broadcaster: Broadcaster) {
        let shown = broadcaster.settings.liveBadge && (broadcaster.phase == .live || { if case .reconnecting = broadcaster.phase { return true } else { return false } }())
        state.live = broadcaster.phase == .live
        state.duration = broadcaster.stats.duration
        guard shown, broadcaster.persists, let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? make()
        self.panel = panel
        let size = CGSize(width: 220, height: 44)
        let top = screen.frame.maxY - screen.safeAreaInsets.top
        panel.setFrame(NSRect(x: screen.frame.minX + 18, y: top - size.height - 14, width: size.width, height: size.height), display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: LiveBadgeView(state: state))
        return panel
    }
}

final class LiveBadgeState: ObservableObject {
    @Published var live = true
    @Published var duration: Double = 0
}

/// "● LIVE 12:04": red while live, amber while reconnecting.
struct LiveBadgeView: View {
    @ObservedObject var state: LiveBadgeState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color.white).frame(width: 7, height: 7)
                    .opacity(pulse ? 0.45 : 1)
                Text(TB.text(.liveBadge)).font(.system(size: 13, weight: .bold)).tracking(1.2)
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(state.live ? Color(red: 0.92, green: 0.16, blue: 0.2) : Color(red: 0.95, green: 0.6, blue: 0.15)))
            Text(TB.clock(state.duration))
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .padding(.leading, 9).padding(.trailing, 11)
        }
        .foregroundStyle(.white)
        .frame(height: 26)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
