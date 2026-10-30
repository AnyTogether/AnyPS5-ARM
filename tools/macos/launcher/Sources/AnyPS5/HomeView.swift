import AnyPS5Core
import SwiftUI

/// The theme animation, the user's own picture or video, and the selected game's artwork over it.
struct Backdrop: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.stillBackground) private var stillBackground
    @Environment(\.look) private var look

    var body: some View {
        let preferences = model.preferences
        let paused = model.running != nil || !model.active || preferences.reducedMotion || model.powerDimmed
        ZStack {
            if let design = model.activeDesign, let file = model.themes.file(design.background, of: design) {
                if design.backgroundIsVideo {
                    LoopingVideo(url: file, paused: paused)
                } else {
                    DriftingImage(url: file, animated: !preferences.reducedMotion && !paused)
                }
            } else {
            switch preferences.backdrop {
            case .image where preferences.backdropFile != nil:
                DriftingImage(url: URL(fileURLWithPath: preferences.backdropFile!), animated: !preferences.reducedMotion && !paused)
            case .video where preferences.backdropFile != nil:
                LoopingVideo(url: URL(fileURLWithPath: preferences.backdropFile!), paused: paused)
            default:
                // Glass's see-through window: the desktop behind it is the background.
                if look.seeThrough {
                    Color.clear
                } else if let still = stillBackground {
                    Image(nsImage: still).resizable()
                } else {
                    ThemeBackground(theme: model.lookStyle, palette: model.activeDesign?.palette, paused: paused)
                }
            }
            }
            // Over the see-through window the key art is laid only when asked for (Show Game Art
            // Behind), and lets some of the desktop through.
            let artwork = look.seeThrough ? preferences.glassArtwork == true : preferences.gameArtwork
            if preferences.onboarded, artwork, model.overlay != .settings, let game = model.backdropGame, let background = game.background {
                Group {
                    if look.glass {
                        FrostedArtwork(url: background, animated: !look.reduceMotion && !paused, solid: look.solid)
                            .opacity(look.seeThrough ? 0.72 : 1)
                    } else {
                        GameArtwork(url: background, animated: !preferences.reducedMotion && !paused)
                    }
                }
                .id(game.id)
                .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: model.backdropGame?.id)
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
        .drifting($drift, animated: animated, period: 24)
    }
}

/// The Glass theme's key art: pic0.png seen through frosted ice — blurred once at a small size,
/// a navy scrim over it everywhere (deeper where the text sits), a cold light from the top right
/// and fine grain. With Reduce Transparency the art gives way to the theme's solid colors.
struct FrostedArtwork: View {
    let url: URL
    var animated: Bool
    var solid = false
    @ObservedObject private var artwork = Artwork.shared
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if solid {
                    LinearGradient(colors: [Ice.solid, Ice.scrim], startPoint: .topTrailing, endPoint: .bottomLeading)
                } else {
                    if let image = artwork.frosted(url) {
                        Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(drift ? 1.09 : 1.04, anchor: .topTrailing)
                            .clipped()
                            .transition(.opacity)
                    }
                    // A cold cast over any art: ice is blue whatever is behind it.
                    LinearGradient(colors: [Ice.frost, Color(red: 0.32, green: 0.56, blue: 0.82)], startPoint: .topTrailing, endPoint: .bottomLeading)
                        .blendMode(.color)
                        .opacity(0.32)
                    Ice.scrim.opacity(GlassRecipe.scrimOpacity)
                    LinearGradient(stops: [.init(color: Ice.scrim.opacity(0.5), location: 0), .init(color: Ice.scrim.opacity(0.18), location: 0.5), .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [.init(color: Ice.scrim.opacity(0.3), location: 0), .init(color: .clear, location: 0.28), .init(color: .clear, location: 0.5), .init(color: Ice.scrim.opacity(0.72), location: 1)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Ice.frost.opacity(0.16), .clear], center: UnitPoint(x: 0.88, y: -0.08), startRadius: 0, endRadius: proxy.size.width * 0.5)
                    // Where the pane refracts: a soft streak of light, cold along one edge.
                    LightStreak(drift: drift)
                    GrainLayer(strength: 0.045)
                }
            }
            .animation(.easeOut(duration: 0.35), value: artwork.frosted(url) != nil)
        }
        .drifting($drift, animated: animated, period: 28)
    }
}

