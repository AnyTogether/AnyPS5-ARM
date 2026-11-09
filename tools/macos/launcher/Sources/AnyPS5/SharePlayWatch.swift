import AnyPS5Core
import AnyPS5MediaServer
import AnyPS5SharePlay
import GameController
import SwiftUI
import WebRTC

/// Watching a friend's share play in the launcher: their game full screen, its sound, and, once
/// they let this user play, the controller as player 2, 3 or 4 in their game (its packets on the
/// share play's pad channel, 120 times a second and at once on a change). Straight from the host
/// (the mesh), or, in a big share play while the user holds no pad, from the media server.
@MainActor
final class ShareWatchSession {
    let id: String
    let watcher: SharePlayWatcher
    let speaker: SharePlaySpeaker
    let video: RTCMTLNSVideoView
    /// Where the picture comes from now; nil until started.
    private(set) var route: TogetherMediaRoute?
    /// The media server's side, while the route is "sfu".
    private(set) var mediaServer: SfuShareWatcher?
    /// A fresh media server token (the join's first, then GET /share-plays/:id/sfu).
    var access: () async throws -> TogetherSfuAccess = { throw CancellationError() }
    /// The picture showing or not, from whichever route is on.
    var connected: (Bool) -> Void = { _ in }
    /// The media server could not be reached.
    var failed: () -> Void = {}
    /// The view the picture is in now.
    var view: NSView { mediaServer?.view ?? video }
    private var pump: Timer?
    private var stats: Timer?
    private var sequence: UInt32 = 0
    private let session = UInt64.random(in: 1 ... UInt64.max)
    private var last: SharePadState?
    private var lastSent = Date.distantPast
    /// The pad the host handed this user, nil while they only watch.
    var slot: Int? {
        didSet { slot == nil ? stopPad() : startPad() }
    }

    init(id: String, watcher: SharePlayWatcher, speaker: SharePlaySpeaker, video: RTCMTLNSVideoView) {
        self.id = id
        self.watcher = watcher
        self.speaker = speaker
        self.video = video
    }

    func start(route: TogetherMediaRoute = .mesh, measured: @escaping (Double?, Double?, Int?) -> Void) {
        try? speaker.start()
        go(route)
        stats = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let server = self.mediaServer {
                    let stats = server.statistics()
                    measured(stats.roundTrip, stats.fps, stats.height)
                } else {
                    self.watcher.statistics { roundTrip, fps, height in Task { @MainActor in measured(roundTrip, fps, height) } }
                }
            }
        }
    }

    /// Onto a route: the mesh asks the host for a connection (and leaves the media server's
    /// room); the media server says goodbye to the host's connection and joins the room.
    func go(_ next: TogetherMediaRoute) {
        guard next != route else { return }
        let before = route
        route = next
        switch next {
        case .mesh:
            if let server = mediaServer {
                mediaServer = nil
                Task { await server.close() }
            }
            connected(false)
            watcher.start()
        case .sfu:
            if before == .mesh { watcher.close() }
            let server = SfuShareWatcher(hostId: watcher.hostId) { [weak self] on in
                guard let self, self.route == .sfu else { return }
                self.connected(on)
            }
            mediaServer = server
            connected(false)
            Task {
                do {
                    let given = try await access()
                    guard mediaServer === server else { return }
                    try await server.start(given)
                } catch {
                    RemoteServer.log.error("share play: media server: \(String(describing: error), privacy: .public)")
                    if mediaServer === server { failed() }
                }
            }
        }
    }

    func close() {
        stopPad()
        stats?.invalidate()
        speaker.stop()
        watcher.close()
        if let server = mediaServer {
            mediaServer = nil
            Task { await server.close() }
        }
    }

    private func startPad() {
        guard pump == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sendPad() } }
        RunLoop.main.add(timer, forMode: .common)
        pump = timer
    }

    private func stopPad() {
        pump?.invalidate()
        pump = nil
        last = nil
    }

    /// The controller now as the engine's pad; sent when it changed, and at least every 8 ms.
    private func sendPad() {
        guard slot != nil, let state = ShareWatchSession.read(GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad) else { return }
        guard state != last || Date().timeIntervalSince(lastSent) >= 0.008 else { return }
        sequence &+= 1
        let micros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        if watcher.sendPad(state.packet(sequence: sequence, sentMicros: micros, session: session)) {
            last = state
            lastSent = Date()
        }
    }

    /// A controller as the DualSense the game expects.
    static func read(_ pad: GCExtendedGamepad?) -> SharePadState? {
        guard let pad else { return nil }
        typealias B = SharePadState.Button
        var state = SharePadState()
        let pressed: [(GCControllerButtonInput?, UInt32)] = [
            (pad.buttonA, B.cross), (pad.buttonB, B.circle), (pad.buttonX, B.square), (pad.buttonY, B.triangle),
            (pad.leftShoulder, B.l1), (pad.rightShoulder, B.r1), (pad.leftThumbstickButton, B.l3), (pad.rightThumbstickButton, B.r3),
            (pad.buttonMenu, B.options), (pad.dpad.up, B.up), (pad.dpad.down, B.down), (pad.dpad.left, B.left), (pad.dpad.right, B.right),
            ((pad as? GCDualSenseGamepad)?.touchpadButton ?? (pad as? GCDualShockGamepad)?.touchpadButton ?? pad.buttonOptions, B.touchPad),
        ]
        for (button, bit) in pressed where button?.isPressed == true { state.buttons |= bit }
        state.l2 = SharePadState.trigger(pad.leftTrigger.value)
        state.r2 = SharePadState.trigger(pad.rightTrigger.value)
        if pad.leftTrigger.value > 0.1 { state.buttons |= B.l2 }
        if pad.rightTrigger.value > 0.1 { state.buttons |= B.r2 }
        state.sticks = [SharePadState.axis(pad.leftThumbstick.xAxis.value), SharePadState.axis(pad.leftThumbstick.yAxis.value, up: true),
                        SharePadState.axis(pad.rightThumbstick.xAxis.value), SharePadState.axis(pad.rightThumbstick.yAxis.value, up: true)]
        return state
    }
}

