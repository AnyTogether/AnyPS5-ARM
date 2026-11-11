import AnyPS5Core
import SwiftUI

/// A profile's round picture: its own picture when it has one, else its initial on its colour,
/// with the controller's light-bar strip in that colour under it.
struct ProfileTileAvatar: View {
    let profile: LauncherProfile?
    let picture: NSImage?
    let size: CGFloat
    var focused = false
    @Environment(\.scale) private var scale

    var body: some View {
        let color = profile.map(AppModel.profileColor) ?? .gray
        ZStack {
            Circle().fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            // A soft sheen from the top left: the console's tiles are lit, not flat.
            Circle().fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: size * 0.9))
            Text(profile?.initial ?? "?").font(.display(size * 0.42, .semibold)).foregroundStyle(.white)
            if let picture {
                Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 0.95 : 0.16), lineWidth: (focused ? 4 : 1.5) * scale))
        .shadow(color: color.opacity(focused ? 0.65 : 0.25), radius: (focused ? 34 : 14) * scale)
    }
}

/// AnyTogether's mark: its two rings, on the blue, violet and mint of the website's (drawn on its
/// 32-unit grid: rings of radius 8.5 at x 12 and 20, a 2.5 stroke).
struct TogetherMark: View {
    let size: CGFloat

    static let gradient = LinearGradient(stops: [
        .init(color: Color(red: 0x4F / 255, green: 0x7C / 255, blue: 1), location: 0),
        .init(color: Color(red: 0xB6 / 255, green: 0x5C / 255, blue: 1), location: 0.55),
        .init(color: Color(red: 0x2F / 255, green: 0xE0 / 255, blue: 0xC4 / 255), location: 1),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let unit = size / 32
        Self.gradient
            .frame(width: size, height: size)
            .mask {
                ZStack {
                    Circle().stroke(lineWidth: 2.5 * unit).frame(width: 17 * unit, height: 17 * unit).offset(x: -4 * unit)
                    Circle().stroke(lineWidth: 2.5 * unit).frame(width: 17 * unit, height: 17 * unit).offset(x: 4 * unit)
                }
                .frame(width: size, height: size)
            }
            .accessibilityHidden(true)
    }
}

/// The mark on a small dark disc, worn on the picker's tile of a profile linked to an account.
struct TogetherBadge: View {
    let size: CGFloat
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.047, green: 0.055, blue: 0.086))
            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5 * scale)
            TogetherMark(size: size * 0.62)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 10 * scale)
    }
}

