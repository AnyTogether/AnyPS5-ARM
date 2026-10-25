import AnyPS5Core
import AppKit
import Combine
import SwiftUI

/// Settings → Controllers: the controllers connected (Player 1 first), the test, vibration, the
/// light bar, the confirm button, the dead zone and the troubleshooter.
extension AppModel {
    /// Reads the controllers from launch on: the roster's changes redraw the screens, a connect
    /// or disconnect is a toast (not in the first seconds, nor while a game is in front) and a
    /// line in the game's log while one runs.
    func startControllers() {
        let controllers = Controllers.shared
        let launched = Date()
        controllers.announce = { [weak self] text, symbol in
            guard let self, self.running == nil, Date().timeIntervalSince(launched) > 3 else { return }
            self.show(text, symbol: symbol)
        }
        controllers.gameLog = { [weak self] line in
            guard let game = self?.running?.game else { return }
            let file = AppModel.logFile(for: game)
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("[anyps5-launcher] \(line)\n".utf8))
            try? handle.close()
        }
        controllerSink = controllers.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        controllers.start()
    }

    func controllerRows() -> [PanelRow] {
        let controllers = Controllers.shared
        let pads = controllers.roster.pads
        let one = controllers.roster.playerOne
        var rows: [PanelRow] = []
        if pads.isEmpty {
            rows.append(PanelRow(id: "pads-none", title: TP.text(.noneConnected), detail: TP.text(.noneConnectedDetail), symbol: "gamecontroller", kind: .info(""), wraps: true))
        }
        for pad in pads.filter({ $0.id == one }) + pads.filter({ $0.id != one }) {
            rows.append(PanelRow(id: "pad-\(pad.id)", title: pad.id == one ? "\(pad.name) · \(TP.text(.playerOne))" : pad.name, detail: TP.summary(pad),
                                 symbol: controllers.symbol(pad.kind), kind: .action(destructive: false) { [weak self] in
                                     controllers.used(pad.id)
                                     self?.openControllerTest()
                                 }))
        }
        rows += [
            PanelRow(id: "padTest", title: TP.text(.testInputs), detail: TP.text(.testInputsDetail), symbol: "dot.circle.and.hand.point.up.left.fill",
                     kind: .action(destructive: false) { [weak self] in self?.openControllerTest() }),
            PanelRow(id: "padVibrate", title: TP.text(.testVibration), detail: TP.text(.testVibrationDetail), symbol: "waveform.path",
                     kind: .action(destructive: false) { [weak self] in
                         guard let pad = controllers.playerOne else { return }
                         let shook = controllers.testVibration()
                         self?.show(TP.format(shook ? .vibrated : .noVibration, pad.name), symbol: shook ? "waveform.path" : "waveform.slash")
                     }),
            PanelRow(id: "padLight", title: TP.text(.light), detail: TP.text(.lightDetail), symbol: "lightbulb.led",
                     kind: .choice(options: PadLight.allCases.map(TP.light), selected: PadLight.allCases.firstIndex(of: controllers.light) ?? 0) { [weak self] index in
                         let light = PadLight.allCases[index]
                         self?.preferences.controllerLight = light == .theme ? nil : light.rawValue
                     }),
            PanelRow(id: "padConfirm", title: TP.text(.confirm), detail: TP.text(.confirmDetail), symbol: "circle.circle",
                     kind: .choice(options: [TP.text(.confirmCross), TP.text(.confirmCircle)], selected: preferences.confirmCircle == true ? 1 : 0) { [weak self] index in
                         self?.preferences.confirmCircle = index == 1 ? true : nil
                     }),
            PanelRow(id: "padDeadzone", title: TP.text(.deadzone), detail: TP.text(.deadzoneDetail), symbol: "smallcircle.circle",
                     kind: .stepper(value: preferences.stickDeadzone ?? 0, range: StickDeadzone.range, step: StickDeadzone.step, format: { $0 == 0 ? T.text(.off) : "\($0)%" }) { [weak self] value in
                         self?.preferences.stickDeadzone = value == 0 ? nil : value
                     }),
            PanelRow(id: "padTroubleshoot", title: TP.text(.troubleshoot), kind: .info("")),
        ]
        let findings = controllers.findings
        if !findings.contains(where: \.isProblem) && !pads.isEmpty {
            rows.append(PanelRow(id: "pad-ok", title: TP.text(.allGood), detail: TP.text(.allGoodDetail), symbol: "checkmark.circle", kind: .info(""), wraps: true))
        }
        for (index, finding) in findings.enumerated() {
            let text = TP.finding(finding)
            rows.append(PanelRow(id: "finding-\(index)-\(finding.id)", title: text.title, detail: text.detail,
                                 symbol: finding.isProblem ? "exclamationmark.triangle" : "lightbulb", kind: .info(""), wraps: true))
        }
        return rows
    }

    func openControllerTest() {
        Controllers.shared.refresh()
        withAnimation(Motion.overlay) { overlay = .controllerTest }
        Sounds.shared.play(.select)
    }

    /// Back to Settings → Controllers.
    func closeControllerTest() {
        withAnimation(Motion.overlay) { overlay = .settings }
        Sounds.shared.play(.back)
    }

    /// The test takes the pads' buttons: Esc (or a click) leaves it; a controller leaves by
    /// holding Circle (ControllerTestView).
    func controllerTestCommand(_ command: Command) -> Bool {
        if command == .back && !Feel.shared.haptics.padInUse { closeControllerTest() }
        return true
    }
}

