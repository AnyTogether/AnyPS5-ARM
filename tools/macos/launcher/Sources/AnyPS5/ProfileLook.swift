import AnyPS5Core
import AppKit
import SwiftUI

/// A profile's look (its cover or Theme Hub theme behind the header, its accent) and editing the
/// user's own: Edit showcase (six pins, trophies and games together) and Profile theme, each a
/// panel at the side of the profile. A Hub theme in Settings → Themes is worn with △ too.
extension AppModel {
    // MARK: Look

    /// The look of the profile on screen; plain from an older server.
    var profileLook: TogetherProfileLook {
        guard let profile = profilePage?.profile else { return .plain }
        return profile.isMe ? togetherProfile?.look ?? profile.look : profile.look
    }

    /// The profile's highlights: its accent, else its theme's, else the launcher's own.
    var profileAccent: Color {
        profileLook.accentHex.flatMap(ThemeDesign.rgb).map { Color(rgb: $0) } ?? accent
    }

    /// The theme the user's own profile wears.
    var wornThemeID: String? { togetherProfile?.look.theme?.id }

    /// The user's own profile is on screen, signed in and connected: it can be edited.
    var editingOwnProfile: Bool { profilePage?.profile.isMe == true && togetherUser != nil }

    /// The buttons over the own profile's columns: Edit showcase (when the server has showcases)
    /// and Profile theme.
    var profileButtons: [ProfileButton] {
        guard editingOwnProfile else { return [] }
        var buttons: [ProfileButton] = social.profileShowcase == nil ? [] : [.showcase]
        buttons.append(.theme)
        return buttons
    }

    enum ProfileButton { case showcase, theme }

    func profileButton(_ button: ProfileButton) {
        switch button {
        case .showcase: openShowcaseEditor()
        case .theme: openProfileTheme()
        }
    }

    /// The look the server keeps now, on the own profile and on the page showing it.
    func keepOwnLook(_ look: TogetherProfileLook) {
        withAnimation(Motion.overlay) {
            togetherProfile?.look = look
            if profilePage?.profile.isMe == true { profilePage?.profile.look = look }
        }
    }

