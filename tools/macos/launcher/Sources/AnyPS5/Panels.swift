import AnyPS5Core
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A settings row the panels draw and the input moves through.
struct PanelRow: Identifiable {
    enum Kind {
        case choice(options: [String], selected: Int, set: (Int) -> Void)
        case toggle(Bool, set: (Bool) -> Void)
        case stepper(value: Int, range: ClosedRange<Int>, step: Int, format: (Int) -> String, set: (Int) -> Void)
        case action(destructive: Bool, run: () -> Void)
        case info(String)
        case text(String, set: (String) -> Void)
        /// A pad action's keys and mouse buttons (ini sources); choosing it waits for a key.
        case keys([String], capturing: Bool, capture: () -> Void)
    }

    let id: String
    let title: String
    var detail: String?
    var symbol: String?
    let kind: Kind

    var focusable: Bool {
        if case .info = kind { return false }
        return true
    }
}

struct PanelCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let rows: [PanelRow]
}

extension AppModel {
    /// A volume in a panel: Off at zero.
    static func percent(_ value: Int) -> String { value == 0 ? T.text(.off) : "\(value)%" }

    func panelCategories() -> [PanelCategory] {
        switch overlay {
        case .settings: return settingsCategories()
        case .gameSettings: return selectedGame.map { [PanelCategory(id: "game", title: $0.name, symbol: "gamecontroller", rows: gameRows($0))] } ?? []
        case .controls: return selectedGame.map { [PanelCategory(id: "controls", title: $0.name, symbol: "keyboard", rows: controlRows($0))] } ?? []
        case .advanced: return selectedGame.map { [PanelCategory(id: "advanced", title: $0.name, symbol: "slider.horizontal.below.rectangle", rows: advancedRows($0))] } ?? []
        case .confirmUninstall:
            guard let game = selectedGame else { return [] }
            return [PanelCategory(id: "confirm", title: T.text(.uninstall), symbol: "trash", rows: [
                PanelRow(id: "confirm", title: T.text(.uninstall), symbol: "trash", kind: .action(destructive: true) { [weak self] in
                    self?.uninstall(game)
                    self?.closeOverlay()
                }),
                PanelRow(id: "cancel", title: T.text(.cancel), kind: .action(destructive: false) { [weak self] in self?.closeOverlay() }),
            ])]
        case .updateChoice:
            guard let game = selectedGame else { return [] }
            return [PanelCategory(id: "update", title: T.text(.updateAvailable), symbol: "arrow.triangle.2.circlepath", rows: [
                PanelRow(id: "update", title: T.text(.updateAndPlay), detail: T.text(.updateAndPlayDetail), symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in
                    self?.closeOverlay()
                    self?.updateAndPlay(game)
                }),
                PanelRow(id: "play", title: T.text(.playNow), detail: T.text(.playNowDetail), symbol: "play.fill", kind: .action(destructive: false) { [weak self] in
                    self?.closeOverlay()
                    self?.play(game)
                }),
            ])]
        default: return []
        }
    }

    private func settingsCategories() -> [PanelCategory] {
        let preferences = self.preferences
        var appearance: [PanelRow] = [
            PanelRow(id: "theme", title: T.text(.theme), symbol: "paintpalette", kind: .choice(options: Theme.allCases.map(\.title), selected: preferences.theme.rawValue) { [weak self] index in
                self?.preferences.theme = Theme(rawValue: index) ?? .cosmic
            }),
            PanelRow(id: "accent", title: T.text(.accent), symbol: "circle.lefthalf.filled", kind: .choice(options: AccentColor.allCases.map(\.title), selected: AccentColor.allCases.firstIndex(of: preferences.accent ?? preferences.theme.defaultAccent) ?? 0) { [weak self] index in
                self?.preferences.accent = AccentColor.allCases[index]
            }),
            PanelRow(id: "backdrop", title: T.text(.background), symbol: "photo.on.rectangle", kind: .choice(options: [T.text(.backgroundTheme), T.text(.backgroundImage), T.text(.backgroundVideo)], selected: [Preferences.Backdrop.theme, .image, .video].firstIndex(of: preferences.backdrop) ?? 0) { [weak self] index in
                let backdrop = [Preferences.Backdrop.theme, .image, .video][index]
                if backdrop != .theme && (self?.preferences.backdropFile == nil || self?.preferences.backdrop != backdrop) {
                    self?.chooseBackdrop(backdrop)
                } else {
                    self?.preferences.backdrop = backdrop
                }
            }),
        ]
        if preferences.backdrop != .theme {
            appearance.append(PanelRow(id: "file", title: T.text(.chooseFile), detail: preferences.backdropFile.map { URL(fileURLWithPath: $0).lastPathComponent }, symbol: "folder", kind: .action(destructive: false) { [weak self] in
                self?.chooseBackdrop(preferences.backdrop)
            }))
        }
        appearance += [
            PanelRow(id: "artwork", title: T.text(.gameArtwork), symbol: "photo", kind: .toggle(preferences.gameArtwork) { [weak self] value in self?.preferences.gameArtwork = value }),
            PanelRow(id: "motion", title: T.text(.motion), symbol: "wind", kind: .choice(options: [T.text(.motionFull), T.text(.motionReduced)], selected: preferences.reducedMotion ? 1 : 0) { [weak self] index in
                self?.preferences.reducedMotion = index == 1
            }),
        ]

        let library: [PanelRow] = [
            PanelRow(id: "folder", title: T.text(.folder), detail: preferences.gamesFolder ?? "—", symbol: "folder", kind: .action(destructive: false) { [weak self] in self?.pickGamesFolder() }),
            PanelRow(id: "rescan", title: T.text(.rescan), detail: T.format(.gamesFound, games.count), symbol: "arrow.clockwise", kind: .action(destructive: false) { [weak self] in
                self?.rescan()
                Sounds.shared.play(.select)
            }),
            PanelRow(id: "clones", title: T.text(.installedSize), kind: .info("")),
        ]

        let language = PanelRow(id: "language", title: T.text(.language), symbol: "globe", kind: .choice(options: Language.allCases.map(\.displayName), selected: Language.allCases.firstIndex(of: preferences.language) ?? 0) { [weak self] index in
            self?.preferences.language = Language.allCases[index]
        })

        var behaviour: [PanelRow] = [
            PanelRow(id: "name", title: T.text(.profileName), symbol: "person.crop.circle", kind: .text(preferences.profileName) { [weak self] value in self?.preferences.profileName = value }),
            PanelRow(id: "sounds", title: T.text(.sounds), symbol: "speaker.wave.2",
                     kind: .stepper(value: preferences.sounds ? preferences.soundVolume ?? 100 : 0, range: 0...100, step: 10, format: Self.percent) { [weak self] value in
                         self?.preferences.sounds = value > 0
                         if value > 0 { self?.preferences.soundVolume = value }
                     }),
            PanelRow(id: "music", title: T.text(.gameMusic), detail: T.text(.gameMusicDetail), symbol: "music.note",
                     kind: .stepper(value: musicVolume, range: 0...100, step: 10, format: Self.percent) { [weak self] value in
                         self?.preferences.musicVolume = value
                     }),
            PanelRow(id: "hide", title: T.text(.hideWhilePlaying), symbol: "eye.slash", kind: .toggle(preferences.hideWhilePlaying) { [weak self] value in self?.preferences.hideWhilePlaying = value }),
            PanelRow(id: "discord", title: T.text(.discordPresence), detail: T.text(.discordPresenceDetail), symbol: "person.2.wave.2", kind: .toggle(preferences.discordPresence ?? true) { [weak self] value in
                self?.preferences.discordPresence = value
                if !value { self?.discordOff() }
            }),
            PanelRow(id: "checkUpdates", title: T.text(.checkUpdates), detail: T.text(.checkUpdatesDetail), symbol: "arrow.down.circle", kind: .toggle(preferences.checkUpdates ?? true) { [weak self] value in
                self?.preferences.checkUpdates = value
                if value { self?.checkForUpdate() }
            }),
        ]
        if rosettaMissing {
            behaviour.append(PanelRow(id: "rosetta", title: T.text(.rosettaInstall), detail: T.text(.rosettaMissing), symbol: "cpu", kind: .action(destructive: false) { [weak self] in self?.installRosetta() }))
        } else {
            behaviour.append(PanelRow(id: "rosetta", title: T.text(.rosettaInstalled), symbol: "checkmark.seal", kind: .info("")))
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        var about: [PanelRow] = [
            PanelRow(id: "text", title: T.text(.aboutText), kind: .info("")),
            PanelRow(id: "version", title: T.text(.version), kind: .info(version)),
        ]
        if let update = availableUpdate {
            let detail = updateProgress.map { T.format(.updateDownloading, Int($0 * 100)) } ?? T.text(.updateDetail)
            about.append(PanelRow(id: "update", title: T.format(.updateTo, update.version), detail: detail, symbol: "arrow.down.circle.fill", kind: .action(destructive: false) { [weak self] in
                self?.installUpdate()
            }))
            about.append(PanelRow(id: "whatsNew", title: T.text(.whatsNew), detail: update.page.absoluteString.replacingOccurrences(of: "https://", with: ""), symbol: "sparkles", kind: .action(destructive: false) {
                NSWorkspace.shared.open(update.page)
            }))
        }
        about += [
            PanelRow(id: "toolkit", title: T.text(.toolkitVersion), kind: .info(toolkit?.version ?? "—")),
            PanelRow(id: "author", title: T.text(.madeBy), kind: .info("Utku Halis")),
            PanelRow(id: "github", title: "GitHub", detail: "github.com/utkuhalis/AnyPS5-ARM", symbol: "chevron.left.forwardslash.chevron.right", kind: .action(destructive: false) {
                NSWorkspace.shared.open(URL(string: "https://github.com/utkuhalis/AnyPS5-ARM")!)
            }),
            PanelRow(id: "upstream", title: T.text(.builtOn), detail: "github.com/boykopovar/AnyPS5", symbol: "heart", kind: .action(destructive: false) {
                NSWorkspace.shared.open(URL(string: "https://github.com/boykopovar/AnyPS5")!)
            }),
        ]
        if translocated {
            about.append(PanelRow(id: "move", title: T.text(.moveToApplications), symbol: "arrow.down.app", kind: .action(destructive: false) { _ = AppLocation.moveToApplications() }))
        }
        about.append(PanelRow(id: "quit", title: T.text(.quit), symbol: "power", kind: .action(destructive: true) { NSApp.terminate(nil) }))

        var advanced: [PanelRow] = [
            PanelRow(id: "screenshots", title: T.text(.screenshotsFolder), detail: screenshotsFolder.abbreviatedPath, symbol: "camera", kind: .action(destructive: false) { [weak self] in self?.chooseScreenshotsFolder() }),
            PanelRow(id: "showScreenshots", title: T.text(.showScreenshots), symbol: "photo.on.rectangle.angled", kind: .action(destructive: false) { [weak self] in self?.showScreenshots() }),
            PanelRow(id: "fonts", title: T.text(.fontsFolder), detail: fontsFolder?.abbreviatedPath ?? T.text(.fontsNone), symbol: "textformat", kind: .action(destructive: false) { [weak self] in self?.chooseFontsFolder() }),
        ]
        if preferences.fontsFolder != nil {
            advanced.append(PanelRow(id: "fontsReset", title: T.text(.fontsReset), symbol: "xmark.circle", kind: .action(destructive: false) { [weak self] in self?.preferences.fontsFolder = nil }))
        }
        advanced.append(PanelRow(id: "fontsHint", title: T.text(.fontsHint), kind: .info("")))
        advanced.append(PanelRow(id: "phones", title: T.text(.phones), kind: .info(phones.isEmpty ? T.text(.phonesNone) : "")))
        for device in phones {
            advanced.append(PanelRow(id: "phone-" + device.id, title: device.name, detail: T.text(.phoneRemove), symbol: "iphone.gen3", kind: .action(destructive: true) { [weak self] in
                self?.removePhone(device.id)
            }))
        }

        return [
            PanelCategory(id: "appearance", title: T.text(.appearance), symbol: "paintbrush", rows: appearance),
            PanelCategory(id: "library", title: T.text(.storage), symbol: "square.grid.2x2", rows: library),
            PanelCategory(id: "language", title: T.text(.language), symbol: "globe", rows: [language]),
            PanelCategory(id: "behaviour", title: T.text(.behaviour), symbol: "slider.horizontal.3", rows: behaviour),
            PanelCategory(id: "advanced", title: T.text(.advanced), symbol: "wrench.and.screwdriver", rows: advanced),
            PanelCategory(id: "about", title: T.text(.about), symbol: "info.circle", rows: about),
        ]
    }

    private func gameRows(_ game: Game) -> [PanelRow] {
        let settings = settings(for: game)
        var rows: [PanelRow] = []
        let choices = resolutionChoices(for: game)
        if !choices.isEmpty {
            let options = [T.text(.resolutionDefault)] + choices
            rows.append(PanelRow(id: "resolution", title: T.text(.resolution), symbol: "rectangle.on.rectangle", kind: .choice(options: options, selected: settings.resolution.flatMap { choices.firstIndex(of: $0) }.map { $0 + 1 } ?? 0) { [weak self] index in
                self?.update(game) { $0.resolution = index == 0 ? nil : choices[index - 1] }
            }))
        }
        rows.append(PanelRow(id: "display", title: T.text(.display), symbol: "macwindow", kind: .choice(options: [T.text(.windowed), T.text(.fullscreen)], selected: settings.fullscreen ? 1 : 0) { [weak self] index in
            self?.update(game) { $0.fullscreen = index == 1 }
        }))
        if !settings.fullscreen {
            rows.append(PanelRow(id: "size", title: T.text(.windowSize), symbol: "arrow.up.left.and.arrow.down.right", kind: .stepper(value: settings.windowSize, range: 40...100, step: 5, format: { "\($0)%" }) { [weak self] value in
                self?.update(game) { $0.windowSize = value }
            }))
        }
        rows.append(PanelRow(id: "vsync", title: T.text(.vsync), symbol: "waveform.path", kind: .toggle(settings.vsync) { [weak self] value in self?.update(game) { $0.vsync = value } }))
        rows.append(PanelRow(id: "controls", title: T.text(.controls), symbol: "keyboard", kind: .action(destructive: false) { [weak self] in self?.open(.controls) }))
        if let set = trophies[game.id] {
            rows.append(PanelRow(id: "trophies", title: T.text(.trophies), detail: "\(set.unlockedCount)/\(set.trophies.count) · \(set.percent)%", symbol: "trophy", kind: .action(destructive: false) { [weak self] in self?.open(.trophies) }))
        }
        rows.append(PanelRow(id: "advanced", title: T.text(.advanced), detail: T.text(.advancedDetail), symbol: "slider.horizontal.below.rectangle", kind: .action(destructive: false) { [weak self] in self?.open(.advanced) }))
        let overlays = GameSettings.Overlay.allCases
        let overlayNames = [T.text(.overlayOff), T.text(.overlayTopLeft), T.text(.overlayTopRight), T.text(.overlayBottomLeft), T.text(.overlayBottomRight)]
        rows.append(PanelRow(id: "overlay", title: T.text(.overlay), symbol: "speedometer", kind: .choice(options: overlayNames, selected: overlays.firstIndex(of: settings.overlay) ?? 0) { [weak self] index in
            self?.update(game) { $0.overlay = overlays[index] }
        }))
        let languages = ConsoleLanguage.all
        rows.append(PanelRow(id: "language", title: T.text(.gameLanguage), symbol: "character.bubble", kind: .choice(options: [T.text(.followLauncher)] + languages.map(\.name), selected: settings.language.flatMap { number in languages.firstIndex { $0.number == number } }.map { $0 + 1 } ?? 0) { [weak self] index in
            self?.update(game) { $0.language = index == 0 ? nil : languages[index - 1].number }
        }))
        let state = state(of: game)
        if case .installed = state {
            rows.append(PanelRow(id: "reinstall", title: T.text(.reinstall), symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in
                self?.closeOverlay()
                self?.unlock(game)
            }))
        }
        let shots = screenshots(of: game).count
        rows.append(PanelRow(id: "gallery", title: T.text(.screenshots), detail: shots == 0 ? T.text(.screenshotsNone) : "\(shots)", symbol: "photo.on.rectangle", kind: .action(destructive: false) { [weak self] in
            self?.open(.gallery)
        }))
        if case .installed = state {
            let last = lastBackup(of: game).map { T.format(.lastBackup, $0.formatted(date: .abbreviated, time: .shortened)) } ?? T.text(.backUpSavesDetail)
            rows.append(PanelRow(id: "backup", title: T.text(.backUpSaves), detail: last, symbol: "externaldrive.badge.plus", kind: .action(destructive: false) { [weak self] in self?.backUpSaves(game) }))
            rows.append(PanelRow(id: "restore", title: T.text(.restoreSaves), detail: T.text(.restoreSavesDetail), symbol: "arrow.counterclockwise", kind: .action(destructive: false) { [weak self] in self?.restoreSaves(game) }))
        }
        rows.append(PanelRow(id: "finder", title: T.text(.showInFinder), symbol: "folder", kind: .action(destructive: false) { [weak self] in self?.showInFinder(game) }))
        rows.append(PanelRow(id: "log", title: T.text(.openLog), symbol: "doc.text", kind: .action(destructive: false) { [weak self] in self?.openLog(game) }))
        rows.append(PanelRow(id: "report", title: T.text(.makeReport), detail: T.text(.makeReportDetail), symbol: "stethoscope", kind: .action(destructive: false) { [weak self] in self?.makeReport(game) }))
        rows.append(PanelRow(id: "cache", title: T.text(.clearShaderCache), symbol: "sparkles", kind: .action(destructive: false) { [weak self] in self?.clearShaderCache(game) }))
        if case .installed = state {
            rows.append(PanelRow(id: "uninstall", title: T.text(.uninstall), symbol: "trash", kind: .action(destructive: true) { [weak self] in self?.open(.confirmUninstall) }))
        }
        return rows
    }

    private func controlRows(_ game: Game) -> [PanelRow] {
        let changes = settings(for: game).controls ?? [:]
        var rows = [PanelRow(id: "hint", title: T.text(.controlsHint), kind: .info(""))]
        for action in PadAction.allCases {
            rows.append(PanelRow(id: action.rawValue, title: action.title, symbol: action.symbol, kind: .keys(Controls.sources(action, changes), capturing: capturing == action) { [weak self] in
                self?.startCapture(action)
            }))
        }
        rows.append(PanelRow(id: "reset", title: T.text(.resetControls), symbol: "arrow.counterclockwise", kind: .action(destructive: false) { [weak self] in self?.resetControls(game) }))
        return rows
    }

    /// The game's sticks, mouse and keyboard sticks, its shader cache, and sharing its settings.
    private func advancedRows(_ game: Game) -> [PanelRow] {
        let settings = settings(for: game)
        let tuning = settings.tuning ?? InputTuning()
        func tune(_ id: String, _ title: T.Key, _ detail: T.Key, _ symbol: String, _ value: Int, _ range: ClosedRange<Int>, _ step: Int,
                  _ format: @escaping (Int) -> String, _ set: @escaping (inout InputTuning, Int) -> Void) -> PanelRow {
            PanelRow(id: id, title: T.text(title), detail: T.text(detail), symbol: symbol, kind: .stepper(value: value, range: range, step: step, format: format) { [weak self] value in
                self?.update(game) { settings in
                    var changed = settings.tuning ?? InputTuning()
                    set(&changed, value)
                    settings.tuning = changed == InputTuning() ? nil : changed
                }
            })
        }
        let percent: (Int) -> String = { "\($0)%" }
        let times: (Int) -> String = { String(format: "%.1f×", Double($0) / 10) }
        let tenths: (Int) -> String = { String(format: "%.1f", Double($0) / 10) }
        let milliseconds: (Int) -> String = { $0 == 0 ? T.text(.off) : "\($0) ms" }
        return [
            PanelRow(id: "sticksSection", title: T.text(.sectionSticks), kind: .info("")),
            tune("leftDeadzone", .leftDeadzone, .deadzoneDetail, "l.joystick", tuning.leftDeadzone, 0...90, 2, percent) { $0.leftDeadzone = $1 },
            tune("rightDeadzone", .rightDeadzone, .deadzoneDetail, "r.joystick", tuning.rightDeadzone, 0...90, 2, percent) { $0.rightDeadzone = $1 },
            PanelRow(id: "mouseSection", title: T.text(.sectionMouse), kind: .info("")),
            tune("sensitivity", .mouseSensitivity, .mouseSensitivityDetail, "computermouse", tuning.mouseSensitivity, 1...100, 1, times) { $0.mouseSensitivity = $1 },
            tune("vertical", .mouseVertical, .mouseVerticalDetail, "arrow.up.and.down", tuning.mouseVerticalScale, 1...100, 1, times) { $0.mouseVerticalScale = $1 },
            tune("curve", .mouseCurve, .mouseCurveDetail, "chart.line.uptrend.xyaxis", tuning.mouseCurve, 2...50, 1, tenths) { $0.mouseCurve = $1 },
            tune("offset", .mouseMinimum, .mouseMinimumDetail, "scope", tuning.mouseDeadzoneOffset, 0...90, 2, percent) { $0.mouseDeadzoneOffset = $1 },
            tune("maxSpeed", .mouseMaxSpeed, .mouseMaxSpeedDetail, "speedometer", tuning.mouseMaxSpeed, 1...100, 1, times) { $0.mouseMaxSpeed = $1 },
            tune("smoothing", .mouseSmoothing, .mouseSmoothingDetail, "waveform.path", tuning.mouseSmoothingMs, 0...500, 5, milliseconds) { $0.mouseSmoothingMs = $1 },
            tune("decay", .mouseDecay, .mouseDecayDetail, "timer", tuning.mouseDecayMs, 5...1000, 5, { "\($0) ms" }) { $0.mouseDecayMs = $1 },
            PanelRow(id: "keyboardSection", title: T.text(.sectionKeyboard), kind: .info("")),
            tune("modifier", .stickModifierScale, .stickModifierScaleDetail, "tortoise", tuning.stickModifierScale, 5...100, 5, percent) { $0.stickModifierScale = $1 },
            tune("keyboardRamp", .keyboardRamp, .keyboardRampDetail, "keyboard", tuning.keyboardRampMs, 0...2000, 50, milliseconds) { $0.keyboardRampMs = $1 },
            tune("triggerRamp", .triggerRamp, .triggerRampDetail, "l2.rectangle.roundedtop", tuning.triggerRampMs, 0...2000, 50, milliseconds) { $0.triggerRampMs = $1 },
            PanelRow(id: "graphicsSection", title: T.text(.sectionGraphics), kind: .info("")),
            PanelRow(id: "shaderCache", title: T.text(.shaderCache), detail: T.text(.shaderCacheDetail), symbol: "square.stack.3d.up", kind: .toggle(settings.shaderCache ?? true) { [weak self] value in
                self?.update(game) { $0.shaderCache = value ? nil : false }
            }),
            PanelRow(id: "shareSection", title: T.text(.sectionShare), kind: .info("")),
            PanelRow(id: "export", title: T.text(.exportSettings), detail: T.text(.exportSettingsDetail), symbol: "square.and.arrow.up", kind: .action(destructive: false) { [weak self] in self?.exportSettings(game) }),
            PanelRow(id: "import", title: T.text(.importSettings), detail: T.text(.importSettingsDetail), symbol: "square.and.arrow.down", kind: .action(destructive: false) { [weak self] in self?.importSettings(game) }),
            PanelRow(id: "resetAdvanced", title: T.text(.resetAdvanced), symbol: "arrow.counterclockwise", kind: .action(destructive: false) { [weak self] in
                self?.update(game) { settings in
                    settings.tuning = nil
                    settings.shaderCache = nil
                }
            }),
        ]
    }

    /// From the controls or the advanced page back to the game's settings, on the row that opened it.
    func backToGameSettings() {
        let opener = overlay == .advanced ? "advanced" : "controls"
        endCapture()
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { overlay = .gameSettings }
        panelRow = panelCategories().first?.rows.firstIndex { $0.id == opener } ?? 0
        panelInRows = true
    }

    func pickGamesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = T.text(.pickFolder)
        if let root { panel.directoryURL = root }
        if panel.runModal() == .OK, let url = panel.url { chooseFolder(url) }
    }

    func chooseBackdrop(_ kind: Preferences.Backdrop) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = kind == .video ? [.movie, .mpeg4Movie, .quickTimeMovie] : [.image]
        panel.prompt = T.text(.chooseFile)
        if panel.runModal() == .OK, let url = panel.url {
            preferences.backdropFile = url.path
            preferences.backdrop = kind
        }
    }

    // MARK: Panel input

    /// Moves through the open panel; returns whether the command was used.
    func panelCommand(_ command: Command) -> Bool {
        let categories = panelCategories()
        guard !categories.isEmpty else { return false }
        panelCategory = min(panelCategory, categories.count - 1)
        let rows = categories[panelCategory].rows
        let single = categories.count == 1
        if !panelInRows && !single {
            switch command {
            case .up: movePanelCategory(-1, count: categories.count)
            case .down: movePanelCategory(1, count: categories.count)
            case .right, .select: enterRows(rows)
            case .back, .options: closeOverlay()
            case .left, .previousGame, .nextGame, .home: break
            }
            return true
        }
        guard !rows.isEmpty else {
            if command == .back || command == .left { leaveRows(single) }
            return true
        }
        panelRow = min(panelRow, rows.count - 1)
        if !rows[panelRow].focusable, let first = rows.firstIndex(where: \.focusable) { panelRow = first }
        let row = rows[panelRow]
        switch command {
        case .up: movePanelRow(-1, rows)
        case .down: movePanelRow(1, rows)
        case .left:
            if !change(row, by: -1) { leaveRows(single) }
        case .right:
            _ = change(row, by: 1)
        case .select:
            activate(row)
        case .back:
            leaveRows(single)
        case .options:
            closeOverlay()
        case .previousGame, .nextGame, .home:
            break
        }
        return true
    }

    private func movePanelCategory(_ delta: Int, count: Int) {
        let next = min(count - 1, max(0, panelCategory + delta))
        guard next != panelCategory else { return }
        panelCategory = next
        panelRow = 0
        Sounds.shared.play(.move)
    }

    private func enterRows(_ rows: [PanelRow]) {
        guard let first = rows.firstIndex(where: \.focusable) else { return }
        panelRow = first
        panelInRows = true
        Sounds.shared.play(.move)
    }

    private func leaveRows(_ single: Bool) {
        if single { closeOverlay(); return }
        panelInRows = false
        Sounds.shared.play(.back)
    }

    private func movePanelRow(_ delta: Int, _ rows: [PanelRow]) {
        var next = panelRow + delta
        while rows.indices.contains(next) && !rows[next].focusable { next += delta }
        guard rows.indices.contains(next) else { return }
        panelRow = next
        Sounds.shared.play(.move)
    }

    @discardableResult
    func change(_ row: PanelRow, by delta: Int) -> Bool {
        switch row.kind {
        case .choice(let options, let selected, let set):
            let next = min(options.count - 1, max(0, selected + delta))
            if next != selected { set(next); Sounds.shared.play(.move) }
            return true
        case .toggle(let value, let set):
            if (delta > 0) != value { set(delta > 0); Sounds.shared.play(.move) }
            return true
        case .stepper(let value, let range, let step, _, let set):
            let next = min(range.upperBound, max(range.lowerBound, value + delta * step))
            if next != value { set(next); Sounds.shared.play(.move) }
            return true
        default:
            return false
        }
    }

    func activate(_ row: PanelRow) {
        switch row.kind {
        case .choice(let options, let selected, let set):
            set((selected + 1) % options.count)
            Sounds.shared.play(.move)
        case .toggle(let value, let set):
            set(!value)
            Sounds.shared.play(.move)
        case .stepper(let value, let range, let step, _, let set):
            set(value + step > range.upperBound ? range.lowerBound : value + step)
            Sounds.shared.play(.move)
        case .action(_, let run):
            Sounds.shared.play(.select)
            run()
        case .keys(_, _, let capture):
            capture()
        case .info, .text:
            break
        }
    }
}