/// A diagonal streak of light across the Glass theme's key art, moving a little with its drift.
struct LightStreak: View {
    var drift: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height
            ZStack {
                LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.07), location: 0.5), .init(color: .white.opacity(0), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.16)
                LinearGradient(stops: [.init(color: Ice.cyan.opacity(0), location: 0), .init(color: Ice.cyan.opacity(0.07), location: 0.5), .init(color: Ice.cyan.opacity(0), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 22)
                    .offset(x: width * 0.08)
            }
            .frame(height: height * 2)
            .rotationEffect(.degrees(28))
            .position(x: width * (drift ? 0.66 : 0.62), y: height * 0.45)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
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
    @Environment(\.look) private var look
    @Namespace private var lens

    var body: some View {
        HStack(spacing: 22 * scale) {
            Text(T.text(.games))
                .font(.display(24 * scale, .semibold))
                .foregroundStyle(.white)
                .legible(14)
            if model.scanning {
                ProgressView().controlSize(.small).tint(.white).scaleEffect(scale)
            }
            Spacer()
            if model.showsUpdateNotice {
                UpdateNoticeView()
                    .transition(.opacity.combined(with: .offset(y: -8 * scale)))
                    .padding(.trailing, 6 * scale)
            }
            iconButton("square.grid.3x3.fill", index: 0) { model.open(.library) }
            iconButton("gearshape.fill", index: 1) { model.open(.settings) }
            iconButton("person.2.fill", index: 2, badge: model.togetherRequests.incoming.count + model.friendsOnline) { model.open(.friends) }
            iconButton("bubble.left.and.bubble.right.fill", index: 3, badge: model.unreadMessages) { model.openMessages() }
            // In the party's voice: the microphone, ringed while someone speaks.
            iconButton(model.voiceCall == nil ? (model.party == nil ? "person.3" : "person.3.fill") : (model.micSending ? "mic.fill" : "mic.slash.fill"),
                       index: 4, badge: model.partyInvites.count, ring: !model.voiceSpeaking.isEmpty) { model.open(.party) }
            iconButton(model.social.notifications.unread > 0 ? "bell.badge.fill" : "bell.fill", index: 5, badge: model.social.notifications.unread) { model.openNotifications() }
            // A controller running out of battery says so here (and in Settings → Controllers).
            if let line = PadTroubleshooter.statusLine(Controllers.shared.pads) { PadStatusPill(text: line) }
            PhoneIndicator(phone: model.phone, connecting: model.phoneConnecting, badges: model.phoneBadges)
            HStack(spacing: 10 * scale) {
                // Signed in to AnyTogether: the avatar and name others see.
                let name = model.togetherUser?.displayName ?? model.preferences.profileName
                ProfileAvatar(url: model.togetherUser?.avatar, name: name, size: 36 * scale, glow: false, picture: model.profilePicture)
                    .overlay(alignment: .bottomTrailing) {
                        // Appearing offline: a moon where friends would see a dot.
                        if model.togetherUser != nil, model.appearingOffline { AppearingOfflineDot(size: 15 * scale).offset(x: 3 * scale, y: 3 * scale) }
                    }
                Text(name).font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.9)).legible(12)
                if let level = model.myLevel { LevelBadgeView(badge: level.badge, size: 30 * scale) }
            }
            Clock().legible(12)
        }
        .glassGroup(look, spacing: 10 * scale)
        .animation(Motion.overlay, value: model.showsUpdateNotice)
    }

    private func iconButton(_ symbol: String, index: Int, badge: Int = 0, ring: Bool = false, action: @escaping () -> Void) -> some View {
        let focused = model.focus == .top(index) && model.overlay == nil
        return Button(action: action) {
            Group {
                let icon = Image(systemName: symbol)
                    .font(.system(size: 18 * scale, weight: .semibold))
                    .frame(width: 44 * scale, height: 44 * scale)
                if look.glass {
                    icon.foregroundStyle(focused ? Ice.ink : .white.opacity(0.92))
                        .modifier(ButtonGlass(shape: Circle(), focused: focused, lens: ("top-\(index)", lens)))
                } else {
                    icon.foregroundStyle(focused ? Color.black : .white.opacity(0.9))
                        .background(Circle().fill(focused ? Color.white : Color.white.opacity(0.1)))
                }
            }
                .overlay(Circle().strokeBorder(model.accent, lineWidth: 2.5 * scale).padding(-3 * scale).opacity(ring ? 1 : 0).animation(.easeOut(duration: 0.15), value: ring))
                .overlay(alignment: .topTrailing) {
                    // Friends online or asking, in the accent.
                    if badge > 0 {
                        Text("\(min(badge, 99))").font(.display(11 * scale, .bold)).foregroundStyle(look.glass ? model.accent.onFill : .white)
                            .padding(.horizontal, 5 * scale).frame(minWidth: 18 * scale, minHeight: 18 * scale)
                            .background(Capsule().fill(model.accent)).offset(x: 4 * scale, y: -4 * scale)
                    }
                }
                .scaleEffect(focused ? 1.1 : 1)
                .shadow(color: .white.opacity(focused && !look.glass ? 0.4 : 0), radius: 10 * scale)
        }
        .buttonStyle(.plain)
        .hoverTick("top-\(index)")
        .animation(Motion.focus, value: focused)
    }
}

