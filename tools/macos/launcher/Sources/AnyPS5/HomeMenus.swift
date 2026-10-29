import AnyPS5Core
import AppKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// A shortcut waiting for its new key (or, with `pad`, its new chord).
struct ShortcutCapture: Equatable {
    let action: ShortcutAction
    let pad: Bool
}

// The PS button's menus (the quick menu over a game, "Close game?", the home menu), the Options
// press that pauses a game first, Create's clip and screenshot, full screen and Settings →
// Shortcuts.

extension AppModel {
    var shortcutMap: ShortcutMap { preferences.shortcuts ?? ShortcutMap() }

    /// A shortcut from a key, a chord or the phone, pressed or held.
    func shortcut(_ action: ShortcutAction, hold: Bool) {
        switch action {
        case .home:
            if hold { homeButton(hold: true) } else { _ = handle(.home) }
        case .quickMenu:
            guard running != nil, starting == nil, pairing == nil else { return }
            if NSApp.isActive && overlay == .quickMenu { resumeGame() } else if !NSApp.isActive { openGameMenu(.quickMenu) }
        case .screenshot:
            takeScreenshot()
        case .clip:
            saveClip()
        case .fullScreen:
            toggleFullScreen()
        case .previousSection:
            _ = handle(.previousGame)
        case .nextSection:
            _ = handle(.nextGame)
        }
    }

    /// PS: over a game, the quick menu (held, "Close game?"); in the launcher, back to the game
    /// or, held, the home menu; on the game's menus, back to the game.
    func homeButton(hold: Bool) {
        // At start a profile is picked first.
        if overlay == .profilePicker && profileFlow.atLaunch { return Sounds.shared.play(.bump) }
        if hold {
            guard pairing == nil, preferences.onboarded, starting == nil, fontWait == nil else { return }
            if watchCommand(.home) != nil { return }
        }
        let now = Date()
        if let last = lastHome, now.timeIntervalSince(last) < Self.toggleDebounce, now >= last { return }
        if running != nil, !NSApp.isActive {
            lastHome = now
            return openGameMenu(hold ? .closeGame : .quickMenu)
        }
        switch overlay {
        case .quickMenu, .closeGame:
            resumeGame()
        case .homeMenu:
            closeOverlay()
        default:
            if hold {
                menuIndex = 0
                open(.homeMenu)
            } else {
                togglePlaying()
            }
        }
    }

    /// The launcher in front of the game with `next` on top. The quick menu presses Options in
    /// the game first (with the setting on and a way in, GamePause), while the game still has
    /// the screen to see it.
    func openGameMenu(_ next: Overlay) {
        guard running != nil, starting == nil else { return }
        let settle = next == .quickMenu ? pauseGame() : nil
        let paused = settle != nil
        let show = { [weak self] in
            guard let self, let game = self.running?.game else { return }
            if let index = self.games.firstIndex(where: { $0.id == game.id }) { self.selected = index }
            self.pausedGame = paused
            self.menuIndex = 0
            self.bringLauncherFront()
            withAnimation(Motion.overlay) { self.overlay = next }
            Sounds.shared.play(.select)
        }
        if let settle {
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { show() }
        } else {
            show()
        }
    }

    /// Back to the game; its own pause menu, if the press opened one, stays for the player.
    func resumeGame() {
        pausedGame = false
        withAnimation(Motion.overlay) { overlay = nil }
        guard let running else { return }
        Sounds.shared.play(.select)
        lastHome = Date()
        NSApp.yieldActivation(to: running.app)
        running.app.activate()
    }

    func closeRunningGame() {
        pausedGame = false
        withAnimation(Motion.overlay) { overlay = nil }
        Sounds.shared.play(.select)
        running?.app.forceTerminate()
    }

    /// Quit AnyPS5 from the home menu: a game playing closes first.
    func quitApp() {
        if let running {
            running.app.forceTerminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
        } else {
            NSApp.terminate(nil)
        }
    }

