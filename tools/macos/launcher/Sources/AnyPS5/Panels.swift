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
    /// Someone on AnyTogether: their avatar stands in for the symbol.
    var person: PanelPerson?
    /// The detail is advice to read whole (the controller troubleshooter): no line limit.
    var wraps = false

    var focusable: Bool {
        if case .info = kind { return false }
        return true
    }

    /// How left and right treat the row (RowEditor): a choice or a stepper steps its value.
    var valueKind: RowValueKind {
        switch kind {
        case .choice, .stepper: return .choice
        case .toggle: return .toggle
        default: return .other
        }
    }
}

/// A person a row is about: avatar (or initial), and a dot for playing or online.
struct PanelPerson {
    enum Status { case playing, online, offline }

    let name: String
    let avatar: String?
    /// A picture on this Mac in place of the avatar (the user's own profile picture).
    var picture: NSImage?
    var status: Status?
    /// Speaking in the party's voice: a ring in the accent.
    var speaking = false
    /// Their trophy level, beside the row's words.
    var level: TogetherLevelBadge?
    /// The user's own row while they appear offline: a moon on the avatar.
    var appearingOffline = false
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
        case .themes: return [PanelCategory(id: "themes", title: T.text(.themes), symbol: "paintpalette", rows: themeRows())]
        case .studio: return [PanelCategory(id: "studio", title: T.text(.themeStudio), symbol: "wand.and.stars", rows: studioRows())]
        case .friends: return [PanelCategory(id: "friends", title: T.text(.friendsTitle), symbol: "person.2", rows: friendRows())]
        case .party: return [PanelCategory(id: "party", title: T.text(.partyTitle), symbol: "person.3", rows: partyRows())]
        case .notifications: return [PanelCategory(id: "notifications", title: TS.text(.notifTitle), symbol: "bell", rows: notificationRows())]
        case .cloudStorage: return [PanelCategory(id: "cloud", title: TCloud.text(.storageTitle), symbol: "externaldrive.badge.icloud", rows: cloudStorageRows())]
        case .compat: return [PanelCategory(id: "compat", title: compatTitle, symbol: "person.3.sequence", rows: compatRows())]
        case .crashReport: return [PanelCategory(id: "report", title: TC.text(.reportKicker), symbol: "stethoscope", rows: crashReportRows())]
        case .findPlayers: return findPlayersCategories()
        case .gameHub: return hubCategories()
        case .lfgPost: return [PanelCategory(id: "post", title: FP.text(.findPlayers), symbol: "plus.bubble", rows: lfgPostRows())]
        case .confirmUninstall:
            guard let game = selectedGame else { return [] }
            return [PanelCategory(id: "confirm", title: T.text(.uninstall), symbol: "trash", rows: [
                PanelRow(id: "confirm", title: T.text(.uninstall), symbol: "trash", kind: .action(destructive: true) { [weak self] in
                    self?.uninstall(game)
                    self?.closeOverlay()
                }),
                PanelRow(id: "cancel", title: T.text(.cancel), kind: .action(destructive: false) { [weak self] in self?.closeOverlay() }),
            ])]
        case .updateRequired:
            return [PanelCategory(id: "updateRequired", title: TK.text(.updateRequiredTitle), symbol: "arrow.down.circle", rows: updateRequiredRows())]
        case .updateChoice:
            guard let game = selectedGame else { return [] }
            // Which engine unlocked it and which one is chosen now.
            let engine = installedRecords[game.id].flatMap { record in
                engineVersion(for: game).map { TE.format(.engineSwitch, Toolkit.shortVersion(record.toolkit), Toolkit.shortVersion($0)) }
            }
            return [PanelCategory(id: "update", title: T.text(.updateAvailable), symbol: "arrow.triangle.2.circlepath", rows: [
                PanelRow(id: "update", title: T.text(.updateAndPlay), detail: [T.text(.updateAndPlayDetail), engine].compactMap { $0 }.joined(separator: "\n"), symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in
                    self?.closeOverlay()
                    self?.updateAndPlay(game)
                }),
                PanelRow(id: "play", title: T.text(.playNow), detail: T.text(.playNowDetail), symbol: "play.fill", kind: .action(destructive: false) { [weak self] in
                    self?.closeOverlay()
                    self?.play(game)
                }),
            ])]
        case .noSpace:
            guard let (game, shortage) = spaceShortage else { return [] }
            return [PanelCategory(id: "noSpace", title: TPrep.text(.noSpaceTitle), symbol: "externaldrive.badge.exclamationmark", rows: noSpaceRows(game, shortage))]
        case .signIn: return [PanelCategory(id: "signin", title: "AnyTogether", symbol: "person.2.circle", rows: signInRows())]
        default: return []
        }
    }

    /// The no-space panel: how much the unlock needs and what is free, and the ways out.
    func noSpaceRows(_ game: Game, _ shortage: SpaceShortage) -> [PanelRow] {
        [
            PanelRow(id: "amount", title: TPrep.format(.noSpaceAmount, shortage.needed.byteText, shortage.free.byteText, shortage.volume),
                     detail: TPrep.text(.noSpaceNothingWritten) + "\n" + TPrep.text(.noSpaceWhy), symbol: "externaldrive.badge.exclamationmark", kind: .info(""), wraps: true),
            PanelRow(id: "folder", title: TPrep.text(.noSpaceFolder), detail: TPrep.text(.noSpaceFolderDetail), symbol: "folder", kind: .action(destructive: false) { [weak self] in
                self?.closeOverlay()
                self?.pickGamesFolder()
            }),
            PanelRow(id: "storage", title: TPrep.text(.noSpaceStorage), detail: TPrep.text(.noSpaceStorageDetail), symbol: "internaldrive", kind: .action(destructive: false) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
            }),
            PanelRow(id: "retry", title: TPrep.text(.noSpaceRetry), detail: TPrep.text(.noSpaceRetryDetail), symbol: "arrow.clockwise", kind: .action(destructive: false) { [weak self] in
                self?.closeOverlay()
                self?.unlock(game)
            }),
        ]
    }

    private func settingsCategories() -> [PanelCategory] {
        let preferences = self.preferences
        // The built-in themes, then the made and installed ones.
        let designs = self.designs
        let custom = designs.firstIndex { $0.id == preferences.customTheme }
        var appearance: [PanelRow] = [
            PanelRow(id: "theme", title: T.text(.theme), symbol: "paintpalette", kind: .choice(options: Theme.allCases.map(\.title) + designs.map(\.name), selected: custom.map { Theme.allCases.count + $0 } ?? preferences.theme.rawValue) { [weak self] index in
                if index < Theme.allCases.count {
                    self?.preferences.theme = Theme(rawValue: index) ?? .cosmic
                    self?.preferences.customTheme = nil
                } else {
                    self?.preferences.customTheme = designs[index - Theme.allCases.count].id
                }
            }),
        ]
        if custom == nil {
            appearance.append(PanelRow(id: "accent", title: T.text(.accent), symbol: "circle.lefthalf.filled", kind: .choice(options: AccentColor.allCases.map(\.title), selected: AccentColor.allCases.firstIndex(of: preferences.accent ?? preferences.theme.defaultAccent) ?? 0) { [weak self] index in
                self?.preferences.accent = AccentColor.allCases[index]
            }))
        }
        appearance += [
            PanelRow(id: "themes", title: T.text(.themes), detail: T.text(.themesDetail), symbol: "square.grid.2x2", kind: .action(destructive: false) { [weak self] in self?.open(.themes) }),
            PanelRow(id: "studio", title: T.text(.themeStudio), detail: T.text(.themeStudioDetail), symbol: "wand.and.stars", kind: .action(destructive: false) { [weak self] in self?.openStudio() }),
            PanelRow(id: "backdrop", title: T.text(.background), symbol: "photo.on.rectangle", kind: .choice(options: [lookStyle.isGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency && (preferences.glassTransparency ?? 1) > 0 ? TG.text(.desktop) : T.text(.backgroundTheme), T.text(.backgroundImage), T.text(.backgroundVideo)], selected: [Preferences.Backdrop.theme, .image, .video].firstIndex(of: preferences.backdrop) ?? 0) { [weak self] index in
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
        if lookStyle.isGlass {
            // The see-through window: how much of the desktop shows, and the key art over it.
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            appearance += [
                PanelRow(id: "glassTransparency", title: TG.text(.transparency), detail: TG.text(reduced ? .transparencyReduced : .transparencyDetail), symbol: "square.on.square.dashed",
                         kind: .stepper(value: preferences.glassTransparency ?? GlassWindowRecipe.defaultTransparency, range: 0...100, step: 10, format: Self.percent) { [weak self] value in
                             self?.preferences.glassTransparency = value == GlassWindowRecipe.defaultTransparency ? nil : value
                         }),
                PanelRow(id: "glassArtwork", title: TG.text(.artworkBehind), detail: TG.text(.artworkBehindDetail), symbol: "photo",
                         kind: .toggle(preferences.glassArtwork == true) { [weak self] value in self?.preferences.glassArtwork = value ? true : nil }),
            ]
        } else {
            appearance.append(PanelRow(id: "artwork", title: T.text(.gameArtwork), symbol: "photo", kind: .toggle(preferences.gameArtwork) { [weak self] value in self?.preferences.gameArtwork = value }))
        }
        appearance += [
            PanelRow(id: "motion", title: T.text(.motion), symbol: "wind", kind: .choice(options: [T.text(.motionFull), T.text(.motionReduced)], selected: preferences.reducedMotion ? 1 : 0) { [weak self] index in
                self?.preferences.reducedMotion = index == 1
            }),
            PanelRow(id: "fullScreen", title: TH.text(.fullScreen), detail: TH.text(.fullScreenDetail), symbol: "arrow.up.left.and.arrow.down.right",
                     kind: .toggle(isFullScreen) { [weak self] value in
                         guard let self, value != self.isFullScreen else { return }
                         self.toggleFullScreen()
                     }),
        ]

        let library: [PanelRow] = libraryFolderRows() + [
            PanelRow(id: "rescan", title: T.text(.rescan), detail: T.format(.gamesFound, games.count), symbol: "arrow.clockwise", kind: .action(destructive: false) { [weak self] in
                self?.rescan()
                Sounds.shared.play(.select)
            }),
            PanelRow(id: "prepare", title: TPrep.text(.prepareNewGames), detail: TPrep.text(.prepareNewGamesDetail), symbol: "arrow.down.circle",
                     kind: .toggle(preparesNewGames) { [weak self] value in self?.preferences.prepareNewGames = value ? nil : false }),
            PanelRow(id: "clones", title: T.text(.installedSize), kind: .info("")),
        ]

        let language = PanelRow(id: "language", title: T.text(.language), symbol: "globe", kind: .choice(options: Language.allCases.map(\.displayName), selected: Language.allCases.firstIndex(of: preferences.language) ?? 0) { [weak self] index in
            self?.preferences.language = Language.allCases[index]
        })

        // The name and picture are the profile's: Settings → Profiles.
        var behaviour: [PanelRow] = [
            PanelRow(id: "sounds", title: T.text(.sounds), symbol: "speaker.wave.2",
                     kind: .stepper(value: preferences.sounds ? preferences.soundVolume ?? 100 : 0, range: 0...100, step: 10, format: Self.percent) { [weak self] value in
                         self?.preferences.sounds = value > 0
                         if value > 0 { self?.preferences.soundVolume = value }
                     }),
            PanelRow(id: "music", title: T.text(.gameMusic), detail: T.text(.gameMusicDetail), symbol: "music.note",
                     kind: .stepper(value: musicVolume, range: 0...100, step: 10, format: Self.percent) { [weak self] value in
                         self?.preferences.musicVolume = value
                     }),
            PanelRow(id: "vibration", title: TU.text(.controllerVibration), detail: TU.text(.controllerVibrationDetail), symbol: "gamecontroller",
                     kind: .toggle(preferences.controllerVibration ?? true) { [weak self] value in
                         self?.preferences.controllerVibration = value ? nil : false
                         // Turned on from the pad: a pulse at once says what it feels like.
                         if value { Feel.shared.vibrate(.select) }
                     }),
            PanelRow(id: "hide", title: T.text(.hideWhilePlaying), symbol: "eye.slash", kind: .toggle(preferences.hideWhilePlaying) { [weak self] value in self?.preferences.hideWhilePlaying = value }),
            PanelRow(id: "hiddenTrophies", title: T.text(.alwaysShowHiddenTrophies), detail: T.text(.alwaysShowHiddenTrophiesDetail), symbol: "trophy",
                     kind: .toggle(preferences.alwaysShowHiddenTrophies == true) { [weak self] value in self?.preferences.alwaysShowHiddenTrophies = value ? true : nil }),
            PanelRow(id: "discord", title: T.text(.discordPresence), detail: T.text(.discordPresenceDetail), symbol: "person.2.wave.2", kind: .toggle(preferences.discordPresence ?? true) { [weak self] value in
                self?.preferences.discordPresence = value
                if value { self?.discordOn() } else { self?.discordOff() }
            }),
            PanelRow(id: "discordJoin", title: JS.text(.discordJoin), detail: JS.text(.discordJoinDetail), symbol: "person.badge.plus",
                     kind: .toggle(preferences.discordJoin ?? true) { [weak self] value in
                         self?.preferences.discordJoin = value ? nil : false
                         self?.updateDiscord()
                     }),
            PanelRow(id: "clips", title: T.text(.clips), detail: T.format(.clipsDetail, clipSeconds), symbol: "record.circle", kind: .toggle(preferences.clips == true) { [weak self] value in
                self?.clipsChanged(value)
            }),
            PanelRow(id: "clipLength", title: T.text(.clipLength), detail: TH.format(.clipsCost, clipMegabytes), symbol: "timer",
                     kind: .choice(options: ReplayBudget.lengths.map(TH.length), selected: ReplayBudget.lengths.firstIndex(of: clipSeconds) ?? 1) { [weak self] index in
                         self?.setClipLength(ReplayBudget.lengths[index])
                     }),
            PanelRow(id: "pauseOnMenu", title: TH.text(.pauseOnMenu), detail: TH.text(.pauseOnMenuDetail), symbol: "pause.circle",
                     kind: .toggle(preferences.pauseOnMenu ?? true) { [weak self] value in self?.preferences.pauseOnMenu = value ? nil : false }),
        ] + saveSyncRows() + [
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
            PanelRow(id: "version", title: T.text(.version), kind: .info(version + (updateChannel == .nightly ? " · " + T.text(.channelNightlyShort) : ""))),
            PanelRow(id: "channel", title: T.text(.updateChannel), detail: T.text(updateChannel == .nightly ? .updateChannelNightlyDetail : .updateChannelStableDetail),
                     symbol: "point.3.connected.trianglepath.dotted",
                     kind: .choice(options: [T.text(.channelStable), T.text(.channelNightly)], selected: updateChannel == .nightly ? 1 : 0) { [weak self] index in
                         self?.setUpdateChannel(index == 1 ? .nightly : .stable)
                     }),
        ]
        // The launcher's own update: at most one row that acts, then the check and its state.
        let updateState = launcherUpdateState
        switch updateState {
        case .ready(let version):
            if restartAfterGame {
                about.append(PanelRow(id: "update", title: TU.text(.noticeWaiting), detail: TU.text(.cancelRestart), symbol: "hourglass", kind: .action(destructive: false) { [weak self] in
                    self?.cancelRestartAfterGame()
                }))
            } else {
                about.append(PanelRow(id: "update", title: TU.format(.noticeReady, version) + " · " + TU.text(.restartNow), detail: TU.text(.noticeReadyDetail),
                                      symbol: "arrow.clockwise.circle.fill", kind: .action(destructive: false) { [weak self] in self?.restartForUpdate() }))
            }
        case .downloading(let version, _):
            about.append(PanelRow(id: "update", title: TU.format(.stateDownloading, version, updateState.percent ?? 0), symbol: "arrow.down.circle", kind: .info("")))
        case .available(let version):
            about.append(PanelRow(id: "update", title: T.format(.updateTo, version), detail: canReplaceItself ? TU.text(.stateAvailableDetail) : T.text(.updateNotWritable),
                                  symbol: "arrow.down.circle.fill", kind: .action(destructive: false) { [weak self] in self?.installUpdate() }))
        default:
            break
        }
        if let update = readyUpdate?.release ?? availableUpdate {
            about.append(PanelRow(id: "whatsNew", title: T.text(.whatsNew), detail: update.page.absoluteString.replacingOccurrences(of: "https://", with: ""), symbol: "sparkles", kind: .action(destructive: false) {
                NSWorkspace.shared.open(update.page)
            }))
        }
        about.append(PanelRow(id: "checkForUpdates", title: T.text(.checkForUpdatesNow), detail: TU.checkLine(updateState),
                              symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in self?.checkForUpdatesNow() }))
        about += [
            PanelRow(id: "toolkit", title: T.text(.toolkitVersion), kind: .info(builtInToolkit.map { Toolkit.shortVersion($0.version) } ?? "—")),
            PanelRow(id: "author", title: T.text(.madeBy), kind: .info("Utku Halis")),
            PanelRow(id: "github", title: "GitHub", detail: "github.com/AnyTogether/AnyPS5-ARM", symbol: "chevron.left.forwardslash.chevron.right", kind: .action(destructive: false) {
                NSWorkspace.shared.open(URL(string: "https://github.com/AnyTogether/AnyPS5-ARM")!)
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
            PanelRow(id: "screenshotsHint", title: T.text(.screenshotsHint), kind: .info("")),
        ]
        advanced.append(PanelRow(id: "phones", title: T.text(.phones), kind: .info(phones.isEmpty ? T.text(.phonesNone)
            : connectedPhones.isEmpty ? "" : T.format(.phonesConnectedCount, connectedPhones.count))))
        for device in phones {
            let online = connectedPhones.contains(device.id)
            advanced.append(PanelRow(id: "phone-" + device.id, title: online ? "\(device.name) · \(T.text(.phoneOnline))" : device.name, detail: T.text(.phoneRemove),
                                     symbol: online ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3", kind: .action(destructive: true) { [weak self] in
                self?.removePhone(device.id)
            }))
        }
        advanced += browserPlayRows()

        return [
            PanelCategory(id: "profiles", title: TPro.text(.profilesCategory), symbol: "person.crop.circle", rows: profileRows()),
            PanelCategory(id: "appearance", title: T.text(.appearance), symbol: "paintbrush", rows: appearance),
            PanelCategory(id: "library", title: T.text(.storage), symbol: "square.grid.2x2", rows: library),
            PanelCategory(id: "language", title: T.text(.language), symbol: "globe", rows: [language]),
            PanelCategory(id: "behaviour", title: T.text(.behaviour), symbol: "slider.horizontal.3", rows: behaviour),
            PanelCategory(id: "power", title: TPow.text(.title), symbol: "battery.75percent", rows: powerRows()),
            PanelCategory(id: "controllers", title: TP.text(.title), symbol: "gamecontroller", rows: controllerRows()),
            PanelCategory(id: "display", title: T.text(.displayDefaults), symbol: "macwindow", rows: displayDefaultRows()),
            PanelCategory(id: "presets", title: TPresets.text(.title), symbol: "dial.medium", rows: gamePresetRows()),
            PanelCategory(id: "shortcuts", title: TH.text(.shortcuts), symbol: "command", rows: shortcutRows()),
            PanelCategory(id: "together", title: "AnyTogether", symbol: "person.2.circle", rows: togetherRows()),
            PanelCategory(id: "broadcast", title: TB.text(.title), symbol: "dot.radiowaves.left.and.right", rows: broadcastSettingsRows()),
            PanelCategory(id: "engine", title: TE.text(.engineTitle), symbol: "gearshape.2", rows: engineRows()),
            PanelCategory(id: "fonts", title: TF.text(.title), symbol: "textformat", rows: fontRows()),
            PanelCategory(id: "advanced", title: T.text(.advanced), symbol: "wrench.and.screwdriver", rows: advanced),
            PanelCategory(id: "steam", title: TSteam.text(.title), symbol: "gamecontroller.fill", rows: steamRows()),
            PanelCategory(id: "about", title: T.text(.about), symbol: "info.circle", rows: about),
        ]
    }

    private func gameRows(_ game: Game) -> [PanelRow] {
        let settings = settings(for: game)
        // The game playing can be broadcast from here (BroadcastPanel.swift).
        var rows: [PanelRow] = broadcastGameRows(game)
        let choices = resolutionChoices(for: game)
        if !choices.isEmpty {
            let options = [T.text(.resolutionDefault)] + choices
            rows.append(PanelRow(id: "resolution", title: T.text(.resolution), symbol: "rectangle.on.rectangle", kind: .choice(options: options, selected: settings.resolution.flatMap { choices.firstIndex(of: $0) }.map { $0 + 1 } ?? 0) { [weak self] index in
                self?.update(game) { $0.resolution = index == 0 ? nil : choices[index - 1] }
            }))
        }
        rows += gameDisplayRows(game, settings)
        rows.append(PanelRow(id: "frameGeneration", title: T.text(.frameGeneration), detail: T.text(lowPowerNotice != nil ? .frameGenerationLowPower : .frameGenerationDetail), symbol: "square.stack.3d.forward.dottedline",
                             kind: .toggle(settings.frameGeneration == true) { [weak self] value in self?.update(game) { $0.frameGeneration = value ? true : nil } }))
        rows.append(PanelRow(id: "controls", title: T.text(.controls), symbol: "keyboard", kind: .action(destructive: false) { [weak self] in self?.open(.controls) }))
        if let set = trophies[game.id] {
            rows.append(PanelRow(id: "trophies", title: T.text(.trophies), detail: "\(set.unlockedCount)/\(set.trophies.count) · \(set.percent)%", symbol: "trophy", kind: .action(destructive: false) { [weak self] in self?.open(.trophies) }))
        }
        rows += gameSocialRows(game)
        rows.append(PanelRow(id: "advanced", title: T.text(.advanced), detail: T.text(.advancedDetail), symbol: "slider.horizontal.below.rectangle", kind: .action(destructive: false) { [weak self] in self?.open(.advanced) }))
        let overlays = GameSettings.Overlay.allCases
        let overlayNames = [T.text(.overlayOff), T.text(.overlayTopLeft), T.text(.overlayTopRight), T.text(.overlayBottomLeft), T.text(.overlayBottomRight)]
        rows.append(PanelRow(id: "overlay", title: T.text(.overlay), symbol: "speedometer", kind: .choice(options: overlayNames, selected: overlays.firstIndex(of: settings.overlay) ?? 0) { [weak self] index in
            self?.update(game) { $0.overlay = overlays[index] }
        }))
        if settings.overlay != .off {
            let styles = GameSettings.OverlayStyle.allCases
            rows.append(PanelRow(id: "overlayStyle", title: T.text(.overlayStyle), symbol: "textformat.size",
                                 kind: .choice(options: [T.text(.overlayMinimal), T.text(.overlayDetailed)], selected: styles.firstIndex(of: settings.style) ?? 0) { [weak self] index in
                self?.update(game) { $0.overlayStyle = styles[index] }
            }))
        }
        let languages = ConsoleLanguage.all
        rows.append(PanelRow(id: "language", title: T.text(.gameLanguage), symbol: "character.bubble", kind: .choice(options: [T.text(.followLauncher)] + languages.map(\.name), selected: settings.language.flatMap { number in languages.firstIndex { $0.number == number } }.map { $0 + 1 } ?? 0) { [weak self] index in
            self?.update(game) { $0.language = index == 0 ? nil : languages[index - 1].number }
        }))
        rows.append(gameEngineRow(game))
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
        rows.append(PanelRow(id: "link", title: T.text(.copyLink), detail: DeepLink.game(game.titleID).url.absoluteString, symbol: "link", kind: .action(destructive: false) { [weak self] in self?.copyLink(game) }))
        rows.append(PanelRow(id: "log", title: T.text(.openLog), symbol: "doc.text", kind: .action(destructive: false) { [weak self] in self?.openLog(game) }))
        rows.append(PanelRow(id: "report", title: TC.text(.lastSessionReport), detail: diagnoses[game.id]?.summary ?? TC.text(.lastSessionReportDetail), symbol: "stethoscope",
                             kind: .action(destructive: false) { [weak self] in self?.makeReport(game) }))
        rows.append(PanelRow(id: "trace", title: TC.text(.traceTitle), detail: TC.text(.traceDetail), symbol: "text.magnifyingglass",
                             kind: .toggle(settings.trace == true) { [weak self] value in self?.update(game) { $0.trace = value ? true : nil } }))
        if case .installed = state {
            rows.append(PanelRow(id: "playTraced", title: TC.text(.reportPlayTraced), detail: TC.text(.reportPlayTracedDetail), symbol: "play.circle",
                                 kind: .action(destructive: false) { [weak self] in
                self?.closeOverlay()
                self?.play(game, trace: true)
            }))
        }
        rows.append(PanelRow(id: "cache", title: T.text(.clearShaderCache), symbol: "sparkles", kind: .action(destructive: false) { [weak self] in self?.clearShaderCache(game) }))
        if case .installed = state {
            rows.append(PanelRow(id: "uninstall", title: T.text(.uninstall), symbol: "trash", kind: .action(destructive: true) { [weak self] in self?.open(.confirmUninstall) }))
        }
        return rows
    }

    private func controlRows(_ game: Game) -> [PanelRow] {
        let changes = settings(for: game).controls ?? [:]
        // The game's own actions, when its files name them, under each button.
        let actions = gameControls[game.id] ?? [:]
        var rows = gyroRows(game)
        rows.append(PanelRow(id: "hint", title: T.text(.controlsHint), detail: actions.isEmpty ? nil : T.text(.controlsFromGame), kind: .info("")))
        for action in PadAction.allCases {
            rows.append(PanelRow(id: action.rawValue, title: action.title, detail: actions[action]?.joined(separator: " · "), symbol: action.symbol,
                                 kind: .keys(Controls.sources(action, changes), capturing: capturing == action) { [weak self] in
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

    /// Settings → Game Library's folders: one row each (where, and how many games or not
    /// connected), pressed to remove it after asking, then Add Folder.
    func libraryFolderRows() -> [PanelRow] {
        let statuses = libraryFolders
        var rows: [PanelRow] = []
        for path in preferences.libraryFolders {
            let url = URL(fileURLWithPath: path)
            let status = statuses.first { $0.url.standardizedFileURL == url.standardizedFileURL }
            let connected = status?.connected ?? true
            let state = !connected ? T.text(.folderNotConnected) : status.map { $0.games == 1 ? T.text(.folderOneGame) : T.format(.folderGames, $0.games) } ?? T.text(.scanning)
            let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
            rows += askingFirst(PanelRow(id: "folder-" + path, title: name, detail: url.abbreviatedPath + " · " + state,
                                         symbol: connected ? "folder" : "externaldrive.badge.xmark", kind: .action(destructive: false) { [weak self] in self?.removeFolder(path) }),
                                question: T.format(.removeFolderAsk, name), confirm: T.text(.removeFolder))
        }
        rows.append(PanelRow(id: "addFolder", title: T.text(.addFolder), detail: T.text(.addFolderDetail), symbol: "folder.badge.plus",
                             kind: .action(destructive: false) { [weak self] in self?.pickGamesFolder() }))
        return rows
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

    /// Picks a games folder: added to the list, or as the first one (`first`, the first-run setup).
    func pickGamesFolder(first: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = T.text(.pickFolder)
        if let root = libraryRoots.first { panel.directoryURL = root }
        if panel.runModal() == .OK, let url = panel.url { chooseFolder(url, first: first) }
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
    /// Panels with categories on the left (Settings, Find players, a game's hub).
    var overlayHasCategories: Bool { overlay == .settings || overlay == .findPlayers || overlay == .gameHub }

    func panelCommand(_ command: Command) -> Bool {
        let categories = panelCategories()
        guard !categories.isEmpty else { return false }
        // Written only when it changes: a command that changed nothing hit the end (Input's bump).
        if panelCategory > categories.count - 1 { panelCategory = categories.count - 1 }
        let rows = categories[panelCategory].rows
        let single = categories.count == 1
        if !panelInRows && !single {
            switch command {
            case .up: movePanelCategory(-1, count: categories.count)
            case .down: movePanelCategory(1, count: categories.count)
            case .right, .select: enterRows(rows)
            case .back, .options: closeOverlay()
            case .left, .previousGame, .nextGame, .home, .capture: break
            }
            return true
        }
        guard !rows.isEmpty else {
            if command == .back || command == .left { leaveRows(single) }
            return true
        }
        focusRow(focusedRow(in: rows), in: rows)
        if !rows[panelRow].focusable, let first = rows.firstIndex(where: \.focusable) { focusRow(first, in: rows) }
        let row = rows[panelRow]
        // △ on a shortcut's row clears it.
        if command == .options, row.id.hasPrefix("shortcut-"), clearShortcut(row: row.id) { return true }
        // With the pad a choice changes only while it is edited (✕ starts, ✕ or ○ end); the
        // keyboard and the mouse change it at once.
        // Written only when it changes, so a move that went nowhere still bumps.
        var editor = rowEditor
        let intent = editor.intent(for: command, row: row.id, kind: row.valueKind, mode: InputModeState.shared.mode)
        if editor != rowEditor { rowEditor = editor }
        switch intent {
        case .move(let delta): movePanelRow(delta, rows)
        case .change(let delta): change(row, by: delta)
        case .activate: activate(row)
        case .startEditing, .stopEditing: Sounds.shared.play(.select)
        case .leaveRows:
            // On a value with the pad, left in a panel without categories goes nowhere rather
            // than closing it.
            if command == .left && single && row.valueKind != .other && InputModeState.shared.mode == .pad { break }
            // A question asked in place (AskFirst.swift) is answered Cancel first.
            if !cancelAsk() { leaveRows(single) }
        case .close: closeOverlay()
        case .none: break
        }
        return true
    }

    /// L1 and R1 in Settings (and the other panels with categories): the category before or after.
    func panelCategoryStep(_ delta: Int) -> Bool {
        let categories = panelCategories()
        guard categories.count > 1, capturing == nil, shortcutCapture == nil else { return true }
        let next = min(categories.count - 1, max(0, panelCategory + delta))
        guard next != panelCategory else { return true }
        if rowEditor.editing != nil { rowEditor.stop() }
        withAnimation(Motion.focus) { panelCategory = next }
        panelRow = 0
        if panelInRows {
            let rows = categories[next].rows
            if let first = rows.firstIndex(where: \.focusable) { focusRow(first, in: rows) } else { panelInRows = false }
        }
        Sounds.shared.play(.move)
        return true
    }

    private func movePanelCategory(_ delta: Int, count: Int) {
        let next = min(count - 1, max(0, panelCategory + delta))
        guard next != panelCategory else { return }
        if rowEditor.editing != nil { rowEditor.stop() }
        panelCategory = next
        panelRow = 0
        Sounds.shared.play(.move)
    }

    private func enterRows(_ rows: [PanelRow]) {
        guard let first = rows.firstIndex(where: \.focusable) else { return }
        focusRow(first, in: rows)
        panelInRows = true
        Sounds.shared.play(.move)
    }

    private func leaveRows(_ single: Bool) {
        if rowEditor.editing != nil { rowEditor.stop() }
        if single { closeOverlay(); return }
        panelInRows = false
        Sounds.shared.play(.back)
    }

    private func movePanelRow(_ delta: Int, _ rows: [PanelRow]) {
        var next = panelRow + delta
        while rows.indices.contains(next) && !rows[next].focusable { next += delta }
        guard rows.indices.contains(next) else { return }
        focusRow(next, in: rows)
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
    var title = T.text(.settings)
    var subtitle: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let categories = model.panelCategories()
        let current = categories.indices.contains(model.panelCategory) ? categories[model.panelCategory] : nil
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(title).font(.display(40 * scale, .light)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                    .padding(.bottom, subtitle == nil ? 26 * scale : 0)
                if let subtitle {
                    Text(subtitle).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 26 * scale)
                }
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
                    .background(FocusFill(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(selected ? 0.12 : 0), rim: selected))
                    .contentShape(Rectangle())
                    .hoverTick("category-\(index)")
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
                RowList(rows: current.rows, focusedRow: model.panelInRows ? model.focusedRow(in: current.rows) : nil)
                    .id(current.id)
                    .transition(.opacity.combined(with: .offset(x: 18 * scale)))
            }
        }
        .padding(.horizontal, 90 * scale)
        .padding(.top, 70 * scale)
        .padding(.bottom, 50 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenFrost(0.74)
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
                RowList(rows: rows, focusedRow: model.focusedRow(in: rows))
                    .padding(.top, 18 * scale)
            }
            .padding(36 * scale)
            .frame(width: 560 * scale, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .panelFrost()
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
            // An overlay takes no size of its own, so a long list cannot stretch the screen; a row
            // focused further down moves the list up, as scrolling to it would.
            GeometryReader { geometry in
                Color.clear.overlay(alignment: .top) { content.offset(y: -previewShift(geometry.size.height)) }
            }
            .clipped()
        } else {
            scrolling
        }
    }

    private var content: some View {
        VStack(spacing: 8 * scale) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RowView(row: row, focused: focusedRow == index, editing: focusedRow == index && model.rowEditor.isEditing(row.id))
                    .id(row.id)
                    .hoverTick("row-\(row.id)")
                    .onTapGesture {
                        if model.overlayHasCategories { model.panelInRows = true }
                        model.focusRow(index, in: rows)
                        if model.rowEditor.editing != nil { model.rowEditor.stop() }
                        model.activate(row)
                    }
            }
        }
        .padding(6 * scale)
    }

    /// How far the list scrolls to bring the focused row to the middle, from the usual row height.
    private func previewShift(_ height: CGFloat) -> CGFloat {
        guard let focusedRow else { return 0 }
        let row = 66 * scale
        let total = CGFloat(rows.count) * row + 12 * scale
        return min(max(0, (CGFloat(focusedRow) + 0.5) * row + 6 * scale - height / 2), max(0, total - height))
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
    /// The pad is changing this choice: its value wears the accent and its arrows show.
    var editing = false
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var inputMode = InputModeState.shared
    @Environment(\.scale) private var scale
    @State private var text = ""
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        let foreground: Color = focused ? .black : .white
        HStack(spacing: 14 * scale) {
            if let person = row.person {
                ProfileAvatar(url: person.avatar, name: person.name, size: 30 * scale, glow: false, picture: person.picture)
                    .overlay(Circle().strokeBorder(model.accent, lineWidth: 2.5 * scale).padding(-3 * scale).opacity(person.speaking ? 1 : 0))
                    .animation(.easeOut(duration: 0.15), value: person.speaking)
                    .overlay(alignment: .bottomTrailing) {
                        if person.appearingOffline {
                            AppearingOfflineDot(size: 14 * scale).offset(x: 3 * scale, y: 3 * scale)
                        } else if let status = person.status, status != .offline {
                            Circle().fill(status == .playing ? model.accent : Color(red: 0.3, green: 0.85, blue: 0.45))
                                .frame(width: 10 * scale, height: 10 * scale)
                                .overlay(Circle().strokeBorder(focused ? Color.white : Color(white: 0.1), lineWidth: 2 * scale))
                                .offset(x: 2 * scale, y: 2 * scale)
                        }
                    }
                    .frame(width: 30 * scale)
            } else if let symbol = row.symbol {
                Image(systemName: symbol).font(.system(size: 17 * scale, weight: .medium)).frame(width: 24 * scale)
                    .foregroundStyle(destructive && !focused ? Color(red: 1, green: 0.55, blue: 0.5) : foreground.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(row.title).font(.display(17 * scale, .medium)).lineLimit(2).minimumScaleFactor(0.85)
                    .foregroundStyle(destructive && !focused ? Color(red: 1, green: 0.6, blue: 0.55) : foreground.opacity(row.focusable ? 1 : 0.62))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = row.detail {
                    Text(detail).font(.display(13 * scale)).foregroundStyle(foreground.opacity(0.55)).lineLimit(row.wraps ? nil : 2).truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: row.wraps)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12 * scale)
            if let level = row.person?.level { LevelBadgeView(badge: level, size: 30 * scale) }
            value.foregroundStyle(foreground)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 8 * scale)
        .frame(minHeight: 58 * scale)
        .background(FocusFill(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(row.focusable ? 0.07 : 0)))
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
            .modifier(EditRing(editing: editing))
        case .toggle(let value, let set):
            Switch(on: value, accent: model.accent, focused: focused) { set(!value); Sounds.shared.play(.move) }
        case .stepper(let value, let range, let step, let format, let set):
            HStack(spacing: 12 * scale) {
                chevron("minus", enabled: value > range.lowerBound) { set(max(range.lowerBound, value - step)) }
                Text(format(value)).font(.display(16 * scale, .semibold)).monospacedDigit().frame(minWidth: 70 * scale)
                chevron("plus", enabled: value < range.upperBound) { set(min(range.upperBound, value + step)) }
            }
            .modifier(EditRing(editing: editing))
        case .action:
            Image(systemName: "chevron.right").font(.system(size: 14 * scale, weight: .semibold)).opacity(0.6)
        case .info(let value):
            Text(value).font(.display(15 * scale, .medium)).opacity(0.7).textSelection(.enabled)
        case .keys(let sources, let capturing, _):
            KeyCaps(sources: sources, capturing: capturing, focused: focused, prompt: row.id.hasPrefix("shortcut-pad-") ? TH.text(.pressButtons) : nil)
        case .text(let value, let set):
            if previewRender {
                // A text field does not draw offscreen.
                Text(value).font(.display(16 * scale, .semibold)).frame(width: 200 * scale, alignment: .trailing)
            } else {
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
    }

    /// A value's arrow for the pointer. With the pad they show only while the value is edited,
    /// where they say left and right change it.
    @ViewBuilder private func chevron(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let shown = inputMode.mode == .keyboard || editing
        Button(action: { action(); Sounds.shared.play(.move) }) {
            Image(systemName: symbol).font(.system(size: 13 * scale, weight: .bold)).frame(width: 26 * scale, height: 26 * scale).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(shown ? (enabled ? 0.85 : 0.25) : 0)
        .disabled(!enabled || !shown)
        .animation(Motion.focus, value: shown)
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
    /// What the row waits for, if not a key (Settings → Shortcuts: buttons).
    var prompt: String?
    @Environment(\.scale) private var scale
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6 * scale) {
            if capturing {
                Text(prompt ?? T.text(.pressKey)).font(.display(15 * scale, .semibold))
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
        case .aborted: return TC.text(.diagnosisAborted)
        case .exited(let code): return TC.format(.diagnosisExited, code)
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

/// The value of a choice the pad is changing: an accent ring around it, as the console marks a
/// value being set.
struct EditRing: ViewModifier {
    let editing: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6 * scale)
            .padding(.vertical, 3 * scale)
            .background {
                Capsule().fill(model.accent.opacity(editing ? 0.22 : 0))
            }
            .overlay {
                Capsule().strokeBorder(model.accent, lineWidth: 2 * scale).opacity(editing ? 1 : 0)
            }
            .animation(Motion.focus, value: editing)
    }
}
