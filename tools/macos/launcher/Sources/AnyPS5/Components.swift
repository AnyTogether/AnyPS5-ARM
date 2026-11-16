import AnyPS5Core
import SwiftUI

/// The interface is laid out for a 1600x900 window and scaled with it.
struct Scale: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

/// A rendered frame of the theme background, standing in for the Metal view offscreen.
struct StillBackground: EnvironmentKey {
    static let defaultValue: NSImage? = nil
}

/// Rendered frames of every theme, for the onboarding's theme cards offscreen.
struct ThemeStills: EnvironmentKey {
    static let defaultValue: [Theme: NSImage] = [:]
}

extension EnvironmentValues {
    var scale: CGFloat {
        get { self[Scale.self] }
        set { self[Scale.self] = newValue }
    }

    var stillBackground: NSImage? {
        get { self[StillBackground.self] }
        set { self[StillBackground.self] = newValue }
    }

    var themeStills: [Theme: NSImage] {
        get { self[ThemeStills.self] }
        set { self[ThemeStills.self] = newValue }
    }

    /// Offscreen rendering draws no scroll view content, so the previews lay lists out flat.
    var previewRender: Bool { stillBackground != nil }
}

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// A dark, frosted panel; in the Glass theme a pane of frosted ice (see IceSurface).
struct Glass: ViewModifier {
    var radius: CGFloat
    var opacity: Double = 0.38

    func body(content: Content) -> some View {
        content.iceSurface(RoundedRectangle(cornerRadius: radius, style: .continuous), classicOpacity: opacity)
    }
}

/// The ring and glow a focused element wears, as on Windows and Linux: a white ring with a brighter
/// glint travelling around it and a soft halo that breathes slowly and never fully goes out. It
/// closes in from slightly outside as it lands. Only a focused home tile moves (FocusGlint.moves),
/// everywhere else the same ring stands still. In the Glass theme an ice rim with a cold glow.
struct FocusRing: ViewModifier {
    let focused: Bool
    let radius: CGFloat
    let width: CGFloat
    var animated = false
    @Environment(\.look) private var look
    @Environment(\.stillBackground) private var stillBackground

    func body(content: Content) -> some View {
        content.overlay(
            Group {
                if look.glass {
                    RoundedRectangle(cornerRadius: radius + width, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white, Ice.frost, Ice.cyan], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: width)
                        .padding(-width * 1.6)
                        .opacity(focused ? 1 : 0)
                        .shadow(color: Ice.cyan.opacity(focused ? 0.55 : 0), radius: 14)
                } else {
                    ZStack {
                        if focused {
                            let moving = animated && !look.reduceMotion && stillBackground == nil
                            TimelineView(.animation(paused: !moving)) { context in
                                GlintRing(radius: radius + width, width: width, phase: moving ? FocusGlint.phase(at: context.date) : 0)
                            }
                            .padding(-width * 1.6)
                            .transition(AnyTransition.opacity.combined(with: AnyTransition.modifier(
                                active: RingSettle(outset: FocusGlint.settle(width: width, focused: false, reduceMotion: look.reduceMotion)),
                                identity: RingSettle(outset: 0))))
                        }
                    }
                    .animation(Motion.focus, value: focused)
                }
            }
            .allowsHitTesting(false)
        )
    }
}

/// The non-Glass focus ring's numbers, the same as Windows and Linux (FocusRing in components.dart).
enum FocusGlint {
    /// One full turn of the glint around the edge; the halo breathes twice per turn.
    static let period: TimeInterval = 4.8
    /// The ring at its dimmest: as easy to see as the still ring was, the glint brightens it.
    static let ringOpacity = 0.9

    /// Where the glint is at `date`, 0 to 1 of a turn.
    static func phase(at date: Date) -> Double {
        let turns = date.timeIntervalSinceReferenceDate / period
        return turns - turns.rounded(.down)
    }

    /// The halo's breath at `phase`: 0 at rest, 1 at its widest, twice per turn.
    static func breath(_ phase: Double) -> Double { 0.5 - 0.5 * cos(phase * 2 * .pi * 2) }
    static func haloOpacity(_ breath: Double) -> Double { 0.16 + 0.16 * breath }
    static func haloBlur(_ breath: Double) -> CGFloat { 9 + 5 * breath }

    /// Where the ring starts before it closes in: `width` further out, none with reduced motion.
    static func settle(width: CGFloat, focused: Bool, reduceMotion: Bool) -> CGFloat {
        focused || reduceMotion ? 0 : width
    }

