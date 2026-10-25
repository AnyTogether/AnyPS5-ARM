import AnyPS5Core
import AppKit
import SwiftUI

/// The system fonts games get: the Noto fonts inside the app, the Japanese, Chinese and Korean
/// ones downloaded the first time a game needs them, and the user's own folder before both.
///
/// How the launcher knows a game needs Japanese, Chinese or Korean: a game started in one of those
/// languages surely does, so its start waits for the download. Any other game says so itself: the
/// engine logs every font set a game opens (`fontSetType=0x…`), whether a file was found for it or
/// not, and the launcher reads that while the game runs. A game that opened a set with Japanese,
/// Chinese or Korean in it is remembered, the download begins at once (links in the game's font
/// folder let the running game have the fonts for the sets it opens later) and its next start
/// waits for it. The game's region says too little: most games open those sets whatever the
/// region, for names, and many Asian releases play in English.
extension AppModel {
    /// Console languages whose text needs the Japanese, Chinese and Korean fonts.
    static let cjkLanguages: Set<Int> = [0, 9, 10, 11]

    var systemFonts: SystemFonts {
        SystemFonts(user: fontsFolder, downloaded: fontDownloads.folder, builtIn: builtInFonts)
    }

    var cjkDownloadSize: String { ByteCountFormatter.string(fromByteCount: fontDownloads.package.size, countStyle: .file) }

    /// The folder of links a game gets as ANYPS5_SYSTEM_FONTS; nil without any fonts at all.
    func gameFontsFolder() -> URL? {
        do {
            return try systemFonts.assemble(in: gameFonts)
        } catch {
            // Links that cannot be made: the user's folder alone, as before.
            return fontsFolder
        }
    }

    func needsCJK(_ game: Game) -> Bool {
        let language = settings(for: game).language ?? preferences.language.consoleLanguage
        return AppModel.cjkLanguages.contains(language) || preferences.cjkGames?.contains(game.titleID) == true
    }

    /// Before a start: a game that needs the Japanese, Chinese and Korean fonts waits for them.
    func ensureFonts(_ game: Game, then: @escaping @MainActor () -> Void) {
        guard persists, needsCJK(game), !cjkInstalled else { return then() }
        withAnimation(Motion.overlay) { fontWait = game }
        downloadCJK { [weak self] _ in
            guard let self, self.fontWait?.id == game.id else { return }
            withAnimation(Motion.overlay) { self.fontWait = nil }
            then()
        }
    }

    /// Back on the wait: the game does not start; the download goes on.
    func cancelFontWait() {
        guard fontWait != nil else { return }
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { fontWait = nil }
    }

    /// Downloads the Japanese, Chinese and Korean fonts once; `done` hears whether they came.
    func downloadCJK(_ done: (@MainActor (Bool) -> Void)? = nil) {
        if let done { cjkWaiters.append(done) }
        guard persists, cjkProgress == nil else { return }
        if cjkInstalled { return finishCJK(nil) }
        cjkProgress = 0
        let downloads = fontDownloads
        let gate = ProgressGate()
        Task.detached(priority: .utility) {
            let failure: Error?
            do {
                try await downloads.install { fraction in
                    guard gate.passes(fraction) else { return }
                    Task { @MainActor in if self.cjkProgress != nil { self.cjkProgress = fraction } }
                }
                failure = nil
            } catch {
                failure = error
            }
            await MainActor.run { self.finishCJK(failure) }
        }
    }

    private func finishCJK(_ failure: Error?) {
        cjkProgress = nil
        cjkInstalled = fontDownloads.installed
        if let failure {
            show(TF.format(.failed, failure.localizedDescription), symbol: "exclamationmark.triangle.fill")
        } else if let running {
            // The game playing gets them for the sets it opens from now on; all of them next time.
            if gameFontsFolder() != nil, !NSApp.isActive {
                TrophyBanner.shared.notice(TF.text(.ready), detail: TF.format(.readyRestart, running.game.name), symbol: "textformat", sounds: preferences.sounds)
            }
            show(TF.format(.readyRestart, running.game.name), symbol: "textformat")
        } else if fontWait == nil {
            show(TF.text(.ready), symbol: "textformat")
        }
        let waiters = cjkWaiters
        cjkWaiters = []
        for waiter in waiters { waiter(failure == nil) }
    }

    func removeCJK() {
        guard cjkProgress == nil else { return }
        try? fontDownloads.remove()
        cjkInstalled = fontDownloads.installed
        _ = gameFontsFolder()
        show(TF.text(.cjkRemoved), symbol: "trash")
    }

    // MARK: What the game asked for

    /// Where this start's lines begin in the game's log.
    func markFontLog(of game: Game, at offset: UInt64) {
        fontLogOffsets[game.id] = offset
    }

    /// Reads the font sets the game opened every few seconds while it runs (most open theirs at
    /// start), off the main thread.
    func watchFonts(_ game: Game) {
        fontWatch?.cancel()
        guard persists, let offset = fontLogOffsets[game.id] else { return }
        let file = AppModel.logFile(for: game)
        fontWatch = Task.detached(priority: .utility) {
            for _ in 0..<45 {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { return }
                if AppModel.asksForCJK(file, from: offset) {
                    await MainActor.run { self.gameAskedForCJK(game) }
                    return
                }
            }
        }
    }

