import AnyPS5Core
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Themes: the ones on this Mac and the ones people share on the Hub, and the Theme Studio
/// that makes one, its changes drawn behind the panel as they are made.
extension AppModel {
    enum HubState: Equatable {
        case idle, loading, failed
        case loaded([ThemeHub.Theme])
    }

    func reloadDesigns() {
        designs = themes.all
    }

    func activate(_ design: ThemeDesign?) {
        withAnimation(Motion.fade) { preferences.customTheme = design?.id }
        Sounds.shared.play(.select)
    }

    /// The Studio goes back to the themes, the themes back to Settings on the row that opened them.
    func backFromThemes() {
        guard capturing == nil else { return }
        if overlay == .studio {
            open(.themes)
            return
        }
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { overlay = .settings }
        let categories = panelCategories()
        for (index, category) in categories.enumerated() {
            if let row = category.rows.firstIndex(where: { $0.id == "themes" }) {
                panelCategory = index
                panelRow = row
                panelInRows = true
            }
        }
    }

    // MARK: Rows

    func themeRows() -> [PanelRow] {
        var rows = [PanelRow(id: "mac", title: T.text(.themesOnMac), kind: .info(""))]
        for theme in Theme.allCases {
            let active = activeDesign == nil && preferences.theme == theme
            rows.append(PanelRow(id: "builtin-\(theme.rawValue)", title: theme.title, detail: active ? T.text(.themeActive) : nil, symbol: active ? "checkmark.circle.fill" : "paintpalette",
                                 kind: .action(destructive: false) { [weak self] in
                                     self?.preferences.theme = theme
                                     self?.activate(nil)
                                 }))
        }
        for design in designs {
            let active = activeDesign?.id == design.id
            let by = design.author.isEmpty ? nil : T.format(.themeBy, design.author)
            rows.append(PanelRow(id: "design-\(design.id)", title: design.name, detail: active ? [by, T.text(.themeActive)].compactMap { $0 }.joined(separator: " · ") : by,
                                 symbol: active ? "checkmark.circle.fill" : "paintpalette.fill", kind: .action(destructive: false) { [weak self] in self?.activate(design) }))
        }
        rows.append(PanelRow(id: "studio", title: T.text(.themeStudio), detail: T.text(.themeStudioDetail), symbol: "wand.and.stars", kind: .action(destructive: false) { [weak self] in self?.openStudio() }))
        rows.append(PanelRow(id: "file", title: T.text(.installThemeFile), symbol: "square.and.arrow.down", kind: .action(destructive: false) { [weak self] in self?.chooseThemeFile() }))
        rows.append(PanelRow(id: "hub", title: T.text(.themesHub), kind: .info("")))
        switch hub {
        case .idle, .loading:
            rows.append(PanelRow(id: "hub-loading", title: T.text(.hubLoading), kind: .info("")))
        case .failed:
            rows.append(PanelRow(id: "hub-retry", title: T.text(.hubFailed), symbol: "arrow.clockwise", kind: .action(destructive: false) { [weak self] in self?.loadHub(again: true) }))
        case .loaded(let shared) where shared.isEmpty:
            rows.append(PanelRow(id: "hub-empty", title: T.text(.hubEmpty), kind: .info("")))
        case .loaded(let shared):
            for theme in shared {
                let installed = designs.first { $0.id == theme.id }
                let current = installed.map { $0.version >= theme.design.version } ?? false
                rows.append(PanelRow(id: "hub-\(theme.id)", title: theme.name, detail: T.format(.themeBy, theme.design.author), symbol: current ? "checkmark.circle" : "arrow.down.circle",
                                     kind: .action(destructive: false) { [weak self] in
                                         guard let self else { return }
                                         if current, let installed { self.activate(installed) } else { self.installFromHub(theme) }
                                     }))
            }
        }
        rows.append(PanelRow(id: "share", title: T.text(.shareTheme), detail: T.text(.shareThemeHint), symbol: "square.and.arrow.up", kind: .action(destructive: false) { [weak self] in
            guard let self else { return }
            if let design = self.activeDesign { self.share(design) } else { self.openStudio() }
        }))
        return rows
    }

