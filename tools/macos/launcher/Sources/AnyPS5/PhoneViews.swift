import AnyPS5Core
import SwiftUI

/// "Connect this phone?" over everything, with the code the phone shows too.
struct PairingCard: View {
    let request: PairingRequest
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.55)).ignoresSafeArea()
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

/// The connected phone in the top bar: a green dot, the phone and its latency.
struct PhoneIndicator: View {
    let name: String
    let latency: Double?
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 8 * scale) {
            Circle().fill(Color(red: 0.3, green: 0.85, blue: 0.45)).frame(width: 8 * scale, height: 8 * scale)
                .shadow(color: Color(red: 0.3, green: 0.85, blue: 0.45), radius: 4 * scale)
            Image(systemName: "iphone.gen3").font(.system(size: 15 * scale, weight: .semibold))
            if let latency { Text("\(Int(latency.rounded())) ms").font(.display(14 * scale, .semibold)).monospacedDigit() }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14 * scale)
        .frame(height: 36 * scale)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .help(name)
    }
}
