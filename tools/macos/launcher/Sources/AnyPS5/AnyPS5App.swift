import AnyPS5Core
import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        // `AnyPS5 --render-preview <output folder> <games folder>` draws the screens into PNG files
        // without opening a window, for checking the design.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-preview"), arguments.count > index + 2 {
            MainActor.assumeIsolated { PreviewRenderer.run(output: URL(fileURLWithPath: arguments[index + 1]), games: URL(fileURLWithPath: arguments[index + 2])) }
            return
        }
        // `AnyPS5 --glass-selftest` checks how the window is made in every theme, offscreen.
        if arguments.contains("--glass-selftest") {
            exit(MainActor.assumeIsolated { GlassSelfTest.run() })
        }
        // `AnyPS5 --steam-art <output folder> [<a dump's sce_sys>]` draws the Steam pictures.
        if let index = arguments.firstIndex(of: "--steam-art"), arguments.count > index + 1 {
            MainActor.assumeIsolated { SteamArtPreview.run(output: URL(fileURLWithPath: arguments[index + 1]), sceSys: arguments.count > index + 2 ? URL(fileURLWithPath: arguments[index + 2]) : nil) }
            return
        }
        // Started by one of AnyPS5's Steam shortcuts (--steam, --play <title ID>, --fullscreen).
        let launch = SteamLaunch(arguments: arguments, environment: ProcessInfo.processInfo.environment)
        if launch.fromSteam || launch.play != nil {
            // Steam starts the executable itself: a launcher already open takes the request.
            if let identifier = Bundle.main.bundleIdentifier,
               let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0 != NSRunningApplication.current }) {
                if let play = launch.play, let url = DeepLink.play(play).url as URL? {
                    NSWorkspace.shared.open(url)
                } else {
                    other.activate()
                }
                return
            }
            MainActor.assumeIsolated {
                AppModel.steamLaunch = launch
                if let play = launch.play { AppModel.received([DeepLink.play(play).url]) }
            }
        }
        AnyPS5App.main()
    }
}