    func studioRows() -> [PanelRow] {
        guard let design = activeDesign else { return [] }
        let knobs = ThemeKnobs(design)
        func degrees(_ value: Int) -> String { "\(value)°" }
        var rows = [
            PanelRow(id: "name", title: T.text(.themeName), symbol: "textformat", kind: .text(design.name) { [weak self] text in self?.edit { $0.name = text } }),
            PanelRow(id: "author", title: T.text(.themeAuthor), symbol: "person", kind: .text(design.author) { [weak self] text in self?.edit { $0.author = text } }),
            PanelRow(id: "motion", title: T.text(.themeMotion), symbol: "wind", kind: .choice(options: Theme.allCases.map(\.title), selected: min(2, max(0, design.style))) { [weak self] index in
                self?.edit { $0.style = index }
            }),
            PanelRow(id: "hue", title: T.text(.themeHue), symbol: "paintpalette", kind: .stepper(value: Int(knobs.hue), range: 0...355, step: 5, format: degrees) { [weak self] value in
                self?.turn { $0.hue = Double(value) }
            }),
            PanelRow(id: "highlight", title: T.text(.themeHighlight), symbol: "sparkles", kind: .stepper(value: Int(knobs.highlight), range: -90...90, step: 5, format: degrees) { [weak self] value in
                self?.turn { $0.highlight = Double(value) }
            }),
            PanelRow(id: "depth", title: T.text(.themeDepth), symbol: "sun.max", kind: .stepper(value: knobs.depth, range: 1...10, step: 1, format: String.init) { [weak self] value in
                self?.turn { $0.depth = value }
            }),
            PanelRow(id: "accent", title: T.text(.themeAccent), symbol: "circle.lefthalf.filled", kind: .stepper(value: Int(knobs.accentHue), range: 0...355, step: 5, format: degrees) { [weak self] value in
                self?.turn { $0.accentHue = Double(value) }
            }),
            PanelRow(id: "background", title: T.text(.themeBackground), detail: design.background == nil ? T.text(.themeNoFile) : T.text(design.backgroundIsVideo ? .backgroundVideo : .backgroundImage),
                     symbol: "photo.on.rectangle", kind: .action(destructive: false) { [weak self] in self?.chooseThemeFile(music: false) }),
        ]
        if design.background != nil {
            rows.append(PanelRow(id: "background-off", title: T.text(.themeRemoveBackground), symbol: "xmark.circle", kind: .action(destructive: false) { [weak self] in self?.edit { $0.background = nil } }))
        }
        rows.append(PanelRow(id: "music", title: T.text(.themeMusic), detail: design.music == nil ? T.text(.themeNoFile) : T.text(.themeMusicDetail), symbol: "music.note",
                             kind: .action(destructive: false) { [weak self] in self?.chooseThemeFile(music: true) }))
        if design.music != nil {
            rows.append(PanelRow(id: "music-off", title: T.text(.themeRemoveMusic), symbol: "xmark.circle", kind: .action(destructive: false) { [weak self] in self?.edit { $0.music = nil } }))
        }
        rows += [
            PanelRow(id: "export", title: T.text(.exportTheme), detail: T.text(.exportThemeDetail), symbol: "square.and.arrow.down.on.square", kind: .action(destructive: false) { [weak self] in
                _ = self?.export(design)
            }),
            PanelRow(id: "share", title: T.text(.shareTheme), detail: T.text(.shareThemeDetail), symbol: "square.and.arrow.up", kind: .action(destructive: false) { [weak self] in self?.share(design) }),
            PanelRow(id: "delete", title: T.text(.deleteTheme), symbol: "trash", kind: .action(destructive: true) { [weak self] in self?.deleteDesign(design) }),
        ]
        return rows
    }

    // MARK: Studio

    /// The Studio on the theme in use; a built-in one is copied into a new theme first.
    func openStudio() {
        if activeDesign == nil {
            let (deep, middle, bright) = preferences.theme.palette
            let accent = NSColor(preferences.accentColor).usingColorSpace(.sRGB) ?? .systemBlue
            let design = ThemeDesign(name: T.text(.newThemeName), author: preferences.profileName, style: preferences.theme.rawValue,
                                     deep: ThemeDesign.hex(deep), middle: ThemeDesign.hex(middle), bright: ThemeDesign.hex(bright),
                                     accent: ThemeDesign.hex(SIMD3(Float(accent.redComponent), Float(accent.greenComponent), Float(accent.blueComponent))))
            guard let saved = try? themes.save(design, background: nil, music: nil) else { return show(T.text(.themeSaveFailed), symbol: "exclamationmark.triangle.fill") }
            reloadDesigns()
            preferences.customTheme = saved.id
        }
        open(.studio)
    }

