import AnyPS5Core
import AppKit
import Combine
import SwiftUI

/// Broadcasting in the launcher's panels: Settings → Broadcasting (service, key, quality,
/// microphone, badge), and on the game playing its Go live row, then how the broadcast goes and
/// Stop. The phone's PS menu starts and stops it too (the "broadcast" command).
extension AppModel {
    func makeBroadcaster() -> Broadcaster {
        let broadcaster = Broadcaster(persists: persists)
        broadcaster.relay = broadcaster.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        broadcaster.notice = { [weak self] title, detail, symbol in
            TrophyBanner.shared.notice(title, detail: detail, symbol: symbol, sounds: self?.preferences.sounds ?? false)
        }
        broadcaster.phoneTold = { [weak self] live in self?.tellPhoneBroadcast(live) }
        return broadcaster
    }

    /// Go live with the game playing, or end the broadcast.
    func toggleBroadcast() {
        let broadcaster = self.broadcaster
        if broadcaster.phase.active { return broadcaster.stop() }
        guard let running else {
            return show(TB.text(.goLiveNoGame), symbol: "dot.radiowaves.left.and.right")
        }
        guard case .success = broadcaster.endpoint() else {
            TrophyBanner.shared.notice(TB.text(.setUpFirst), detail: TB.text(.setUpFirstDetail), symbol: "dot.radiowaves.left.and.right", sounds: preferences.sounds)
            return
        }
        Sounds.shared.play(.select)
        let pid = running.app.processIdentifier
        let id = running.game.id
        Task { await broadcaster.start(pid: pid, game: id) }
    }

    /// Settings → Broadcasting, focused on its first row.
    func openBroadcastSettings() {
        open(.settings)
        panelCategory = panelCategories().firstIndex { $0.id == "broadcast" } ?? 0
        panelInRows = true
        panelRow = 0
    }

    // MARK: Settings → Broadcasting

    func broadcastSettingsRows() -> [PanelRow] {
        let broadcaster = self.broadcaster
        let settings = broadcaster.settings
        let services = BroadcastSettings.Service.allCases
        var rows: [PanelRow] = []
        if let game = running?.game ?? broadcaster.previewGame.flatMap({ id in games.first { $0.id == id } }) {
            // The microphone has its own row below.
            rows += broadcastGameRows(game).filter { $0.id != "broadcast-live-mic" }
        }
        rows.append(PanelRow(id: "broadcast-service", title: TB.text(.service), symbol: "dot.radiowaves.left.and.right",
                             kind: .choice(options: services.map { $0 == .custom ? TB.text(.serviceCustom) : $0.name }, selected: services.firstIndex(of: settings.service) ?? 0) { [weak broadcaster] index in
                                 broadcaster?.settings.service = services[index]
                             }))
        if settings.service == .custom {
            rows.append(PanelRow(id: "broadcast-server", title: TB.text(.server), detail: TB.text(.serverDetail), symbol: "server.rack",
                                 kind: .text(settings.customURL) { [weak broadcaster] text in broadcaster?.settings.customURL = text }))
        }
        let key = broadcaster.key
        rows.append(PanelRow(id: "broadcast-key", title: TB.text(.key), detail: (key.isEmpty ? TB.text(.keyNone) : BroadcastKeyStore.masked(key)) + " · " + TB.text(.keyDetail),
                             symbol: "key", kind: .action(destructive: false) { [weak self] in self?.askStreamKey() }))
        rows.append(PanelRow(id: "broadcast-paste", title: TB.text(.keyPaste), symbol: "doc.on.clipboard",
                             kind: .action(destructive: false) { [weak self] in self?.pasteStreamKey() }))
        if let page = settings.service.keyPage {
            rows.append(PanelRow(id: "broadcast-page", title: TB.text(.keyPage), detail: TB.format(.keyPageDetail, page.host ?? settings.service.name), symbol: "safari",
                                 kind: .action(destructive: false) { NSWorkspace.shared.open(page) }))
        }
        let qualities = BroadcastSettings.Quality.allCases
        rows.append(PanelRow(id: "broadcast-quality", title: TB.text(.quality), detail: TB.text(.qualityDetail), symbol: "gauge.with.dots.needle.67percent",
                             kind: .choice(options: qualities.map(\.title), selected: qualities.firstIndex(of: settings.quality) ?? 0) { [weak broadcaster] index in
                                 broadcaster?.settings.quality = qualities[index]
                             }))
        rows.append(PanelRow(id: "broadcast-mic", title: TB.text(.microphone), detail: TB.text(.microphoneDetail), symbol: "mic",
                             kind: .toggle(settings.microphone) { [weak broadcaster] on in broadcaster?.settings.microphone = on }))
        if settings.microphone {
            rows.append(PanelRow(id: "broadcast-mic-level", title: TB.text(.microphoneLevel), symbol: "slider.horizontal.3",
                                 kind: .stepper(value: settings.microphoneLevel, range: 10 ... 100, step: 10, format: { "\($0)%" }) { [weak broadcaster] value in
                                     broadcaster?.settings.microphoneLevel = value
                                 }))
        }
        rows.append(PanelRow(id: "broadcast-badge", title: TB.text(.badge), detail: TB.text(.badgeDetail), symbol: "record.circle",
                             kind: .toggle(settings.liveBadge) { [weak broadcaster] on in broadcaster?.settings.liveBadge = on }))
        rows.append(PanelRow(id: "broadcast-link", title: TB.text(.viewerLink), detail: TB.text(.viewerLinkDetail), symbol: "link",
                             kind: .text(settings.viewerLink) { [weak broadcaster] text in broadcaster?.settings.viewerLink = text }))
        rows.append(PanelRow(id: "broadcast-private", title: TB.text(.keptPrivately), symbol: "lock", kind: .info("")))
        return rows
    }

