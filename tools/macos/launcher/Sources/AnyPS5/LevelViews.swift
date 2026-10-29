import AnyPS5Core
import SwiftUI

/// The metals a trophy level is drawn in: a deep tone for the frame and a bright one for the
/// number and the details (the website's colours).
extension TogetherLevelBadge.Tier {
    var metal: Color {
        switch self {
        case .bronze: return Color(red: 0.784, green: 0.545, blue: 0.341)
        case .silver: return Color(red: 0.663, green: 0.69, blue: 0.729)
        case .gold: return Color(red: 0.851, green: 0.663, blue: 0.227)
        case .platinum: return Color(red: 0.557, green: 0.651, blue: 0.839)
        }
    }

    var bright: Color {
        switch self {
        case .bronze: return Color(red: 0.941, green: 0.769, blue: 0.604)
        case .silver: return Color(red: 0.933, green: 0.945, blue: 0.961)
        case .gold: return Color(red: 1, green: 0.89, blue: 0.604)
        case .platinum: return Color(red: 0.91, green: 0.941, blue: 1)
        }
    }

    var name: String {
        switch self {
        case .bronze: return TL.text(.tierBronze)
        case .silver: return TL.text(.tierSilver)
        case .gold: return TL.text(.tierGold)
        case .platinum: return TL.text(.tierPlatinum)
        }
    }
}

/// A path drawn in a 32 × 32 box, scaled into the rect: the level's hexagon and its frame's parts.
private struct LevelGlyph: Shape {
    let points: [CGPoint]
    var closed = true

    static let hexagon = LevelGlyph(points: [.init(x: 16, y: 2.5), .init(x: 27.7, y: 9.25), .init(x: 27.7, y: 22.75), .init(x: 16, y: 29.5), .init(x: 4.3, y: 22.75), .init(x: 4.3, y: 9.25)])
    static let ring = LevelGlyph(points: [.init(x: 16, y: 6.2), .init(x: 24.5, y: 11.1), .init(x: 24.5, y: 20.9), .init(x: 16, y: 25.8), .init(x: 7.5, y: 20.9), .init(x: 7.5, y: 11.1)])
    static let crest = LevelGlyph(points: [.init(x: 12.5, y: 3.9), .init(x: 16, y: 1.2), .init(x: 19.5, y: 3.9)], closed: false)
    static let star = LevelGlyph(points: [.init(x: 16, y: 0.2), .init(x: 16.9, y: 2), .init(x: 18.9, y: 2.3), .init(x: 17.45, y: 3.7), .init(x: 17.8, y: 5.7),
                                          .init(x: 16, y: 4.75), .init(x: 14.2, y: 5.7), .init(x: 14.55, y: 3.7), .init(x: 13.1, y: 2.3), .init(x: 15.1, y: 2)])

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 32
        let origin = CGPoint(x: rect.midX - 16 * unit, y: rect.midY - 16 * unit)
        var path = Path()
        path.addLines(points.map { CGPoint(x: origin.x + $0.x * unit, y: origin.y + $0.y * unit) })
        if closed { path.closeSubpath() }
        return path
    }
}

/// A trophy level: the number in its tier's hexagon, with a frame that grows every 100 levels (an
/// inner ring from 100, a crest from 300, a star from 600, a halo at 900).
struct LevelBadgeView: View {
    let badge: TogetherLevelBadge
    var size: CGFloat = 28
    /// Light behind it (the level-up card, the user's own profile).
    var glow = false

    var body: some View {
        let unit = size / 32
        let tier = badge.tier
        ZStack {
            if badge.frame >= 10 {
                Circle().inset(by: unit).stroke(tier.bright.opacity(0.35), style: StrokeStyle(lineWidth: 0.8 * unit, dash: [1.5 * unit, 2.5 * unit]))
            }
            LevelGlyph.hexagon
                .fill(LinearGradient(colors: [tier.metal.opacity(0.38), tier.metal.opacity(0.14)], startPoint: .top, endPoint: .bottom))
                .background(LevelGlyph.hexagon.fill(Color(red: 0.047, green: 0.055, blue: 0.078)))
            LevelGlyph.hexagon.stroke(LinearGradient(colors: [tier.bright, tier.metal], startPoint: .top, endPoint: .bottom),
                                      style: StrokeStyle(lineWidth: (size >= 48 ? 1.2 : 1.6) * unit, lineJoin: .round))
            if badge.frame >= 2 {
                LevelGlyph.ring.stroke(tier.bright.opacity(0.45), style: StrokeStyle(lineWidth: 0.9 * unit, lineJoin: .round))
            }
            if badge.frame >= 4 {
                LevelGlyph.crest.stroke(tier.bright, style: StrokeStyle(lineWidth: 1.4 * unit, lineCap: .round, lineJoin: .round))
            }
            if badge.frame >= 7 {
                LevelGlyph.star.fill(tier.bright)
            }
            Text("\(badge.level)")
                .font(.system(size: size * (badge.level >= 100 ? (size < 40 ? 0.29 : 0.26) : (size < 40 ? 0.36 : 0.33)), weight: .bold, design: .rounded))
                .monospacedDigit()
                .tracking(-0.3)
                .foregroundStyle(tier.bright)
                .offset(y: 0.4 * unit)
        }
        .frame(width: size, height: size)
        .shadow(color: tier.metal.opacity(glow || tier == .platinum || badge.frame >= 10 ? 0.55 : 0), radius: size * 0.16)
        .accessibilityLabel(TL.format(.levelLabel, badge.level))
    }
}

