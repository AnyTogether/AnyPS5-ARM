import AnyPS5Core
import AppKit
import SwiftUI

/// Leaderboards on AnyTogether: a game's by points, play time or completion (from its options or
/// its trophy list), or overall trophy points (from the Friends panel); among friends or everyone,
/// with the user's own place.
extension AppModel {
    /// Opens a game's board (from this Mac's game), or overall points with nil.
    func openLeaderboard(_ game: Game?) {
        guard togetherUser != nil else { return }
        social.follow(togetherUser?.id)
        if let overlay, overlay != .leaderboard, overlay != .profile {
            social.boardReturn = ProfileReturn(overlay: overlay, category: panelCategory, row: panelRow, inRows: panelInRows)
        }
        let changed = social.boardGame?.titleId != game?.titleID
        social.boardGame = game.map { TogetherActivity.Game(titleId: $0.titleID, names: [T.language.rawValue: $0.name]) }
        if changed {
            social.boardKind = .points
            social.leaderboard = nil
        }
        social.boardIndex = 0
        withAnimation(Motion.overlay) { overlay = .leaderboard }
        Sounds.shared.play(.select)
        loadLeaderboard()
    }

    func loadLeaderboard() {
        let game = social.boardGame, kind = social.boardKind, scope = social.boardScope
        social.boardTask?.cancel()
        social.boardFailed = false
        social.boardMissing = false
        social.boardTask = Task {
            do {
                let board: TogetherLeaderboard
                if let game {
                    board = try await together.gameLeaderboard(game.titleId, by: kind, scope: scope)
                } else {
                    board = try await together.pointsLeaderboard(scope: scope)
                }
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.leaderboard = board
                    // Opens on the user's own line.
                    let lines = board.lines(me: togetherUser?.id ?? "")
                    social.boardIndex = lines.firstIndex { if case .entry(_, true) = $0 { return true } else { return false } } ?? 0
                }
            } catch let problem as TogetherProblem where problem.status == 404 {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.leaderboard = nil
                    social.boardMissing = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.leaderboard = nil
                    social.boardFailed = true
                }
            }
        }
    }

    func closeLeaderboard() {
        social.boardTask?.cancel()
        guard let back = social.boardReturn else { return closeOverlay() }
        social.boardReturn = nil
        withAnimation(Motion.overlay) {
            overlay = back.overlay
            panelCategory = back.category
            panelRow = back.row
            panelInRows = back.inRows
        }
        Sounds.shared.play(.back)
    }

    var boardLines: [TogetherLeaderboard.Line] { social.leaderboard?.lines(me: togetherUser?.id ?? "") ?? [] }

    /// Up and down through the people, left and right through a game's boards, △ between friends
    /// and everyone, select opens someone's profile.
    func leaderboardCommand(_ command: Command) {
        let lines = boardLines
        switch command {
        case .up, .down:
            let way = command == .down ? 1 : -1
            // The gap is passed over.
            guard let next = stride(from: social.boardIndex + way, to: way > 0 ? lines.count : -1, by: way).first(where: { lines[$0] != .gap }) else { return }
            social.boardIndex = next
            Sounds.shared.play(.move)
        case .left, .right:
            guard social.boardGame != nil else { return }
            let all = TogetherGameBoard.allCases
            let index = (all.firstIndex(of: social.boardKind) ?? 0) + (command == .right ? 1 : -1)
            guard all.indices.contains(index) else { return }
            withAnimation(Motion.focus) { social.boardKind = all[index] }
            Sounds.shared.play(.move)
            loadLeaderboard()
        case .options:
            withAnimation(Motion.focus) { social.boardScope = social.boardScope == .friends ? .global : .friends }
            Sounds.shared.play(.move)
            loadLeaderboard()
        case .select:
            guard lines.indices.contains(social.boardIndex), case .entry(let entry, _) = lines[social.boardIndex] else { return }
            openProfile(entry.user.handle, card: entry.user)
        case .back:
            closeLeaderboard()
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    /// A board's value as it reads: "1,830 pts", "12 h 30 min", "64%".
    static func boardValue(_ value: Int, board: String) -> String {
        switch board {
        case "time": return ProfileView.playTime(value)
        case "completion": return "\(value)%"
        default:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = T.locale
            return TS.format(.boardPointsValue, formatter.string(from: NSNumber(value: value)) ?? "\(value)")
        }
    }

    func previewLeaderboard(_ board: TogetherLeaderboard?, game: Game?, kind: TogetherGameBoard = .points, missing: Bool = false, index: Int = 0) {
        social.boardGame = game.map { TogetherActivity.Game(titleId: $0.titleID, names: ["en": $0.name]) }
        social.boardKind = kind
        social.boardScope = board?.scope ?? .friends
        social.leaderboard = board
        social.boardMissing = missing
        social.boardIndex = index
        overlay = .leaderboard
    }
}

struct LeaderboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let social = model.social
        VStack(alignment: .leading, spacing: 28 * scale) {
            header
            HStack(alignment: .top, spacing: 36 * scale) {
                VStack(alignment: .leading, spacing: 18 * scale) {
                    tabs
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if let board = social.leaderboard { rankCard(board).frame(width: 330 * scale) }
            }
        }
        .padding(.horizontal, 80 * scale)
        .padding(.vertical, 56 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenFrost(0.74)
        .environment(\.locale, T.locale)
    }

    // MARK: Header

    private var header: some View {
        let game = model.social.boardGame
        return HStack(alignment: .center, spacing: 26 * scale) {
            let size = 104 * scale
            Group {
                if let game, let icon = model.localIcon(game.titleId) {
                    ArtworkImage(url: icon, maxPixels: 400)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                } else {
                    Image(systemName: game == nil ? "star.fill" : "list.number")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(model.accent)
                        .frame(width: size, height: size)
                        .background(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(model.accent.opacity(0.16)))
                }
            }
            .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(TS.text(.boardTitle))
                    .font(.display(13 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(game.map(model.gameName) ?? TS.text(.boardOverall))
                    .font(.display(38 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                if game != nil { Hint(keys: "← →", label: TS.text(.hintBoard)) }
                Hint(keys: "O / △", label: TS.text(.hintScope))
                Hint(keys: "↩ / ✕", label: TS.text(.hintProfile))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
    }

    /// The game's three boards, and friends or everyone.
    private var tabs: some View {
        let social = model.social
        return HStack(spacing: 10 * scale) {
            if social.boardGame != nil {
                ForEach(TogetherGameBoard.allCases, id: \.self) { kind in
                    pill(Self.title(kind), symbol: Self.symbol(kind), on: social.boardKind == kind)
                        .onTapGesture {
                            model.social.boardKind = kind
                            model.loadLeaderboard()
                        }
                }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 26 * scale).padding(.horizontal, 8 * scale)
            }
            ForEach(TogetherBoardScope.allCases, id: \.self) { scope in
                pill(TS.text(scope == .friends ? .scopeFriends : .scopeGlobal), symbol: scope == .friends ? "person.2.fill" : "globe", on: social.boardScope == scope, quiet: true)
                    .onTapGesture {
                        model.social.boardScope = scope
                        model.loadLeaderboard()
                    }
            }
            Spacer(minLength: 0)
            if let board = social.leaderboard, board.total > 0 {
                Text(TS.format(.boardPlayers, board.total)).font(.display(14 * scale, .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func pill(_ title: String, symbol: String, on: Bool, quiet: Bool = false) -> some View {
        Label(title, systemImage: symbol)
            .font(.display(15 * scale, .semibold))
            .foregroundStyle(.white.opacity(on ? 1 : 0.6))
            .padding(.horizontal, 16 * scale)
            .frame(height: 38 * scale)
            .background(Capsule().fill(on ? (quiet ? Color.white.opacity(0.18) : model.accent.opacity(0.5)) : Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.25 : 0.08), lineWidth: 1))
            .animation(Motion.focus, value: on)
    }

    static func title(_ kind: TogetherGameBoard) -> String {
        switch kind {
        case .points: return TS.text(.boardPoints)
        case .time: return TS.text(.boardTime)
        case .completion: return TS.text(.boardCompletion)
        }
    }

    static func symbol(_ kind: TogetherGameBoard) -> String {
        switch kind {
        case .points: return "star.fill"
        case .time: return "clock.fill"
        case .completion: return "chart.pie.fill"
        }
    }

    // MARK: Lines

    @ViewBuilder private var content: some View {
        let social = model.social
        if let board = social.leaderboard {
            let lines = model.boardLines
            if lines.isEmpty {
                ProfileNotice(symbol: "list.number", text: TS.text(.boardEmpty))
            } else {
                ProfileColumn(title: "", count: nil, focusedIndex: social.boardIndex, ids: lines.indices.map { "line-\($0)" }) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lineView(line, board: board, focused: index == social.boardIndex)
                            .id("line-\(index)")
                            .onTapGesture { model.social.boardIndex = index }
                    }
                }
            }
        } else if social.boardMissing {
            ProfileNotice(symbol: "gamecontroller", text: TS.text(.boardNoGame))
        } else if social.boardFailed {
            ProfileNotice(symbol: "wifi.exclamationmark", text: TS.text(.boardFailed))
        } else {
            VStack(spacing: 18 * scale) {
                IndeterminateLine(color: model.accent).frame(width: 260 * scale)
                Text(TS.text(.boardLoading)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80 * scale)
        }
    }

    @ViewBuilder private func lineView(_ line: TogetherLeaderboard.Line, board: TogetherLeaderboard, focused: Bool) -> some View {
        switch line {
        case .entry(let entry, let me):
            LeaderboardRow(entry: entry, me: me, board: board.board, focused: focused)
        case .gap:
            Image(systemName: "ellipsis")
                .font(.system(size: 18 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 26 * scale)
        case .unlisted(let rank, _):
            ProfileNotice(symbol: "eye.slash", text: board.scope == .global && rank != nil
                ? TS.text(.boardUnlisted) + " · " + TS.format(.boardWouldBe, rank ?? 0)
                : TS.text(.boardNothing))
                .focusRing(focused, radius: 16 * scale, width: 2)
        }
    }

    // MARK: Your rank

    /// "now", "2 minutes ago": boards are kept for half a minute to a minute.
    static func updated(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = T.locale
        formatter.dateTimeStyle = .named
        let now = Date()
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    private func rankCard(_ board: TogetherLeaderboard) -> some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            Text(TS.text(.boardYourRank))
                .font(.display(13 * scale, .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                Text(board.me.rank.map { "#\($0)" } ?? "—")
                    .font(.display(64 * scale, .light))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if board.me.listed, board.total > 0 {
                    Text(TS.format(.boardOf, board.total)).font(.display(17 * scale, .medium)).foregroundStyle(.white.opacity(0.55))
                }
            }
            Text(AppModel.boardValue(board.me.value, board: board.board))
                .font(.display(20 * scale, .semibold))
                .monospacedDigit()
                .foregroundStyle(model.accent)
            if !board.me.listed {
                Label(TS.text(board.scope == .global && board.me.rank != nil ? .boardUnlisted : .boardNothing), systemImage: "eye.slash")
                    .font(.display(13 * scale))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Self.updated(board.updatedAt))
                .font(.display(12 * scale, .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(24 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(22 * scale, opacity: 0.3)
    }
}

/// One person on a board: their place (gold, silver and bronze for the first three), avatar,
/// name and value; the user's own line in the accent.
struct LeaderboardRow: View {
    let entry: TogetherLeaderboard.Entry
    let me: Bool
    let board: String
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 18 * scale) {
            Text("\(entry.rank)")
                .font(.display(22 * scale, .semibold))
                .monospacedDigit()
                .foregroundStyle(medal ?? .white.opacity(0.7))
                .frame(width: 56 * scale)
            ProfileAvatar(url: entry.user.avatar, name: entry.user.displayName, size: 44 * scale, glow: false)
                .overlay(Circle().strokeBorder(medal ?? .clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3 * scale) {
                HStack(spacing: 8 * scale) {
                    Text(entry.user.displayName).font(.display(17 * scale, .semibold)).foregroundStyle(.white).lineLimit(1)
                    if me {
                        Text(TS.text(.boardYou))
                            .font(.display(11 * scale, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8 * scale)
                            .padding(.vertical, 2 * scale)
                            .background(Capsule().fill(model.accent.opacity(0.6)))
                    }
                }
                Text("@\(entry.user.handle)").font(.display(13 * scale)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 12 * scale)
            Text(AppModel.boardValue(entry.value, board: board))
                .font(.display(18 * scale, .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(me ? model.accent.opacity(focused ? 0.32 : 0.2) : Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 16 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    private var medal: Color? {
        switch entry.rank {
        case 1: return TrophySet.Grade.gold.color
        case 2: return TrophySet.Grade.silver.color
        case 3: return TrophySet.Grade.bronze.color
        default: return nil
        }
    }
}

/// On a game's trophy list: the way to its leaderboard.
struct LeaderboardChip: View {
    let game: Game
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: "list.number").foregroundStyle(model.accent)
            Text(TS.text(.boardTitle)).foregroundStyle(.white)
            Text("↩ / ✕")
                .font(.display(12 * scale, .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 3 * scale)
                .background(RoundedRectangle(cornerRadius: 5 * scale).fill(Color.white.opacity(0.12)))
        }
        .font(.display(15 * scale, .semibold))
        .padding(.horizontal, 16 * scale)
        .frame(height: 40 * scale)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .onTapGesture { model.openLeaderboard(game) }
    }
}
