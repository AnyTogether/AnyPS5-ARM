import AnyPS5Core
import SwiftUI

/// First start: language, one of the three themes, the games folder, then offline or online
/// (the first profile; online signs in or makes the account).
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10 * scale) {
                ForEach(0..<4) { step in
                    Capsule()
                        .fill(Color.white.opacity(step <= model.onboardingStep ? 0.95 : 0.22))
                        .frame(width: step == model.onboardingStep ? 46 * scale : 18 * scale, height: 5 * scale)
                }
            }
            .animation(Motion.layout, value: model.onboardingStep)
            .padding(.bottom, 54 * scale)
            Group {
                switch model.onboardingStep {
                case 0: LanguageStep()
                case 1: ThemeStep()
                case 2: FolderStep()
                default: ModeStep()
                }
            }
            .id(model.onboardingStep)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40 * scale)), removal: .opacity.combined(with: .offset(x: -40 * scale))))
            Spacer(minLength: 0)
            HStack {
                if model.onboardingStep > 0 {
                    ConsoleButton(title: T.text(.back), symbol: "chevron.left", focused: false) { model.onboardingBack() }
                }
                Spacer()
                HintBar(options: false)
            }
        }
        .padding(.horizontal, 110 * scale)
        .padding(.vertical, 80 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
        .animation(Motion.layout, value: model.onboardingStep)
    }
}

private struct StepTitle: View {
    let title: String
    let subtitle: String
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            Text(title).font(.display(54 * scale, .light)).foregroundStyle(.white)
            Text(subtitle).font(.display(19 * scale)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: 720 * scale, alignment: .leading)
        }
    }
}

private struct LanguageStep: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 46 * scale) {
            StepTitle(title: T.text(.welcome), subtitle: T.text(.welcomeSubtitle))
            VStack(alignment: .leading, spacing: 16 * scale) {
                Text(T.text(.chooseLanguage)).font(.display(14 * scale, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 20 * scale) {
                    ForEach(Array(Language.allCases.enumerated()), id: \.element) { index, language in
                        let focused = model.onboardingChoice == index
                        VStack(alignment: .leading, spacing: 10 * scale) {
                            Text(language == .turkish ? "TR" : "EN").font(.display(15 * scale, .bold)).opacity(0.6)
                            Text(language.displayName).font(.display(28 * scale, .medium))
                        }
                        .foregroundStyle(focused ? Color.black : .white)
                        .padding(26 * scale)
                        .frame(width: 280 * scale, height: 150 * scale, alignment: .bottomLeading)
                        .background(FocusFill(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous).strokeBorder(Color.white.opacity(focused ? 0 : 0.14)))
                        .scaleEffect(focused ? 1.04 : 1)
                        .shadow(color: .white.opacity(focused ? 0.3 : 0), radius: 20 * scale)
                        .onTapGesture { model.onboardingChoice = index; model.onboardingConfirm() }
                    }
                }
                .animation(Motion.focus, value: model.onboardingChoice)
            }
        }
    }
}

private struct ThemeStep: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.themeStills) private var stills
    /// Four themes fit where three did.
    private var cardWidth: CGFloat { Theme.allCases.count > 3 ? 300 : 330 }

    var body: some View {
        VStack(alignment: .leading, spacing: 46 * scale) {
            StepTitle(title: T.text(.chooseTheme), subtitle: T.text(.chooseThemeSubtitle))
            HStack(spacing: 26 * scale) {
                ForEach(Theme.allCases) { theme in
                    let focused = model.onboardingChoice == theme.rawValue
                    VStack(alignment: .leading, spacing: 14 * scale) {
                        Group {
                            if let still = stills[theme] {
                                Image(nsImage: still).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                ThemeBackground(theme: theme, paused: !focused)
                            }
                        }
                            .frame(width: cardWidth * scale, height: cardWidth * 0.5636 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                            .focusRing(focused, radius: 18 * scale)
                        HStack {
                            Text(theme.title).font(.display(22 * scale, focused ? .semibold : .regular)).foregroundStyle(.white)
                            Spacer()
                            Circle().fill(theme.defaultAccent.color).frame(width: 12 * scale, height: 12 * scale)
                        }
                    }
                    .frame(width: cardWidth * scale)
                    .scaleEffect(focused ? 1.04 : 0.97)
                    .opacity(focused ? 1 : 0.72)
                    .onTapGesture {
                        model.onboardingChoice = theme.rawValue
                        model.preferences.theme = theme
                        Sounds.shared.play(.move)
                    }
                }
            }
            .animation(Motion.focus, value: model.onboardingChoice)
        }
    }
}

