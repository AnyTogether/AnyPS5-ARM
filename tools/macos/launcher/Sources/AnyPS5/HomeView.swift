import AnyPS5Core
import SwiftUI

/// The theme animation, the user's own picture or video, and the selected game's artwork over it.
struct Backdrop: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.stillBackground) private var stillBackground

    var body: some View {
        let preferences = model.preferences
        let paused = model.running != nil || !model.active || preferences.reducedMotion
        ZStack {
            if let design = model.activeDesign, let file = model.themes.file(design.background, of: design) {
                if design.backgroundIsVideo {
                    LoopingVideo(url: file, paused: paused)
                } else {
                    DriftingImage(url: file, animated: !preferences.reducedMotion)
                }
            } else {
            switch preferences.backdrop {
            case .image where preferences.backdropFile != nil:
                DriftingImage(url: URL(fileURLWithPath: preferences.backdropFile!), animated: !preferences.reducedMotion)
            case .video where preferences.backdropFile != nil:
                LoopingVideo(url: URL(fileURLWithPath: preferences.backdropFile!), paused: paused)
            default:
                if let still = stillBackground {
                    Image(nsImage: still).resizable()
                } else {
                    ThemeBackground(theme: model.lookStyle, palette: model.activeDesign?.palette, paused: paused)
                }
            }
            }
            if preferences.onboarded, preferences.gameArtwork, model.overlay != .settings, let game = model.selectedGame, let background = game.background {
                GameArtwork(url: background, animated: !preferences.reducedMotion)
                    .id(game.id)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: model.selectedGame?.id)
        .animation(Motion.fade, value: preferences.theme)
        .animation(Motion.fade, value: model.activeDesign?.background)
        .ignoresSafeArea()
    }
}

/// pic0.png behind the home screen, drifting slowly, darkened where the text sits.
struct GameArtwork: View {
    let url: URL
    var animated: Bool
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ArtworkImage(url: url, maxPixels: Int(max(proxy.size.width, proxy.size.height) * 1.6))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(drift ? 1.07 : 1.01, anchor: .topTrailing)
                    .clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.78), location: 0), .init(color: .black.opacity(0.35), location: 0.5), .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.3), .init(color: .clear, location: 0.55), .init(color: .black.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar()
                .padding(.horizontal, 64 * scale)
                .padding(.top, 34 * scale)
            if model.games.isEmpty {
                EmptyLibrary()
            } else {
                TileRow()
                    .padding(.top, 34 * scale)
                Spacer(minLength: 0)
                if let game = model.selectedGame {
                    HeroInfo(game: game)
                        .id(game.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14 * scale)), removal: .opacity))
                        .padding(.horizontal, 72 * scale)
                }
                HStack {
                    Spacer()
                    HintBar()
                }
                .padding(.horizontal, 64 * scale)
                .padding(.vertical, 28 * scale)
            }
        }
        .animation(Motion.layout, value: model.selectedGame?.id)
    }
}

struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 22 * scale) {
            Text(T.text(.games))
                .font(.display(24 * scale, .semibold))
                .foregroundStyle(.white)
            if model.scanning {
                ProgressView().controlSize(.small).tint(.white).scaleEffect(scale)
            }
            Spacer()
            iconButton("square.grid.3x3.fill", index: 0) { model.open(.library) }
            iconButton("gearshape.fill", index: 1) { model.open(.settings) }
            iconButton("person.2.fill", index: 2, badge: model.togetherRequests.incoming.count + model.friendsOnline) { model.open(.friends) }
            iconButton("bubble.left.and.bubble.right.fill", index: 3, badge: model.unreadMessages) { model.openMessages() }
            // In the party's voice: the microphone, ringed while someone speaks.
            iconButton(model.voiceCall == nil ? (model.party == nil ? "person.3" : "person.3.fill") : (model.micSending ? "mic.fill" : "mic.slash.fill"),
                       index: 4, badge: model.partyInvites.count, ring: !model.voiceSpeaking.isEmpty) { model.open(.party) }
            iconButton(model.social.notifications.unread > 0 ? "bell.badge.fill" : "bell.fill", index: 5, badge: model.social.notifications.unread) { model.openNotifications() }
            PhoneIndicator(phone: model.phone, connecting: model.phoneConnecting, badges: model.phoneBadges)
            HStack(spacing: 10 * scale) {
                // Signed in to AnyTogether: the avatar and name others see.
                let name = model.togetherUser?.displayName ?? model.preferences.profileName
                ProfileAvatar(url: model.togetherUser?.avatar, name: name, size: 36 * scale, glow: false)
                Text(name).font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.9))
            }
            Clock()
        }
    }

    private func iconButton(_ symbol: String, index: Int, badge: Int = 0, ring: Bool = false, action: @escaping () -> Void) -> some View {
        let focused = model.focus == .top(index) && model.overlay == nil
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18 * scale, weight: .semibold))
                .foregroundStyle(focused ? Color.black : .white.opacity(0.9))
                .frame(width: 44 * scale, height: 44 * scale)
                .background(Circle().fill(focused ? Color.white : Color.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(model.accent, lineWidth: 2.5 * scale).padding(-3 * scale).opacity(ring ? 1 : 0).animation(.easeOut(duration: 0.15), value: ring))
                .overlay(alignment: .topTrailing) {
                    // Friends online or asking, in the accent.
                    if badge > 0 {
                        Text("\(min(badge, 99))").font(.display(11 * scale, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5 * scale).frame(minWidth: 18 * scale, minHeight: 18 * scale)
                            .background(Capsule().fill(model.accent)).offset(x: 4 * scale, y: -4 * scale)
                    }
                }
                .scaleEffect(focused ? 1.1 : 1)
                .shadow(color: .white.opacity(focused ? 0.4 : 0), radius: 10 * scale)
        }
        .buttonStyle(.plain)
        .animation(Motion.focus, value: focused)
    }
}

/// The row of game tiles: the selected one is larger, sits at the row's start and carries the
/// game's name beside it, as on the console.
struct TileRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let small = 118 * scale
        let large = 176 * scale
        let gap = 16 * scale
        let label = 300 * scale
        let leading = 64 * scale
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.games.enumerated()), id: \.element.id) { index, game in
                    let selected = index == model.selected
                    let offset = index - model.selected
                    let x: CGFloat = offset < 0
                        ? leading + CGFloat(offset) * (small + gap)
                        : offset == 0 ? leading : leading + large + gap + label + CGFloat(offset - 1) * (small + gap)
                    GameTile(game: game, size: selected ? large : small, focused: selected && model.focus == .tiles && model.overlay == nil)
                        .offset(x: x, y: selected ? 0 : (large - small) * 0.18)
                        .opacity(offset < 0 ? 0.0 : 1)
                        .onTapGesture(count: 2) { model.selected = index; model.primaryAction(game) }
                        .onTapGesture {
                            if model.selected != index { Sounds.shared.play(.move) }
                            model.selected = index
                            model.focus = .tiles
                            model.measureSelected()
                        }
                    if selected {
                        VStack(alignment: .leading, spacing: 6 * scale) {
                            Text(game.name)
                                .font(.display(22 * scale, .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            StateLabel(state: model.state(of: game))
                        }
                        .frame(width: label - gap, alignment: .leading)
                        .offset(x: leading + large + gap * 1.4, y: large * 0.32)
                        .transition(.opacity)
                    }
                }
            }
            .animation(Motion.layout, value: model.selected)
        }
        .frame(height: large + 10 * scale)
    }
}