    /// A home tile's ring moves only when it is focused on the home screen with nothing over it,
    /// no game is starting or running (the GPU is the game's, as for the background) and the
    /// launcher is in front. FocusRing also keeps it still with reduced motion (the launcher's,
    /// the system's or Battery & Heat's), in the Glass theme and in the previews.
    static func moves(focused: Bool, covered: Bool, gameBusy: Bool, active: Bool) -> Bool {
        focused && !covered && !gameBusy && active
    }

    /// The ring: its base white with the glint at 0.8 of a turn from the start.
    static let ringStops: [(location: Double, opacity: Double)] = [(0, ringOpacity), (0.62, ringOpacity), (0.8, 1), (0.98, ringOpacity), (1, ringOpacity)]
    /// The glint's own glow, a tighter pass that lights the halo where it goes by.
    static let glowStops: [(location: Double, opacity: Double)] = [(0, 0), (0.62, 0), (0.8, 0.38), (0.98, 0), (1, 0)]

    static func gradient(_ stops: [(location: Double, opacity: Double)], phase: Double) -> AngularGradient {
        AngularGradient(stops: stops.map { Gradient.Stop(color: .white.opacity($0.opacity), location: $0.location) },
                        center: .center, angle: .degrees(phase * 360))
    }
}

extension AppModel {
    /// Whether a home tile's focus ring moves (FocusGlint.moves).
    func homeTileGlints(_ focused: Bool) -> Bool {
        FocusGlint.moves(focused: focused, covered: overlay != nil, gameBusy: starting != nil || playingGame != nil || fontWait != nil, active: active)
    }
}

/// The ring a little further out, where it starts before it closes in.
private struct RingSettle: ViewModifier {
    let outset: CGFloat
    func body(content: Content) -> some View { content.padding(-outset) }
}

/// The non-Glass ring at one moment of its turn: the halo, the ring with its glint, the glint's glow.
private struct GlintRing: View {
    let radius: CGFloat
    let width: CGFloat
    let phase: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let breath = FocusGlint.breath(phase)
        ZStack {
            shape.inset(by: width / 2)
                .stroke(Color.white.opacity(FocusGlint.haloOpacity(breath)), lineWidth: width * 3)
                .blur(radius: FocusGlint.haloBlur(breath))
            shape.strokeBorder(FocusGlint.gradient(FocusGlint.ringStops, phase: phase), lineWidth: width)
            shape.inset(by: width / 2)
                .stroke(FocusGlint.gradient(FocusGlint.glowStops, phase: phase), lineWidth: width * 2)
                .blur(radius: 6)
        }
    }
}

extension View {
    func glass(_ radius: CGFloat, opacity: Double = 0.38) -> some View { modifier(Glass(radius: radius, opacity: opacity)) }

    /// The ring and glow a focused element wears. `animated` lets it move (a home tile, see
    /// FocusGlint.moves), otherwise it stands still.
    func focusRing(_ focused: Bool, radius: CGFloat, width: CGFloat = 3, animated: Bool = false) -> some View {
        modifier(FocusRing(focused: focused, radius: radius, width: width, animated: animated))
    }
}