private struct FolderStep: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 46 * scale) {
            StepTitle(title: T.text(.chooseFolder), subtitle: T.text(.chooseFolderSubtitle))
            VStack(alignment: .leading, spacing: 22 * scale) {
                HStack(spacing: 18 * scale) {
                    ConsoleButton(title: model.preferences.libraryFolders.isEmpty ? T.text(.pickFolder) : T.text(.changeFolder), symbol: "folder", focused: model.onboardingChoice == 0, minWidth: 220) {
                        model.onboardingChoice = 0
                        model.pickGamesFolder(first: true)
                    }
                    if !model.preferences.libraryFolders.isEmpty {
                        ConsoleButton(title: TPro.text(.continueStep), symbol: "arrow.right", focused: model.onboardingChoice == 1, prominent: true, minWidth: 180) {
                            model.onboardingChoice = 1
                            model.onboardingConfirm()
                        }
                    }
                }
                if let folder = model.preferences.libraryFolders.first {
                    HStack(spacing: 14 * scale) {
                        Image(systemName: model.scanning ? "magnifyingglass" : (model.games.isEmpty ? "questionmark.folder" : "checkmark.circle.fill"))
                            .foregroundStyle(model.games.isEmpty && !model.scanning ? .white.opacity(0.7) : model.accent)
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Text(model.scanning ? T.text(.scanning) : (model.games.isEmpty ? T.text(.noGamesFound) : T.format(.gamesFound, model.games.count)))
                                .font(.display(18 * scale, .medium)).foregroundStyle(.white)
                            Text(folder).font(.display(13 * scale)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.system(size: 22 * scale))
                    .padding(20 * scale)
                    .frame(maxWidth: 640 * scale, alignment: .leading)
                    .glass(16 * scale)
                    if !model.games.isEmpty {
                        HStack(spacing: 12 * scale) {
                            ForEach(model.games.prefix(8)) { game in
                                GameTile(game: game, size: 84 * scale, focused: false)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .animation(Motion.layout, value: model.games.count)
        }
    }
}

extension AppModel {
    var onboardingChoice: Int {
        get { onboardingChoices[onboardingStep] ?? defaultChoice(onboardingStep) }
        set { onboardingChoices[onboardingStep] = newValue }
    }

    private func defaultChoice(_ step: Int) -> Int {
        switch step {
        case 0: return Language.allCases.firstIndex(of: preferences.language) ?? 0
        case 1: return preferences.theme.rawValue
        default: return preferences.libraryFolders.isEmpty ? 0 : 1
        }
    }

    func onboardingCommand(_ command: Command) -> Bool {
        // The last step: the welcome cards, or the sign-in they lead to.
        if onboardingStep == 3 { return overlay == .signIn ? signInCommand(command) : modeChoiceCommand(command) }
        let count = onboardingStep == 0 ? Language.allCases.count : onboardingStep == 1 ? Theme.allCases.count : (preferences.libraryFolders.isEmpty ? 1 : 2)
        switch command {
        case .left:
            if onboardingChoice > 0 { onboardingChoice -= 1; previewChoice(); Sounds.shared.play(.move) }
        case .right:
            if onboardingChoice < count - 1 { onboardingChoice += 1; previewChoice(); Sounds.shared.play(.move) }
        case .select:
            onboardingConfirm()
        case .back:
            onboardingBack()
        default:
            break
        }
        return true
    }

    /// The language and theme steps show their choice at once.
    private func previewChoice() {
        if onboardingStep == 0 { preferences.language = Language.allCases[onboardingChoice] }
        if onboardingStep == 1 { preferences.theme = Theme(rawValue: onboardingChoice) ?? .cosmic }
    }

    func onboardingConfirm() {
        switch onboardingStep {
        case 0:
            preferences.language = Language.allCases[onboardingChoice]
            advance()
        case 1:
            preferences.theme = Theme(rawValue: onboardingChoice) ?? .cosmic
            advance()
        case 2:
            if onboardingChoice == 1 && !preferences.libraryFolders.isEmpty {
                profileFlow.modeChoice = 0
                advance()
            } else {
                pickGamesFolder(first: true)
                onboardingChoice = 1
            }
        default:
            confirmModeChoice()
        }
    }

    private func advance() {
        Sounds.shared.play(.select)
        withAnimation(Motion.layout) { onboardingStep += 1 }
    }

    func onboardingBack() {
        guard onboardingStep > 0 else { return }
        Sounds.shared.play(.back)
        withAnimation(Motion.layout) { onboardingStep -= 1 }
    }

    func finishOnboarding() {
        Sounds.shared.play(.unlocked)
        withAnimation(.easeInOut(duration: 0.7)) { preferences.onboarded = true }
        focus = .tiles
        if games.isEmpty { rescan() }
    }
}

/// The first start's last step: offline or online.
private struct ModeStep: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        // Online's sign-in comes up over it (the overlays are drawn on the first start too).
        VStack(alignment: .leading, spacing: 40 * scale) {
            StepTitle(title: TPro.text(.howToPlay), subtitle: TPro.text(.howToPlaySubtitle))
            ProfileModeCards()
        }
    }
}