/// "Who's playing?": every profile as a tile, the one in use first, and Add Profile.
struct ProfilePickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @State private var shown = false

    var body: some View {
        let tiles = model.profileBook.pickerOrder
        ZStack {
            FrostFill(opacity: 0.78).ignoresSafeArea()
            VStack(spacing: 0) {
                Text(TPro.text(.pickerKicker).uppercased())
                    .font(.display(13 * scale, .semibold)).tracking(2.2 * scale)
                    .foregroundStyle(model.accent)
                Text(TPro.text(.whoIsPlaying))
                    .font(.display(60 * scale, .light)).tracking(-0.8 * scale)
                    .foregroundStyle(.white)
                    .padding(.top, 10 * scale)
                Text(TPro.text(model.profileFlow.atLaunch ? .pickerSubtitleLaunch : .pickerSubtitle))
                    .font(.display(17 * scale)).foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 8 * scale)
                HStack(alignment: .top, spacing: 46 * scale) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, profile in
                        tile(profile, index: index, current: profile.id == model.currentProfile?.id)
                    }
                    addTile(index: tiles.count)
                }
                .padding(.top, 70 * scale)
                .animation(Motion.focus, value: model.profileFlow.pickerIndex)
                Spacer(minLength: 0)
                HStack(spacing: 22 * scale) {
                    Hint(keys: "← →", label: T.text(.hintMove))
                    Hint(keys: "↩ / ✕", label: TPro.text(.hintPlay))
                    if !model.profileFlow.atLaunch {
                        Hint(keys: "O / △", label: TPro.text(.manageProfiles))
                        Hint(keys: "esc / ○", label: T.text(.hintBack))
                    }
                }
                .legible(14)
            }
            .padding(.top, 120 * scale)
            .padding(.bottom, 54 * scale)
            .opacity(shown || previewRender ? 1 : 0)
            .offset(y: shown || previewRender || Motion.reduced ? 0 : 18 * scale)
        }
        .onAppear { withAnimation(Motion.reduced ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.82)) { shown = true } }
    }

    private func tile(_ profile: LauncherProfile, index: Int, current: Bool) -> some View {
        let focused = model.profileFlow.pickerIndex == index
        let picture = NSImage(contentsOf: model.profiles.pictureFile(for: profile.id))
        return Button {
            model.profileFlow.pickerIndex = index
            _ = model.pickerCommand(.select)
        } label: {
            VStack(spacing: 18 * scale) {
                ProfileTileAvatar(profile: profile, picture: picture, size: 168 * scale, focused: focused)
                    .overlay {
                        // Linked to an AnyTogether account: its mark on a small dark disc on the
                        // tile's lower right edge. A local profile's tile stays as it is.
                        if profile.mode == .online {
                            TogetherBadge(size: 168 * scale * 0.28)
                                .offset(x: 168 * scale * 0.3536, y: 168 * scale * 0.3536)
                        }
                    }
                Capsule().fill(AppModel.profileColor(profile)).frame(width: (focused ? 54 : 30) * scale, height: 4 * scale)
                    .opacity(focused ? 1 : 0.55)
                VStack(spacing: 6 * scale) {
                    Text(profile.name).font(.display(23 * scale, focused ? .semibold : .regular)).foregroundStyle(.white).lineLimit(1)
                    modeLine(profile, current: current)
                }
            }
            .frame(width: 190 * scale)
            .scaleEffect(focused ? 1.06 : 0.96)
            .opacity(focused ? 1 : 0.78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTick("profile-\(profile.id)")
        .accessibilityLabel(profile.name)
    }

    /// Under the name: the AnyTogether account a profile is linked to (its @handle, or AnyTogether
    /// while it has none yet), or Local for one that stays on this Mac.
    private func modeLine(_ profile: LauncherProfile, current: Bool) -> some View {
        let online = profile.mode == .online
        let text = online ? (profile.account.map { "@\($0.handle)" } ?? TPro.text(.onlineTag)) : TPro.text(.offlineTag)
        return HStack(spacing: 6 * scale) {
            if online {
                TogetherMark(size: 14 * scale)
            } else {
                Image(systemName: "laptopcomputer").font(.system(size: 11 * scale, weight: .semibold))
            }
            Text(text).font(.display(13 * scale, .medium)).lineLimit(1)
            if current && !model.profileFlow.atLaunch {
                Text("·").opacity(0.5)
                Text(TPro.text(.playingNow)).font(.display(13 * scale, .semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.62))
    }

    private func addTile(index: Int) -> some View {
        let focused = model.profileFlow.pickerIndex == index
        return Button {
            model.profileFlow.pickerIndex = index
            _ = model.pickerCommand(.select)
        } label: {
            VStack(spacing: 18 * scale) {
                ZStack {
                    Circle().fill(Color.white.opacity(focused ? 0.16 : 0.06))
                    Circle().strokeBorder(Color.white.opacity(focused ? 0.95 : 0.3), style: StrokeStyle(lineWidth: (focused ? 4 : 1.5) * scale, dash: focused ? [] : [6 * scale, 6 * scale]))
                    Image(systemName: "plus").font(.system(size: 52 * scale, weight: .light)).foregroundStyle(.white.opacity(focused ? 1 : 0.7))
                }
                .frame(width: 168 * scale, height: 168 * scale)
                .shadow(color: .white.opacity(focused ? 0.25 : 0), radius: 26 * scale)
                Capsule().fill(Color.white.opacity(0.3)).frame(width: 30 * scale, height: 4 * scale).opacity(focused ? 0.9 : 0)
                Text(TPro.text(.addProfile)).font(.display(23 * scale, focused ? .semibold : .regular)).foregroundStyle(.white)
            }
            .frame(width: 190 * scale)
            .scaleEffect(focused ? 1.06 : 0.96)
            .opacity(focused ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTick("profile-add")
        .accessibilityLabel(TPro.text(.addProfile))
    }
}

/// Offline or online: two cards, the focused one lifted. The first start's last step and Add
/// Profile.
struct ProfileModeCards: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 28 * scale) {
            card(0, symbol: "wifi.slash", title: TPro.text(.offlineTitle), lead: TPro.text(.offlineLead),
                 facts: [TPro.text(.offlineFact1), TPro.text(.offlineFact2), TPro.text(.offlineFact3)], tag: TPro.text(.offlineTag))
            card(1, symbol: "person.2.wave.2.fill", title: TPro.text(.onlineTitle), lead: TPro.text(.onlineLead),
                 facts: [TPro.text(.onlineFact1), TPro.text(.onlineFact2), TPro.text(.onlineFact3)], tag: TPro.text(.onlineTag))
        }
        .animation(Motion.focus, value: model.profileFlow.modeChoice)
    }

    private func card(_ index: Int, symbol: String, title: String, lead: String, facts: [String], tag: String) -> some View {
        let focused = model.profileFlow.modeChoice == index
        let shape = RoundedRectangle(cornerRadius: 26 * scale, style: .continuous)
        return Button {
            model.profileFlow.modeChoice = index
            _ = model.modeChoiceCommand(.select)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ZStack {
                        Circle().fill(focused ? Color.black.opacity(0.08) : Color.white.opacity(0.1))
                        Image(systemName: symbol).font(.system(size: 24 * scale, weight: .semibold))
                    }
                    .frame(width: 58 * scale, height: 58 * scale)
                    Spacer()
                    Text(tag.uppercased()).font(.display(11 * scale, .bold)).tracking(1.4 * scale)
                        .padding(.horizontal, 10 * scale).padding(.vertical, 5 * scale)
                        .background(Capsule().fill(focused ? Color.black.opacity(0.08) : Color.white.opacity(0.1)))
                }
                Text(title).font(.display(34 * scale, .semibold)).tracking(-0.4 * scale)
                    .padding(.top, 26 * scale)
                Text(lead).font(.display(16 * scale)).opacity(0.72)
                    .padding(.top, 6 * scale)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 11 * scale) {
                    ForEach(facts, id: \.self) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                            Image(systemName: "checkmark").font(.system(size: 12 * scale, weight: .bold)).opacity(0.7)
                            Text(fact).font(.display(15 * scale, .medium)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 24 * scale)
                Spacer(minLength: 0)
            }
            .foregroundStyle(focused ? Color.black : .white)
            .padding(30 * scale)
            .frame(width: 430 * scale, height: 380 * scale, alignment: .topLeading)
            .background(FocusFill(shape, focused: focused, idle: Color.white.opacity(0.08)))
            .overlay(shape.strokeBorder(Color.white.opacity(focused ? 0 : 0.14)))
            .focusRing(focused, radius: 26 * scale)
            .scaleEffect(focused ? 1.03 : 0.98)
            .opacity(focused ? 1 : 0.8)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .hoverTick("mode-\(index)")
        .accessibilityLabel(title + ". " + lead)
    }
}

/// Add Profile: a name, then offline or online.
struct AddProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @FocusState private var cursor: Bool

    var body: some View {
        ZStack {
            FrostFill(opacity: 0.78).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(TPro.text(.addProfile).uppercased()).font(.display(13 * scale, .semibold)).tracking(2.2 * scale).foregroundStyle(model.accent)
                Text(TPro.text(.howToPlay)).font(.display(54 * scale, .light)).tracking(-0.6 * scale).foregroundStyle(.white).padding(.top, 10 * scale)
                Text(TPro.text(.howToPlaySubtitle)).font(.display(17 * scale)).foregroundStyle(.white.opacity(0.62)).padding(.top, 8 * scale)
                HStack(spacing: 14 * scale) {
                    Image(systemName: "character.cursor.ibeam").foregroundStyle(.white.opacity(0.6))
                    // Offscreen a text field draws nothing: the name as text there.
                    if previewRender {
                        Text(model.profileFlow.name).font(.display(20 * scale, .medium)).foregroundStyle(.white)
                        Spacer(minLength: 0)
                    } else {
                        // Up from the cards (or a click) puts the cursor in; Return, Esc and down give
                        // the keys back to the cards.
                        TextField(TPro.text(.profileNamePlaceholder), text: $model.profileFlow.name)
                            .textFieldStyle(.plain)
                            .font(.display(20 * scale, .medium))
                            .foregroundStyle(.white)
                            .focused($cursor)
                            .onSubmit { model.stopTyping(AppModel.profileNameField) }
                            .onExitCommand { model.stopTyping(AppModel.profileNameField) }
                            .onKeyPress(.downArrow) {
                                model.stopTyping(AppModel.profileNameField)
                                return .handled
                            }
                            .onChange(of: model.typingRow == AppModel.profileNameField, initial: true) { _, on in if cursor != on { cursor = on } }
                            .onChange(of: cursor) { _, on in
                                if on { model.typingRow = AppModel.profileNameField } else { model.stopTyping(AppModel.profileNameField) }
                            }
                    }
                }
                .padding(.horizontal, 20 * scale)
                .frame(width: 430 * scale, height: 56 * scale)
                .glass(16 * scale)
                .overlay(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .strokeBorder(model.accent, lineWidth: 1.5 * scale).opacity(model.typingRow == AppModel.profileNameField ? 1 : 0))
                .contentShape(Rectangle())
                .onTapGesture { model.typingRow = AppModel.profileNameField }
                .padding(.top, 34 * scale)
                .opacity(model.profileFlow.modeChoice == 0 ? 1 : 0.45)
                ProfileModeCards().padding(.top, 26 * scale)
                Spacer(minLength: 0)
                HStack(spacing: 22 * scale) {
                    Hint(keys: "← →", label: T.text(.hintMove))
                    Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
                    Hint(keys: "esc / ○", label: T.text(.hintBack))
                }
                .legible(14)
            }
            .padding(.horizontal, 110 * scale)
            .padding(.vertical, 80 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Signing in to AnyTogether for a profile: the email code (which also makes a new account),
/// the website's code or the phone, as Settings → AnyTogether has them.
struct ProfileSignInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let rows = model.panelCategories().first?.rows ?? []
        let card = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12 * scale) {
                Image(systemName: "person.2.wave.2.fill").font(.system(size: 15 * scale, weight: .semibold)).foregroundStyle(model.accent)
                Text("AnyTogether".uppercased()).font(.display(13 * scale, .semibold)).tracking(2.2 * scale).foregroundStyle(model.accent)
            }
            Text(TPro.text(title)).font(.display(40 * scale, .light)).tracking(-0.5 * scale).foregroundStyle(.white).padding(.top, 10 * scale)
            Text(TPro.text(.signInSubtitle)).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.62)).padding(.top, 6 * scale)
                .fixedSize(horizontal: false, vertical: true)
            RowList(rows: rows, focusedRow: model.focusedRow(in: rows))
                .frame(height: 330 * scale)
                .padding(.top, 22 * scale)
            HStack(spacing: 22 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
            .padding(.top, 18 * scale)
        }
        .padding(40 * scale)
        .frame(width: 680 * scale, alignment: .topLeading)
        ZStack {
            FrostFill(opacity: 0.72).ignoresSafeArea()
            card.glass(30 * scale, opacity: 0.5)
                .shadow(color: .black.opacity(0.45), radius: 40 * scale, y: 18 * scale)
        }
    }

    private var title: TPro.Key {
        switch model.profileFlow.origin {
        case .firstStart, .adding: return .signInTitleNew
        case .goingOnline: return .signInTitleOnline
        case .signingInAgain: return .signInTitleAgain
        }
    }
}