/// The controller test: Player 1's controller drawn, every button lit while it is held, the
/// sticks where they are (with the dead zone's ring), the triggers as far as they go. Any pad
/// pressed becomes the one shown; holding Circle (B) for a second leaves.
struct ControllerTestView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var controllers = Controllers.shared
    @ObservedObject private var live = Controllers.shared.live
    @Environment(\.scale) private var scale
    @State private var leaving: Date?

    static let holdToLeave: TimeInterval = 1.0

    var body: some View {
        let pad = controllers.playerOne
        let state = pad.flatMap { live.states[$0.id] } ?? .idle
        VStack(spacing: 22 * scale) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text(TP.text(.testTitle)).font(.display(40 * scale, .light)).foregroundStyle(.white)
                    Text(pad.map { "\($0.name) · \(TP.summary($0))" } ?? TP.text(.testNoPad))
                        .font(.display(16 * scale)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Button { model.closeControllerTest() } label: {
                    Text(TP.text(.testLeave)).font(.display(15 * scale, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 18 * scale).frame(height: 38 * scale)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            if controllers.roster.pads.count > 1 {
                HStack(spacing: 10 * scale) {
                    ForEach(controllers.roster.pads) { other in
                        let current = other.id == pad?.id
                        HStack(spacing: 8 * scale) {
                            Image(systemName: controllers.symbol(other.kind))
                            Text(other.name).lineLimit(1)
                        }
                        .font(.display(14 * scale, current ? .semibold : .regular))
                        .foregroundStyle(current ? Color.black : .white.opacity(0.75))
                        .padding(.horizontal, 14 * scale).frame(height: 32 * scale)
                        .background(Capsule().fill(current ? Color.white : Color.white.opacity(0.1)))
                        .onTapGesture { controllers.used(other.id) }
                    }
                    Spacer()
                }
            }
            PadDiagram(kind: pad?.kind ?? .dualSense, state: state, deadzone: model.preferences.stickDeadzone ?? 0, accent: model.accent)
                .frame(maxWidth: 900 * scale, maxHeight: .infinity)
                .opacity(pad == nil ? 0.35 : 1)
            HStack(spacing: 28 * scale) {
                readout(TP.text(.testSticks), String(format: "L %+.2f %+.2f   R %+.2f %+.2f", state.leftX + 0, -state.leftY + 0, state.rightX + 0, -state.rightY + 0))
                readout(TP.text(.testTriggers), String(format: "L2 %3d%%   R2 %3d%%", Int(state.l2 * 100), Int(state.r2 * 100)))
                Spacer()
                HStack(spacing: 8 * scale) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 3 * scale)
                        Circle().trim(from: 0, to: leavingFraction).stroke(model.accent, style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 20 * scale, height: 20 * scale)
                    Text(TP.format(.testHoldToLeave, Self.eastGlyph(pad?.kind ?? .dualSense)) + " · Esc").font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .padding(.horizontal, 90 * scale)
        .padding(.top, 70 * scale)
        .padding(.bottom, 50 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenFrost(0.78)
        .onChange(of: state.pressed.contains(.east)) { _, held in
            leaving = held ? Date() : nil
            guard held else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdToLeave) {
                if let leaving, Date().timeIntervalSince(leaving) >= Self.holdToLeave - 0.02, model.overlay == .controllerTest {
                    model.closeControllerTest()
                }
            }
        }
        .animation(.linear(duration: leaving == nil ? 0.1 : Self.holdToLeave), value: leaving)
    }

    private var leavingFraction: CGFloat { leaving == nil ? 0 : 1 }

    /// The east face button's glyph: ○, B, or A on a Switch controller.
    static func eastGlyph(_ kind: PadKind) -> String {
        kind.isPlayStation ? "○" : kind == .switchPro ? "A" : "B"
    }

    private func readout(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(title.uppercased()).font(.display(11 * scale, .semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 15 * scale, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// A controller drawn flat, its family's glyphs on the face buttons: what is held lights in the
/// accent, the sticks sit where they are inside their dead zone's ring, the triggers fill.
struct PadDiagram: View {
    let kind: PadKind
    let state: PadState
    let deadzone: Int
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * 1.6)
            let unit = width / 160
            ZStack {
                // The body and its grips.
                PadSilhouette().fill(Color.white.opacity(0.07))
                PadSilhouette().stroke(Color.white.opacity(0.22), lineWidth: 0.6 * unit)
                // Shoulders and triggers.
                trigger(.l2, value: state.l2, label: kind == .xbox ? "LT" : kind == .switchPro ? "ZL" : "L2").position(x: 36 * unit, y: 3.5 * unit)
                trigger(.r2, value: state.r2, label: kind == .xbox ? "RT" : kind == .switchPro ? "ZR" : "R2").position(x: 124 * unit, y: 3.5 * unit)
                bumper(.l1, label: kind == .xbox ? "LB" : kind == .switchPro ? "L" : "L1").position(x: 36 * unit, y: 10.5 * unit)
                bumper(.r1, label: kind == .xbox ? "RB" : kind == .switchPro ? "R" : "R1").position(x: 124 * unit, y: 10.5 * unit)
                // D-pad.
                ForEach([(PadButton.dpadUp, 0.0, -1.0), (.dpadDown, 0, 1), (.dpadLeft, -1, 0), (.dpadRight, 1, 0)], id: \.0) { button, dx, dy in
                    RoundedRectangle(cornerRadius: 1.4 * unit).fill(fill(button)).frame(width: 7 * unit, height: 7 * unit)
                        .position(x: (36 + dx * 7.5) * unit, y: (38 + dy * 7.5) * unit)
                }
                // Face buttons by place, with the family's glyphs.
                ForEach(Array(faceButtons.enumerated()), id: \.offset) { _, face in
                    ZStack {
                        Circle().fill(fill(face.button))
                        Text(face.glyph).font(.system(size: 5.2 * unit, weight: .bold, design: .rounded))
                            .foregroundStyle(lit(face.button) ? Color.black : .white.opacity(0.85))
                    }
                    .frame(width: 9 * unit, height: 9 * unit)
                    .position(x: (124 + face.dx * 9) * unit, y: (38 + face.dy * 9) * unit)
                }
                // Middle: select, start, guide and the touchpad.
                if kind == .dualSense || kind == .dualShock4 {
                    RoundedRectangle(cornerRadius: 3 * unit).fill(fill(.touchpad)).frame(width: 40 * unit, height: 20 * unit).position(x: 80 * unit, y: 30 * unit)
                }
                pill(.select, label: selectLabel).position(x: 56 * unit, y: 24 * unit)
                pill(.start, label: startLabel).position(x: 104 * unit, y: 24 * unit)
                ZStack {
                    Circle().fill(fill(.guide))
                    Text(kind.isPlayStation ? "PS" : kind == .xbox ? "X" : "⌂").font(.system(size: 3.6 * unit, weight: .heavy, design: .rounded))
                        .foregroundStyle(lit(.guide) ? Color.black : .white.opacity(0.8))
                }
                .frame(width: 8 * unit, height: 8 * unit)
                .position(x: 80 * unit, y: 50 * unit)
                if kind == .xbox || kind == .dualSense {
                    Capsule().fill(fill(.misc)).frame(width: 5 * unit, height: 2.4 * unit).position(x: 80 * unit, y: 57 * unit)
                }
                // Sticks.
                stick(x: state.leftX, y: state.leftY, pressed: lit(.l3), label: "L").position(x: 58 * unit, y: 60 * unit)
                stick(x: state.rightX, y: state.rightY, pressed: lit(.r3), label: "R").position(x: 102 * unit, y: 60 * unit)
            }
            .frame(width: width, height: width / 1.6)
            .environment(\.padUnit, unit)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1.6, contentMode: .fit)
    }

    private var faceButtons: [(button: PadButton, glyph: String, dx: Double, dy: Double)] {
        let glyphs: [PadButton: String]
        switch kind {
        case .dualSense, .dualShock4, .dualShock3: glyphs = [.south: "✕", .east: "○", .west: "□", .north: "△"]
        // By place: Nintendo's B is south and A east.
        case .switchPro: glyphs = [.south: "B", .east: "A", .west: "Y", .north: "X"]
        case .xbox, .generic: glyphs = [.south: "A", .east: "B", .west: "X", .north: "Y"]
        }
        return [(.south, glyphs[.south]!, 0, 1), (.east, glyphs[.east]!, 1, 0), (.west, glyphs[.west]!, -1, 0), (.north, glyphs[.north]!, 0, -1)]
    }

    private var selectLabel: String {
        switch kind {
        case .dualSense: return "Create"
        case .dualShock4: return "Share"
        case .dualShock3: return "Select"
        case .xbox: return "View"
        case .switchPro: return "−"
        case .generic: return "Back"
        }
    }

    private var startLabel: String {
        switch kind {
        case .dualSense, .dualShock4: return "Options"
        case .dualShock3: return "Start"
        case .xbox: return "Menu"
        case .switchPro: return "+"
        case .generic: return "Start"
        }
    }

    private func lit(_ button: PadButton) -> Bool { state.pressed.contains(button) }
    private func fill(_ button: PadButton) -> Color { lit(button) ? accent : Color.white.opacity(0.13) }

    private func trigger(_ button: PadButton, value: Double, label: String) -> some View {
        TriggerBar(value: value, lit: lit(button), label: label, accent: accent)
    }

    private func bumper(_ button: PadButton, label: String) -> some View {
        PadLabelShape(label: label, lit: lit(button), accent: accent, width: 22, height: 5)
    }

    private func pill(_ button: PadButton, label: String) -> some View {
        PadLabelShape(label: label, lit: lit(button), accent: accent, width: 15, height: 4.4)
    }

    private func stick(x: Double, y: Double, pressed: Bool, label: String) -> some View {
        StickView(x: x, y: y, pressed: pressed, deadzone: deadzone, label: label, accent: accent)
    }
}

private struct PadUnit: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    /// One 160th of a controller diagram's width.
    var padUnit: CGFloat {
        get { self[PadUnit.self] }
        set { self[PadUnit.self] = newValue }
    }
}

private struct TriggerBar: View {
    let value: Double
    let lit: Bool
    let label: String
    let accent: Color
    @Environment(\.padUnit) private var unit

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.13))
            Capsule().fill(accent).frame(width: max(0, 22 * unit * value))
            Text(label).font(.system(size: 3.4 * unit, weight: .bold, design: .rounded)).foregroundStyle(lit || value > 0.5 ? Color.black : .white.opacity(0.8))
                .frame(maxWidth: .infinity)
        }
        .frame(width: 22 * unit, height: 6 * unit)
    }
}