struct GameTile: View {
    let game: Game
    let size: CGFloat
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let state = model.state(of: game)
        let radius = size * 0.12
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.08))
            if let icon = game.icon {
                ArtworkImage(url: icon, maxPixels: 400)
            } else {
                Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.32)).foregroundStyle(.white.opacity(0.5))
            }
            overlay(for: state)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: focused ? 22 * scale : 10 * scale, y: 8 * scale)
        .focusRing(focused, radius: radius)
        .animation(Motion.focus, value: focused)
        .animation(Motion.layout, value: size)
    }

    @ViewBuilder private func overlay(for state: GameState) -> some View {
        switch state {
        case .locked, .unreadable, .failed:
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.42)
                Image(systemName: state == .unreadable ? "xmark.octagon.fill" : (state == .locked ? "lock.fill" : "exclamationmark.triangle.fill"))
                    .font(.system(size: size * 0.13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(size * 0.08)
                    .background(Circle().fill(Color.black.opacity(0.55)).padding(size * 0.035))
            }
        case .installing(let step, let fraction):
            VStack {
                Spacer()
                ProgressLine(fraction: step.overall(fraction), color: model.accent, height: max(3, size * 0.03))
                    .padding(size * 0.07)
            }
            .background(Color.black.opacity(0.3))
        case .queued:
            ZStack { Color.black.opacity(0.42); Image(systemName: "clock").font(.system(size: size * 0.18)).foregroundStyle(.white.opacity(0.85)) }
        case .starting:
            ZStack { Color.black.opacity(0.42); ProgressView().controlSize(.small).tint(.white) }
        case .running:
            ZStack(alignment: .topTrailing) {
                Color.clear
                Circle().fill(model.accent).frame(width: size * 0.09, height: size * 0.09).padding(size * 0.07).shadow(color: model.accent, radius: 6)
            }
        case .installed:
            EmptyView()
        }
    }
}

struct StateLabel: View {
    let state: GameState
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let (symbol, text, tint): (String, String, Color) = {
            switch state {
            case .locked: return ("lock.fill", T.text(.locked), .white.opacity(0.75))
            case .unreadable: return ("xmark.octagon.fill", T.text(.unreadableDump), Color(red: 1, green: 0.6, blue: 0.55))
            case .queued: return ("clock", T.text(.queued), .white.opacity(0.75))
            case .installing(let step, _): return ("arrow.down.circle.fill", step.title, model.accent)
            case .failed: return ("exclamationmark.triangle.fill", T.text(.failed), Color(red: 1, green: 0.6, blue: 0.55))
            case .installed(let outdated): return (outdated ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill", outdated ? T.text(.updateAvailable) : T.text(.ready), outdated ? Color(red: 1, green: 0.82, blue: 0.4) : .white.opacity(0.75))
            case .starting: return ("hourglass", T.text(.starting), model.accent)
            case .running: return ("play.circle.fill", T.text(.running), model.accent)
            }
        }()
        Label(text, systemImage: symbol)
            .font(.display(14 * scale, .medium))
            .foregroundStyle(tint)
            .lineLimit(2)
    }
}

/// The selected game's title, its main button and the facts about it.
struct HeroInfo: View {
    let game: Game
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let state = model.state(of: game)
        VStack(alignment: .leading, spacing: 22 * scale) {
            Text(game.name)
                .font(.display(58 * scale, .light))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 12)
            HStack(spacing: 16 * scale) {
                ConsoleButton(title: primaryTitle(state), symbol: primarySymbol(state), focused: model.focus == .actions(0) && model.overlay == nil, prominent: true, minWidth: 210) {
                    model.focus = .actions(0)
                    model.primaryAction(game)
                }
                if let set = model.trophies[game.id] {
                    ConsoleButton(title: "\(set.unlockedCount)/\(set.trophies.count)", symbol: "trophy.fill", focused: model.focus == .actions(1) && model.overlay == nil) {
                        model.focus = .actions(1)
                        model.open(.trophies)
                    }
                }
                let settingsIndex = model.actionCount - 1
                ConsoleButton(title: "", symbol: "ellipsis", focused: model.focus == .actions(settingsIndex) && model.overlay == nil) {
                    model.focus = .actions(settingsIndex)
                    model.open(.gameSettings)
                }
                if case .installing(let step, let fraction) = state {
                    VStack(alignment: .leading, spacing: 8 * scale) {
                        HStack {
                            Text(step.title).font(.display(15 * scale, .medium))
                            Spacer()
                            Text("\(Int(step.overall(fraction) * 100))%").font(.display(15 * scale, .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        if step == .relink && fraction == 0 {
                            IndeterminateLine(color: model.accent)
                        } else {
                            ProgressLine(fraction: step.overall(fraction), color: model.accent)
                        }
                    }
                    .frame(width: 340 * scale)
                    .padding(.leading, 10 * scale)
                    .transition(.opacity)
                } else if case .failed(let message) = state {
                    Text(message)
                        .font(.display(14 * scale))
                        .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.65))
                        .lineLimit(2)
                        .frame(maxWidth: 520 * scale, alignment: .leading)
                } else if let diagnosis = model.diagnoses[game.id] {
                    Label(diagnosis.summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.display(14 * scale))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.5))
                        .lineLimit(2)
                        .frame(maxWidth: 520 * scale, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .animation(Motion.layout, value: state)
            HStack(spacing: 14 * scale) {
                InfoCard(title: T.text(.status), symbol: "circle.dashed") { StateLabel(state: state) }
                InfoCard(title: T.text(.size), symbol: "internaldrive") {
                    Text((model.sizes[game.id] ?? -1).byteText).font(.display(17 * scale, .semibold)).foregroundStyle(.white)
                }
                InfoCard(title: T.text(.titleID), symbol: "number") {
                    Text(game.titleID).font(.display(17 * scale, .semibold)).foregroundStyle(.white)
                }
                InfoCard(title: T.text(.version), symbol: "tag") {
                    Text(game.version).font(.display(17 * scale, .semibold)).foregroundStyle(.white)
                }
            }
        }
        .onAppear { model.measureSelected() }
    }

