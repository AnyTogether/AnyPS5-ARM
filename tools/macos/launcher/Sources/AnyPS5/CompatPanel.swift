import AnyPS5Core
import AppKit
import SwiftUI

/// Community compatibility on AnyTogether: after a session, an optional one-tap "How did it run?"
/// that reports the status with the launcher and engine versions and the Mac model; the game's
/// info shows what the community found.
extension AppModel {
    private static let askedKey = "AnyPS5.compatAsked"
    private static let neverKey = "AnyPS5.compatNever"

    /// After a session: asks once per game and launcher version, unless turned off.
    func askHowItRan(_ game: Game, played seconds: TimeInterval) {
        guard persists, togetherUser != nil, !UserDefaults.standard.bool(forKey: Self.neverKey) else { return }
        let asked = UserDefaults.standard.dictionary(forKey: Self.askedKey) as? [String: String] ?? [:]
        guard TogetherCompatPrompt.shouldAsk(titleId: game.titleID, played: seconds, launcherVersion: Self.runningVersion, asked: asked) else { return }
        // Once the launcher is back in front, and only over the home screen.
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard overlay == nil, starting == nil, running == nil else { return }
            openCompat(game)
        }
    }

    func openCompat(_ game: Game) {
        guard togetherUser != nil else { return }
        var asked = UserDefaults.standard.dictionary(forKey: Self.askedKey) as? [String: String] ?? [:]
        asked[game.titleID] = Self.runningVersion
        if persists { UserDefaults.standard.set(asked, forKey: Self.askedKey) }
        social.compatGame = game
        open(.compat)
        panelInRows = true
        panelRow = 0
    }

    var compatTitle: String { TS.format(.compatAsk, social.compatGame?.name ?? "") }

    func compatRows() -> [PanelRow] {
        guard let game = social.compatGame else { return [] }
        var rows = TogetherCompatStatus.allCases.reversed().map { status in
            PanelRow(id: "compat-\(status.rawValue)", title: Self.compatName(status), detail: Self.compatDetail(status), symbol: Self.compatSymbol(status),
                     kind: .action(destructive: false) { [weak self] in self?.reportCompat(game, status) })
        }
        rows.append(PanelRow(id: "compat-later", title: TS.text(.compatLater), symbol: "clock", kind: .action(destructive: false) { [weak self] in self?.closeOverlay() }))
        rows.append(PanelRow(id: "compat-never", title: TS.text(.compatNever), detail: TS.text(.compatNeverDetail), symbol: "bell.slash",
                             kind: .toggle(UserDefaults.standard.bool(forKey: Self.neverKey)) { [weak self] value in
                                 if self?.persists == true { UserDefaults.standard.set(value, forKey: Self.neverKey) }
                                 self?.objectWillChange.send()
                             }))
        rows.append(PanelRow(id: "compat-what", title: TS.text(.compatWhat), detail: compatSent(game), symbol: "info.circle", kind: .info("")))
        return rows
    }

    /// What goes with the report, said plainly.
    private func compatSent(_ game: Game) -> String {
        [Self.runningVersion, engineVersion(game), Self.machineModel, Self.osName].compactMap { $0 }.joined(separator: " · ")
    }

    private func engineVersion(_ game: Game) -> String? { installedRecords[game.id]?.toolkit ?? engineVersion(for: game) }

    static var osName: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
    }

    func reportCompat(_ game: Game, _ status: TogetherCompatStatus) {
        closeOverlay()
        let report = TogetherCompatReport(titleId: game.titleID, name: game.name, status: status, launcherVersion: Self.runningVersion,
                                          engineVersion: engineVersion(game), machine: Self.machineModel, os: Self.osName, gameVersion: game.version)
        Task {
            do {
                let summary = try await together.reportCompat(report)
                if let summary { social.compat[game.titleID] = .some(summary) }
                show(TS.text(.compatThanks), symbol: "checkmark.seal.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The community's status for a game, read once (signed in only).
    func loadCompat(_ titleId: String) {
        guard togetherUser != nil, social.compat[titleId] == nil else { return }
        social.compat[titleId] = .some(nil)
        Task {
            do {
                social.compat[titleId] = .some(try await together.compat(titleId)?.mac)
            } catch {
                // Asked again next time.
                social.compat[titleId] = nil
            }
        }
    }

    func compatSummary(_ titleId: String) -> TogetherCompatSummary? { social.compat[titleId] ?? nil }

    /// "In game · 0.2.14 · 7 reports".
    func compatText(_ summary: TogetherCompatSummary) -> String {
        [summary.status.map(Self.compatName) ?? summary.statusName, summary.version, TS.format(.compatReports, summary.reports)].joined(separator: " · ")
    }

    static func compatName(_ status: TogetherCompatStatus) -> String {
        switch status {
        case .nothing: return TS.text(.compatNothing)
        case .boots: return TS.text(.compatBoots)
        case .menus: return TS.text(.compatMenus)
        case .ingame: return TS.text(.compatIngame)
        case .playable: return TS.text(.compatPlayable)
        }
    }

    static func compatDetail(_ status: TogetherCompatStatus) -> String {
        switch status {
        case .nothing: return TS.text(.compatNothingDetail)
        case .boots: return TS.text(.compatBootsDetail)
        case .menus: return TS.text(.compatMenusDetail)
        case .ingame: return TS.text(.compatIngameDetail)
        case .playable: return TS.text(.compatPlayableDetail)
        }
    }

    static func compatSymbol(_ status: TogetherCompatStatus) -> String {
        switch status {
        case .nothing: return "xmark.octagon"
        case .boots: return "power"
        case .menus: return "list.bullet.rectangle"
        case .ingame: return "gamecontroller"
        case .playable: return "checkmark.seal"
        }
    }

    static func compatColor(_ status: TogetherCompatStatus?) -> Color {
        switch status {
        case .nothing: return Color(red: 1, green: 0.45, blue: 0.45)
        case .boots: return Color(red: 1, green: 0.62, blue: 0.35)
        case .menus: return Color(red: 1, green: 0.84, blue: 0.4)
        case .ingame: return Color(red: 0.48, green: 0.78, blue: 1)
        case .playable: return Color(red: 0.45, green: 0.9, blue: 0.6)
        case nil: return .white.opacity(0.6)
        }
    }

    func previewCompat(_ game: Game?, row: Int = 1) {
        social.compatGame = game
        overlay = .compat
        panelInRows = true
        panelRow = row
    }
}

/// The game's info card for the community's status; nothing until there is one.
struct CommunityCard: View {
    let game: Game
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        Group {
            if let summary = model.compatSummary(game.titleID) {
                InfoCard(title: TS.text(.compatCommunity), symbol: "person.3.sequence") {
                    HStack(spacing: 8 * scale) {
                        Circle().fill(AppModel.compatColor(summary.status)).frame(width: 9 * scale, height: 9 * scale)
                        Text(summary.status.map(AppModel.compatName) ?? summary.statusName)
                            .font(.display(17 * scale, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(summary.version).font(.display(13 * scale, .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                }
                .transition(.opacity)
            }
        }
        // Asked once the selection rests on the game, not for every game a held direction passes.
        .task(id: game.titleID) {
            try? await Task.sleep(for: AppModel.selectionSettle)
            if !Task.isCancelled { model.loadCompat(game.titleID) }
        }
    }
}