private struct PadLabelShape: View {
    let label: String
    let lit: Bool
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    @Environment(\.padUnit) private var unit

    var body: some View {
        Text(label).font(.system(size: 3.2 * unit, weight: .bold, design: .rounded))
            .foregroundStyle(lit ? Color.black : .white.opacity(0.8))
            .frame(width: width * unit, height: height * unit)
            .background(Capsule().fill(lit ? accent : Color.white.opacity(0.13)))
    }
}

private struct StickView: View {
    let x: Double
    let y: Double
    let pressed: Bool
    let deadzone: Int
    let label: String
    let accent: Color
    @Environment(\.padUnit) private var unit

    var body: some View {
        let radius = 9 * unit
        ZStack {
            Circle().fill(Color.white.opacity(0.06))
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5 * unit)
            if deadzone > 0 {
                Circle().stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 0.4 * unit, dash: [1 * unit, 1 * unit]))
                    .frame(width: radius * 2 * CGFloat(deadzone) / 100, height: radius * 2 * CGFloat(deadzone) / 100)
            }
            Circle().fill(pressed ? accent : Color.white.opacity(0.85))
                .frame(width: 7 * unit, height: 7 * unit)
                .overlay(Text(label).font(.system(size: 3 * unit, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.7)))
                .offset(x: CGFloat(x) * radius, y: CGFloat(y) * radius)
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// A controller's outline in a 160 × 100 box: a wide body and two grips.
struct PadSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 160
        var path = Path()
        path.move(to: CGPoint(x: 30 * u, y: 14 * u))
        path.addLine(to: CGPoint(x: 130 * u, y: 14 * u))
        path.addCurve(to: CGPoint(x: 152 * u, y: 40 * u), control1: CGPoint(x: 144 * u, y: 14 * u), control2: CGPoint(x: 150 * u, y: 26 * u))
        path.addCurve(to: CGPoint(x: 146 * u, y: 92 * u), control1: CGPoint(x: 156 * u, y: 62 * u), control2: CGPoint(x: 158 * u, y: 88 * u))
        path.addCurve(to: CGPoint(x: 118 * u, y: 74 * u), control1: CGPoint(x: 134 * u, y: 96 * u), control2: CGPoint(x: 126 * u, y: 80 * u))
        path.addLine(to: CGPoint(x: 42 * u, y: 74 * u))
        path.addCurve(to: CGPoint(x: 14 * u, y: 92 * u), control1: CGPoint(x: 34 * u, y: 80 * u), control2: CGPoint(x: 26 * u, y: 96 * u))
        path.addCurve(to: CGPoint(x: 8 * u, y: 40 * u), control1: CGPoint(x: 2 * u, y: 88 * u), control2: CGPoint(x: 4 * u, y: 62 * u))
        path.addCurve(to: CGPoint(x: 30 * u, y: 14 * u), control1: CGPoint(x: 10 * u, y: 26 * u), control2: CGPoint(x: 16 * u, y: 14 * u))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The top bar's controller line, shown only when there is something to say (a controller's
/// battery nearly empty): the controller's name and what is left.
struct PadStatusPill: View {
    let text: String
    @Environment(\.scale) private var scale
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: "battery.25percent").font(.system(size: 14 * scale, weight: .semibold)).foregroundStyle(PhoneIndicator.orange)
            Text(text).font(.display(14 * scale, .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14 * scale)
        .frame(height: 36 * scale)
        .background(Capsule().fill(look.seeThrough ? Ice.navy.opacity(GlassWindowRecipe.plateOpacity) : Color.white.opacity(0.1)))
    }
}
