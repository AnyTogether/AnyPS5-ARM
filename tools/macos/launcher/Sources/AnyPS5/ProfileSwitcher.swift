import AnyPS5Core
import SwiftUI

/// Home's profile picture, top right: the pointer over it, a click, or the keys' focus opens a
/// list under it of the other profiles and Add Profile, so a profile is one move away instead of
/// a menu and a screen. Choosing one goes through switchProfile, with everything it refuses (a
/// game running, a save sync on its way).
struct ProfileSwitcherState: Equatable {
    /// The parts the pointer is over: the picture, the list.
    var parts: Set<String> = []
    /// The pointer opened it and has not left for good.
    var hovering = false
    /// Opened with a click: it stays until a choice, Esc or a click elsewhere.
    var pinned = false
    /// Counts the pointer's leavings, so an old one's wait closes nothing after a return.
    var leaves = 0
}

extension AppModel {
    /// The other profiles, in the picker's order.
    var switcherProfiles: [LauncherProfile] {
        let current = currentProfile?.id
        return profileBook.pickerOrder.filter { $0.id != current }
    }

    /// Where the keys' focus is in the switcher: 0 the picture, then the profiles, then Add
    /// Profile; nil when it is elsewhere.
    var switcherFocus: Int? {
        if case .switcher(let index) = focus { return index }
        return nil
    }

    var profileSwitcherShown: Bool {
        overlay == nil && preferences.onboarded && (profileSwitcher.hovering || profileSwitcher.pinned || switcherFocus != nil)
    }

    /// Whether a click outside closes it (opened by a click or the keys; the pointer leaving
    /// closes one it opened by itself).
    var profileSwitcherHeld: Bool { profileSwitcher.pinned || switcherFocus != nil }

    /// The pointer came over, or left, the picture ("picture") or the list ("list"). Leaving both
    /// closes the list a moment later, so the gap between them can be crossed.
    func hoverProfileSwitcher(_ part: String, _ inside: Bool) {
        if inside {
            profileSwitcher.parts.insert(part)
            if !profileSwitcher.hovering { withAnimation(Motion.focus) { profileSwitcher.hovering = true } }
            return
        }
        profileSwitcher.parts.remove(part)
        profileSwitcher.leaves += 1
        let leave = profileSwitcher.leaves
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard self.profileSwitcher.leaves == leave, self.profileSwitcher.parts.isEmpty, self.profileSwitcher.hovering else { return }
            withAnimation(Motion.focus) { self.profileSwitcher.hovering = false }
        }
    }

    /// A click on the picture: the list opens and stays, or closes.
    func toggleProfileSwitcher() {
        if profileSwitcher.pinned { return closeProfileSwitcher() }
        Sounds.shared.play(.select)
        withAnimation(Motion.focus) { profileSwitcher.pinned = true }
    }

    /// Esc, Back, or a click elsewhere: closed, the keys back on the games.
    func closeProfileSwitcher() {
        guard profileSwitcherShown else { return }
        Sounds.shared.play(.back)
        withAnimation(Motion.focus) {
            profileSwitcher = ProfileSwitcherState()
            if switcherFocus != nil { focus = .tiles }
        }
    }

    /// A row of the list chosen (from 1: the profiles, then Add Profile).
    func chooseSwitcher(_ index: Int) {
        let others = switcherProfiles
        profileSwitcher = ProfileSwitcherState()
        if switcherFocus != nil { focus = .tiles }
        if others.indices.contains(index - 1) {
            switchProfile(to: others[index - 1].id)
        } else {
            openAddProfile()
        }
    }

    /// The keys and the controller while the focus is in the switcher: ↓ and ↑ through the list,
    /// Select chooses (on the picture it steps into the list), ← goes back to the top bar's
    /// buttons, Back closes.
    func switcherCommand(_ index: Int, _ command: Command) {
        let last = switcherProfiles.count + 1
        func move(_ next: HomeFocus) {
            withAnimation(Motion.focus) { focus = next }
            Sounds.shared.play(.move)
        }
        switch command {
        case .down:
            if index < last { move(.switcher(index + 1)) } else { Sounds.shared.play(.bump) }
        case .up:
            if index > 0 { move(.switcher(index - 1)) }
        case .left:
            if index == 0 { move(.top(5)) }
        case .select:
            if index == 0 { move(.switcher(1)) } else { chooseSwitcher(index) }
        case .back:
            closeProfileSwitcher()
        default:
            break
        }
    }
}