    private func primaryTitle(_ state: GameState) -> String {
        switch state {
        case .installed: return T.text(.play)
        case .locked, .unreadable: return T.text(.unlock)
        case .failed: return T.text(.retry)
        case .installing, .queued: return T.text(.cancel)
        case .starting: return T.text(.starting)
        case .running: return T.text(.running)
        }
    }

    private func primarySymbol(_ state: GameState) -> String {
        switch state {
        case .installed: return "play.fill"
        case .locked, .unreadable: return "lock.open.fill"
        case .failed: return "arrow.clockwise"
        case .installing, .queued: return "xmark"
        case .starting: return "hourglass"
        case .running: return "play.circle"
        }
    }
}

struct InfoCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Label(title, systemImage: symbol)
                .font(.display(12 * scale, .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            content()
        }
        .padding(18 * scale)
        .frame(width: 236 * scale, height: 96 * scale, alignment: .topLeading)
        .glass(16 * scale)
    }
}

struct EmptyLibrary: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(spacing: 18 * scale) {
            Spacer()
            Image(systemName: model.scanning ? "magnifyingglass" : "square.stack.3d.up.slash")
                .font(.system(size: 54 * scale, weight: .thin))
                .foregroundStyle(.white.opacity(0.8))
            Text(model.scanning ? T.text(.scanning) : T.text(.emptyLibraryTitle)).font(.display(34 * scale, .light)).foregroundStyle(.white)
            Text(T.text(.emptyLibraryText)).font(.display(17 * scale)).foregroundStyle(.white.opacity(0.65))
            if let folder = model.preferences.gamesFolder {
                Text(folder).font(.display(13 * scale)).foregroundStyle(.white.opacity(0.45)).truncationMode(.middle).lineLimit(1)
            }
            ConsoleButton(title: T.text(.changeFolder), symbol: "folder", focused: true) { model.pickGamesFolder() }
                .padding(.top, 10 * scale)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Every game as a grid, opened from the library button.
struct LibraryGrid: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    static let columns = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 26 * scale) {
            HStack {
                Text(T.text(.library)).font(.display(40 * scale, .light)).foregroundStyle(.white)
                Text("\(model.games.count)").font(.display(22 * scale, .medium)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 8 * scale)
                Spacer()
                HintBar(options: false)
            }
            if previewRender {
                grid.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) { grid }
                        .onChange(of: model.libraryIndex) { _, index in
                            guard model.games.indices.contains(index) else { return }
                            withAnimation(Motion.focus) { proxy.scrollTo(model.games[index].id, anchor: .center) }
                        }
                }
            }
        }
        .padding(.horizontal, 80 * scale)
        .padding(.vertical, 60 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.74).background(.ultraThinMaterial))
    }

    private var grid: some View {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(196 * scale), spacing: 26 * scale), count: LibraryGrid.columns), alignment: .leading, spacing: 30 * scale) {
                        ForEach(Array(model.games.enumerated()), id: \.element.id) { index, game in
                            let focused = index == model.libraryIndex
                            VStack(alignment: .leading, spacing: 10 * scale) {
                                GameTile(game: game, size: 196 * scale, focused: focused)
                                Text(game.name).font(.display(15 * scale, focused ? .semibold : .regular)).foregroundStyle(.white.opacity(focused ? 1 : 0.75)).lineLimit(1)
                                StateLabel(state: model.state(of: game)).font(.display(12 * scale))
                            }
                            .id(game.id)
                            .onTapGesture { model.libraryIndex = index; model.pickFromLibrary() }
                        }
                    }
                    .padding(14 * scale)
    }
}