/// The settings screen: categories on the left, their rows on the right.
struct SettingsPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let categories = model.panelCategories()
        let current = categories.indices.contains(model.panelCategory) ? categories[model.panelCategory] : nil
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(T.text(.settings)).font(.display(40 * scale, .light)).foregroundStyle(.white).padding(.bottom, 26 * scale)
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    let selected = index == model.panelCategory
                    let focused = selected && !model.panelInRows
                    HStack(spacing: 14 * scale) {
                        Image(systemName: category.symbol).font(.system(size: 18 * scale, weight: .medium)).frame(width: 26 * scale)
                        Text(category.title).font(.display(19 * scale, selected ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(focused ? Color.black : .white.opacity(selected ? 1 : 0.7))
                    .padding(.horizontal, 18 * scale)
                    .frame(height: 52 * scale)
                    .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(focused ? Color.white : Color.white.opacity(selected ? 0.12 : 0)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.panelCategory = index
                        model.panelRow = 0
                        model.panelInRows = false
                        Sounds.shared.play(.move)
                    }
                }
                Spacer()
            }
            .frame(width: 330 * scale)
            .padding(.trailing, 36 * scale)
            if let current {
                RowList(rows: current.rows, focusedRow: model.panelInRows ? model.panelRow : nil)
                    .id(current.id)
                    .transition(.opacity.combined(with: .offset(x: 18 * scale)))
            }
        }
        .padding(.horizontal, 90 * scale)
        .padding(.top, 70 * scale)
        .padding(.bottom, 50 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.74).background(.ultraThinMaterial))
        .animation(Motion.focus, value: model.panelCategory)
    }
}