    /// Changes the theme in use and saves it at once, so the launcher behind the Studio shows it.
    func edit(_ change: (inout ThemeDesign) -> Void) {
        guard var design = activeDesign else { return }
        let before = design
        change(&design)
        guard design != before, let saved = try? themes.save(design, background: nil, music: nil) else { return }
        // A file taken off goes from the theme's folder too.
        for (old, new) in [(before.background, saved.background), (before.music, saved.music)] where old != nil && new == nil {
            if let file = themes.file(old, of: before) { try? FileManager.default.removeItem(at: file) }
        }
        if let index = designs.firstIndex(where: { $0.id == saved.id }) { designs[index] = saved }
    }

    private func turn(_ change: (inout ThemeKnobs) -> Void) {
        guard let design = activeDesign else { return }
        var knobs = ThemeKnobs(design)
        change(&knobs)
        edit { knobs.apply(to: &$0) }
    }

    func chooseThemeFile(music: Bool) {
        guard let design = activeDesign else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = music ? [.audio] : [.image, .movie]
        panel.prompt = T.text(.chooseFile)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let saved = try themes.save(design, background: music ? nil : url, music: music ? url : nil)
            if let index = designs.firstIndex(where: { $0.id == saved.id }) { designs[index] = saved }
        } catch {
            show(T.text(.themeSaveFailed), symbol: "exclamationmark.triangle.fill")
        }
    }

    @discardableResult
    func export(_ design: ThemeDesign) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(design.name).\(ThemeDesign.fileExtension)"
        if let type = UTType(filenameExtension: ThemeDesign.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try themes.export(design, to: url)
            show(T.text(.themeSaved), symbol: "checkmark.circle.fill")
            return url
        } catch {
            show(T.text(.themeSaveFailed), symbol: "exclamationmark.triangle.fill")
            return nil
        }
    }

    /// Saves the theme as a file and opens the page it is sent to the Hub from.
    func share(_ design: ThemeDesign) {
        guard let file = export(design) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
        var page = URLComponents(url: ThemeHub.shareURL, resolvingAgainstBaseURL: false)
        let items = (page?.queryItems ?? []).map { $0.name == "title" ? URLQueryItem(name: "title", value: "Theme: \(design.name)") : $0 }
        page?.queryItems = items
        if let url = page?.url { NSWorkspace.shared.open(url) }
        show(T.text(.themeShareNext), symbol: "square.and.arrow.up")
    }

    func deleteDesign(_ design: ThemeDesign) {
        try? themes.remove(design.id)
        reloadDesigns()
        if preferences.customTheme == design.id { preferences.customTheme = nil }
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { open(.themes) }
    }

    // MARK: Installing

    func chooseThemeFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: ThemeDesign.fileExtension) { panel.allowedContentTypes = [type] }
        panel.prompt = T.text(.chooseFile)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installTheme(url)
    }

    /// A theme file from Finder, a download or the Install row: installed and used.
    func installTheme(_ file: URL) {
        do {
            let design = try themes.install(file)
            reloadDesigns()
            activate(design)
            show(T.format(.themeInstalled, design.name), symbol: "paintpalette.fill")
        } catch {
            show(T.text(.themeInstallFailed), symbol: "exclamationmark.triangle.fill")
        }
    }

    func loadHub(again: Bool = false) {
        switch hub {
        case .loading: return
        case .loaded where !again: return
        default: break
        }
        hub = .loading
        Task {
            do {
                let shared = try await ThemeHub.themes()
                withAnimation(Motion.overlay) { self.hub = .loaded(shared) }
            } catch {
                withAnimation(Motion.overlay) { self.hub = .failed }
            }
        }
    }

    func installFromHub(_ theme: ThemeHub.Theme) {
        show(T.format(.themeDownloading, theme.name), symbol: "arrow.down.circle")
        Task {
            do {
                let design = try await ThemeHub.install(theme, into: themes)
                reloadDesigns()
                activate(design)
                show(T.format(.themeInstalled, design.name), symbol: "paintpalette.fill")
            } catch {
                show(T.text(.themeInstallFailed), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}
