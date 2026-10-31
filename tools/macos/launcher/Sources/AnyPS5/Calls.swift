import AnyPS5Core
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Calls with one friend on AnyTogether. A call to the user rings: a card in the launcher, or a
/// banner over a game with ⌥A to answer and ⌥D to decline; unanswered, it gives up after a while.
/// The user calls a friend from the Friends panel, and hangs up there. The voice is the party's
/// (PartyVoice: the same mesh, microphone and push-to-talk).
extension AppModel {
    // MARK: Ringing

    func directCallEvent(_ event: TogetherSocket.Event) {
        let data = event.data
        switch event.type {
        case "call.ringing":
            guard let call = event.decode(TogetherRinging.self), call.callId != voiceCall else { return }
            ring(call)
        case "call.answered":
            guard let id = data["callId"] else { return }
            if id == voiceCall, data["userId"] != togetherUser?.id {
                withAnimation(Motion.overlay) { callWaiting = false }
                show(T.format(.callWith, callFriend?.displayName ?? ""), symbol: "phone.fill")
            } else if ringing?.callId == id {
                // Answered on another of the user's devices.
                stopRinging()
            }
        case "call.ended":
            guard let id = data["callId"] else { return }
            if let call = ringing, call.callId == id {
                stopRinging()
                // Declined here or on another device says nothing; the caller giving up is a missed call.
                guard data["reason"] != "declined" else { return }
                missedCall(call.from)
            } else if id == voiceCall, let friend = callFriend {
                show(T.format(data["reason"] == "declined" ? .callDeclined : .callEnded, friend.displayName), symbol: "phone.down.fill")
            }
        default:
            break
        }
    }