extension AppModel {
    /// Watch a friend's share play here; signed out, the website's page opens instead.
    func watchShare(_ id: String) {
        guard familyPermits(.sharePlay) else { return }
        guard togetherUser != nil, let me = togetherUser?.id else {
            NSWorkspace.shared.open(together.base.appendingPathComponent("watch").appendingPathComponent(id))
            return
        }
        if shareWatch?.id == id { return }
        leaveWatching()
        Task {
            do {
                let joined = try await together.joinSharePlay(id)
                guard let host = joined.sharePlay.host else { return }
                if mediaLimits == nil { loadMediaLimits() }
                let video = RTCMTLNSVideoView(frame: .zero)
                // The sound channel's packets go straight to the speaker, on WebRTC's thread.
                let speaker = SharePlaySpeaker()
                let watcher = SharePlayWatcher(hostId: host.userId, hostDevice: joined.sharePlay.hostDevice, iceServers: joined.iceServers, renderer: video,
                                               send: { [weak self] to, device, signal in
                                                   self?.togetherSocket?.signal(to: to, device: device, share: id, kind: signal.kind, data: signal.data)
                                               },
                                               onSound: { packet in speaker.play(packet) },
                                               onPadOutput: { _ in },
                                               changed: { [weak self] state in
                                                   guard let self, self.shareWatch?.route != .sfu else { return }
                                                   self.share.watchConnected = state == .connected
                                               })
                let session = ShareWatchSession(id: id, watcher: watcher, speaker: speaker, video: video)
                // The join's room access first, a fresh one after.
                var first = joined.sfu
                let client = together
                session.access = {
                    if let given = first {
                        first = nil
                        return given
                    }
                    return try await client.sharePlaySfu(id)
                }
                session.connected = { [weak self] on in
                    guard let self, self.shareWatch === session else { return }
                    self.share.watchConnected = on
                    self.share.watchViaServer = session.route == .sfu
                }
                session.failed = { [weak self] in self?.show(SP.text(.mediaServerFailed), symbol: "exclamationmark.triangle.fill") }
                shareWatch = session
                share.invites.removeAll { $0.sharePlayId == id }
                withAnimation(Motion.overlay) {
                    share.watching = joined.sharePlay
                    share.watchConnected = false
                    share.watchStats = nil
                }
                session.slot = joined.sharePlay.viewers.first { $0.user.userId == me }?.slot
                session.start(route: SharePlayMedia.viewerRoute(joined.sharePlay, me: me)) { [weak self] roundTrip, fps, height in
                    self?.share.watchStats = .init(roundTrip: roundTrip, fps: fps, height: height)
                }
            } catch let problem as TogetherProblem where problem.code == "full" {
                show(SP.text(.full), symbol: "person.3.fill")
            } catch {
                show(SP.text(.couldNotWatch) + ": \(error)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func leaveWatching(tellServer: Bool = true) {
        guard let session = shareWatch else { return }
        session.close()
        shareWatch = nil
        if tellServer { Task { try? await together.leaveSharePlay(session.id) } }
        withAnimation(Motion.overlay) {
            share.watching = nil
            share.watchStats = nil
            share.watchViaServer = false
        }
    }

    /// The share play watched changed (a pad handed over or taken back), or a signal came.
    func watchEvent(_ event: TogetherSocket.Event) -> Bool {
        guard let session = shareWatch else { return false }
        switch event.type {
        case "share_play.updated":
            guard let sharePlay = event.decode(TogetherSharePlay.self), sharePlay.id == session.id else { return false }
            let slot = sharePlay.viewers.first { $0.user.userId == togetherUser?.id }?.slot
            if slot != session.slot { show(slot.map { SP.format(.youPlay, $0) } ?? SP.text(.youWatch), symbol: slot == nil ? "eye" : "gamecontroller.fill") }
            session.slot = slot
            share.watching = sharePlay
            // A pad handed over: straight to the host; taken back, or the share play grew past
            // the mesh: from the media server.
            if let me = togetherUser?.id { session.go(SharePlayMedia.viewerRoute(sharePlay, me: me)) }
            return true
        case "share_play.signal":
            guard let raw = event.decode(TogetherShareSignal.self), raw.sharePlayId == session.id, let signal = ShareSignal(raw) else { return false }
            // From the media server, no mesh signals at all.
            if session.route != .sfu { session.watcher.receive(signal, from: raw.from, device: raw.device) }
            return true
        case "share_play.ended":
            guard event.data["sharePlayId"] == session.id else { return false }
            let host = share.watching?.host?.displayName ?? ""
            leaveWatching(tellServer: false)
            show(event.data["reason"] == "removed" ? SP.format(.tookYouOut, host) : SP.format(.hostStopped, host), symbol: "shareplay.slash")
            return true
        default:
            return false
        }
    }

    /// While watching, the controller is the game's: only the PS button (or esc while only
    /// watching) leaves; nil when not watching.
    func watchCommand(_ command: Command) -> Bool? {
        guard let session = shareWatch else { return nil }
        // Without a controller there is no pad to keep circle for: esc always leaves then.
        if command == .home || (command == .back && (session.slot == nil || GCController.controllers().isEmpty)) { leaveWatching() }
        return true
    }
}

/// The friend's game over everything, with who and how it goes in a corner.
struct ShareWatchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session = model.shareWatch {
                ShareVideo(view: session.view)
                    .id(ObjectIdentifier(session.view))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .opacity(model.share.watchConnected ? 1 : 0.0001)
            }
            if !model.share.watchConnected {
                VStack(spacing: 14 * scale) {
                    ProgressView().controlSize(.large)
                    Text(SP.text(.connecting)).font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
            VStack {
                HStack(alignment: .top) {
                    chip
                    Spacer()
                }
                Spacer()
                HStack(spacing: 22 * scale) {
                    Hint(keys: model.shareWatch?.slot == nil ? "PS / esc / ○" : "PS", label: SP.text(.leave))
                }
                .opacity(0.7)
            }
            .padding(28 * scale)
        }
    }

    private var chip: some View {
        let sharePlay = model.share.watching
        let slot = model.shareWatch?.slot
        return HStack(spacing: 12 * scale) {
            ProfileAvatar(url: sharePlay?.host?.avatar, name: sharePlay?.host?.displayName ?? "", size: 36 * scale)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(sharePlay.map { "\($0.host?.displayName ?? "") · \($0.title ?? model.gameName($0.titleId))" } ?? "")
                    .font(.display(15 * scale, .semibold)).lineLimit(1)
                Text(statusLine(slot: slot)).font(.display(13 * scale)).opacity(0.72).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 10 * scale)
        .glass(22 * scale, opacity: 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([sharePlay.map { "\($0.host?.displayName ?? ""), \($0.title ?? model.gameName($0.titleId))" } ?? "", statusLine(slot: slot)].joined(separator: ", "))
    }

    private func statusLine(slot: Int?) -> String {
        var parts = [slot.map { SP.format(.player, $0) } ?? SP.text(.onlyWatches)]
        if model.share.watchViaServer { parts.append(SP.text(.viaServer)) }
        if let stats = model.share.watchStats {
            if let roundTrip = stats.roundTrip { parts.append(SP.format(.roundTrip, Int(roundTrip.rounded()))) }
            if let fps = stats.fps, let height = stats.height { parts.append("\(height)p\(Int(fps.rounded()))") }
        }
        return parts.joined(separator: " · ")
    }
}

/// The picture's view in SwiftUI: WebRTC's Metal view from the host, or LiveKit's from the media server.
struct ShareVideo: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