    /// The key typed into a secure field, never shown.
    func askStreamKey() {
        let alert = NSAlert()
        alert.messageText = TB.format(.keyEnter, broadcaster.serviceName)
        alert.informativeText = TB.text(.keyEnterDetail)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = broadcaster.key.isEmpty ? "live_…" : BroadcastKeyStore.masked(broadcaster.key)
        alert.accessoryView = field
        alert.addButton(withTitle: TB.text(.save))
        alert.addButton(withTitle: TB.text(.cancel))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        broadcaster.setKey(key)
        show(TB.text(.keyPasted), symbol: "key")
    }

    /// The key on the clipboard, for a controller with no keyboard at hand.
    func pasteStreamKey() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return show(TB.text(.keyClipboardEmpty), symbol: "doc.on.clipboard")
        }
        broadcaster.setKey(text)
        show(TB.text(.keyPasted), symbol: "key")
    }

    // MARK: The game playing

    /// On the game playing: Go live, or the broadcast's state, its numbers and Stop.
    func broadcastGameRows(_ game: Game) -> [PanelRow] {
        let broadcaster = self.broadcaster
        guard running?.game.id == game.id || broadcaster.previewGame == game.id else { return [] }
        let settings = broadcaster.settings
        var rows: [PanelRow] = []
        switch broadcaster.phase {
        case .off, .failed:
            if case .success = broadcaster.endpoint() {
                var detail = TB.format(.goLiveDetail, broadcaster.serviceName, settings.quality.title)
                if case .failed(let reason) = broadcaster.phase { detail = reason }
                rows.append(PanelRow(id: "broadcast-go", title: TB.format(.goLive, game.name), detail: detail, symbol: "dot.radiowaves.left.and.right",
                                     kind: .action(destructive: false) { [weak self] in self?.toggleBroadcast() }))
            } else {
                rows.append(PanelRow(id: "broadcast-setup", title: TB.text(.setUpFirst), detail: TB.text(.setUpFirstDetail), symbol: "dot.radiowaves.left.and.right",
                                     kind: .action(destructive: false) { [weak self] in self?.openBroadcastSettings() }))
            }
            return rows
        case .starting:
            rows.append(PanelRow(id: "broadcast-state", title: TB.format(.starting, broadcaster.serviceName), symbol: "antenna.radiowaves.left.and.right", kind: .info("")))
        case .reconnecting(_, let delay):
            rows.append(PanelRow(id: "broadcast-state", title: TB.format(.reconnecting, Int(delay.rounded(.up))), detail: broadcastNumbers(), symbol: "wifi.exclamationmark", kind: .info("")))
        case .live:
            rows.append(PanelRow(id: "broadcast-state", title: TB.format(.liveStats, TB.clock(broadcaster.stats.duration)), detail: broadcastNumbers(),
                                 symbol: "dot.radiowaves.left.and.right", kind: .info(TB.text(.live))))
        }
        if let link = settings.viewerURL {
            rows.append(PanelRow(id: "broadcast-copy", title: TB.text(.copyLink), detail: link.absoluteString.replacingOccurrences(of: "https://", with: ""), symbol: "link",
                                 kind: .action(destructive: false) { [weak self] in
                                     NSPasteboard.general.clearContents()
                                     NSPasteboard.general.setString(link.absoluteString, forType: .string)
                                     self?.show(TB.text(.linkCopied), symbol: "link")
                                 }))
        }
        rows.append(PanelRow(id: "broadcast-live-mic", title: TB.text(.microphone), detail: TB.text(.microphoneDetail), symbol: settings.microphone ? "mic" : "mic.slash",
                             kind: .toggle(settings.microphone) { [weak broadcaster] on in broadcaster?.settings.microphone = on }))
        rows.append(PanelRow(id: "broadcast-stop", title: TB.text(.stop), symbol: "stop.circle", kind: .action(destructive: true) { [weak self] in self?.toggleBroadcast() }))
        return rows
    }

    /// "Twitch · 4.4 Mbit/s · 0 dropped (0.0%)"
    private func broadcastNumbers() -> String {
        let stats = broadcaster.stats
        return TB.format(.stateLine, broadcaster.serviceName, TB.rate(stats.bitRate), TB.format(.dropped, stats.framesDropped, stats.droppedPercent))
    }

    // MARK: The phone

    /// The phone's PS menu shows Go live or Stop broadcast as the launcher's state changes.
    func tellPhoneBroadcast(_ on: Bool) {
        remote?.publish(.broadcast(on: on))
    }

    /// The phone's Go live and Stop broadcast: what it asks for, then what the launcher does now,
    /// in case it showed the wrong one.
    func phoneBroadcast(_ start: Bool) {
        if start != broadcaster.phase.active { toggleBroadcast() }
        // What it is now; a start under way tells the phone itself once it begins.
        tellPhoneBroadcast(broadcaster.phase.active)
    }
}