struct LogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * scale) {
            HStack(spacing: 14 * scale) {
                Text(T.text(.logTitle) + (model.selectedGame.map { " · " + $0.name } ?? "")).font(.display(30 * scale, .light)).foregroundStyle(.white)
                Spacer()
                if let game = model.selectedGame {
                    ConsoleButton(title: T.text(.makeReport), symbol: "stethoscope", focused: false) { model.makeReport(game) }
                }
                ConsoleButton(title: T.text(.close), symbol: "xmark", focused: true) { model.closeOverlay() }
            }
            if let diagnosis = model.selectedGame.flatMap({ model.diagnoses[$0.id] }) {
                Label(diagnosis.summary, systemImage: "exclamationmark.triangle.fill")
                    .font(.display(16 * scale, .medium))
                    .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.5))
                    .padding(16 * scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(14 * scale, opacity: 0.5)
            }
            ScrollView {
                Text(model.logText)
                    .font(.system(size: 12 * scale, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18 * scale)
            }
            .defaultScrollAnchor(.bottom)
            .glass(14 * scale, opacity: 0.55)
        }
        .padding(70 * scale)
        .background(Color.black.opacity(0.65).background(.ultraThinMaterial))
    }
}

extension AppModel {
    func moveSelection(_ delta: Int) {
        let next = min(games.count - 1, max(0, selected + delta))
        guard next != selected else { return }
        selected = next
        Sounds.shared.play(.move)
        measureSelected()
    }

    /// Play, the trophies when the game has any, and the settings.
    var actionCount: Int {
        selectedGame.flatMap { trophies[$0.id] } != nil ? 3 : 2
    }

    func pickFromLibrary() {
        guard games.indices.contains(libraryIndex) else { return }
        selected = libraryIndex
        focus = .tiles
        measureSelected()
        closeOverlay()
    }