/// A game's settings, sliding in from the right.
struct SidePanel: View {
    let title: String
    var subtitle: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let rows = model.panelCategories().first?.rows ?? []
        HStack(spacing: 0) {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.closeOverlay() }
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text(title).font(.display(30 * scale, .light)).foregroundStyle(.white).lineLimit(2)
                if let subtitle { Text(subtitle).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.6)) }
                RowList(rows: rows, focusedRow: model.panelRow)
                    .padding(.top, 18 * scale)
            }
            .padding(36 * scale)
            .frame(width: 560 * scale, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.06).opacity(0.92).background(.ultraThinMaterial))
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
        }
    }
}

struct RowList: View {
    let rows: [PanelRow]
    let focusedRow: Int?
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        if previewRender {
            // An overlay takes no size of its own, so a long list cannot stretch the screen.
            Color.clear.overlay(alignment: .top) { content }.clipped()
        } else {
            scrolling
        }
    }

    private var content: some View {
        VStack(spacing: 8 * scale) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RowView(row: row, focused: focusedRow == index)
                    .id(row.id)
                    .onTapGesture {
                        if model.overlay == .settings { model.panelInRows = true }
                        model.panelRow = index
                        model.activate(row)
                    }
            }
        }
        .padding(6 * scale)
    }

    private var scrolling: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content
            }
            .onChange(of: focusedRow) { _, row in
                guard let row, rows.indices.contains(row) else { return }
                withAnimation(Motion.focus) { proxy.scrollTo(rows[row].id, anchor: .center) }
            }
        }
    }
}