    /// The quick menu, "Close game?" and the home menu, from the keys and the pad.
    func gameMenuCommand(_ command: Command) -> Bool {
        func move(_ delta: Int, count: Int) {
            let next = min(count - 1, max(0, menuIndex + delta))
            guard next != menuIndex else { return }
            withAnimation(Motion.focus) { menuIndex = next }
            Sounds.shared.play(.move)
        }
        switch overlay {
        case .quickMenu:
            // Resume, Game Settings, the battery and heat profiles' Undo while there is one, Close.
            let undo = quickMenuUndo != nil
            switch command {
            case .up, .left: move(-1, count: undo ? 4 : 3)
            case .down, .right: move(1, count: undo ? 4 : 3)
            case .back: resumeGame()
            case .select:
                switch menuIndex {
                case 0: resumeGame()
                case 1: open(.gameSettings)
                case 2 where undo:
                    undoPowerAdjustment()
                    withAnimation(Motion.focus) { menuIndex = 0 }
                default:
                    Sounds.shared.play(.select)
                    menuIndex = 0
                    withAnimation(Motion.overlay) { overlay = .closeGame }
                }
            default: break
            }
        case .closeGame:
            switch command {
            case .up, .left: move(-1, count: 2)
            case .down, .right: move(1, count: 2)
            case .back: resumeGame()
            case .select: if menuIndex == 1 { closeRunningGame() } else { resumeGame() }
            default: break
            }
        case .homeMenu:
            switch command {
            case .up, .left: move(-1, count: 2)
            case .down, .right: move(1, count: 2)
            case .back, .options: closeOverlay()
            case .select:
                if menuIndex == 1 {
                    Sounds.shared.play(.select)
                    quitApp()
                } else {
                    // Not while a game plays: it is closed first.
                    openProfilePicker()
                }
            default: break
            }
        case .confirmQuit:
            switch command {
            case .up, .left: move(-1, count: 2)
            case .down, .right: move(1, count: 2)
            case .back, .options: closeOverlay()
            case .select:
                if menuIndex == 1 {
                    Sounds.shared.play(.select)
                    quitApp()
                } else {
                    closeOverlay()
                }
            default: break
            }
        case .launcherReport:
            switch command {
            case .up, .left: move(-1, count: 2)
            case .down, .right: move(1, count: 2)
            case .back, .options: closeOverlay()
            case .select: menuIndex == 0 ? sendLauncherReport() : putLauncherReportAside()
            default: break
            }
        case .profileMenu:
            let items = profileMenuItems()
            switch command {
            case .up, .left: move(-1, count: items.count)
            case .down, .right: move(1, count: items.count)
            case .back, .options: closeOverlay()
            case .select:
                guard items.indices.contains(menuIndex) else { return true }
                Sounds.shared.play(.select)
                runProfileMenu(items[menuIndex].action)
            default: break
            }
        default:
            return false
        }
        return true
    }

    // MARK: Pausing the game

