import AnyPS5Core
import AppKit
import SwiftUI

/// Friends' activity on AnyTogether: trophies, platinums, first plays, long sessions, new friends
/// and milestones, newest first, with the four reactions. The socket's `feed.item` events replace
/// items by ID while it is open; games this Mac has show their own names and icons.
extension AppModel {
    /// How close to the end of the list the next, older page is read.
    static let feedPrefetch = 4

    func openFeed() {
        guard togetherUser != nil else { return }
        social.follow(togetherUser?.id)
        if let overlay, overlay != .feed, overlay != .profile {
            social.feedReturn = ProfileReturn(overlay: overlay, category: panelCategory, row: panelRow, inRows: panelInRows)
        }
        social.feedIndex = 0
        social.feedReaction = social.feed.items.first?.reactions.mine.flatMap { TogetherReaction.allCases.firstIndex(of: $0) } ?? 0
        withAnimation(Motion.overlay) { overlay = .feed }
        Sounds.shared.play(.select)
        loadFeed()
    }

    func loadFeed() {
        social.feedTask?.cancel()
        social.feedOlderTask?.cancel()
        social.feedTask = Task {
            do {
                let page = try await together.feed()
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.feed.load(page)
                    social.feedFailed = false
                    social.feedIndex = min(social.feedIndex, max(0, social.feed.items.count - 1))
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { social.feedFailed = !social.feed.loaded }
            }
        }
    }

    /// The next, older page, once the focus nears the end.
    func loadOlderFeed() {
        guard let before = social.feed.next, social.feedOlderTask == nil else { return }
        social.feedOlderTask = Task {
            defer { social.feedOlderTask = nil }
            guard let page = try? await together.feed(before: before), !Task.isCancelled else { return }
            withAnimation(Motion.overlay) { social.feed.loadOlder(page) }
        }
    }

    func closeFeed() {
        social.feedTask?.cancel()
        guard let back = social.feedReturn else { return closeOverlay() }
        social.feedReturn = nil
        withAnimation(Motion.overlay) {
            overlay = back.overlay
            panelCategory = back.category
            panelRow = back.row
            panelInRows = back.inRows
        }
        Sounds.shared.play(.back)
    }