struct RowView: View {
    let row: PanelRow
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @State private var text = ""

    var body: some View {
        let foreground: Color = focused ? .black : .white
        HStack(spacing: 14 * scale) {
            if let symbol = row.symbol {
                Image(systemName: symbol).font(.system(size: 17 * scale, weight: .medium)).frame(width: 24 * scale)
                    .foregroundStyle(destructive && !focused ? Color(red: 1, green: 0.55, blue: 0.5) : foreground.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(row.title).font(.display(17 * scale, .medium)).lineLimit(2).minimumScaleFactor(0.85)
                    .foregroundStyle(destructive && !focused ? Color(red: 1, green: 0.6, blue: 0.55) : foreground.opacity(row.focusable ? 1 : 0.62))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = row.detail {
                    Text(detail).font(.display(13 * scale)).foregroundStyle(foreground.opacity(0.55)).lineLimit(2).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12 * scale)
            value.foregroundStyle(foreground)
        }
        .padding(.horizontal, 18 * scale)
        .frame(minHeight: 58 * scale)
        .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(focused ? Color.white : Color.white.opacity(row.focusable ? 0.07 : 0)))
        .shadow(color: .white.opacity(focused ? 0.22 : 0), radius: 12 * scale)
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
        .contentShape(Rectangle())
    }

    private var destructive: Bool {
        if case .action(let destructive, _) = row.kind { return destructive }
        return false
    }

    @ViewBuilder private var value: some View {
        switch row.kind {
        case .choice(let options, let selected, let set):
            HStack(spacing: 12 * scale) {
                chevron("chevron.left", enabled: selected > 0) { set(selected - 1) }
                Text(options.indices.contains(selected) ? options[selected] : "").font(.display(16 * scale, .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7).frame(minWidth: 120 * scale, maxWidth: 190 * scale)
                chevron("chevron.right", enabled: selected < options.count - 1) { set(selected + 1) }
            }
        case .toggle(let value, let set):
            Switch(on: value, accent: model.accent, focused: focused) { set(!value); Sounds.shared.play(.move) }
        case .stepper(let value, let range, let step, let format, let set):
            HStack(spacing: 12 * scale) {
                chevron("minus", enabled: value > range.lowerBound) { set(max(range.lowerBound, value - step)) }
                Text(format(value)).font(.display(16 * scale, .semibold)).monospacedDigit().frame(minWidth: 70 * scale)
                chevron("plus", enabled: value < range.upperBound) { set(min(range.upperBound, value + step)) }
            }
        case .action:
            Image(systemName: "chevron.right").font(.system(size: 14 * scale, weight: .semibold)).opacity(0.6)
        case .info(let value):
            Text(value).font(.display(15 * scale, .medium)).opacity(0.7).textSelection(.enabled)
        case .keys(let sources, let capturing, _):
            KeyCaps(sources: sources, capturing: capturing, focused: focused)
        case .text(let value, let set):
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.display(16 * scale, .semibold))
                .multilineTextAlignment(.trailing)
                .frame(width: 200 * scale)
                .onAppear { text = value }
                .onSubmit { set(text) }
                .onChange(of: text) { _, new in set(new) }
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Sounds.shared.play(.move) }) {
            Image(systemName: symbol).font(.system(size: 13 * scale, weight: .bold)).frame(width: 26 * scale, height: 26 * scale).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 0.85 : 0.25)
        .disabled(!enabled)
    }
}