/// The launcher's own update, ready: a quiet line beside the top bar's buttons with Restart Now
/// and Later; nothing blocks, nothing comes back after Later. With a game running, Restart Now
/// waits for it and the line says so.
struct UpdateNoticeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.look) private var look

    var body: some View {
        let waiting = model.restartAfterGame
        let version = model.readyUpdate?.release.version ?? ""
        HStack(spacing: 12 * scale) {
            Image(systemName: waiting ? "hourglass" : "arrow.down.circle.fill")
                .font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(model.accent)
            Text(waiting ? TU.text(.noticeWaiting) : TU.format(.noticeReady, version))
                .font(.display(15 * scale, .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 6 * scale) {
                pill(waiting ? TU.text(.cancelRestart) : TU.text(.restartNow), index: 0) {
                    waiting ? model.cancelRestartAfterGame() : model.restartForUpdate()
                }
                if !waiting {
                    pill(TU.text(.later), index: 1) { model.updateLater() }
                }
            }
        }
        .padding(.leading, 16 * scale)
        .padding(.trailing, 5 * scale)
        .frame(height: 44 * scale)
        .modifier(NoticeCapsule())
    }

    private func pill(_ title: String, index: Int, action: @escaping () -> Void) -> some View {
        let focused = model.focus == .notice(index) && model.overlay == nil
        return Button(action: action) {
            Text(title)
                .font(.display(13 * scale, .semibold))
                .foregroundStyle(focused ? (look.glass ? Ice.ink : Color.black) : .white.opacity(index == 0 ? 0.95 : 0.7))
                .padding(.horizontal, 14 * scale)
                .frame(height: 34 * scale)
                .background(FocusFill(Capsule(), focused: focused, idle: Color.white.opacity(index == 0 ? 0.14 : 0.06)))
                .contentShape(Capsule())
                .scaleEffect(focused ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .hoverTick("notice-\(index)")
        .animation(Motion.focus, value: focused)
    }
}

/// The update notice's capsule: dark frost, or a pane of glass in the Glass theme.
private struct NoticeCapsule: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        if look.glass {
            content.iceSurface(Capsule(), shadow: false)
        } else {
            content
                .background(Capsule().fill(Color.black.opacity(0.28)).background(.ultraThinMaterial, in: Capsule()))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
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
                        .hoverTick("tile-\(game.id)")
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
                            StateLabel(state: model.state(of: game), game: game)
                        }
                        .legible(16)
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
    @Environment(\.look) private var look

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
            if look.glass {
                // The icon under glass: light across its top, the ice rim around it.
                LinearGradient(stops: [.init(color: .white.opacity(focused ? 0.2 : 0.12), location: 0), .init(color: .white.opacity(0), location: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
                IceRim(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), strength: focused ? 0.9 : 0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: look.glass ? Ice.scrim.opacity(0.7) : .black.opacity(0.45), radius: focused ? 22 * scale : 10 * scale, y: 8 * scale)
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
            FamilyTileBadge(game: game, size: size)
        }
    }
}

struct StateLabel: View {
    let state: GameState
    /// The game it is about, for what the background preparation adds.
    var game: Game? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let (symbol, text, tint): (String, String, Color) = {
            switch state {
            case .locked where model.prepare.pending.contains(game?.id ?? ""): return ("clock", TPrep.text(.waitingToPrepare), .white.opacity(0.75))
            case .locked: return ("lock.fill", T.text(.locked), .white.opacity(0.75))
            case .unreadable: return ("xmark.octagon.fill", T.text(.unreadableDump), Color(red: 1, green: 0.6, blue: 0.55))
            case .queued: return ("clock", T.text(.queued), .white.opacity(0.75))
            case .installing where game.map(model.isPreparing) == true:
                return model.prepare.paused ? ("pause.circle.fill", TPrep.text(.preparingPaused), .white.opacity(0.75)) : ("arrow.down.circle.fill", TPrep.text(.preparing), model.accent)
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
    @Environment(\.look) private var look
    @Namespace private var lens

    var body: some View {
        let state = model.state(of: game)
        VStack(alignment: .leading, spacing: 22 * scale) {
            Text(game.name)
                .font(.display(58 * scale, .light))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 12)
                .legible(26)
            HStack(spacing: 16 * scale) {
                let family = model.familyPrimary(game, state)
                let preparing = model.isPreparing(game)
                ConsoleButton(title: family?.title ?? (preparing ? TPrep.text(.playWhenReady) : primaryTitle(state)), symbol: family?.symbol ?? (preparing ? "play.fill" : primarySymbol(state)), focused: model.focus == .actions(0) && model.overlay == nil, prominent: true, minWidth: 210, lens: ("action-0", lens)) {
                    model.focus = .actions(0)
                    model.primaryAction(game)
                }
                if let set = model.trophies[game.id] {
                    ConsoleButton(title: "\(set.unlockedCount)/\(set.trophies.count)", symbol: "trophy.fill", focused: model.focus == .actions(1) && model.overlay == nil, lens: ("action-1", lens)) {
                        model.focus = .actions(1)
                        model.open(.trophies)
                    }
                }
                let settingsIndex = model.actionCount - 1
                ConsoleButton(title: "", symbol: "ellipsis", focused: model.focus == .actions(settingsIndex) && model.overlay == nil, lens: ("action-settings", lens)) {
                    model.focus = .actions(settingsIndex)
                    model.open(.gameSettings)
                }
                if case .installing(let step, let fraction) = state {
                    VStack(alignment: .leading, spacing: 8 * scale) {
                        HStack {
                            Text(model.isPreparing(game) ? (model.prepare.paused ? TPrep.text(.preparingPaused) : TPrep.format(.preparingStep, step.title)) : step.title).font(.display(15 * scale, .medium))
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
                    .legible(12)
                    .padding(.leading, 10 * scale)
                    .transition(.opacity)
                } else if case .failed(let message) = state {
                    // The relinker's reason and the file it names, wrapped; selectable to copy, and
                    // the game's log (Options) has all the relinker printed.
                    Text(message)
                        .font(.display(14 * scale))
                        .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.65))
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: 520 * scale, alignment: .leading)
                        .legible(12)
                } else if let diagnosis = model.diagnoses[game.id] {
                    Label(diagnosis.summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.display(14 * scale))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.5))
                        .lineLimit(2)
                        .frame(maxWidth: 520 * scale, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .glassGroup(look, spacing: 12 * scale)
            .animation(Motion.layout, value: state)
            HStack(spacing: 14 * scale) {
                InfoCard(title: T.text(.status), symbol: "circle.dashed") { StateLabel(state: state, game: game) }
                InfoCard(title: T.text(.size), symbol: "internaldrive") {
                    Text((model.sizes[game.id] ?? -1).byteText).font(.display(17 * scale, .semibold)).foregroundStyle(.white)
                }
                InfoCard(title: T.text(.titleID), symbol: "number") {
                    Text(game.titleID).font(.display(17 * scale, .semibold)).foregroundStyle(.white)
                }
                InfoCard(title: T.text(.version), symbol: "tag") {
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text(game.update?.version ?? game.version).font(.display(17 * scale, .semibold)).foregroundStyle(.white)
                        // The update dumped beside it, else the engine that unlocked it.
                        if let update = game.update {
                            let applied = model.installedRecords[game.id]?.update == update.version
                            Text(TAddons.format(applied ? .updateApplied : .updateToApply, update.shortVersion))
                                .font(.display(12 * scale, .medium)).foregroundStyle(applied ? .white.opacity(0.5) : model.accent).lineLimit(1).truncationMode(.middle)
                        } else if let record = model.installedRecords[game.id] {
                            Text(TE.text(.engineTitle) + " " + Toolkit.shortVersion(record.toolkit))
                                .font(.display(12 * scale, .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                CommunityCard(game: game)
                if !game.addons.isEmpty { AddonsCard(addons: game.addons) }
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

/// The add-ons dumped beside the game: the engine mounts each one the game asks for.
struct AddonsCard: View {
    let addons: [GameAddon]
    @Environment(\.scale) private var scale

    var body: some View {
        InfoCard(title: TAddons.format(.addons, addons.count), symbol: "shippingbox") {
            VStack(alignment: .leading, spacing: 2 * scale) {
                ForEach(addons.prefix(addons.count > 2 ? 1 : 2), id: \.label) { addon in
                    Text(addon.name).font(.display(14 * scale, .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                }
                if addons.count > 2 {
                    Text(TAddons.format(.addonsMore, addons.count - 1)).font(.display(12 * scale, .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
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
            Text(model.scanning ? T.text(.scanning) : T.text(.emptyLibraryTitle)).font(.display(34 * scale, .light)).foregroundStyle(.white).legible(16)
            Text(T.text(.emptyLibraryText)).font(.display(17 * scale)).foregroundStyle(.white.opacity(0.75)).legible(12)
            // The folders looked in, a drive that is not plugged in said so.
            ForEach(model.preferences.libraryFolders.prefix(4), id: \.self) { folder in
                let missing = model.libraryFolders.first { $0.url.path == folder }?.connected == false
                Text(missing ? folder + " · " + T.text(.folderNotConnected) : folder).font(.display(13 * scale)).foregroundStyle(.white.opacity(missing ? 0.5 : 0.7))
                    .truncationMode(.middle).lineLimit(1).legible(10)
            }
            // Another folder joins the list; the folders themselves are in Settings → Game Library.
            let none = model.preferences.libraryFolders.isEmpty
            ConsoleButton(title: none ? T.text(.pickFolder) : T.text(.addFolder), symbol: none ? "folder" : "folder.badge.plus", focused: true) { model.pickGamesFolder() }
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
        .screenFrost(0.74)
    }

    private var grid: some View {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(196 * scale), spacing: 26 * scale), count: LibraryGrid.columns), alignment: .leading, spacing: 30 * scale) {
                        ForEach(Array(model.games.enumerated()), id: \.element.id) { index, game in
                            let focused = index == model.libraryIndex
                            VStack(alignment: .leading, spacing: 10 * scale) {
                                GameTile(game: game, size: 196 * scale, focused: focused)
                                Text(game.name).font(.display(15 * scale, focused ? .semibold : .regular)).foregroundStyle(.white.opacity(focused ? 1 : 0.75)).lineLimit(1)
                                StateLabel(state: model.state(of: game), game: game).font(.display(12 * scale))
                            }
                            .id(game.id)
                            .hoverTick("library-\(game.id)")
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
        .screenFrost(0.65)
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
        if fontWait != nil {
            if command == .back { cancelFontWait() }
            return true
        }
        if command == .home {
            homeButton(hold: false)
            return true
        }
        if command == .capture {
            saveClip()
            return true
        }
        if let handled = gameMenuCommandIfOpen(command) { return handled }
        if command == .previousGame || command == .nextGame {
            // In panels with categories L1 and R1 change the category, wherever the focus is.
            if overlayHasCategories { return panelCategoryStep(command == .nextGame ? 1 : -1) }
            switchGame(command == .nextGame ? 1 : -1)
            return true
        }
        switch overlay {
        case .settings, .gameSettings, .confirmUninstall, .updateChoice, .updateRequired, .noSpace:
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
                // A question asked in place (AskFirst.swift) is answered Cancel first.
                if !cancelAsk() { closeOverlay() }
                return true
            }
            return panelCommand(command)
        case .profile:
            profileCommand(command)
            return true
        case .compare:
            compareCommand(command)
            return true
        case .cropPicture:
            cropCommand(command)
            return true
        case .messages:
            messagesCommand(command)
            return true
        case .feed:
            feedCommand(command)
            return true
        case .captures:
            capturesCommand(command)
            return true
        case .leaderboard:
            leaderboardCommand(command)
            return true
        case .findPlayers:
            return panelCommand(command)
        case .gameHub:
            if command == .options || (command == .back && !panelInRows) {
                backFromDiscover()
                return true
            }
            return panelCommand(command)
        case .lfgPost:
            if command == .back || command == .options {
                backFromDiscover()
                return true
            }
            return panelCommand(command)
        case .notifications, .compat:
            if command == .back {
                closeOverlay()
                return true
            }
            return panelCommand(command)
        case .cloudStorage:
            if command == .back || command == .options {
                if cloud.armed != nil || cloud.expanded != nil {
                    withAnimation(Motion.focus) {
                        cloud.armed = nil
                        cloud.expanded = nil
                    }
                    Sounds.shared.play(.back)
                } else {
                    backFromCloudStorage()
                }
                return true
            }
            if command == .up || command == .down { cloud.armed = nil }
            return panelCommand(command)
        case .log:
            if command == .back || command == .select { closeOverlay() }
            return true
        case .crashReport:
            return crashReportCommand(command)
        case .controllerTest:
            return controllerTestCommand(command)
        case .browserPlay:
            return browserPlayCommand(command)
        case .quickMenu, .closeGame, .homeMenu, .profileMenu, .confirmQuit, .launcherReport:
            return gameMenuCommand(command)
        case .profilePicker:
            return pickerCommand(command)
        case .addProfile:
            return modeChoiceCommand(command)
        case .signIn:
            return signInCommand(command)
        case .gallery:
            galleryCommand(command)
            return true
        case .trophies:
            switch command {
            case .up: moveTrophy(-1)
            case .down: moveTrophy(1)
            case .select: if togetherUser != nil { openLeaderboard(selectedGame) }
            // △ shows (or hides again) the focused hidden trophy; on any other it closes the list.
            case .options: if !toggleFocusedHiddenTrophy() { closeOverlay() }
            case .back: closeOverlay()
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
        // The notice went (Later, or the update went in): its focus goes to the top bar.
        if case .notice = focus, !showsUpdateNotice { focus = .top(0) }
        if case .notice(1) = focus, restartAfterGame { focus = .notice(0) }
        switch (focus, command) {
        case (.tiles, .left): moveSelection(-1)
        case (.tiles, .right): moveSelection(1)
        case (.tiles, .down): moveFocus(.actions(0))
        case (.tiles, .up): moveFocus(.top(1))
        case (.tiles, .select): primaryAction(game)
        case (.top(0), .left) where showsUpdateNotice: moveFocus(.notice(restartAfterGame ? 0 : 1))
        case (.top(let index), .left): moveFocus(.top(max(0, index - 1)))
        case (.notice(let index), .left): moveFocus(.notice(max(0, index - 1)))
        case (.notice(let index), .right): moveFocus(index == 1 || restartAfterGame ? .top(0) : .notice(1))
        case (.notice, .down), (.notice, .back): moveFocus(.tiles)
        case (.notice(0), .select):
            Sounds.shared.play(.select)
            restartAfterGame ? cancelRestartAfterGame() : restartForUpdate()
        case (.notice, .select):
            updateLater()
            moveFocus(.top(0))
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
        if captures.draft != nil { return postDraftCommand(command) }
        if cloud.sharing { return shareCommand(command) }
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
            // Share (a chat, the user's gallery, Finder) where AnyTogether keeps files; else Finder.
            openShareMenu()
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
            revealedTrophies = []
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