/// A console button: translucent until focused, then solid white; in the Glass theme a pane of
/// glass that turns into the ice chip.
struct ConsoleButton: View {
    let title: String
    var symbol: String?
    var focused: Bool
    var prominent = false
    var destructive = false
    var minWidth: CGFloat = 0
    /// The Liquid Glass id this button's glass morphs by (see ButtonGlass).
    var lens: (id: String, namespace: Namespace.ID)?
    let action: () -> Void
    @Environment(\.scale) private var scale
    @Environment(\.look) private var look
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
        Button(action: action) {
            let label = HStack(spacing: 10 * scale) {
                if let symbol { Image(systemName: symbol).font(.system(size: 17 * scale, weight: .semibold)) }
                if !title.isEmpty { Text(title).font(.display(19 * scale, .semibold)) }
            }
            .padding(.horizontal, (title.isEmpty ? 18 : 30) * scale)
            .frame(minWidth: minWidth * scale, minHeight: 54 * scale)
            if look.glass {
                label
                    .foregroundStyle(focused ? Ice.ink : (destructive ? Color(red: 1, green: 0.6, blue: 0.55) : .white))
                    .modifier(ButtonGlass(shape: shape, focused: focused, idle: prominent ? 0.1 : (hovering ? 0.08 : 0), lens: lens))
                    .sheenSweep(focused, in: shape)
                    .scaleEffect(focused ? 1.04 : 1)
                    .contentShape(Rectangle())
            } else {
                label
                    .foregroundStyle(focused ? Color.black : (destructive ? Color(red: 1, green: 0.55, blue: 0.5) : .white))
                    .background(shape.fill(focused ? Color.white : Color.white.opacity(prominent ? 0.2 : (hovering ? 0.16 : 0.1))))
                    .overlay(shape.strokeBorder(Color.white.opacity(focused ? 0 : 0.12), lineWidth: 1))
                    .shadow(color: .white.opacity(focused ? 0.28 : 0), radius: 18 * scale)
                    .scaleEffect(focused ? 1.05 : 1)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hoverTick("button-\(title)-\(symbol ?? "")")
        .animation(Motion.focus, value: focused)
    }
}

/// A thin capsule progress bar.
struct ProgressLine: View {
    let fraction: Double
    var color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(color).frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
                    .shadow(color: color.opacity(0.6), radius: 6)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

/// An endless sweep for steps whose length is not known (the relinker's run).
struct IndeterminateLine: View {
    var color: Color
    var height: CGFloat = 4
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(LinearGradient(colors: [color.opacity(0), color, color.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * 0.35)
                    .offset(x: proxy.size.width * phase)
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.05 } }
    }
}

struct Clock: View {
    @Environment(\.scale) private var scale

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.display(20 * scale, .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

/// The hint a preview draws as if the pointer were over it (offscreen there is no pointer).
struct HintHover: EnvironmentKey {
    static let defaultValue: Command? = nil
}

extension EnvironmentValues {
    var hintHover: Command? {
        get { self[HintHover.self] }
        set { self[HintHover.self] = newValue }
    }

    /// Settings → Controllers → Confirm Button is Circle: the hints show ○ to select and ✕ to go back.
    var circleConfirms: Bool {
        get { self[CircleConfirms.self] }
        set { self[CircleConfirms.self] = newValue }
    }
}

struct CircleConfirms: EnvironmentKey {
    static let defaultValue = false
}

/// A key or button glyph with what it does. A click does what the key does: the whole pill when
/// its glyphs all give one command ("↩ / ✕"), each glyph on its own when they give several (the
/// arrows, Q and E). The click goes through the same handler as the key.
struct Hint: View {
    let label: String
    @Environment(\.scale) private var scale
    @Environment(\.circleConfirms) private var circleConfirms
    @ObservedObject private var inputMode = InputModeState.shared

    /// The keys of the input in use: a controller's glyphs or the keyboard's, never both.
    private var keys: String { HintKeys.keys(allKeys, for: inputMode.mode) }

    init(keys: String, label: String) {
        self.allKeys = keys
        self.label = label
    }

    private let allKeys: String

    var body: some View {
        if let command = HintKeys.single(keys) {
            Button { Input.shared.press(command) } label: {
                HStack(spacing: 8 * scale) {
                    keycap(Text(ConfirmButton.glyphs(keys, circleConfirms: circleConfirms)).font(glyphFont).padding(.horizontal, 7 * scale).padding(.vertical, 3 * scale))
                    Text(label).font(.display(13 * scale, .medium))
                }
            }
            .buttonStyle(HintPillStyle(command: command))
        } else {
            HStack(spacing: 8 * scale) {
                keycap(HStack(spacing: 0) {
                    ForEach(Array(HintKeys.tokens(keys).enumerated()), id: \.offset) { _, token in
                        if let command = token.command {
                            Button { Input.shared.press(command) } label: {
                                Text(ConfirmButton.glyphs(token.text, circleConfirms: circleConfirms)).font(glyphFont)
                            }
                            .buttonStyle(HintGlyphStyle(command: command))
                        } else {
                            Text(token.text).font(glyphFont).padding(.horizontal, 2 * scale).opacity(0.6)
                        }
                    }
                }
                .padding(.horizontal, 2 * scale))
                Text(label).font(.display(13 * scale, .medium))
            }
            .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var glyphFont: Font { .system(size: 12 * scale, weight: .bold, design: .rounded) }

    private func keycap(_ content: some View) -> some View {
        content.background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 5 * scale))
    }
}

/// A whole hint pill as a button: it lifts under the pointer and sinks while pressed.
private struct HintPillStyle: ButtonStyle {
    let command: Command

    func makeBody(configuration: Configuration) -> some View {
        HintPress(command: command, pressed: configuration.isPressed, whole: true) { configuration.label }
    }
}

/// One glyph of a hint pill as a button (an arrow, Q or E).
private struct HintGlyphStyle: ButtonStyle {
    let command: Command

    func makeBody(configuration: Configuration) -> some View {
        HintPress(command: command, pressed: configuration.isPressed, whole: false) { configuration.label }
    }
}

/// The hover and pressed looks of a hint's button. The pill's highlight reaches past its layout,
/// so that hovering never moves the hints beside it.
private struct HintPress<Label: View>: View {
    let command: Command
    let pressed: Bool
    /// The whole pill (a capsule around glyph and label) or one glyph inside the keycap.
    let whole: Bool
    @ViewBuilder let label: () -> Label
    @Environment(\.scale) private var scale
    @Environment(\.hintHover) private var forced
    @State private var hovering = false

    var body: some View {
        let lit = hovering || forced == command
        let inset = whole ? CGSize(width: 9 * scale, height: 5 * scale) : CGSize(width: 5 * scale, height: 3 * scale)
        let shape = RoundedRectangle(cornerRadius: whole ? 40 * scale : 4 * scale, style: .continuous)
        label()
            .foregroundStyle(.white.opacity(lit || pressed ? 1 : 0.72))
            .padding(.horizontal, inset.width)
            .padding(.vertical, inset.height)
            .background(shape.fill(Color.white.opacity(pressed ? (whole ? 0.2 : 0.32) : lit ? (whole ? 0.1 : 0.2) : 0)))
            .overlay(shape.strokeBorder(Color.white.opacity(whole && lit ? 0.14 : 0), lineWidth: 1))
            .contentShape(shape)
            .pointingHand($hovering)
            .hoverTick("hint-\(command.rawValue)-\(whole)")
            .padding(.horizontal, whole ? -inset.width : 0)
            .padding(.vertical, whole ? -inset.height : 0)
            .scaleEffect(pressed ? (whole ? 0.96 : 0.9) : 1)
            .animation(.easeOut(duration: 0.12), value: lit)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension View {
    /// Tracks the pointer over the view and shows the pointing hand (or another cursor) while it
    /// is there.
    func pointingHand(_ hovering: Binding<Bool>, cursor: NSCursor = .pointingHand) -> some View {
        onHover { inside in
            guard inside != hovering.wrappedValue else { return }
            hovering.wrappedValue = inside
            if inside { cursor.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if hovering.wrappedValue { NSCursor.pop() }
            hovering.wrappedValue = false
        }
    }
}

/// The launcher's language, set at the root: a view whose texts come from T but that holds nothing
/// that changes with the language reads it, so SwiftUI draws it again when the language changes
/// (it skips a view whose own values are all the same).
private struct LanguageCodeKey: EnvironmentKey {
    static let defaultValue = "en"
}

extension EnvironmentValues {
    var languageCode: String {
        get { self[LanguageCodeKey.self] }
        set { self[LanguageCodeKey.self] = newValue }
    }
}

struct HintBar: View {
    var options = true
    @Environment(\.scale) private var scale

    /// Read so the view is drawn again in another language (its texts come from T).
    @Environment(\.languageCode) private var languageCode

    var body: some View {
        let _ = languageCode
        HStack(spacing: 22 * scale) {
            Hint(keys: "← → ↑ ↓", label: T.text(.hintMove))
            Hint(keys: "Q E / L1 R1", label: T.text(.hintGame))
            Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
            Hint(keys: "esc / ○", label: T.text(.hintBack))
            if options { Hint(keys: "O / △", label: T.text(.hintOptions)) }
        }
        .legible(14)
    }
}

extension Installer.Step {
    var title: String {
        switch self {
        case .unwrap: return T.text(.stepUnwrap)
        case .relink: return T.text(.stepRelink)
        case .copy: return T.text(.stepCopy)
        case .bundle: return T.text(.stepBundle)
        case .finish: return T.text(.stepFinish)
        }
    }

    /// Each step's share of the whole unlock, for one overall bar.
    var span: (start: Double, length: Double) {
        switch self {
        case .unwrap: return (0, 0.12)
        case .relink: return (0.12, 0.5)
        case .copy: return (0.62, 0.26)
        case .bundle: return (0.88, 0.08)
        case .finish: return (0.96, 0.04)
        }
    }

    func overall(_ fraction: Double) -> Double { span.start + span.length * fraction }
}

extension Int64 {
    var byteText: String {
        self < 0 ? "…" : ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

/// Screen reader words for views the pad and the keys drive, as on Windows and Linux.
extension View {
    /// A control tapped by the pointer, read as one button with `label`; `action` is what the
    /// tap does, so VoiceOver can press it too.
    func spokenButton(_ label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction(.default, action)
    }

    /// A row the pointer selects: its text read as one element, a button VoiceOver can press.
    func spokenRow(action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }

    /// Status read as one element with `label`.
    func spokenStatus(_ label: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}