/// An on and off switch drawn like the console's.
struct Switch: View {
    let on: Bool
    let accent: Color
    let focused: Bool
    let toggle: () -> Void
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? accent : (focused ? Color.black.opacity(0.18) : Color.white.opacity(0.18)))
            Circle().fill(Color.white).padding(3 * scale).shadow(color: .black.opacity(0.25), radius: 2 * scale, y: 1)
        }
        .frame(width: 50 * scale, height: 28 * scale)
        .animation(Motion.focus, value: on)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// A pad action's keys drawn as keycaps, or the prompt while one is awaited.
struct KeyCaps: View {
    let sources: [String]
    let capturing: Bool
    let focused: Bool
    @Environment(\.scale) private var scale
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6 * scale) {
            if capturing {
                Text(T.text(.pressKey)).font(.display(15 * scale, .semibold))
                    .opacity(pulse ? 0.45 : 1)
                    .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
            } else if sources.allSatisfy({ $0 == Controls.unbound }) {
                Text(T.text(.noKey)).font(.display(15 * scale, .medium)).opacity(0.5)
            } else {
                ForEach(sources.filter { $0 != Controls.unbound }, id: \.self) { source in
                    Text(KeyCaps.name(source))
                        .font(.display(13.5 * scale, .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 9 * scale)
                        .frame(minWidth: 30 * scale, minHeight: 28 * scale)
                        .background(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).fill((focused ? Color.black : Color.white).opacity(source.hasPrefix("KEY:") ? 0.12 : 0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).strokeBorder((focused ? Color.black : Color.white).opacity(0.18), lineWidth: 1))
                }
            }
        }
    }

    /// How a source reads in the launcher's language: Shift rather than Left Shift, arrows as arrows.
    static func name(_ source: String) -> String {
        let parts = source.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return source }
        switch (parts[0], parts[1]) {
        case ("MOUSE", "Left"): return T.text(.mouseLeft)
        case ("MOUSE", "Right"): return T.text(.mouseRight)
        case ("MOUSE", "Middle"): return T.text(.mouseMiddle)
        case ("MOUSE", "X1"): return T.text(.mouseBack)
        case ("MOUSE", "X2"): return T.text(.mouseForward)
        case ("WHEEL", "Up"): return T.text(.wheelUp)
        case ("WHEEL", "Down"): return T.text(.wheelDown)
        case ("KEY", "Space"): return T.text(.keySpace)
        case ("KEY", "Return"): return T.text(.keyEnter)
        case ("KEY", "Escape"): return "Esc"
        case ("KEY", "Backspace"): return "⌫"
        case ("KEY", "Up"): return "↑"
        case ("KEY", "Down"): return "↓"
        case ("KEY", "Left"): return "←"
        case ("KEY", "Right"): return "→"
        case ("KEY", "Left Shift"), ("KEY", "Right Shift"): return "Shift"
        case ("KEY", "Left Ctrl"), ("KEY", "Right Ctrl"): return "Ctrl"
        case ("KEY", "Left Alt"), ("KEY", "Right Alt"): return "Option"
        case ("KEY", "Left GUI"), ("KEY", "Right GUI"): return "Cmd"
        case ("KEY", let key): return key
        default: return parts[1]
        }
    }
}

