import AnyPS5Core
import SwiftUI

/// Trophies compared with a friend, opened from their profile: the games either has trophies in
/// (the ones both play first) with both sides' progress, then one game's trophies side by side —
/// who earned which, and when.
struct CompareView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let social = model.social
        VStack(alignment: .leading, spacing: 26 * scale) {
            header
            if social.compareTitle != nil { gameContent } else { gamesContent }
        }
        .padding(.horizontal, 80 * scale)
        .padding(.vertical, 56 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenFrost(0.74)
        .environment(\.locale, T.locale)
    }

    private var them: String { model.social.compareWith?.displayName ?? "" }

    /// The game on screen, as this Mac or the server names it.
    private var gameName: String {
        let social = model.social
        guard let title = social.compareTitle else { return "" }
        if let local = model.games.first(where: { $0.titleID == title }) { return local.name }
        if let name = social.compareView?.game?.name(in: T.language.rawValue) { return name }
        return social.compareGames.first { $0.titleId == title }?.name(in: T.language.rawValue) ?? title
    }

    // MARK: Header

    private var header: some View {
        let social = model.social
        let inGame = social.compareTitle != nil
        return HStack(alignment: .center, spacing: 28 * scale) {
            faces
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text(inGame ? TL.text(.compareTrophies) + " · " + TL.format(.compareTitle, them) : TL.text(.compareTrophies))
                    .font(.display(13 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(inGame ? gameName : TL.format(.compareTitle, them))
                    .font(.display(38 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(TL.text(inGame ? .compareGameLead : .compareLead))
                    .font(.display(15 * scale))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                if !inGame { Hint(keys: "↩ / ✕", label: TL.text(.hintTrophies)) }
                Hint(keys: "esc / ○", label: inGame ? TL.text(.compareGames) : T.text(.hintBack))
            }
        }
    }

    /// The user and the friend, each with their level.
    private var faces: some View {
        let social = model.social
        let me = social.compareView?.me
        let other = social.compareView?.them
        let user = model.togetherUser
        let size = 76 * scale
        return HStack(spacing: -14 * scale) {
            face(url: me?.avatar ?? user?.avatar, name: me?.displayName ?? user?.displayName ?? "", level: me?.level ?? model.togetherProfile?.trophyLevel?.badge, size: size)
            face(url: other?.avatar ?? social.compareWith?.avatar, name: other?.displayName ?? them,
                 level: other?.level ?? model.profilePage?.profile.trophyLevel?.badge, size: size)
                .zIndex(-1)
        }
    }

    private func face(url: String?, name: String, level: TogetherLevelBadge?, size: CGFloat) -> some View {
        ProfileAvatar(url: url, name: name, size: size, glow: false)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 3 * scale))
            .overlay(alignment: .bottomTrailing) {
                if let level { LevelBadgeView(badge: level, size: 32 * scale).offset(x: 6 * scale, y: 4 * scale) }
            }
    }

    // MARK: Games

    @ViewBuilder private var gamesContent: some View {
        let social = model.social
        switch social.compareGamesLoad {
        case .shown where social.compareGames.isEmpty:
            ProfileNotice(symbol: "trophy", text: TL.text(.compareNoGames))
        case .shown:
            VStack(alignment: .leading, spacing: 6 * scale) {
                sideTitles(leading: 64 * scale + 18 * scale)
                ProfileColumn(title: "", count: nil, focusedIndex: social.compareIndex, ids: social.compareGames.map(\.id)) {
                    ForEach(Array(social.compareGames.enumerated()), id: \.element.id) { index, game in
                        CompareGameRow(game: game, icon: model.localIcon(game.titleId), localName: model.games.first { $0.titleID == game.titleId }?.name,
                                       focused: index == social.compareIndex)
                            .id(game.id)
                            .onTapGesture {
                                if model.social.compareIndex == index { model.openCompareGame(game.titleId) } else { model.social.compareIndex = index }
                            }
                    }
                }
            }
        case .hidden:
            ProfileNotice(symbol: "lock.fill", text: TL.format(.comparePrivate, them))
        case .failed:
            ProfileNotice(symbol: "wifi.exclamationmark", text: TL.text(.compareFailed))
        case .unknown:
            ProfileNotice(symbol: "trophy", text: TL.text(.compareNoGames))
        case .loading:
            loading
        }
    }

    /// "You" and the friend's name above the two sides.
    private func sideTitles(leading: CGFloat) -> some View {
        HStack(spacing: 18 * scale) {
            Spacer(minLength: 0)
            Label(TL.text(.compareYou), systemImage: "person.fill")
                .foregroundStyle(model.accent)
                .frame(width: CompareSides.width * scale, alignment: .leading)
            Label(them, systemImage: "person")
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: CompareSides.width * scale, alignment: .leading)
        }
        .font(.display(13 * scale, .semibold))
        .textCase(.uppercase)
        .tracking(0.6)
        .lineLimit(1)
        .padding(.horizontal, 8 * scale + 16 * scale)
    }

    private var loading: some View {
        VStack(spacing: 18 * scale) {
            IndeterminateLine(color: model.accent).frame(width: 260 * scale)
            Text(TL.text(.compareLoading)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80 * scale)
    }

    // MARK: One game

    @ViewBuilder private var gameContent: some View {
        let social = model.social
        switch social.compareViewLoad {
        case .shown:
            if let view = social.compareView {
                VStack(alignment: .leading, spacing: 14 * scale) {
                    totals(view)
                    sideTitles(leading: 0)
                    ProfileColumn(title: "", count: nil, focusedIndex: social.compareTrophyIndex, ids: view.trophies.map { "t\($0.id)" }) {
                        ForEach(Array(view.trophies.enumerated()), id: \.element.id) { index, trophy in
                            CompareTrophyRow(trophy: trophy, focused: index == social.compareTrophyIndex)
                                .id("t\(trophy.id)")
                                .onTapGesture { model.social.compareTrophyIndex = index }
                        }
                    }
                }
            }
        case .hidden:
            ProfileNotice(symbol: "lock.fill", text: TL.format(.comparePrivate, them))
        case .unknown:
            ProfileNotice(symbol: "trophy", text: TL.text(.compareUnknownGame))
        case .failed:
            ProfileNotice(symbol: "wifi.exclamationmark", text: TL.text(.compareFailed))
        case .loading:
            loading
        }
    }

    /// "You 12/48 · Mira 30/48 · 9 earned by both".
    private func totals(_ view: TogetherCompareView) -> some View {
        HStack(spacing: 12 * scale) {
            total(TL.text(.compareYou), view.totals.mine, of: view.totals.total, color: model.accent)
            total(view.them.displayName, view.totals.theirs, of: view.totals.total, color: .white.opacity(0.85))
            Label(TL.format(.compareBoth, view.totals.both), systemImage: "person.2.fill")
                .font(.display(14 * scale, .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 14 * scale)
                .frame(height: 40 * scale)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            Spacer(minLength: 0)
        }
    }

    private func total(_ who: String, _ earned: Int, of all: Int, color: Color) -> some View {
        HStack(spacing: 10 * scale) {
            Text(who).font(.display(14 * scale, .semibold)).foregroundStyle(color).lineLimit(1)
            Text("\(earned)/\(all)").font(.display(17 * scale, .bold)).monospacedDigit().foregroundStyle(.white)
            ProgressLine(fraction: all > 0 ? Double(earned) / Double(all) : 0, color: color, height: 4 * scale).frame(width: 90 * scale)
        }
        .padding(.horizontal, 16 * scale)
        .frame(height: 40 * scale)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

enum CompareSides {
    /// The width of each side's column, before the scale.
    static let width: CGFloat = 250
}

/// A game compared: its icon and name, then the user's and the friend's progress.
struct CompareGameRow: View {
    let game: TogetherCompareGame
    let icon: URL?
    let localName: String?
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 18 * scale) {
            let size = 64 * scale
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).fill(Color.white.opacity(0.07))
                if let icon {
                    ArtworkImage(url: icon, maxPixels: 400)
                } else if let remote = game.iconUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: remote) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { placeholder(size) }
                } else {
                    placeholder(size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(localName ?? game.name(in: T.language.rawValue))
                    .font(.display(18 * scale, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if game.both {
                    Label(TL.text(.compareBothPlay), systemImage: "person.2.fill")
                        .font(.display(13 * scale, .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12 * scale)
            CompareSideCell(side: game.mine, color: model.accent)
            CompareSideCell(side: game.theirs, color: .white.opacity(0.85))
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 12 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 16 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    private func placeholder(_ size: CGFloat) -> some View {
        Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.34)).foregroundStyle(.white.opacity(0.4))
    }
}

/// One side of a compared game: earned of total, the percentage and a bar; "Not played" without.
struct CompareSideCell: View {
    let side: TogetherCompareSide?
    let color: Color
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            if let side {
                HStack(spacing: 8 * scale) {
                    Image(systemName: "trophy.fill").foregroundStyle(TrophySet.Grade.gold.color.opacity(side.earned > 0 ? 1 : 0.45))
                    Text(side.total.map { "\(side.earned)/\($0)" } ?? "\(side.earned)").monospacedDigit().foregroundStyle(.white)
                    if let progress = side.progress {
                        Text("\(progress)%").monospacedDigit().foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    Text(TL.format(.levelPoints, LevelCard.number(side.points))).monospacedDigit().foregroundStyle(.white.opacity(0.45))
                        .font(.display(12 * scale, .medium))
                }
                .font(.display(14 * scale, .semibold))
                ProgressLine(fraction: Double(side.progress ?? 0) / 100, color: color, height: 4 * scale)
            } else {
                Label(TL.text(.compareNotPlayed), systemImage: "minus.circle")
                    .font(.display(14 * scale, .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: CompareSides.width * scale, alignment: .leading)
    }
}

/// A trophy side by side: its grade, name and rarity, then when each earned it.
struct CompareTrophyRow: View {
    let trophy: TogetherCompareView.Trophy
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let grade = TrophySet.Grade(name: trophy.grade)
        let language = T.language.rawValue
        HStack(spacing: 16 * scale) {
            Image(systemName: trophy.name(in: language) == nil ? "lock.fill" : "trophy.fill")
                .font(.system(size: 20 * scale, weight: .semibold))
                .foregroundStyle(grade.color)
                .frame(width: 48 * scale, height: 48 * scale)
                .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(grade.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text(trophy.name(in: language) ?? T.text(.trophyHidden))
                    .font(.display(16 * scale, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8 * scale) {
                    if let label = trophy.rarityLabel {
                        Text(ProfileTrophyRow.rarityName(label) + (trophy.rarity.map { " · " + ProfileTrophyRow.percent($0) } ?? ""))
                            .foregroundStyle(ProfileTrophyRow.rarityColor(label))
                    }
                    if let detail = trophy.detail(in: language) {
                        Text(detail).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .font(.display(13 * scale))
                .lineLimit(1)
            }
            Spacer(minLength: 12 * scale)
            earned(trophy.mine, color: model.accent)
            earned(trophy.theirs, color: .white.opacity(0.85))
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 10 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 14 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    private func earned(_ date: Date?, color: Color) -> some View {
        HStack(spacing: 10 * scale) {
            if let date {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18 * scale, weight: .semibold)).foregroundStyle(color)
                Text(ProfileView.day(date)).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.85))
            } else {
                Image(systemName: "circle.dashed").font(.system(size: 18 * scale)).foregroundStyle(.white.opacity(0.3))
                Text(TL.text(.compareNotYet)).font(.display(14 * scale)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .lineLimit(1)
        .frame(width: CompareSides.width * scale, alignment: .leading)
    }
}