/// Where Home's profile picture is, for the list that opens under it.
struct ProfileSwitcherAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The list under the picture: each other profile with its picture, its name and AnyTogether's
/// mark when it is linked to an account, then Add Profile.
struct ProfileSwitcherMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.look) private var look
    @Environment(\.previewRender) private var previewRender
    @State private var shown = false
    @State private var hovered: Int?

    static let width: CGFloat = 292

    var body: some View {
        let others = model.switcherProfiles
        let open = shown || previewRender
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(TH.text(.switchProfile).uppercased(with: T.locale))
                .font(.display(11 * scale, .semibold)).tracking(1.8 * scale)
                .foregroundStyle(model.accent)
                .padding(.horizontal, 12 * scale).padding(.top, 6 * scale).padding(.bottom, 4 * scale)
            ForEach(Array(others.enumerated()), id: \.element.id) { offset, profile in
                row(index: offset + 1) { ink in
                    ProfileTileAvatar(profile: profile, picture: NSImage(contentsOf: model.profiles.pictureFile(for: profile.id)), size: 38 * scale)
                    Text(profile.name).font(.display(17 * scale, .medium)).foregroundStyle(ink).lineLimit(1)
                    Spacer(minLength: 8 * scale)
                    // Linked to an AnyTogether account: its two rings.
                    if profile.mode == .online { TogetherMark(size: 22 * scale) }
                }
            }
            if !others.isEmpty {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.horizontal, 12 * scale).padding(.vertical, 4 * scale)
            }
            row(index: others.count + 1) { ink in
                ZStack {
                    Circle().strokeBorder(ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5 * scale, dash: [4 * scale, 4 * scale]))
                    Image(systemName: "plus").font(.system(size: 17 * scale, weight: .medium)).foregroundStyle(ink)
                }
                .frame(width: 38 * scale, height: 38 * scale)
                Text(TPro.text(.addProfile)).font(.display(17 * scale, .medium)).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 8 * scale)
            }
        }
        .padding(8 * scale)
        .frame(width: ProfileSwitcherMenu.width * scale)
        .glass(22 * scale, opacity: 0.66)
        .shadow(color: .black.opacity(0.45), radius: 30 * scale, y: 14 * scale)
        .onHover { model.hoverProfileSwitcher("list", $0) }
        // It drops out of the picture: a short spring, or a plain fade with Reduce Motion.
        .scaleEffect(open || Motion.reduced ? 1 : 0.92, anchor: .top)
        .offset(y: open || Motion.reduced ? 0 : -8 * scale)
        .opacity(open ? 1 : 0)
        .onAppear { withAnimation(Motion.reduced ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.72)) { shown = true } }
    }

    private func row<Content: View>(index: Int, @ViewBuilder content: (Color) -> Content) -> some View {
        let focused = model.switcherFocus == index
        let ink: Color = focused ? (look.glass ? Ice.ink : .black) : .white
        let shape = RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
        return Button {
            model.chooseSwitcher(index)
        } label: {
            HStack(spacing: 12 * scale) { content(ink) }
                .padding(.horizontal, 10 * scale).padding(.vertical, 7 * scale)
                .background(FocusFill(shape, focused: focused, idle: Color.white.opacity(hovered == index ? 0.12 : 0)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
        }
        .hoverTick("switcher-\(index)")
        .animation(Motion.focus, value: focused)
        .animation(Motion.focus, value: hovered == index)
    }
}

/// The list placed under the picture over the whole home screen, and, while it is held open, the
/// rest of the screen as the place a click closes it.
struct ProfileSwitcherLayer: View {
    let anchor: Anchor<CGRect>?
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { proxy in
            if let anchor, model.profileSwitcherShown {
                let picture = proxy[anchor]
                let width = ProfileSwitcherMenu.width * scale
                // Its edge under the picture's side of the bar, kept on the screen.
                let wanted = direction == .rightToLeft ? picture.maxX - width / 2 : picture.minX + width / 2
                let middle = min(max(wanted, width / 2 + 16 * scale), proxy.size.width - width / 2 - 16 * scale)
                ZStack {
                    if model.profileSwitcherHeld {
                        Color.clear.contentShape(Rectangle()).onTapGesture { model.closeProfileSwitcher() }
                    }
                    VStack(spacing: 0) {
                        ProfileSwitcherMenu()
                        Spacer(minLength: 0)
                    }
                    .padding(.top, picture.maxY + 10 * scale)
                    .frame(width: width)
                    .position(x: middle, y: proxy.size.height / 2)
                }
                .transition(.opacity)
            }
        }
    }
}