/// The level on a profile: the badge, its tier, and how far to the next one.
struct LevelCard: View {
    let level: TogetherTrophyLevel
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let tier = level.tier
        HStack(spacing: 14 * scale) {
            LevelBadgeView(badge: level.badge, size: 54 * scale, glow: true)
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    Text(TL.text(.trophyLevel)).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(Self.number(level.level)).font(.display(19 * scale, .bold)).monospacedDigit().foregroundStyle(.white)
                    Text(tier.name)
                        .font(.system(size: 10.5 * scale, weight: .semibold, design: .monospaced))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(tier.bright)
                        .padding(.horizontal, 6 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous).strokeBorder(tier.metal.opacity(0.7), lineWidth: 1))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [tier.metal, model.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(5 * scale, proxy.size.width * level.fraction))
                    }
                }
                .frame(height: 5 * scale)
                Text(meta).font(.display(12.5 * scale)).monospacedDigit().foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            .frame(width: 270 * scale)
        }
        .padding(.leading, 10 * scale)
        .padding(.trailing, 16 * scale)
        .padding(.vertical, 9 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
            .fill(LinearGradient(colors: [tier.metal.opacity(0.16), Color.white.opacity(0.03)], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    /// "20 points to level 13 · 700 points".
    private var meta: String {
        let next = level.pointsToNext.map { TL.format(.levelNext, Self.number($0), level.level + 1) } ?? TL.text(.levelTop)
        return next + " · " + TL.format(.levelPoints, Self.number(level.points))
    }

    /// "1,830", or "1.830" in Turkish.
    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = T.locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// "Appearing offline", on the user's own profile and beside their name on the home screen.
struct AppearingOfflineTag: View {
    var compact = false
    @Environment(\.scale) private var scale

    var body: some View {
        Label(TL.text(.appearingOffline), systemImage: "moon.fill")
            .font(.display((compact ? 11 : 12) * scale, .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, (compact ? 8 : 10) * scale)
            .padding(.vertical, (compact ? 3 : 4) * scale)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3 * scale, 2 * scale])))
            .fixedSize()
    }
}

/// The moon on the user's avatar while they appear offline.
struct AppearingOfflineDot: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "moon.fill")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(white: 0.32)))
            .overlay(Circle().strokeBorder(Color(white: 0.08), lineWidth: size * 0.14))
    }
}

/// The card that drops in when the user reaches a new trophy level, over a game too.
struct LevelUpToast: View {
    let badge: TogetherLevelBadge
    var still = false
    let done: () -> Void

    var body: some View {
        let tier = badge.tier
        DroppingCard(still: still, done: done) { popped in
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(tier.metal.opacity(0.4)).blur(radius: 14).frame(width: 64, height: 64)
                        .opacity(popped ? 1 : 0)
                    LevelBadgeView(badge: badge, size: 60, glow: true)
                        .scaleEffect(popped ? 1 : 0.6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(TL.text(.levelUp), systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tier.bright)
                    Text(TL.format(.levelUpTitle, badge.level))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(TL.text(.levelUpDetail) + " · " + tier.name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [tier.metal.opacity(0.7), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .padding(-14))
        }
    }
}

/// A profile's showcase under its card: the favourite games' icons with their progress, then the
/// pinned trophies; a lock when the owner keeps it private.
struct ProfileShowcaseStrip: View {
    let showcase: TogetherShowcase
    let owner: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 30 * scale) {
            if showcase.isPrivate {
                Label(TL.format(.showcasePrivate, owner), systemImage: "lock.fill")
                    .font(.display(14 * scale, .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 6 * scale)
            }
            if let games = showcase.games, !games.isEmpty {
                section(TL.text(.showcaseGames)) {
                    HStack(spacing: 12 * scale) {
                        ForEach(games.prefix(4)) { game in gameTile(game) }
                    }
                }
            }
            if let trophies = showcase.trophies, !trophies.isEmpty {
                section(TL.text(.showcaseTrophies)) {
                    HStack(spacing: 10 * scale) {
                        ForEach(trophies.prefix(6)) { trophy in trophyChip(trophy) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8 * scale)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Text(title)
                .font(.display(12 * scale, .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }

    private func gameTile(_ game: TogetherShowcaseGame) -> some View {
        let size = 64 * scale
        return VStack(spacing: 7 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(Color.white.opacity(0.07))
                if let icon = model.localIcon(game.titleId) {
                    ArtworkImage(url: icon, maxPixels: 400)
                } else if let remote = game.iconUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: remote) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                } else {
                    Text(String(game.name(in: T.language.rawValue).prefix(1)).uppercased())
                        .font(.display(size * 0.36, .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            ProgressLine(fraction: Double(game.progress ?? 0) / 100, color: model.accent, height: 3 * scale)
                .frame(width: size)
                .opacity(game.progress == nil ? 0 : 1)
        }
        .accessibilityLabel(game.name(in: T.language.rawValue))
    }

    private func trophyChip(_ trophy: TogetherEarnedTrophy) -> some View {
        let grade = TrophySet.Grade(name: trophy.grade)
        return HStack(spacing: 10 * scale) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(grade.color)
                .frame(width: 38 * scale, height: 38 * scale)
                .background(Circle().fill(grade.color.opacity(0.16)))
                .overlay(Circle().strokeBorder(grade.color.opacity(0.45), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(trophy.name(in: T.language.rawValue) ?? T.text(.trophyHidden))
                    .font(.display(14 * scale, .semibold))
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white)
                Text(model.games.first { $0.titleID == trophy.titleId }?.name ?? trophy.gameName(in: T.language.rawValue))
                    .font(.display(12 * scale))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 8 * scale)
        .frame(minWidth: 150 * scale, maxWidth: 250 * scale)
        .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
}
