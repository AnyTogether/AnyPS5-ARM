import AnyPS5Core
import SwiftUI

/// "Connect this phone?" over everything, with the code the phone shows too.
struct PairingCard: View {
    let request: PairingRequest
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            FrostFill(opacity: 0.55).ignoresSafeArea()
            VStack(spacing: 22 * scale) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 44 * scale, weight: .light))
                    .foregroundStyle(model.accent)
                VStack(spacing: 8 * scale) {
                    Text(T.text(.phonePairingTitle)).font(.display(30 * scale, .light)).foregroundStyle(.white)
                    Text(request.deviceName).font(.display(17 * scale, .medium)).foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 14 * scale) {
                    ForEach(Array(request.code.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 52 * scale, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 70 * scale, height: 88 * scale)
                            .glass(16 * scale, opacity: 0.5)
                    }
                }
                Text(T.text(.phonePairingText)).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 16 * scale) {
                    ConsoleButton(title: T.text(.phoneDeny), symbol: "xmark", focused: false, minWidth: 170) { model.answerPairing(false) }
                    ConsoleButton(title: T.text(.phoneAllow), symbol: "checkmark", focused: true, prominent: true, minWidth: 170) { model.answerPairing(true) }
                }
                .padding(.top, 6 * scale)
            }
            .padding(44 * scale)
            .glass(28 * scale, opacity: 0.45)
        }
    }
}

/// mController, the phone, in the top bar: an empty ring with no phone, orange while one
/// connects, green with its latency once it is connected.
/// A connected phone in the indicator: its player number, or nil while it is none yet.
struct PhoneBadge: Identifiable, Equatable {
    let id: String
    let name: String
    let number: Int?
}

struct PhoneIndicator: View {
    let phone: (name: String, latency: Double?)?
    let connecting: String?
    /// The connected phones, a numbered light each.
    var badges: [PhoneBadge] = []
    @Environment(\.scale) private var scale
    @Environment(\.look) private var look
    @State private var pulse = false

    static let green = Color(red: 0.3, green: 0.85, blue: 0.45)
    static let orange = Color(red: 1, green: 0.62, blue: 0.2)

    /// Read so the view is drawn again in another language (its texts come from T).
    @Environment(\.languageCode) private var languageCode

    var body: some View {
        let _ = languageCode
        let color: Color? = phone != nil ? Self.green : connecting != nil ? Self.orange : nil
        HStack(spacing: 8 * scale) {
            if badges.isEmpty {
                ZStack {
                    Circle().strokeBorder(.white.opacity(color == nil ? 0.45 : 0), lineWidth: 1.5 * scale)
                    if let color {
                        Circle().fill(color)
                            .shadow(color: color, radius: 4 * scale)
                            .opacity(phone == nil && pulse ? 0.35 : 1)
                    }
                }
                .frame(width: 9 * scale, height: 9 * scale)
            } else {
                HStack(spacing: 4 * scale) {
                    ForEach(badges) { badge in
                        Badge(number: badge.number)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.35), value: badges)
            }
            Text("mController").font(.display(14 * scale, .semibold))
            if let latency = phone?.latency {
                Text("\(Int(latency.rounded())) ms").font(.display(14 * scale, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white.opacity(color == nil ? (look.seeThrough ? 0.75 : 0.55) : 0.9))
        .padding(.leading, (badges.isEmpty ? 14 : 8) * scale)
        .padding(.trailing, 14 * scale)
        .frame(height: 36 * scale)
                // On Glass's see-through window the pill is a plate its words read on.
        .background(Capsule().fill(look.seeThrough ? Ice.navy.opacity(GlassWindowRecipe.plateOpacity) : Color.white.opacity(0.1)))
        .animation(.easeInOut(duration: 0.25), value: color)
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        .help(help)
    }

    private var help: String {
        guard badges.count > 1 || badges.first?.number == nil, !badges.isEmpty else {
            return phone.map { T.format(.phoneConnected, $0.name) } ?? connecting.map { T.format(.phoneConnecting, $0) } ?? T.text(.phoneNone)
        }
        return badges.map { badge in badge.number.map { T.format(.phonePlayer, $0, badge.name) } ?? T.format(.phoneWaiting, badge.name) }
            .joined(separator: "\n")
    }

    /// One phone: its number on a lit green disc, or an empty ring while it has none.
    private struct Badge: View {
        let number: Int?
        @Environment(\.scale) private var scale

        var body: some View {
            ZStack {
                if let number {
                    Circle().fill(PhoneIndicator.green)
                        .shadow(color: PhoneIndicator.green.opacity(0.7), radius: 4 * scale)
                    Text("\(number)")
                        .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.78))
                        .contentTransition(.numericText())
                } else {
                    Circle().strokeBorder(PhoneIndicator.green, lineWidth: 1.5 * scale)
                }
            }
            .frame(width: 18 * scale, height: 18 * scale)
        }
    }
}