    /// PATCH /me/look: the theme on (or nil, off). An older server ignores the theme: said so.
    func wearProfileTheme(_ id: String?, name: String? = nil) {
        guard togetherUser != nil else { return }
        social.profileThemeSaving = id ?? ""
        Task {
            defer { social.profileThemeSaving = nil }
            do {
                let look = try await together.setProfileTheme(id)
                if let id, look.theme?.id != id {
                    return show(TL.text(.profileThemeUnavailable), symbol: "exclamationmark.triangle.fill")
                }
                keepOwnLook(look)
                if id == nil {
                    show(TL.text(.profileThemeOff), symbol: "xmark.circle")
                } else {
                    show(TL.format(.profileThemeOn, look.theme?.name ?? name ?? ""), symbol: "paintpalette.fill")
                }
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The "Theme: <name>" chip: that theme in Settings → Themes, on its Hub row when listed.
    func openWornTheme(_ id: String) {
        open(.themes)
        let rows = themeRows()
        if let index = rows.firstIndex(where: { $0.id == "hub-\(id)" }) { focusRow(index, in: rows) }
    }

    // MARK: Edit showcase

    func openShowcaseEditor() {
        guard editingOwnProfile, let showcase = social.profileShowcase else { return }
        social.showcasePins = TogetherShowcasePins(showcase)
        social.showcasePinsBefore = social.showcasePins
        panelCategory = 0
        panelInRows = true
        let rows = showcaseRows()
        focusRow(rows.firstIndex(where: \.focusable) ?? 0, in: rows)
        withAnimation(Motion.overlay) { overlay = .showcaseEdit }
        Sounds.shared.play(.select)
    }

    /// The trophies the user earned (newest first) and the games they played, with what is pinned
    /// now kept pickable even when those lists leave it out.
    var showcaseTrophyChoices: [TogetherEarnedTrophy] {
        let earned = profilePage?.trophies.value ?? []
        let pinned = (social.profileShowcase?.trophies ?? []).filter { pin in !earned.contains { $0.id == pin.id } }
        return pinned + earned
    }

    var showcaseGameChoices: [(titleId: String, name: String, detail: String)] {
        let language = T.language.rawValue
        let played = (profilePage?.library.value ?? []).map { ($0.titleId, $0.name(in: language), ProfileView.playTime($0.secondsPlayed)) }
        let pinned = (social.profileShowcase?.games ?? []).filter { pin in !played.contains { $0.0 == pin.titleId } }
            .map { ($0.titleId, $0.name(in: language), ProfileView.playTime($0.secondsPlayed)) }
        return (pinned + played).map { choice in
            (titleId: choice.0, name: games.first { $0.titleID == choice.0 }?.name ?? choice.1, detail: choice.2)
        }
    }

    func showcaseRows() -> [PanelRow] {
        let pins = social.showcasePins
        let language = T.language.rawValue
        var rows = [PanelRow(id: "showcase-count", title: TL.format(.showcasePinnedCount, pins.count), symbol: "pin.fill", kind: .info(""))]
        let trophies = showcaseTrophyChoices
        rows.append(PanelRow(id: "showcase-trophies", title: T.text(.profileTrophies), kind: .info("")))
        if trophies.isEmpty { rows.append(PanelRow(id: "showcase-no-trophies", title: T.text(.profileNoTrophies), kind: .info(""))) }
        for trophy in trophies {
            let pinned = pins.contains(trophy: trophy)
            let game = games.first { $0.titleID == trophy.titleId }?.name ?? trophy.gameName(in: language)
            rows.append(PanelRow(id: "pin-trophy-\(trophy.id)", title: trophy.name(in: language) ?? T.text(.trophyHidden),
                                 detail: "\(TrophySet.Grade(name: trophy.grade).title) · \(game)", symbol: pinned ? "pin.fill" : "trophy",
                                 kind: .toggle(pinned) { [weak self] _ in self?.togglePin { $0.toggle(trophy: trophy) } }))
        }
        let played = showcaseGameChoices
        rows.append(PanelRow(id: "showcase-games", title: T.text(.profileGamesTitle), kind: .info("")))
        if played.isEmpty { rows.append(PanelRow(id: "showcase-no-games", title: T.text(.profileNoGames), kind: .info(""))) }
        for game in played {
            let pinned = pins.contains(game: game.titleId)
            rows.append(PanelRow(id: "pin-game-\(game.titleId)", title: game.name, detail: game.detail, symbol: pinned ? "pin.fill" : "gamecontroller",
                                 kind: .toggle(pinned) { [weak self] _ in self?.togglePin { $0.toggle(game: game.titleId) } }))
        }
        return rows
    }

    /// Six pinned already: a bump and a note, and the switch stays off.
    private func togglePin(_ change: (inout TogetherShowcasePins) -> Bool) {
        var pins = social.showcasePins
        guard change(&pins) else {
            Sounds.shared.play(.bump)
            return show(TL.text(.showcaseFull), symbol: "pin.slash")
        }
        social.showcasePins = pins
    }

    /// Back to the profile; what changed is saved (PUT /me/showcase with both lists) and shown at
    /// once, put back with the reason when the server says no.
    func closeShowcaseEditor() {
        let pins = social.showcasePins
        let changed = pins != social.showcasePinsBefore
        withAnimation(Motion.overlay) { overlay = profilePage == nil ? nil : .profile }
        Sounds.shared.play(.back)
        guard changed, let before = social.profileShowcase else { return }
        withAnimation(Motion.overlay) { social.profileShowcase = Self.showcase(pins, from: before, trophies: showcaseTrophyChoices) }
        Task {
            do {
                let saved = try await together.setShowcase(pins)
                withAnimation(Motion.overlay) { social.profileShowcase = saved }
                show(TL.text(.showcaseSaved), symbol: "pin.fill")
            } catch {
                withAnimation(Motion.overlay) { social.profileShowcase = before }
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The showcase as it will look once saved, from what is known of each pin.
    static func showcase(_ pins: TogetherShowcasePins, from before: TogetherShowcase, trophies: [TogetherEarnedTrophy]) -> TogetherShowcase {
        let known = (before.trophies ?? []) + trophies
        return TogetherShowcase(trophies: pins.trophies.compactMap { pin in known.first { $0.titleId == pin.titleId && $0.trophyId == pin.trophyId } },
                                games: pins.games.map { id in
                                    before.games?.first { $0.titleId == id } ?? TogetherShowcaseGame(titleId: id, names: [:], iconUrl: nil, secondsPlayed: 0, trophiesEarned: nil, trophiesTotal: nil, progress: nil)
                                })
    }

    // MARK: Profile theme

    func openProfileTheme() {
        guard editingOwnProfile else { return }
        panelCategory = 0
        panelInRows = true
        withAnimation(Motion.overlay) { overlay = .profileTheme }
        Sounds.shared.play(.select)
        let rows = profileThemeRows()
        focusRow(rows.firstIndex { $0.id == "wear-\(wornThemeID ?? "")" } ?? rows.firstIndex(where: \.focusable) ?? 0, in: rows)
        loadProfileThemes()
    }

    func loadProfileThemes() {
        social.profileThemesTask?.cancel()
        if social.profileThemes.isEmpty { social.profileThemesLoad = .loading }
        social.profileThemesTask = Task {
            do {
                let themes = try await together.popularThemes()
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.profileThemes = themes.map { TogetherProfileTheme($0) }
                    social.profileThemesLoad = .shown
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { social.profileThemesLoad = .failed }
            }
        }
    }

    func profileThemeRows() -> [PanelRow] {
        let worn = togetherProfile?.look.theme ?? (profilePage?.profile.isMe == true ? profilePage?.profile.look.theme : nil)
        var rows: [PanelRow] = []
        if let worn {
            rows.append(PanelRow(id: "theme-off", title: TL.text(.themeTakeOff), detail: TL.format(.profileThemeName, worn.name), symbol: "xmark.circle",
                                 kind: .action(destructive: false) { [weak self] in self?.wearProfileTheme(nil) }))
        }
        rows.append(PanelRow(id: "themes-hub", title: T.text(.themesHub), kind: .info("")))
        // The worn one first, even when the Hub's list has moved on.
        let listed = social.profileThemes
        let themes = (worn.map { worn in listed.contains { $0.id == worn.id } ? [] : [worn] } ?? []) + listed
        switch social.profileThemesLoad {
        case .loading where listed.isEmpty:
            rows.append(PanelRow(id: "themes-loading", title: T.text(.hubLoading), kind: .info("")))
        case .failed where listed.isEmpty:
            rows.append(PanelRow(id: "themes-retry", title: T.text(.hubFailed), symbol: "arrow.clockwise", kind: .action(destructive: false) { [weak self] in self?.loadProfileThemes() }))
        default:
            if listed.isEmpty && worn == nil { rows.append(PanelRow(id: "themes-empty", title: T.text(.hubEmpty), kind: .info(""))) }
        }
        for theme in themes {
            let on = theme.id == worn?.id
            let by = theme.maker.map { T.format(.themeBy, $0.displayName) }
            rows.append(PanelRow(id: "wear-\(theme.id)", title: theme.name, detail: [by, on ? TL.text(.profileThemeWorn) : nil].compactMap { $0 }.joined(separator: " · "),
                                 symbol: on ? "checkmark.circle.fill" : "paintpalette", kind: .action(destructive: false) { [weak self] in
                                     guard let self, !on else { return }
                                     self.wearProfileTheme(theme.id, name: theme.name)
                                 }))
        }
        return rows
    }

    func closeProfileTheme() {
        social.profileThemesTask?.cancel()
        withAnimation(Motion.overlay) { overlay = profilePage == nil ? nil : .profile }
        Sounds.shared.play(.back)
    }

    // MARK: Theme Hub

    /// △ on a theme of AnyTogether's Hub: on the user's profile, or off it when it is the one worn.
    func hubWearOption(_ theme: ThemeHub.Theme) -> PanelRow.Option? {
        guard togetherUser != nil, theme.source == ThemeHub.base(onServer: together.base), TogetherHubTheme.isID(theme.id) else { return nil }
        if wornThemeID == theme.id {
            return PanelRow.Option(label: TL.text(.themeTakeOff)) { [weak self] in self?.wearProfileTheme(nil) }
        }
        return PanelRow.Option(label: TL.text(.themeWear)) { [weak self] in self?.wearProfileTheme(theme.id, name: theme.name) }
    }

    // MARK: Previews

    func previewShowcaseEditor(pins: TogetherShowcasePins, row: String? = nil) {
        social.showcasePins = pins
        social.showcasePinsBefore = pins
        overlay = .showcaseEdit
        panelInRows = true
        let rows = showcaseRows()
        focusRow(rows.firstIndex { $0.id == row } ?? rows.firstIndex(where: \.focusable) ?? 0, in: rows)
    }

    func previewProfileTheme(_ themes: [TogetherProfileTheme], row: String? = nil) {
        social.profileThemes = themes
        social.profileThemesLoad = .shown
        overlay = .profileTheme
        panelInRows = true
        let rows = profileThemeRows()
        focusRow(rows.firstIndex { $0.id == row } ?? rows.firstIndex(where: \.focusable) ?? 0, in: rows)
    }
}

// MARK: Views

/// The picture behind a profile's header: its cover, else its theme's still, tinted from the
/// theme's deep tone to its middle one, darkened where the name and numbers sit.
struct ProfileBackdrop: View {
    let look: TogetherProfileLook
    @Environment(\.scale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
        ZStack {
            if let tint = look.tint {
                LinearGradient(colors: [Self.color(tint.deep), Self.color(tint.middle)], startPoint: .bottomLeading, endPoint: .topTrailing)
            } else {
                Color.black.opacity(0.35)
            }
            if let picture = look.picture.flatMap(URL.init(string:)) {
                // Sized by the header, never by the picture: a filled picture larger than it is cut.
                Color.clear.overlay {
                    if picture.isFileURL {
                        ArtworkImage(url: picture, maxPixels: 1800)
                    } else {
                        AsyncImage(url: picture) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                    }
                }
                .clipped()
            }
            if let tint = look.tint {
                // The theme's own colour over its picture, deeper where the text is.
                LinearGradient(colors: [Self.color(tint.deep).opacity(0.85), Self.color(tint.middle).opacity(0.35), Self.color(tint.middle).opacity(0.1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.18), .black.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 30 * scale, y: 12 * scale)
        .allowsHitTesting(false)
    }

    static func color(_ hex: String) -> Color { ThemeDesign.rgb(hex).map { Color(rgb: $0) } ?? .black }
}

/// "Theme: Neon Nights", in the theme's colours; a click shows it in Settings → Themes.
struct ProfileThemeChip: View {
    let theme: TogetherProfileTheme
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let bright = ProfileBackdrop.color(theme.colors.bright)
        Button { model.openWornTheme(theme.id) } label: {
            HStack(spacing: 7 * scale) {
                // The theme's three tones, as its swatch.
                HStack(spacing: -4 * scale) {
                    ForEach([theme.colors.deep, theme.colors.middle, theme.colors.accent], id: \.self) { hex in
                        Circle().fill(ProfileBackdrop.color(hex)).frame(width: 12 * scale, height: 12 * scale)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    }
                }
                Text(TL.format(.profileThemeName, theme.name)).lineLimit(1)
            }
            .font(.display(12 * scale, .semibold))
            .foregroundStyle(.white)
            .padding(.leading, 8 * scale)
            .padding(.trailing, 11 * scale)
            .padding(.vertical, 5 * scale)
            .background(Capsule().fill(bright.opacity(0.22)))
            .overlay(Capsule().strokeBorder(bright.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
