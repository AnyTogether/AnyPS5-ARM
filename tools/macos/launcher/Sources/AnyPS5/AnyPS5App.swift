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
            window.backgroundColor = .black
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.collectionBehavior.insert(.fullScreenPrimary)
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1.45, max(0.68, min(proxy.size.width / 1600, proxy.size.height / 900)))
            ZStack {
                Backdrop()
                if model.preferences.onboarded {
                    HomeView()
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
                overlays
                VStack(spacing: 10 * scale) {
                    if model.translocated { MoveBanner() }
                    if let toast = model.toast { ToastView(toast: toast).transition(.move(edge: .top).combined(with: .opacity)) }
                    Spacer()
                }
                .padding(.top, 26 * scale)
            }
            .environment(\.scale, scale)
            .preferredColorScheme(.dark)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            Input.shared.handler = { [weak model] command in model?.handle(command) ?? false }
            Input.shared.scrollHandler = { [weak model] command in
                guard let model, model.preferences.onboarded, model.overlay == nil else { return false }
                model.moveSelection(command == .left ? -1 : 1)
                return true
            }
            Input.shared.start()
        }
    }

    @ViewBuilder private var overlays: some View {
        switch model.overlay {
        case .settings:
            SettingsPanel().transition(.opacity)
        case .library:
            LibraryGrid().transition(.opacity.combined(with: .scale(scale: 1.03)))
        case .gameSettings, .confirmUninstall:
            if let game = model.selectedGame {
                SidePanel(title: model.overlay == .confirmUninstall ? T.text(.uninstall) : game.name, subtitle: model.overlay == .confirmUninstall ? T.text(.uninstallConfirm) : T.text(.gameSettings))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        case .log:
            LogView().transition(.opacity)
        case nil:
            EmptyView()
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: toast.symbol).font(.system(size: 17 * scale, weight: .semibold))
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