    /// Home screen and library navigation; panels go through panelCommand.
    func handle(_ command: Command) -> Bool {
        if pairing != nil {
            if command == .select { answerPairing(true) }
            if command == .back { answerPairing(false) }
            return true
        }
        if ringing != nil, command != .home {
            if command == .select { acceptRinging() }
            if command == .back { declineRinging() }
            return true
        }
        if let watching = watchCommand(command) { return watching }
        guard preferences.onboarded else { return onboardingCommand(command) }
        if starting != nil {
            if command == .back { cancelStart() }
            return true
        }
        if command == .home {
            togglePlaying()
            return true
        }
        if command == .capture {
            saveClip()
            return true
        }
        if command == .previousGame || command == .nextGame {
            switchGame(command == .nextGame ? 1 : -1)
            return true
        }
        switch overlay {
        case .settings, .gameSettings, .confirmUninstall, .updateChoice:
            return panelCommand(command)
        case .controls, .advanced:
            if command == .back || command == .options {
                backToGameSettings()
                return true
            }
            return panelCommand(command)
        case .themes, .studio:
            if command == .back || command == .options {
                backFromThemes()
                return true
            }
            return panelCommand(command)
        case .friends, .party:
            if command == .back {
                closeOverlay()
                return true
            }
            return panelCommand(command)
        case .profile:
            profileCommand(command)
            return true
        case .messages:
            messagesCommand(command)
            return true
        case .feed:
            feedCommand(command)
            return true
        case .leaderboard:
            leaderboardCommand(command)
            return true
        case .notifications:
            if command == .back {
                closeOverlay()
                return true
            }
            return panelCommand(command)
        case .log:
            if command == .back || command == .select { closeOverlay() }
            return true
        case .gallery:
            galleryCommand(command)
            return true
        case .trophies:
            switch command {
            case .up: moveTrophy(-1)
            case .down: moveTrophy(1)
            case .select: if togetherUser != nil { openLeaderboard(selectedGame) }
            case .back, .options: closeOverlay()
            default: break
            }
            return true
        case .library:
            switch command {
            case .left: moveLibrary(-1)
            case .right: moveLibrary(1)
            case .up: moveLibrary(-LibraryGrid.columns)
            case .down: moveLibrary(LibraryGrid.columns)
            case .select: pickFromLibrary()
            case .back, .options: closeOverlay()
            case .previousGame, .nextGame, .home, .capture: break
            }
            return true
        case nil:
            break
        }
        guard let game = selectedGame else {
            if command == .select { pickGamesFolder() }
            return true
        }
        switch (focus, command) {
        case (.tiles, .left): moveSelection(-1)
        case (.tiles, .right): moveSelection(1)
        case (.tiles, .down): moveFocus(.actions(0))
        case (.tiles, .up): moveFocus(.top(1))
        case (.tiles, .select): primaryAction(game)
        case (.top(let index), .left): moveFocus(.top(max(0, index - 1)))
        case (.top(let index), .right): moveFocus(.top(min(5, index + 1)))
        case (.top, .down), (.top, .back): moveFocus(.tiles)
        case (.top(3), .select): openMessages()
        case (.top(4), .select): open(.party)
        case (.top(5), .select): openNotifications()
        case (.top(let index), .select): open(index == 0 ? .library : index == 1 ? .settings : .friends)
        case (.actions(let index), .left): moveFocus(.actions(max(0, index - 1)))
        case (.actions(let index), .right): moveFocus(.actions(min(actionCount - 1, index + 1)))
        case (.actions, .up), (.actions, .back): moveFocus(.tiles)
        case (.actions(0), .select): primaryAction(game)
        case (.actions(1), .select) where actionCount == 3: open(.trophies)
        case (.actions, .select): open(.gameSettings)
        case (_, .options): open(.gameSettings)
        default: break
        }
        return true
    }

    private func galleryCommand(_ command: Command) {
        let count = galleryShots.count
        func move(_ delta: Int) {
            let next = min(count - 1, max(0, galleryIndex + delta))
            guard count > 0, next != galleryIndex else { return }
            galleryIndex = next
            Sounds.shared.play(.move)
        }
        switch command {
        case .left: move(-1)
        case .right: move(1)
        case .up: if !galleryViewing { move(-Gallery.columns) }
        case .down: if !galleryViewing { move(Gallery.columns) }
        case .select:
            guard count > 0 else { return }
            Sounds.shared.play(.select)
            withAnimation(Motion.overlay) { galleryViewing.toggle() }
        case .back:
            if galleryViewing {
                Sounds.shared.play(.back)
                withAnimation(Motion.overlay) { galleryViewing = false }
            } else {
                closeOverlay()
            }
        case .options:
            if galleryShots.indices.contains(galleryIndex) { NSWorkspace.shared.activateFileViewerSelecting([galleryShots[galleryIndex]]) }
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    /// L1 and R1 move to the next game and keep the game's panel open on it; panels about the
    /// launcher itself, and a key being bound, keep the game.
    func switchGame(_ delta: Int) {
        guard capturing == nil else { return }
        switch overlay {
        case nil, .gameSettings, .controls, .advanced, .trophies, .gallery: break
        default: return
        }
        let before = selected
        moveSelection(delta)
        guard selected != before else { return }
        if overlay == .gallery { loadGallery() }
        if overlay == .trophies {
            if let game = selectedGame, trophies[game.id] != nil {
                trophyIndex = 0
            } else {
                closeOverlay()
            }
        }
        if focus == .actions(1), actionCount < 3 { focus = .actions(0) }
    }

    private func moveFocus(_ next: HomeFocus) {
        guard next != focus else { return }
        withAnimation(Motion.focus) { focus = next }
        Sounds.shared.play(.move)
    }

    private func moveLibrary(_ delta: Int) {
        let next = min(games.count - 1, max(0, libraryIndex + delta))
        guard next != libraryIndex else { return }
        libraryIndex = next
        Sounds.shared.play(.move)
    }
}