extension URL {
    /// The path with the home folder written as ~.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

extension Diagnosis {
    /// One sentence in the launcher's language.
    var summary: String {
        switch self {
        case .missingModule(let name): return T.format(.diagnosisMissingModule, name)
        case .unsupported(let function): return T.format(.diagnosisUnsupported, function)
        case .gpuLost: return T.text(.diagnosisGpuLost)
        case .outOfMemory: return T.text(.diagnosisOutOfMemory)
        case .engineError(let message): return T.format(.diagnosisEngineError, message)
        case .crashed(let exception): return T.format(.diagnosisCrashed, exception)
        }
    }
}

extension PadAction {
    var title: String {
        switch self {
        case .cross: return "✕  Cross"
        case .circle: return "○  Circle"
        case .square: return "□  Square"
        case .triangle: return "△  Triangle"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .options: return "Options"
        case .touchLeft: return T.text(.touchpadLeft)
        case .touchRight: return T.text(.touchpadRight)
        case .up: return "\(T.text(.dpad)) · \(T.text(.directionUp))"
        case .down: return "\(T.text(.dpad)) · \(T.text(.directionDown))"
        case .left: return "\(T.text(.dpad)) · \(T.text(.directionLeft))"
        case .right: return "\(T.text(.dpad)) · \(T.text(.directionRight))"
        case .leftStickUp: return "\(T.text(.leftStick)) · \(T.text(.directionUp))"
        case .leftStickDown: return "\(T.text(.leftStick)) · \(T.text(.directionDown))"
        case .leftStickLeft: return "\(T.text(.leftStick)) · \(T.text(.directionLeft))"
        case .leftStickRight: return "\(T.text(.leftStick)) · \(T.text(.directionRight))"
        case .rightStickUp: return "\(T.text(.rightStick)) · \(T.text(.directionUp))"
        case .rightStickDown: return "\(T.text(.rightStick)) · \(T.text(.directionDown))"
        case .rightStickLeft: return "\(T.text(.rightStick)) · \(T.text(.directionLeft))"
        case .rightStickRight: return "\(T.text(.rightStick)) · \(T.text(.directionRight))"
        case .stickModifier: return T.text(.stickModifier)
        }
    }

    var symbol: String {
        switch self {
        case .cross, .circle, .square, .triangle: return "circle.grid.cross"
        case .l1, .r1, .l2, .r2: return "l.rectangle.roundedbottom"
        case .l3, .r3: return "l.joystick.press.down"
        case .options: return "line.3.horizontal"
        case .touchLeft, .touchRight: return "hand.point.up.left"
        case .up, .down, .left, .right: return "dpad"
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight: return "l.joystick"
        case .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight: return "r.joystick"
        case .stickModifier: return "tortoise"
        }
    }
}