    /// One Options press on the game's first player (GamePause); the seconds until the game has
    /// seen it, nil when none went.
    private func pauseGame() -> Double? {
        guard let remote else { return nil }
        let pressBridge = remote.pressBridge
        let free = pauseBridge.map { remote.padChannelOpen(bridge: $0) } ?? true
        let route = GamePause.route(enabled: preferences.pauseOnMenu ?? true, takesPresses: pressBridge != nil, controllers: Controllers.shared.pads.count,
                                    phonePlayers: Array(phonePlayers.values), channelFree: free)
        if route == .press, let pressBridge {
            pausePress &+= 1
            for (packet, at) in zip(GamePause.pressPackets(id: pausePress), GamePause.pressRepeats) {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { remote.sendPress(packet, bridge: pressBridge) }
            }
            return GamePause.settle(.press)
        }
        guard route == .send else {
            RemoteServer.log.info("pause before the quick menu: \(String(describing: route), privacy: .public)")
            return nil
        }
        guard let bridge = pauseBridge ?? remote.reservePadBridge() else { return nil }
        guard remote.padChannelOpen(bridge: bridge) else {
            remote.releasePadBridge(bridge)
            pauseBridge = nil
            RemoteServer.log.info("pause before the quick menu: the game has no remote pad channel")
            return nil
        }
        pauseBridge = bridge
        let packets = GamePause.packets(session: pauseSession, firstSequence: pauseSequence)
        pauseSequence &+= UInt32(packets.count)
        for (packet, step) in zip(packets, GamePause.press) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.at) { remote.sendPad(packet, bridge: bridge) }
        }
        // The engine gives the pad's player back after five silent seconds; the channel goes back then.
        pauseRelease?.cancel()
        pauseRelease = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, let bridge = self.pauseBridge else { return }
            self.remote?.releasePadBridge(bridge)
            self.pauseBridge = nil
        }
        return GamePause.settle(.send)
    }

    // MARK: Create: clips and screenshots

    /// Create held (or Screenshot's shortcut): the game's picture as it is now, beside its clips
    /// in the gallery.
    func takeScreenshot() {
        guard let game = running?.game, let pid = running?.app.processIdentifier else { return }
        guard familyAllows(.mediaSharing) else { return TrophyBanner.shared.notice(FS.refusal(.mediaSharing), detail: "", symbol: "hand.raised.fill", sounds: preferences.sounds) }
        let folder = screenshotsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(game.titleID)-\(Self.captureStamp()).png")
        Task { @MainActor in
            do {
                try await Self.screenshot(pid: pid, to: file)
                Sounds.shared.play(.select)
                TrophyBanner.shared.notice(TH.text(.screenshotSaved), detail: file.lastPathComponent, symbol: "camera.fill", sounds: false)
            } catch ClipRecorder.Failure.noPermission {
                TrophyBanner.shared.notice(T.text(.clipsNeedPermission), detail: T.text(.clipsNeedPermissionDetail), symbol: "camera", sounds: self.preferences.sounds)
            } catch {
                TrophyBanner.shared.notice(TH.text(.screenshotFailed), detail: "\(error)", symbol: "exclamationmark.triangle.fill", sounds: self.preferences.sounds)
            }
        }
    }

    /// The name a capture takes after the title ID, as the clips' and the engine's screenshots.
    static func captureStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// The game's window without its title bar, through ScreenCaptureKit, as a PNG.
    static func screenshot(pid: pid_t, to file: URL) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ClipRecorder.Failure.noPermission
        }
        guard let app = content.applications.first(where: { $0.processID == pid }),
              let window = ClipRecorder.mainWindow(of: pid, in: content),
              let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else { throw ClipRecorder.Failure.noWindow }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let configuration = ClipRecorder.configuration(window: window, display: display, scale: CGFloat(filter.pointPixelScale), maxWidth: .max, maxHeight: .max, queueDepth: 3)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ClipRecorder.Failure.nothingRecorded }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipRecorder.Failure.nothingRecorded }
    }

    // MARK: Full screen

    var mainWindow: NSWindow? { NSApp?.windows.first { !($0 is NSPanel) && $0.canBecomeMain } }

    /// The window is full screen now (offscreen, the saved choice).
    var isFullScreen: Bool {
        guard let window = mainWindow else { return preferences.fullScreen ?? true }
        return window.styleMask.contains(.fullScreen)
    }

    func toggleFullScreen() {
        mainWindow?.toggleFullScreen(nil)
    }

    /// Every switch, from the setting, F11, ⌃⌘F or the green button, is the choice the next start keeps.
    func watchFullScreen() {
        for (name, value) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow, window === self.mainWindow else { return }
                    if self.preferences.fullScreen != value { self.preferences.fullScreen = value }
                    self.objectWillChange.send()
                }
            }
        }
    }

    // MARK: Settings → Shortcuts

    func shortcutRows() -> [PanelRow] {
        let map = shortcutMap
        var rows = [PanelRow(id: "shortcutsIntro", title: TH.text(.shortcutsIntro), kind: .info(""), wraps: true)]
        for action in ShortcutAction.allCases {
            let binding = map.binding(action)
            let conflicts = map.conflicts(of: action)
            let keyConflict = conflicts.first { conflict in
                switch conflict {
                case .samePad, .navigationButton: return false
                default: return true
                }
            }
            let padConflict = conflicts.first { conflict in
                switch conflict {
                case .samePad, .navigationButton: return true
                default: return false
                }
            }
            let keyLine = action.worksInGame ? TH.text(.keyboard) + " · " + TH.text(.inGameToo) : TH.text(.keyboard)
            rows.append(PanelRow(id: "shortcut-key-\(action.rawValue)", title: TH.name(action),
                                 detail: keyConflict.map { TH.conflict($0, for: action) } ?? keyLine, symbol: "keyboard",
                                 kind: .keys(binding.key.map { [$0.display] } ?? [], capturing: shortcutCapture == ShortcutCapture(action: action, pad: false)) { [weak self] in
                                     self?.startShortcutCapture(action, pad: false)
                                 }))
            rows.append(PanelRow(id: "shortcut-pad-\(action.rawValue)", title: TH.name(action),
                                 detail: padConflict.map { TH.conflict($0, for: action) } ?? TH.text(.controller), symbol: "gamecontroller",
                                 kind: .keys(binding.pad.map { [TH.chord($0)] } ?? [], capturing: shortcutCapture == ShortcutCapture(action: action, pad: true)) { [weak self] in
                                     self?.startShortcutCapture(action, pad: true)
                                 }))
        }
        rows.append(PanelRow(id: "shortcutsReset", title: TH.text(.resetShortcuts), detail: TH.text(.resetShortcutsDetail), symbol: "arrow.counterclockwise",
                             kind: .action(destructive: false) { [weak self] in
                                 guard let self else { return }
                                 self.preferences.shortcuts = nil
                                 self.show(TH.text(.shortcutsReset), symbol: "command")
                             }))
        rows.append(PanelRow(id: "gameButtons", title: TH.text(.gameButtons), detail: TH.text(.gameButtonsDetail), symbol: "circle.grid.cross",
                             kind: .action(destructive: false) { [weak self] in
                                 guard let self else { return }
                                 guard self.selectedGame != nil else { return self.show(TH.text(.gameButtonsNoGame), symbol: "gamecontroller") }
                                 self.open(.controls)
                             }))
        return rows
    }

    /// The row waits for a key (Esc cancels, ⌫ clears) or a chord (○ alone cancels, △ alone clears).
    func startShortcutCapture(_ action: ShortcutAction, pad: Bool) {
        shortcutCapture = ShortcutCapture(action: action, pad: pad)
        chordRecorder = ChordRecorder()
        Sounds.shared.play(.select)
        Input.shared.capture = { [weak self] event in
            guard let self, event.type == .keyDown else { return true }
            let plain = Input.modifiers(event.modifierFlags).isEmpty
            if event.keyCode == KeyChord.escape && plain {
                self.endShortcutCapture()
                Sounds.shared.play(.back)
            } else if event.keyCode == KeyChord.backspace && plain {
                self.assignShortcut(action, key: nil, pad: nil, clear: true)
            } else if !pad, let chord = Input.chord(of: event) {
                self.assignShortcut(action, key: chord, pad: nil, clear: false)
            }
            return true
        }
        Input.shared.padCapture = { [weak self] pressed, time in
            guard let self, var recorder = self.chordRecorder else { return }
            let chord = recorder.update(pressed, at: time)
            self.chordRecorder = recorder
            guard let chord else { return }
            if chord.set == [.east] && !chord.hold {
                self.endShortcutCapture()
                Sounds.shared.play(.back)
            } else if chord.set == [.north] && !chord.hold {
                self.assignShortcut(action, key: nil, pad: nil, clear: true)
            } else if pad {
                self.assignShortcut(action, key: nil, pad: chord, clear: false)
            }
        }
    }

    func endShortcutCapture() {
        shortcutCapture = nil
        chordRecorder = nil
        Input.shared.capture = nil
        Input.shared.padCapture = nil
    }

    /// The new key or chord, refused when it clashes (the old one stays); `clear` takes the
    /// binding of the row's input away.
    private func assignShortcut(_ action: ShortcutAction, key: KeyChord?, pad: PadChord?, clear: Bool) {
        let forPad = shortcutCapture?.pad ?? false
        endShortcutCapture()
        var candidate = shortcutMap
        if forPad { candidate.setPad(clear ? nil : pad, for: action) } else { candidate.setKey(clear ? nil : key, for: action) }
        if let conflict = candidate.conflicts(of: action).first {
            Sounds.shared.play(.bump)
            return show(TH.format(.refused, TH.conflict(conflict, for: action)), symbol: "exclamationmark.triangle.fill")
        }
        preferences.shortcuts = candidate.isDefault ? nil : candidate
        Sounds.shared.play(.select)
        if clear { show(TH.format(.cleared, TH.name(action)), symbol: "command") }
    }

    /// △ on a shortcut's row clears it.
    func clearShortcut(row id: String) -> Bool {
        for action in ShortcutAction.allCases {
            if id == "shortcut-key-\(action.rawValue)" || id == "shortcut-pad-\(action.rawValue)" {
                var candidate = shortcutMap
                if id.hasPrefix("shortcut-pad-") { candidate.setPad(nil, for: action) } else { candidate.setKey(nil, for: action) }
                preferences.shortcuts = candidate.isDefault ? nil : candidate
                Sounds.shared.play(.back)
                show(TH.format(.cleared, TH.name(action)), symbol: "command")
                return true
            }
        }
        return false
    }
}