    /// Up and down through the items, left and right through the reactions, select reacts, △ opens
    /// the person's profile.
    func feedCommand(_ command: Command) {
        let items = social.feed.items
        switch command {
        case .up, .down:
            let next = min(items.count - 1, max(0, social.feedIndex + (command == .down ? 1 : -1)))
            guard !items.isEmpty, next != social.feedIndex else { return }
            social.feedIndex = next
            if let mine = items[next].reactions.mine, let index = TogetherReaction.allCases.firstIndex(of: mine) { social.feedReaction = index }
            if next >= items.count - Self.feedPrefetch { loadOlderFeed() }
            Sounds.shared.play(.move)
        case .left, .right:
            let next = min(TogetherReaction.allCases.count - 1, max(0, social.feedReaction + (command == .right ? 1 : -1)))
            guard !items.isEmpty, next != social.feedReaction else { return }
            withAnimation(Motion.focus) { social.feedReaction = next }
            Sounds.shared.play(.move)
        case .select:
            guard items.indices.contains(social.feedIndex) else { return }
            react(to: items[social.feedIndex], with: TogetherReaction.allCases[social.feedReaction])
        case .options:
            guard items.indices.contains(social.feedIndex) else { return }
            openProfile(items[social.feedIndex].actor.handle, card: items[social.feedIndex].actor)
        case .back:
            closeFeed()
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    /// Shows the reaction at once, then what the server says; a failure puts the old ones back.
    func react(to item: TogetherActivity, with reaction: TogetherReaction) {
        let before = item.reactions
        let chosen = before.choosing(reaction)
        withAnimation(Motion.focus) { setReactions(chosen, for: item.id) }
        Sounds.shared.play(.select)
        Task {
            do {
                let now = try await together.react(to: item.id, with: chosen.mine)
                withAnimation(Motion.focus) { setReactions(now, for: item.id) }
            } catch {
                withAnimation(Motion.focus) { setReactions(before, for: item.id) }
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func setReactions(_ reactions: TogetherActivity.Reactions, for id: String) {
        social.feed.setReactions(reactions, for: id)
        if let index = social.profileActivity?.firstIndex(where: { $0.id == id }) { social.profileActivity?[index].reactions = reactions }
    }

    /// A socket event the other panels leave: activity, and what comes later.
    func socialEvent(_ event: TogetherSocket.Event) {
        if let notification = TogetherNotificationEvent(event) { return notificationEvent(notification) }
        if let item = TogetherActivity.from(event) {
            // Only into a feed already read: the first read brings it anyway.
            guard social.feed.loaded else { return }
            let focused = social.feed.items.indices.contains(social.feedIndex) ? social.feed.items[social.feedIndex].id : nil
            withAnimation(Motion.overlay) {
                social.feed.upsert(item)
                // The focus stays on the item it was on when a new one comes in above it.
                if let focused, let index = social.feed.index(of: focused) { social.feedIndex = index }
            }
            if let index = social.profileActivity?.firstIndex(where: { $0.id == item.id }) { social.profileActivity?[index] = item }
        }
    }

    // MARK: Profile

    /// The profile's recent activity, read with it.
    func loadProfileActivity(_ handle: String) {
        social.profileActivity = nil
        social.profileActivityFailed = false
        social.profileActivityTask?.cancel()
        social.profileActivityTask = Task {
            do {
                let page = try await together.activity(of: handle, limit: 20)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { social.profileActivity = page.items }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { social.profileActivityFailed = true }
            }
        }
    }

    // MARK: Texts

    /// A game's name: this Mac's own copy's when it has it.
    func gameName(_ game: TogetherActivity.Game) -> String {
        games.first { $0.titleID == game.titleId }?.name ?? game.name(in: T.language.rawValue)
    }

    /// What someone did, after their name: "earned 4 trophies in Stray".
    func activityText(_ item: TogetherActivity) -> String {
        let game = item.game.map(gameName) ?? item.game?.titleId ?? ""
        switch item.kind {
        case .trophy:
            let count = item.trophyCount ?? item.trophies?.count ?? 1
            return count == 1 ? TS.format(.feedTrophy, game) : TS.format(.feedTrophies, game, count)
        case .platinum: return TS.format(.feedPlatinum, game)
        case .firstPlay: return TS.format(.feedFirstPlay, game)
        case .longSession: return TS.format(.feedLongSession, game, ProfileView.playTime(item.seconds ?? 0))
        case .friendship: return TS.format(.feedFriendship, item.friend?.displayName ?? "")
        case .milestone:
            let value = item.milestone?.value ?? 0
            switch item.milestone?.kind {
            case "platinums": return TS.format(.feedMilestonePlatinums, value)
            case "games": return TS.format(.feedMilestoneGames, value)
            case "hours": return TS.format(.feedMilestoneHours, value)
            default: return TS.format(.feedMilestoneTrophies, value)
            }
        case .other: return TS.text(.feedOther)
        }
    }

    func previewFeed(_ items: [TogetherActivity], index: Int = 0, reaction: Int = 0) {
        social.feed.load(TogetherFeedPage(items: items, next: nil))
        social.feedIndex = index
        social.feedReaction = reaction
        overlay = .feed
    }
}

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let social = model.social
        VStack(alignment: .leading, spacing: 30 * scale) {
            header
            if social.feed.loaded && !social.feed.items.isEmpty {
                ProfileColumn(title: "", count: nil, focusedIndex: social.feedIndex, ids: social.feed.items.map(\.id)) {
                    ForEach(Array(social.feed.items.enumerated()), id: \.element.id) { index, item in
                        let focused = social.feedIndex == index
                        ActivityRow(item: item, focused: focused, reactionFocus: focused ? social.feedReaction : nil)
                            .id(item.id)
                            .onTapGesture { model.social.feedIndex = index }
                    }
                    if social.feed.next != nil {
                        Text(TS.text(.feedMore)).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.4)).padding(.vertical, 12 * scale)
                    }
                }
            } else {
                VStack(spacing: 18 * scale) {
                    if social.feed.loaded {
                        ProfileNotice(symbol: "sparkles", text: TS.text(.feedEmpty)).frame(maxWidth: 760 * scale)
                    } else if social.feedFailed {
                        ProfileNotice(symbol: "wifi.exclamationmark", text: TS.text(.feedFailed)).frame(maxWidth: 560 * scale)
                    } else {
                        IndeterminateLine(color: model.accent).frame(width: 260 * scale)
                        Text(TS.text(.feedLoading)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 1180 * scale)
        .padding(.horizontal, 80 * scale)
        .padding(.vertical, 56 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .screenFrost(0.74)
        .environment(\.locale, T.locale)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24 * scale) {
            Image(systemName: "sparkles")
                .font(.system(size: 30 * scale, weight: .semibold))
                .foregroundStyle(model.accent)
                .frame(width: 72 * scale, height: 72 * scale)
                .background(Circle().fill(model.accent.opacity(0.16)))
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text(TS.text(.feedTitle)).font(.display(40 * scale, .light)).foregroundStyle(.white)
                Text(TS.text(.feedSubtitle)).font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            HStack(spacing: 22 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                Hint(keys: "← → ↩ / ✕", label: TS.text(.hintReact))
                Hint(keys: "O / △", label: TS.text(.hintProfile))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
    }
}

/// One activity item: the game's icon (or the new friend, or the milestone) with the person's
/// avatar on its corner, what they did, the best trophies, and the reactions.
struct ActivityRow: View {
    let item: TogetherActivity
    let focused: Bool
    /// The focused reaction, on the focused item of the feed.
    var reactionFocus: Int?
    /// Narrower, in a profile's column: no avatar badge, the reactions as a line.
    var compact = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(alignment: .center, spacing: (compact ? 14 : 20) * scale) {
            picture
            VStack(alignment: .leading, spacing: (compact ? 5 : 8) * scale) {
                (Text(item.actor.displayName).font(.display((compact ? 15 : 18) * scale, .semibold)).foregroundColor(.white)
                    + Text(" " + model.activityText(item)).font(.display((compact ? 15 : 18) * scale)).foregroundColor(.white.opacity(0.82)))
                    .lineLimit(compact ? 2 : 1)
                if !compact, let trophies = item.trophies, !trophies.isEmpty { trophyLine(trophies) }
                HStack(spacing: 8 * scale) {
                    Text(ProfileView.relative(item.createdAt))
                    if item.highlight == "rare" {
                        Text("·")
                        Text(TS.text(.feedRare)).foregroundStyle(ProfileTrophyRow.rarityColor("very_rare"))
                    }
                    if compact, item.reactions.total > 0 {
                        Text("·")
                        Text(TogetherReaction.allCases.compactMap { reaction in item.reactions.counts[reaction].map { "\(reaction.emoji) \($0)" } }.joined(separator: "  "))
                    }
                }
                .font(.display((compact ? 12 : 13) * scale, .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            }
            Spacer(minLength: 8 * scale)
            if !compact { reactions }
        }
        .padding(.horizontal, (compact ? 14 : 18) * scale)
        .padding(.vertical, (compact ? 11 : 15) * scale)
        .background(
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.13 : 0.05))
                .overlay(alignment: .leading) {
                    // A platinum glows along its edge.
                    if item.highlight == "platinum" {
                        LinearGradient(colors: [TrophySet.Grade.platinum.color.opacity(0.32), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 220 * scale)
                            .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                    }
                }
        )
        .focusRing(focused, radius: 18 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    // MARK: Picture

    private var picture: some View {
        let size = (compact ? 52 : 72) * scale
        return ZStack(alignment: .bottomTrailing) {
            Group {
                switch item.kind {
                case .friendship:
                    ProfileAvatar(url: item.friend?.avatar, name: item.friend?.displayName ?? "?", size: size, glow: false)
                case .milestone:
                    symbol(milestoneSymbol, size: size, color: model.accent)
                default:
                    if let game = item.game {
                        gameIcon(game, size: size)
                    } else {
                        symbol("sparkles", size: size, color: model.accent)
                    }
                }
            }
            .frame(width: size, height: size)
            if !compact {
                ProfileAvatar(url: item.actor.avatar, name: item.actor.displayName, size: size * 0.44, glow: false)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 2))
                    .offset(x: size * 0.12, y: size * 0.12)
            }
        }
        .padding(.trailing, compact ? 0 : size * 0.1)
    }

    private var milestoneSymbol: String {
        switch item.milestone?.kind {
        case "platinums": return "trophy.circle.fill"
        case "games": return "gamecontroller.fill"
        case "hours": return "clock.fill"
        default: return "trophy.fill"
        }
    }

    private func gameIcon(_ game: TogetherActivity.Game, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(Color.white.opacity(0.07))
            if let icon = model.localIcon(game.titleId) {
                ArtworkImage(url: icon, maxPixels: 400)
            } else if let remote = game.iconUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: remote) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
            } else {
                Image(systemName: item.kind == .platinum ? "trophy.fill" : "gamecontroller.fill")
                    .font(.system(size: size * 0.34))
                    .foregroundStyle(item.kind == .platinum ? TrophySet.Grade.platinum.color : .white.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private func symbol(_ name: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(color.opacity(0.16)))
    }

    // MARK: Trophies and reactions

    private func trophyLine(_ trophies: [TogetherActivity.Trophy]) -> some View {
        let shown = Array(trophies.prefix(3))
        let rest = max(0, (item.trophyCount ?? trophies.count) - shown.count)
        return HStack(spacing: 10 * scale) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, trophy in
                let grade = TrophySet.Grade(name: trophy.grade)
                HStack(spacing: 6 * scale) {
                    Image(systemName: "trophy.fill").foregroundStyle(grade.color)
                    Text(trophy.name(in: T.language.rawValue) ?? T.text(.trophyHidden)).lineLimit(1)
                    if let label = trophy.rarityLabel, let rarity = trophy.rarity, label != "common" {
                        Text(ProfileTrophyRow.percent(rarity)).monospacedDigit().foregroundStyle(ProfileTrophyRow.rarityColor(label))
                    }
                }
                .font(.display(13 * scale, .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 5 * scale)
                .background(Capsule().fill(grade.color.opacity(0.12)))
            }
            if rest > 0 {
                Text(TS.format(.feedAndMore, rest)).font(.display(13 * scale, .medium)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// All four on the focused item; elsewhere only the ones someone chose.
    private var reactions: some View {
        HStack(spacing: 8 * scale) {
            ForEach(Array(TogetherReaction.allCases.enumerated()), id: \.element) { index, reaction in
                let count = item.reactions.counts[reaction] ?? 0
                let mine = item.reactions.mine == reaction
                if focused || count > 0 {
                    HStack(spacing: 5 * scale) {
                        Text(reaction.emoji).font(.system(size: 17 * scale))
                        if count > 0 {
                            Text("\(count)").font(.display(14 * scale, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(mine ? 1 : 0.75))
                        }
                    }
                    .padding(.horizontal, 11 * scale)
                    .frame(height: 36 * scale)
                    .background(Capsule().fill(mine ? model.accent.opacity(0.45) : Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(reactionFocus == index ? 0.95 : 0), lineWidth: 2))
                    .scaleEffect(reactionFocus == index ? 1.08 : 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .onTapGesture { model.react(to: item, with: reaction) }
                }
            }
        }
        .animation(Motion.focus, value: focused)
        .animation(Motion.focus, value: reactionFocus)
    }
}

/// The recent activity column of a profile.
struct ProfileActivityColumn: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let items = model.social.profileActivity ?? []
        ProfileColumn(title: TS.text(.profileActivity), count: nil, focusedIndex: model.profileColumn == 2 ? model.profileIndex : nil, ids: items.map(\.id)) {
            if let list = model.social.profileActivity {
                if list.isEmpty {
                    ProfileNotice(symbol: "sparkles", text: TS.text(.profileNoActivity))
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        ActivityRow(item: item, focused: model.profileColumn == 2 && model.profileIndex == index, compact: true)
                            .id(item.id)
                            .onTapGesture { model.profileColumn = 2; model.profileIndex = index }
                    }
                }
            } else if model.social.profileActivityFailed {
                ProfileNotice(symbol: "wifi.exclamationmark", text: TS.text(.feedFailed))
            } else {
                IndeterminateLine(color: model.accent).frame(width: 160 * scale).padding(.vertical, 20 * scale)
            }
        }
    }
}