    /// Rings until answered, declined, or long enough to count as not answered.
    func ring(_ call: TogetherRinging) {
        guard familyAllows(.voiceChat) else { return }
        stopRinging()
        withAnimation(Motion.overlay) { ringing = call }
        if !NSApp.isActive { RingBanner.shared.show(call) }
        Input.shared.registerHotKey(id: Input.answerKey, keyCode: kVK_ANSI_A, modifiers: optionKey) { [weak self] pressed in
            if pressed { self?.acceptRinging() }
        }
        Input.shared.registerHotKey(id: Input.declineKey, keyCode: kVK_ANSI_D, modifiers: optionKey) { [weak self] pressed in
            if pressed { self?.declineRinging() }
        }
        ringTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled, Date().timeIntervalSince(start) < TogetherVoice.ringFor {
                Sounds.shared.play(.ring)
                Feel.shared.vibrate(.ring)
                try? await Task.sleep(for: .seconds(2.4))
            }
            guard !Task.isCancelled, let self, self.ringing?.callId == call.callId else { return }
            // Not answered: it ends for the caller too.
            self.declineRinging()
            self.missedCall(call.from)
        }
    }

    func stopRinging() {
        ringTask?.cancel()
        ringTask = nil
        RingBanner.shared.hide()
        Input.shared.unregisterHotKey(id: Input.answerKey)
        Input.shared.unregisterHotKey(id: Input.declineKey)
        if ringing != nil { withAnimation(Motion.overlay) { ringing = nil } }
    }

    private func missedCall(_ from: TogetherPerson) {
        show(T.format(.callMissed, from.displayName), symbol: "phone.arrow.down.left")
        if !NSApp.isActive { TrophyBanner.shared.notice(T.format(.callMissed, from.displayName), detail: "@\(from.handle)", symbol: "phone.arrow.down.left", sounds: preferences.sounds) }
    }

    /// Answered here: out of any other voice, into this call.
    func acceptRinging() {
        guard let call = ringing else { return }
        stopRinging()
        Task {
            guard await PartyVoice.microphoneAllowed() else {
                try? await together.declineCall(call.callId)
                return show(T.text(.voiceNoMic), symbol: "mic.slash.fill")
            }
            if voiceCall != nil { leaveVoice() }
            do {
                startVoice(try await together.answerCall(call.callId), friend: call.from)
                Sounds.shared.play(.select)
                show(T.format(.callWith, call.from.displayName), symbol: "phone.fill")
            } catch let problem as TogetherProblem where problem.status == 409 {
                show(T.text(.callAnsweredElsewhere), symbol: "phone.badge.checkmark")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func declineRinging() {
        guard let call = ringing else { return }
        stopRinging()
        Sounds.shared.play(.back)
        let client = together
        Task { try? await client.declineCall(call.callId) }
    }

    // MARK: Calling a friend

    /// Rings the friend; the call is joined here already and waits for them to answer.
    func startCall(with friend: TogetherPerson) {
        guard togetherUser != nil, familyPermits(.voiceChat) else { return }
        Task {
            guard await PartyVoice.microphoneAllowed() else {
                return show(T.text(.voiceNoMic), symbol: "mic.slash.fill")
            }
            if voiceCall != nil { leaveVoice() }
            do {
                let joined = try await together.call(friend: friend.userId)
                startVoice(joined, friend: friend, waiting: true)
                Sounds.shared.play(.select)
                show(T.format(.callCalling, friend.displayName), symbol: "phone.arrow.up.right")
                let call = joined.call.id
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(TogetherVoice.ringFor + 5))
                    guard let self, self.voiceCall == call, self.callWaiting else { return }
                    self.leaveVoice()
                    self.show(T.format(.callNoAnswer, friend.displayName), symbol: "phone.down.fill")
                }
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The Friends panel's rows while in a call with a friend: who, then the microphone and hanging up.
    func callRows() -> [PanelRow] {
        guard let friend = callFriend, voiceCall != nil else { return [] }
        var details: [String] = []
        if voiceDeafened.contains(friend.userId) {
            details.append(JS.text(.deafened))
        } else if voiceMuted.contains(friend.userId) {
            details.append(T.text(.voiceMuted))
        }
        if voiceSpeaking.contains(friend.userId) { details.append(T.text(.voiceSpeaking)) }
        return [PanelRow(id: "call-\(friend.userId)", title: T.format(callWaiting ? .callCalling : .callWith, friend.displayName),
                         detail: details.isEmpty ? "@\(friend.handle)" : details.joined(separator: " · "), symbol: "phone.fill", kind: .info(""),
                         person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: callWaiting ? nil : .online, speaking: voiceSpeaking.contains(friend.userId)))]
            + voiceControlRows()
    }

    /// Leaving the call as the app quits; nil when there is nothing to leave.
    func leaveTogetherOnQuit() -> Task<Void, Never>? {
        guard let call = voiceCall else { return nil }
        let client = together
        partyVoice?.close()
        partyVoice = nil
        return Task { _ = await client.leaveCall(call, within: .seconds(2)) }
    }

    func previewRinging(_ call: TogetherRinging?) { ringing = call }

    func previewCall(with friend: TogetherPerson, waiting: Bool, speaking: Set<String> = [], muted: Set<String> = [], deafened: Set<String> = [], deafenedHere: Bool = false) {
        voiceCall = "call-preview"
        callFriend = friend
        callWaiting = waiting
        voiceSpeaking = speaking
        voiceMuted = muted
        voiceDeafened = deafened
        mic = TogetherVoiceMic()
        if deafenedHere { mic.deafen() }
    }
}

/// A friend calling, over the launcher: who, and Answer or Decline.
struct RingingCard: View {
    let call: TogetherRinging
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @State private var pulse = false

    var body: some View {
        ZStack {
            FrostFill(opacity: 0.55).ignoresSafeArea()
            VStack(spacing: 24 * scale) {
                ZStack {
                    ForEach(0 ..< 2) { ring in
                        Circle().strokeBorder(model.accent.opacity(0.5), lineWidth: 2 * scale)
                            .frame(width: 132 * scale, height: 132 * scale)
                            .scaleEffect(pulse || previewRender ? 1.45 + Double(ring) * 0.3 : 1)
                            .opacity(pulse || previewRender ? (previewRender ? 0.35 - Double(ring) * 0.15 : 0) : 0.8)
                            .animation(Motion.reduced ? nil : .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(ring) * 0.45), value: pulse)
                    }
                    ProfileAvatar(url: call.from.avatar, name: call.from.displayName, size: 132 * scale)
                }
                .frame(height: 200 * scale)
                VStack(spacing: 8 * scale) {
                    Text(call.from.displayName).font(.display(32 * scale, .light)).foregroundStyle(.white)
                    Label(T.text(.callRinging), systemImage: "phone.arrow.down.left.fill")
                        .font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 16 * scale) {
                    ConsoleButton(title: T.text(.callDecline), symbol: "phone.down.fill", focused: false, destructive: true, minWidth: 170) { model.declineRinging() }
                    ConsoleButton(title: T.text(.callAnswer), symbol: "phone.fill", focused: true, prominent: true, minWidth: 170) { model.acceptRinging() }
                }
                .padding(.top, 6 * scale)
                HStack(spacing: 22 * scale) {
                    Hint(keys: "↩ / ✕", label: T.text(.callAnswer))
                    Hint(keys: "esc / ○", label: T.text(.callDecline))
                }
            }
            .padding(.horizontal, 64 * scale)
            .padding(.vertical, 40 * scale)
            .glass(28 * scale, opacity: 0.45)
        }
        .onAppear { pulse = true }
    }
}

/// A friend calling while a game is in front: a card at the top of the screen that stays while it
/// rings, never taking the keyboard or the mouse from the game; ⌥A answers, ⌥D declines.
@MainActor
final class RingBanner {
    static let shared = RingBanner()
    private var panel: NSPanel?
    private var activation: NSObjectProtocol?

    func show(_ call: TogetherRinging) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = TrophyBanner.size
        let top = screen.frame.maxY - screen.safeAreaInsets.top
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: false)
        panel.contentView = NSHostingView(rootView: RingToast(call: call))
        panel.orderFrontRegardless()
        // The launcher in front shows its own card instead.
        activation = activation ?? NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RingBanner.shared.hide() }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        if let activation { NotificationCenter.default.removeObserver(activation) }
        activation = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}

/// The ringing card over a game.
struct RingToast: View {
    let call: TogetherRinging
    var still = false
    @State private var shown = false
    @State private var swing = false

    /// Read so the view is drawn again in another language (its texts come from T).
    @Environment(\.languageCode) private var languageCode

    var body: some View {
        let _ = languageCode
        let visible = shown || still
        VStack {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 0.3, green: 0.8, blue: 0.45), Color(red: 0.2, green: 0.6, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                    Text(String(call.from.displayName.prefix(1)).uppercased()).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Label(T.text(.callRinging), systemImage: "phone.arrow.down.left.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.55))
                    Text(call.from.displayName).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(T.text(.callKeys)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "phone.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(red: 0.25, green: 0.75, blue: 0.4)))
                    .rotationEffect(.degrees(swing ? 12 : -12))
                    .padding(.trailing, 4)
            }
            .padding(14)
            .frame(width: 480)
            .modifier(BannerGlass(still: still))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            .offset(y: visible ? 14 : -TrophyBanner.size.height)
            .opacity(visible ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(width: TrophyBanner.size.width, height: TrophyBanner.size.height)
        .onAppear {
            guard !still else { return }
            withAnimation(Motion.reduced ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.78)) { shown = true }
            guard !Motion.reduced else { return }
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { swing = true }
        }
    }
}