// MARK: The menus

/// The quick menu, "Close game?" and the home menu: a card over the frosted launcher, its items
/// in a column the focus moves down.
struct GameMenuCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @ObservedObject private var inputMode = InputModeState.shared
    @State private var shown = false

    private struct Item: Identifiable {
        let id: Int
        let title: String
        var detail: String?
        let symbol: String
        var destructive = false
        var disabled = false
    }

    var body: some View {
        let game = model.overlay == .homeMenu || model.overlay == .profileMenu || model.overlay == .confirmQuit || model.overlay == .launcherReport ? nil : (model.selectedGame ?? model.runningGame)
        ZStack {
            FrostFill(opacity: 0.6).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { _ = model.gameMenuCommand(.back) }
            VStack(alignment: .leading, spacing: 0) {
                header(game)
                    .padding(.bottom, 26 * scale)
                VStack(spacing: 10 * scale) {
                    ForEach(items(game)) { item in
                        row(item)
                    }
                }
                hints
                    .padding(.top, 28 * scale)
            }
            .padding(.horizontal, 40 * scale)
            .padding(.vertical, 36 * scale)
            .frame(width: (model.overlay == .closeGame ? 560 : 520) * scale)
            .glass(30 * scale, opacity: 0.5)
            .overlay(alignment: .top) {
                // The accent edge the console's cards wear: which game the menu is about.
                Capsule().fill(model.accent).frame(width: 64 * scale, height: 4 * scale).padding(.top, 12 * scale).opacity(0.85)
            }
            .shadow(color: .black.opacity(0.45), radius: 40 * scale, y: 18 * scale)
            .scaleEffect(shown || previewRender || Motion.reduced ? 1 : 0.96)
            .opacity(shown || previewRender ? 1 : 0)
        }
        .onAppear {
            withAnimation(Motion.reduced ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.78)) { shown = true }
        }
    }

    @ViewBuilder private func header(_ game: Game?) -> some View {
        HStack(alignment: .center, spacing: 18 * scale) {
            if model.overlay == .homeMenu || model.overlay == .profileMenu || model.overlay == .confirmQuit {
                ProfileTileAvatar(profile: model.currentProfile, picture: model.profilePicture, size: 64 * scale)
            } else if model.overlay == .launcherReport {
                // The launcher's own trouble: its mark, not a game's.
                ZStack {
                    RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color(red: 1, green: 0.62, blue: 0.3).opacity(0.16))
                    Image(systemName: model.launcherReport?.problem.kind == .crash ? "bolt.trianglebadge.exclamationmark.fill" : "hourglass")
                        .font(.system(size: 28 * scale, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.4))
                }
                .frame(width: 64 * scale, height: 64 * scale)
                .shadow(color: Color(red: 1, green: 0.55, blue: 0.25).opacity(0.35), radius: 18 * scale)
            } else if let game {
                ZStack {
                    RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(0.08))
                    if let icon = game.icon {
                        ArtworkImage(url: icon, maxPixels: 400)
                    } else {
                        Image(systemName: "gamecontroller.fill").font(.system(size: 26 * scale)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 72 * scale, height: 72 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
                .shadow(color: model.accent.opacity(0.4), radius: 18 * scale)
            }
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(kicker.uppercased())
                    .font(.display(12 * scale, .semibold)).tracking(1.6 * scale)
                    .foregroundStyle(model.accent)
                Text(title(game))
                    .font(.display(model.overlay == .closeGame ? 28 * scale : 30 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                status(game)
            }
        }
    }

    private var kicker: String {
        switch model.overlay {
        case .closeGame: return TH.text(.closeGame)
        case .homeMenu, .confirmQuit: return TH.text(.homeMenuKicker)
        case .profileMenu: return TPro.text(.menuKicker)
        case .launcherReport: return TC.text(.launcherReportWhen)
        default: return TH.text(.quickMenuKicker)
        }
    }

    private func title(_ game: Game?) -> String {
        switch model.overlay {
        case .closeGame: return TH.format(.closeGameTitle, game?.name ?? "")
        case .homeMenu, .profileMenu: return model.currentProfile?.name ?? model.preferences.profileName
        case .confirmQuit: return TH.text(.quitQuestion)
        case .launcherReport: return model.launcherReport?.headline ?? ""
        default: return game?.name ?? ""
        }
    }

    @ViewBuilder private func status(_ game: Game?) -> some View {
        switch model.overlay {
        case .quickMenu:
            HStack(spacing: 8 * scale) {
                if model.pausedGame {
                    Label(TH.text(.paused), systemImage: "pause.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.display(12 * scale, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(Capsule().fill(model.accent.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(model.accent.opacity(0.8), lineWidth: 1))
                } else {
                    Circle().fill(Color(red: 0.3, green: 0.85, blue: 0.45)).frame(width: 7 * scale, height: 7 * scale)
                    Text(TH.text(.stillRunning))
                }
                if let since = model.sessionStart {
                    Text("·")
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(Self.clock(context.date.timeIntervalSince(since))).monospacedDigit()
                    }
                }
            }
            .font(.display(13 * scale, .medium))
            .foregroundStyle(.white.opacity(0.7))
            powerLine
        case .closeGame:
            Text(TH.text(.closeGameText)).font(.display(14 * scale)).foregroundStyle(.white.opacity(0.65))
        case .homeMenu, .profileMenu:
            let online = model.currentProfile?.mode == .online
            Label(online ? (model.togetherUser.map { "@\($0.handle)" } ?? TPro.text(.online)) : TPro.text(.offline),
                  systemImage: online ? "person.2.wave.2.fill" : "wifi.slash")
                .font(.display(13 * scale, .medium)).foregroundStyle(.white.opacity(0.65))
        default:
            EmptyView()
        }
    }

    /// The battery and what the battery and heat profiles do now: "On battery · 64% · about 2 h
    /// left · Battery profile · 40 FPS cap". A Mac without a battery shows it only while hot.
    @ViewBuilder private var powerLine: some View {
        let reading = model.power.reading
        if reading.hasBattery || model.power.mode == .hot {
            let hot = model.power.mode == .hot
            let warm = Color(red: 1, green: 0.62, blue: 0.3)
            HStack(alignment: .firstTextBaseline, spacing: 7 * scale) {
                Image(systemName: hot ? "thermometer.sun.fill" : reading.onBattery ? "battery.75percent" : "powerplug.fill")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(hot ? warm : .white.opacity(0.7))
                    .frame(width: 18 * scale)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    if reading.hasBattery {
                        Text(model.powerSourceLine).monospacedDigit()
                    }
                    Text(model.powerProfileLine)
                        .foregroundStyle(hot ? warm : model.power.adjustment.isNone ? .white.opacity(0.5) : model.accent)
                }
                .lineLimit(1).minimumScaleFactor(0.85)
            }
            .font(.display(12.5 * scale, .medium))
            .foregroundStyle(.white.opacity(0.66))
            .padding(.top, 2 * scale)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }

    private func items(_ game: Game?) -> [Item] {
        switch model.overlay {
        case .closeGame:
            return [Item(id: 0, title: T.text(.cancel), symbol: "arrow.uturn.backward"),
                    Item(id: 1, title: TH.text(.closeGame), symbol: "xmark.circle.fill", destructive: true)]
        case .homeMenu:
            let others = model.profileBook.profiles.count - 1
            return [Item(id: 0, title: TH.text(.switchProfile), detail: TPro.others(others), symbol: "person.2.circle"),
                    Item(id: 1, title: TH.text(.quitApp), detail: model.runningGame.map { TH.format(.quitWithGame, $0.name) }, symbol: "power", destructive: true)]
        case .confirmQuit:
            return [Item(id: 0, title: T.text(.cancel), detail: TH.text(.quitStay), symbol: "arrow.uturn.backward"),
                    Item(id: 1, title: TH.text(.quitApp), detail: model.runningGame.map { TH.format(.quitWithGame, $0.name) }, symbol: "power", destructive: true)]
        case .launcherReport:
            return [Item(id: 0, title: TC.text(.launcherReportSend), detail: TC.text(.launcherReportSendDetail), symbol: "paperplane.fill"),
                    Item(id: 1, title: TC.text(.launcherReportLater), detail: TC.text(.launcherReportLaterDetail), symbol: "clock.arrow.circlepath")]
        case .profileMenu:
            return model.profileMenuItems().map { Item(id: $0.id, title: $0.title, detail: $0.detail, symbol: $0.symbol) }
        default:
            var items = [Item(id: 0, title: TH.text(.resume), symbol: "play.fill"),
                         Item(id: 1, title: T.text(.gameSettings), symbol: "slider.horizontal.3")]
            if let undo = model.quickMenuUndo {
                items.append(Item(id: 2, title: undo.title, detail: undo.detail, symbol: "arrow.uturn.backward"))
            }
            items.append(Item(id: items.count, title: TH.text(.closeGame), symbol: "xmark.circle", destructive: true))
            return items
        }
    }

    private func row(_ item: Item) -> some View {
        let focused = model.menuIndex == item.id
        // Focused, a destructive item turns red rather than white: what X does here cannot be undone.
        let danger = focused && item.destructive
        let foreground: Color = danger ? .white : focused ? .black : (item.destructive ? Color(red: 1, green: 0.6, blue: 0.55) : .white)
        return Button {
            model.menuIndex = item.id
            _ = model.gameMenuCommand(.select)
        } label: {
            HStack(spacing: 14 * scale) {
                Image(systemName: item.symbol).font(.system(size: 17 * scale, weight: .semibold)).frame(width: 24 * scale)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(item.title).font(.display(18 * scale, .semibold))
                    if let detail = item.detail {
                        Text(detail).font(.display(12.5 * scale)).opacity(0.6)
                    }
                }
                Spacer(minLength: 0)
                if focused && !item.disabled {
                    Image(systemName: "chevron.right").font(.system(size: 13 * scale, weight: .bold)).opacity(0.5)
                }
            }
            .foregroundStyle(foreground.opacity(item.disabled ? 0.45 : 1))
            .padding(.horizontal, 20 * scale)
            // A detail of several lines keeps clear of the row's edges.
            .padding(.vertical, 10 * scale)
            .frame(maxWidth: .infinity, minHeight: 56 * scale)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                if danger {
                    shape.fill(Color(red: 0.86, green: 0.25, blue: 0.24))
                } else {
                    FocusFill(shape, focused: focused, idle: Color.white.opacity(0.07))
                }
            }
            .shadow(color: (danger ? Color(red: 1, green: 0.3, blue: 0.28) : .white).opacity(focused ? 0.25 : 0), radius: 12 * scale)
            .scaleEffect(focused ? 1.02 : 1)
            .animation(Motion.focus, value: focused)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTick("menu-\(item.id)")
        .accessibilityLabel(item.title)
    }

    private var hints: some View {
        HStack(spacing: 20 * scale) {
            Hint(keys: "↑ ↓", label: T.text(.hintMove))
            Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
            Spacer(minLength: 0)
            if model.overlay == .homeMenu || model.overlay == .profileMenu || model.overlay == .confirmQuit || model.overlay == .launcherReport {
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            } else {
                Hint(keys: "PS / esc / ○", label: TH.text(.resume))
            }
        }
    }
}

extension AppModel {
    /// The game playing, whichever game the home screen has selected.
    var runningGame: Game? { running?.game }
}

extension AppModel {
    /// The PS menus take every command while one is up.
    func gameMenuCommandIfOpen(_ command: Command) -> Bool? {
        switch overlay {
        case .quickMenu, .closeGame, .homeMenu, .profileMenu, .confirmQuit, .launcherReport: return gameMenuCommand(command)
        default: return nil
        }
    }
}