struct AnyPS5App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("AnyPS5", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(T.text(.settings) + "…") { if model.preferences.onboarded { model.open(.settings) } }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            // Its background color and opacity follow the theme (GlassWindowHook): black, or clear
            // for Glass's see-through window.
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.collectionBehavior.insert(.fullScreenPrimary)
            // The pointer's moves tell the screens the mouse is in use (InputModeState).
            window.acceptsMouseMovedEvents = true
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: true)
            }
            // Full screen the first time and then as it was left (WindowStart); a Steam shortcut's
            // --fullscreen (Big Picture) always.
            let fullScreen = WindowStart.fullScreen(saved: Preferences.load().fullScreen, steamFullScreen: MainActor.assumeIsolated { AppModel.steamLaunch.fullscreen })
            if fullScreen, !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// A call is left on the server before the app goes (waiting two seconds at most), so friends
    /// do not keep a silent member.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let leaving = AppModel.beforeQuit?() else { return .terminateNow }
            Task { @MainActor in
                await leaving.value
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    /// anyps5:// links, and folders opened with AnyPS5 from Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppModel.received(urls) }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.stillBackground) private var stillBackground
    @Environment(\.mockDesktop) private var mockDesktop

    private var look: Look {
        // On battery or hot, Settings → Battery & Heat can turn the blur and the motion down.
        Look.make(style: model.lookStyle, reduceTransparency: reduceTransparency || model.powerDimmed, offscreen: stillBackground != nil,
                  reduceMotion: model.preferences.reducedMotion || systemReduceMotion || model.powerDimmed,
                  transparency: model.preferences.glassTransparency, seeThrough: stillBackground == nil || mockDesktop != nil)
    }

    var body: some View {
        let look = look
        GeometryReader { proxy in
            let scale = min(1.45, max(0.68, min(proxy.size.width / 1600, proxy.size.height / 900)))
            ZStack {
                Group {
                    Backdrop()
                    if model.preferences.onboarded {
                        HomeView()
                            .transition(.opacity)
                    } else {
                        OnboardingView()
                            .transition(.opacity)
                    }
                }
                // Offscreen there is no material to frost what a full-screen panel covers: the
                // Glass look's renders blur it here instead, as the window's material does live.
                .blur(radius: stillBackground != nil && look.glass && (model.overlay?.coversScreen == true || model.starting != nil) ? 30 * scale : 0)
                overlays
                if model.share.watching != nil {
                    ShareWatchView().transition(.opacity)
                }
                if let game = model.starting ?? model.fontWait {
                    LaunchSplash(game: game)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
                if let call = model.ringing, model.pairing == nil {
                    RingingCard(call: call)
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                }
                if let request = model.pairing {
                    PairingCard(request: request)
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                }
                VStack(spacing: 10 * scale) {
                    if model.translocated { MoveBanner() }
                    if let toast = model.toast { ToastView(toast: toast).transition(.move(edge: .top).combined(with: .opacity)) }
                    Spacer()
                }
                .padding(.top, 26 * scale)
            }
            .environment(\.scale, scale)
            .environment(\.look, look)
            .environment(\.languageCode, model.preferences.language.code)
            .environment(\.circleConfirms, model.preferences.confirmCircle == true)
            .animation(Motion.fade, value: look)
            .preferredColorScheme(.dark)
        }
        // Glass: the window is see-through and this is the blurred, tinted desktop behind it.
        .background {
            if look.seeThrough {
                GlassWindowBackdrop(recipe: look.window).transition(.opacity)
            } else {
                Color.black
            }
        }
        .background(GlassWindowHook(recipe: look.window))
        .ignoresSafeArea()
        .onChange(of: look, initial: true) { _, now in Look.current = now }
        .onAppear {
            Input.shared.handler = { [weak model] command in model?.handle(command) ?? false }
            Input.shared.shortcutHandler = { [weak model] action, hold in model?.shortcut(action, hold: hold) }
            Input.shared.activity = { [weak model] in (model?.changeCount ?? 0) &+ Sounds.shared.requests }
            Input.shared.rightClickHandler = { [weak model] in model?.homeRightClick() ?? false }
            Input.shared.menuHandler = { [weak model] in model?.homeRightClick() ?? false }
            Input.shared.escapeHandler = { [weak model] in model?.escape() ?? false }
            Input.shared.sideButtonHandler = { [weak model] button in
                switch button {
                case .back: model?.mouseBack()
                case .forward: model?.mouseForward()
                }
            }
            Input.shared.scrollHandler = { [weak model] command in
                guard let model, model.preferences.onboarded, model.overlay == nil else { return false }
                model.moveSelection(command == .left ? -1 : 1)
                return true
            }
            Input.shared.start()
        }
    }

    private var subtitleKey: T.Key {
        switch model.overlay {
        case .confirmUninstall: return .uninstallConfirm
        case .controls: return .controls
        case .advanced: return .advancedTitle
        case .updateChoice: return .updateChoiceText
        default: return .gameSettings
        }
    }

    @ViewBuilder private var overlays: some View {
        switch model.overlay {
        case .settings:
            SettingsPanel().transition(.opacity)
        case .library:
            LibraryGrid().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .noSpace:
            if let (game, _) = model.spaceShortage {
                SidePanel(title: TPrep.text(.noSpaceTitle), subtitle: game.name + " · " + TPrep.text(.noSpaceSubtitle))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        case .gameSettings, .confirmUninstall, .controls, .advanced, .updateChoice:
            if let game = model.selectedGame {
                SidePanel(title: model.overlay == .confirmUninstall ? T.text(.uninstall) : game.name, subtitle: T.text(subtitleKey))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        case .updateRequired:
            SidePanel(title: TK.text(.updateRequiredTitle), subtitle: model.updateRequired.map { TK.format(.updateRequiredSubtitle, $0.minimum) })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .friends:
            SidePanel(title: T.text(.friendsTitle), subtitle: model.togetherUser.map { "@\($0.handle) · \(T.format(.friendsOnlineCount, model.friendsOnline))" })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .party:
            SidePanel(title: T.text(.partyTitle), subtitle: model.partySubtitle)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .themes, .studio:
            SidePanel(title: T.text(model.overlay == .studio ? .themeStudio : .themes), subtitle: T.text(model.overlay == .studio ? .themeStudioSubtitle : .themesDetail))
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .messages:
            MessagesView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .profile:
            ProfileView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .compare:
            CompareView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .feed:
            FeedView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .captures:
            CapturesView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .leaderboard:
            LeaderboardView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .notifications:
            SidePanel(title: TS.text(.notifTitle), subtitle: model.notificationsSubtitle)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .compat:
            SidePanel(title: model.compatTitle, subtitle: TS.text(.compatSubtitle))
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .cloudStorage:
            CloudStorageView().transition(.move(edge: .trailing).combined(with: .opacity))
        case .findPlayers:
            SettingsPanel(title: FP.text(.findPlayers), subtitle: model.togetherUser.map { "@\($0.handle)" }).transition(.opacity)
        case .gameHub:
            SettingsPanel(title: model.discover.hubName, subtitle: FP.text(.hubDetail)).transition(.opacity)
        case .lfgPost:
            SidePanel(title: FP.text(.findPlayers), subtitle: model.discover.draftName)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .log:
            LogView().transition(.opacity)
        case .crashReport:
            CrashReportView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .controllerTest:
            ControllerTestView().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .browserPlay:
            BrowserPlayCard(play: model.browserPlay).transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .cropPicture:
            PictureCropView().transition(.opacity.combined(with: .scale(scale: 1.02)))
        case .trophies:
            if let game = model.selectedGame, let set = model.trophies[game.id] {
                TrophyList(game: game, set: set).transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        case .gallery:
            if let game = model.selectedGame {
                Gallery(game: game, shots: model.galleryShots).transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        case .quickMenu, .closeGame, .homeMenu, .profileMenu, .confirmQuit, .launcherReport:
            GameMenuCard().id(model.overlay == .homeMenu ? "home" : model.overlay == .profileMenu ? "options" : model.overlay == .confirmQuit ? "quit" : model.overlay == .launcherReport ? "report" : "game").transition(.opacity)
        case .profilePicker:
            ProfilePickerView().transition(.opacity.combined(with: .scale(scale: 1.02)))
        case .addProfile:
            AddProfileView().transition(.opacity)
        case .signIn:
            ProfileSignInView().transition(.opacity.combined(with: .scale(scale: 1.02)))
        case nil:
            EmptyView()
        }
    }
}

/// Shown from the press of Play until the game's window appears, like the console's start screen.
struct LaunchSplash: View {
    let game: Game
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @State private var since = Date()
    @State private var breathe = false

    var body: some View {
        let size = 200 * scale
        ZStack {
            FrostFill(opacity: 0.55)
            VStack(spacing: 26 * scale) {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).fill(Color.white.opacity(0.08))
                    if let icon = game.icon {
                        ArtworkImage(url: icon, maxPixels: 400)
                    } else {
                        Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.32)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                .shadow(color: model.accent.opacity(breathe ? 0.55 : 0.2), radius: breathe ? 40 * scale : 18 * scale)
                .scaleEffect(breathe ? 1.015 : 0.985)
                Text(game.name)
                    .font(.display(34 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                // A game that needs the Japanese, Chinese and Korean fonts waits for their download.
                let fonts = model.starting == nil && model.fontWait?.id == game.id
                VStack(spacing: 14 * scale) {
                    HStack {
                        Text(fonts ? TF.text(.getting) : T.text(.starting)).font(.display(16 * scale, .medium))
                        Spacer()
                        if fonts {
                            Text(TF.format(.gettingProgress, Int((model.cjkProgress ?? 0) * 100))).font(.display(16 * scale, .semibold)).monospacedDigit()
                        } else {
                            TimelineView(.periodic(from: since, by: 1)) { context in
                                let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                                Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).font(.display(16 * scale, .semibold)).monospacedDigit()
                            }
                        }
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    if fonts {
                        ProgressLine(fraction: model.cjkProgress ?? 0, color: model.accent)
                    } else {
                        IndeterminateLine(color: model.accent)
                    }
                    Text(fonts ? TF.format(.gettingText, game.name, model.cjkDownloadSize) : T.text(.startingText))
                        .font(.display(14 * scale))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 380 * scale)
            }
            VStack {
                Spacer()
                Hint(keys: "esc / ○", label: T.text(.cancel))
                    .padding(.bottom, 40 * scale)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onAppear {
            since = Date()
            guard !model.preferences.reducedMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 12 * scale) {
            if let image = toast.icon.flatMap({ NSImage(contentsOf: $0) }) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: 30 * scale, height: 30 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
            } else {
                Image(systemName: toast.symbol).font(.system(size: 17 * scale, weight: .semibold))
            }
            Text(toast.text).font(.display(16 * scale, .medium)).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22 * scale)
        .padding(.vertical, 14 * scale)
        .glass(28 * scale, opacity: 0.6)
        .shadow(color: .black.opacity(0.4), radius: 20 * scale, y: 8 * scale)
    }
}

/// Offered while macOS runs the app from its read-only download copy.
struct MoveBanner: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 18 * scale) {
            Image(systemName: "arrow.down.app.fill").font(.system(size: 26 * scale)).foregroundStyle(model.accent)
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(T.text(.moveToApplications)).font(.display(17 * scale, .semibold))
                Text(T.text(.moveToApplicationsText)).font(.display(13 * scale)).opacity(0.75).frame(maxWidth: 560 * scale, alignment: .leading)
            }
            ConsoleButton(title: T.text(.moveNow), focused: false, prominent: true) {
                if !AppLocation.moveToApplications() { model.show(T.text(.moveToApplications), symbol: "exclamationmark.triangle") }
            }
            ConsoleButton(title: T.text(.later), focused: false) { withAnimation(Motion.overlay) { model.translocated = false } }
        }
        .foregroundStyle(.white)
        .padding(18 * scale)
        .glass(20 * scale, opacity: 0.6)
    }
}