    /// Once more when the game ends: a game that stopped at start shows it only now.
    func checkFontsAfterEnd(_ game: Game) {
        fontWatch?.cancel()
        fontWatch = nil
        guard persists, let offset = fontLogOffsets.removeValue(forKey: game.id) else { return }
        let file = AppModel.logFile(for: game)
        Task.detached(priority: .utility) {
            guard AppModel.asksForCJK(file, from: offset) else { return }
            await MainActor.run { self.gameAskedForCJK(game) }
        }
    }

    /// Whether the log from `offset` on shows a font set with Japanese, Chinese or Korean in it.
    nonisolated static func asksForCJK(_ file: URL, from offset: UInt64) -> Bool {
        SystemFontSet.scripts(inLog: logText(file, from: offset)).contains(where: \.isCJK)
    }

    /// The first time: the game is remembered (its next start waits for the fonts) and they begin
    /// downloading.
    func gameAskedForCJK(_ game: Game) {
        fontLogOffsets[game.id] = nil
        if preferences.cjkGames?.contains(game.titleID) != true {
            preferences.cjkGames = (preferences.cjkGames ?? []) + [game.titleID]
        }
        if !cjkInstalled && cjkProgress == nil {
            show(TF.format(.neededDownloading, game.name), symbol: "arrow.down.circle")
            downloadCJK()
        }
    }

    /// The log from `offset` on, at most 16 MB of it.
    nonisolated static func logText(_ file: URL, from offset: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        guard end > offset else { return "" }
        try? handle.seek(toOffset: max(offset, end > 16 << 20 ? end - (16 << 20) : 0))
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }

    // MARK: Settings → Fonts

    /// A font as the rows name it: the family for Noto, the file for the console's own.
    static func fontName(_ file: String) -> String {
        let base = (file as NSString).deletingPathExtension
        let families = ["NotoSansCJK": "Noto Sans CJK", "NotoSansMono": "Noto Sans Mono", "NotoSansThai": "Noto Sans Thai",
                        "NotoSansArabic": "Noto Sans Arabic", "NotoSans": "Noto Sans"]
        if let family = families.keys.sorted(by: { $0.count > $1.count }).first(where: { base.hasPrefix($0 + "-") }) { return families[family]! }
        return TF.format(.console, base)
    }

    static func describe(_ pick: SystemFonts.Pick?) -> String {
        guard let pick else { return TF.text(.none) }
        let name = fontName(pick.file)
        switch pick.source {
        case .builtIn: return TF.format(.builtIn, name)
        case .downloaded: return TF.format(.downloaded, name)
        case .user: return TF.format(.yourFolder, name)
        }
    }

    func fontRows() -> [PanelRow] {
        let fonts = systemFonts
        var rows = [PanelRow(id: "fontsIntro", title: TF.text(.intro), kind: .info(""))]
        let scripts: [(String, TF.Key, FontScript, String)] = [
            ("latin", .latin, .latin, "textformat"), ("italic", .italic, .latinItalic, "italic"),
            ("typewriter", .typewriter, .typewriter, "keyboard"), ("thai", .thai, .thai, "character.textbox"), ("arabic", .arabic, .arabic, "character.textbox"),
        ]
        for (id, title, script, symbol) in scripts {
            rows.append(PanelRow(id: "font-" + id, title: TF.text(title), symbol: symbol, kind: .info(AppModel.describe(fonts.pick(script)))))
        }
        let cjk = fonts.pick(.japanese)
        let cjkValue = cjkProgress.map { TF.format(.cjkDownloading, Int($0 * 100)) } ?? cjk.map(AppModel.describe) ?? TF.text(.cjkNotYet)
        rows.append(PanelRow(id: "font-cjk", title: TF.text(.cjk), detail: cjk == nil ? TF.format(.cjkOnNeed, cjkDownloadSize) : nil, symbol: "character.ja", kind: .info(cjkValue)))
        if cjkProgress == nil && !cjkInstalled {
            rows.append(PanelRow(id: "cjkDownload", title: TF.text(.cjkDownloadNow), detail: TF.format(.cjkDownloadNowDetail, cjkDownloadSize), symbol: "arrow.down.circle",
                                 kind: .action(destructive: false) { [weak self] in self?.downloadCJK() }))
        }
        if cjkInstalled {
            let size = ByteCountFormatter.string(fromByteCount: fontDownloads.package.installedSize, countStyle: .file)
            rows.append(PanelRow(id: "cjkRemove", title: TF.text(.cjkRemove), detail: TF.format(.cjkRemoveDetail, size), symbol: "trash",
                                 kind: .action(destructive: true) { [weak self] in self?.removeCJK() }))
        }
        rows.append(PanelRow(id: "fonts", title: TF.text(.userFolder), detail: fontsFolder?.abbreviatedPath ?? TF.text(.userFolderNone), symbol: "folder",
                             kind: .action(destructive: false) { [weak self] in self?.chooseFontsFolder() }))
        if preferences.fontsFolder != nil {
            rows.append(PanelRow(id: "fontsReset", title: TF.text(.userFolderReset), symbol: "xmark.circle", kind: .action(destructive: false) { [weak self] in
                self?.preferences.fontsFolder = nil
            }))
        }
        rows.append(PanelRow(id: "fontsHint", title: TF.text(.hint), kind: .info("")))
        return rows
    }
}

/// Lets a download's progress through once per percent, not for every piece that comes.
final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1

    func passes(_ fraction: Double) -> Bool {
        let percent = Int(fraction * 100)
        return lock.withLock {
            guard percent != last else { return false }
            last = percent
            return true
        }
    }
}
