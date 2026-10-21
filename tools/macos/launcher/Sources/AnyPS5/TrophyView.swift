import AnyPS5Core
import AppKit
import SwiftUI

/// The selected game's trophies, as the console lists them: the progress at the top, then every
/// trophy with its icon, grade and the day it was earned.
struct TrophyList: View {
    let game: Game
    let set: TrophySet
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        VStack(alignment: .leading, spacing: 28 * scale) {
            header
            if previewRender {
                Color.clear.overlay(alignment: .top) { rows }.clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) { rows }
                        .onChange(of: model.trophyIndex) { _, index in
                            guard set.trophies.indices.contains(index) else { return }
                            withAnimation(Motion.focus) { proxy.scrollTo(set.trophies[index].id, anchor: .center) }
                        }
                }
            }
        }
        .padding(.horizontal, 80 * scale)
        .padding(.vertical, 56 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.74).background(.ultraThinMaterial))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 26 * scale) {
            TrophyIcon(data: set.icon, key: game.id + "/set", size: 112 * scale, earned: true)
            VStack(alignment: .leading, spacing: 12 * scale) {
                Text(T.text(.trophies))
                    .font(.display(13 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(set.title.isEmpty ? game.name : set.title)
                    .font(.display(36 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 16 * scale) {
                    Text("\(set.percent)%")
                        .font(.display(22 * scale, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    ProgressLine(fraction: Double(set.percent) / 100, color: model.accent)
                        .frame(width: 260 * scale)
                    ForEach(TrophySet.Grade.allCases, id: \.self) { grade in
                        let count = set.count(grade)
                        if count.total > 0 {
                            HStack(spacing: 6 * scale) {
                                Image(systemName: "trophy.fill").foregroundStyle(grade.color)
                                Text("\(count.unlocked)/\(count.total)").monospacedDigit()
                            }
                            .font(.display(15 * scale, .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HintBar(options: false)
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 10 * scale) {
            ForEach(Array(set.trophies.enumerated()), id: \.element.id) { index, trophy in
                TrophyRow(game: game, trophy: trophy, focused: index == model.trophyIndex)
                    .id(trophy.id)
                    .onTapGesture { model.trophyIndex = index }
            }
        }
        .padding(8 * scale)
    }
}

struct TrophyRow: View {
    let game: Game
    let trophy: TrophySet.Trophy
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let earned = trophy.unlocked != nil
        let secret = trophy.hidden && !earned
        HStack(spacing: 20 * scale) {
            if secret {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 68 * scale, height: 68 * scale)
                    .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(Color.white.opacity(0.07)))
            } else {
                TrophyIcon(data: trophy.icon, key: game.id + "/" + trophy.id, size: 68 * scale, earned: earned)
            }
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(secret ? T.text(.trophyHidden) : trophy.name)
                    .font(.display(18 * scale, .semibold))
                    .foregroundStyle(.white.opacity(earned ? 1 : 0.8))
                    .lineLimit(1)
                Text(secret ? T.text(.trophyHiddenDetail) : trophy.detail)
                    .font(.display(14 * scale))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                if !earned, !secret, let progress = trophy.progress {
                    HStack(spacing: 10 * scale) {
                        ProgressLine(fraction: Double(progress.value) / Double(progress.target), color: model.accent, height: 4 * scale)
                            .frame(width: 180 * scale)
                        Text("\(progress.value)/\(progress.target)")
                            .font(.display(12 * scale, .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 12 * scale)
            VStack(alignment: .trailing, spacing: 6 * scale) {
                Label(trophy.grade.title, systemImage: "trophy.fill")
                    .font(.display(14 * scale, .semibold))
                    .foregroundStyle(trophy.grade.color.opacity(earned ? 1 : 0.55))
                Text(trophy.unlocked.map(TrophyRow.date) ?? T.text(.trophyLocked))
                    .font(.display(13 * scale))
                    .foregroundStyle(.white.opacity(earned ? 0.7 : 0.4))
            }
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 16 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: T.language == .turkish ? "tr_TR" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// A trophy's PNG from the package, grey until it is earned.
struct TrophyIcon: View {
    let data: Data?
    let key: String
    let size: CGFloat
    let earned: Bool
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).fill(Color.white.opacity(0.07))
            if let image = TrophyIcon.image(data, key: key) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .saturation(earned ? 1 : 0)
                    .opacity(earned ? 1 : 0.45)
            } else {
                Image(systemName: "trophy.fill").font(.system(size: size * 0.38)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ data: Data?, key: String) -> NSImage? {
        if let image = cache[key] { return image }
        guard let data, let image = NSImage(data: data) else { return nil }
        cache[key] = image
        return image
    }
}

extension TrophySet.Grade {
    var title: String {
        switch self {
        case .platinum: return T.text(.gradePlatinum)
        case .gold: return T.text(.gradeGold)
        case .silver: return T.text(.gradeSilver)
        case .bronze: return T.text(.gradeBronze)
        }
    }

    var color: Color {
        switch self {
        case .platinum: return Color(red: 0.74, green: 0.84, blue: 0.97)
        case .gold: return Color(red: 0.97, green: 0.78, blue: 0.34)
        case .silver: return Color(red: 0.8, green: 0.82, blue: 0.86)
        case .bronze: return Color(red: 0.83, green: 0.55, blue: 0.36)
        }
    }
}

extension AppModel {
    func moveTrophy(_ delta: Int) {
        guard let game = selectedGame, let set = trophies[game.id] else { return }
        let next = min(set.trophies.count - 1, max(0, trophyIndex + delta))
        guard next != trophyIndex else { return }
        trophyIndex = next
        Sounds.shared.play(.move)
    }
}
