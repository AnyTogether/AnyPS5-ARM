import AnyPS5Core
import AppKit
import SwiftUI

/// Challenges on AnyTogether (made on the website): a strip of them over the leaderboard (the
/// game's, or the user's own over overall points), and a challenge's page with its window, its
/// standings, and Join or Leave. A server from before challenges shows none, without a word.
extension AppModel {
    // MARK: The strip

    /// The challenges over the board on screen.
    func loadChallenges() {
        let titleId = social.boardGame?.titleId
        social.challengesTask?.cancel()
        social.challengesTask = Task {
            // Not there (an older server, 404) or not reachable: no strip, and no error box.
            let list = (try? await together.challengeStrip(titleId: titleId)) ?? []
            guard !Task.isCancelled, social.boardGame?.titleId == titleId else { return }
            withAnimation(Motion.overlay) {
                social.challenges = list
                social.challengeStripIndex = min(social.challengeStripIndex, max(0, list.count - 1))
                if list.isEmpty { social.boardOnChallenges = false }
            }
        }
    }

    /// A challenge the server answered again (joined, left): the strip shows it so too.
    func keepChallenge(_ challenge: TogetherChallenge) {
        if let index = social.challenges.firstIndex(where: { $0.id == challenge.id }) { social.challenges[index] = challenge }
        if social.challengeShown?.id == challenge.id { social.challengeShown = challenge }
        if social.challengeDetail?.challenge.id == challenge.id { social.challengeDetail = social.challengeDetail?.with(challenge) }
    }

    /// ← → through the strip, ↓ back to the board, select opens one; the rest as on the board.
    /// Returns false for a command the board handles.
    func challengeStripCommand(_ command: Command) -> Bool {
        let list = social.challenges
        guard social.boardOnChallenges, !list.isEmpty else { return false }
        switch command {
        case .left, .right:
            let next = social.challengeStripIndex + (command == .right ? 1 : -1)
            guard list.indices.contains(next) else { return true }
            withAnimation(Motion.focus) { social.challengeStripIndex = next }
            Sounds.shared.play(.move)
        case .down:
            withAnimation(Motion.focus) { social.boardOnChallenges = false }
            Sounds.shared.play(.move)
        case .up:
            break
        case .select:
            let challenge = list[min(social.challengeStripIndex, list.count - 1)]
            openChallenge(challenge.id, shown: challenge)
        default:
            return false
        }
        return true
    }

    // MARK: A challenge's page

    /// Opens a challenge's page. Over the leaderboard it goes back to the board; from anywhere
    /// else (a notification) back to where it was opened.
    func openChallenge(_ id: String, shown: TogetherChallenge? = nil) {
        guard togetherUser != nil else { return }
        social.follow(togetherUser?.id)
        if overlay == .leaderboard {
            social.challengeAlone = false
        } else {
            social.challengeAlone = true
            social.boardReturn = overlay.flatMap { $0 == .profile ? nil : ProfileReturn(overlay: $0, category: panelCategory, row: panelRow, inRows: panelInRows) }
        }
        social.challengeId = id
        social.challengeShown = shown
        social.challengeDetail = nil
        social.challengeFailed = false
        social.challengeGone = false
        social.challengeIndex = 0
        social.challengeColumn = 0
        social.challengeButton = 0
        withAnimation(Motion.overlay) { overlay = .leaderboard }
        Sounds.shared.play(.select)
        loadChallenge()
    }

    func loadChallenge() {
        guard let id = social.challengeId else { return }
        social.challengeTask?.cancel()
        social.challengeTask = Task {
            do {
                let detail = try await together.challenge(id)
                guard !Task.isCancelled, social.challengeId == id else { return }
                let first = social.challengeDetail == nil
                withAnimation(Motion.overlay) {
                    social.challengeDetail = detail
                    social.challengeShown = detail.challenge
                    social.challengeFailed = false
                    keepChallenge(detail.challenge)
                    // Opens on the user's own line.
                    if first { social.challengeIndex = detail.lines.firstIndex { if case .standing(let standing) = $0 { return standing.me } else { return false } } ?? 0 }
                }
            } catch let problem as TogetherProblem where problem.status == 404 {
                guard !Task.isCancelled, social.challengeId == id else { return }
                withAnimation(Motion.overlay) { social.challengeGone = true }
            } catch {
                guard !Task.isCancelled, social.challengeId == id else { return }
                withAnimation(Motion.overlay) { social.challengeFailed = social.challengeDetail == nil }
            }
        }
    }

    func closeChallenge() {
        social.challengeTask?.cancel()
        guard !social.challengeAlone else {
            // The page goes with the leaderboard it was shown in.
            closeLeaderboard()
            return
        }
        withAnimation(Motion.overlay) {
            social.challengeId = nil
            social.challengeDetail = nil
            social.challengeShown = nil
        }
        Sounds.shared.play(.back)
    }

    /// What the page's card offers: Join or Leave while it can, and the website.
    enum ChallengeAction: Equatable { case join, leave, website }

    var challengeActions: [ChallengeAction] {
        guard let challenge = social.challengeShown else { return [.website] }
        var actions: [ChallengeAction] = []
        if challenge.isOpen {
            if !challenge.joined { actions.append(.join) } else if !challenge.mine { actions.append(.leave) }
        }
        return actions + [.website]
    }

    func challengeAction(_ action: ChallengeAction) {
        switch action {
        case .join, .leave: toggleChallenge()
        case .website: openChallengeWebsite()
        }
    }

    /// The website's page to make one, in the browser (only when asked).
    func openChallengeWebsite() {
        var parts = URLComponents(url: together.base.appendingPathComponent("challenges"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "new", value: "1")]
        guard let url = parts?.url else { return }
        Sounds.shared.play(.select)
        openLink(url)
    }

    func toggleChallenge() {
        guard let challenge = social.challengeShown, !social.challengeBusy else { return }
        guard challenge.isOpen else { return show(TChal.text(.over), symbol: "flag.checkered") }
        if challenge.joined, challenge.mine { return show(TChal.text(.youMadeIt), symbol: "flag.fill") }
        let leaving = challenge.joined
        social.challengeBusy = true
        Sounds.shared.play(.select)
        Task {
            defer { social.challengeBusy = false }
            do {
                let now = leaving ? try await together.leaveChallenge(challenge.id) : try await together.joinChallenge(challenge.id)
                withAnimation(Motion.overlay) {
                    keepChallenge(now)
                    // Join and Leave swap in place: the focus stays on the button.
                    social.challengeButton = 0
                }
                show(TChal.format(now.joined ? .joined : .left, now.title), symbol: now.joined ? "flag.fill" : "flag.slash")
                loadChallenge()
            } catch let problem as TogetherProblem {
                show(Self.challengeProblem(problem, leaving: leaving, mine: challenge.mine), symbol: "exclamationmark.circle")
                if problem.status == 409 { loadChallenge() }
            } catch {
                show(TChal.text(.actionFailed), symbol: "wifi.exclamationmark")
            }
        }
    }

    static func challengeProblem(_ problem: TogetherProblem, leaving: Bool, mine: Bool) -> String {
        switch problem.code {
        case "full": return TChal.text(.full)
        case "conflict": return TChal.text(leaving && mine ? .youMadeIt : .over)
        case "restricted_by_family": return TChal.text(.family)
        default: return TChal.text(.actionFailed)
        }
    }

    /// ↑ ↓ through the standings (or the card's buttons), → to the card and ← back, △ joins or
    /// leaves, select opens someone's profile or presses the button.
    func challengeCommand(_ command: Command) {
        let lines = social.challengeDetail?.lines ?? []
        let actions = challengeActions
        let inCard = social.challengeColumn == 1
        switch command {
        case .up, .down:
            let way = command == .down ? 1 : -1
            if inCard {
                let next = social.challengeButton + way
                guard actions.indices.contains(next) else { return }
                withAnimation(Motion.focus) { social.challengeButton = next }
            } else {
                guard let next = stride(from: social.challengeIndex + way, to: way > 0 ? lines.count : -1, by: way).first(where: { lines[$0] != .gap }) else { return }
                social.challengeIndex = next
            }
            Sounds.shared.play(.move)
        case .right, .left:
            let card = command == .right
            guard card != inCard else { return }
            withAnimation(Motion.focus) {
                social.challengeColumn = card ? 1 : 0
                social.challengeButton = 0
            }
            Sounds.shared.play(.move)
        case .options:
            toggleChallenge()
        case .select:
            if inCard {
                guard actions.indices.contains(social.challengeButton) else { return }
                challengeAction(actions[social.challengeButton])
            } else if lines.indices.contains(social.challengeIndex), case .standing(let standing) = lines[social.challengeIndex], let user = standing.user {
                openProfile(user.handle, card: user)
            }
        case .back:
            closeChallenge()
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    // MARK: Texts

    static func challengeMetric(_ metric: TogetherChallenge.Metric) -> String {
        switch metric {
        case .points: return TChal.text(.metricPoints)
        case .trophies: return TChal.text(.metricTrophies)
        case .time: return TChal.text(.metricTime)
        case .other: return TChal.text(.metricOther)
        }
    }

    static func challengeSymbol(_ metric: TogetherChallenge.Metric) -> String {
        switch metric {
        case .points: return "star.fill"
        case .trophies: return "trophy.fill"
        case .time: return "clock.fill"
        case .other: return "flag.fill"
        }
    }

    /// A value as it reads: "420 pts", "12 trophies", "12 h 30 min" (as the leaderboards show
    /// play time).
    static func challengeValue(_ value: Int, metric: TogetherChallenge.Metric) -> String {
        switch metric {
        case .points: return boardValue(value, board: "points")
        case .time: return ProfileView.playTime(value)
        case .trophies: return TChal.format(value == 1 ? .trophyValue : .trophiesValue, value)
        case .other: return "\(value)"
        }
    }

    /// "2 days", "36 hours", "5 minutes", in the launcher's language.
    static func spanText(_ span: TogetherChallenge.Span) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = T.locale
        formatter.calendar = calendar
        var parts = DateComponents()
        switch span.unit {
        case .days:
            formatter.allowedUnits = [.day]
            parts.day = span.amount
        case .hours:
            formatter.allowedUnits = [.hour]
            parts.hour = span.amount
        case .minutes:
            formatter.allowedUnits = [.minute]
            parts.minute = span.amount
        }
        return formatter.string(from: parts) ?? "\(span.amount)"
    }

    /// "Ends in 2 days", "Starts in 3 hours", "Ended".
    static func challengeClock(_ clock: TogetherChallenge.Clock) -> String {
        switch clock {
        case .startsIn(let seconds): return TChal.format(.startsIn, spanText(.init(seconds: seconds)))
        case .endsIn(let seconds): return TChal.format(.endsIn, spanText(.init(seconds: seconds)))
        case .finishing: return TChal.text(.finishing)
        case .ended: return TChal.text(.ended)
        case .cancelled: return TChal.text(.cancelled)
        }
    }

    /// "For friends", "For Souls fans", "For everyone".
    static func challengeAudience(_ challenge: TogetherChallenge) -> String? {
        switch challenge.audience {
        case .friends: return TChal.text(.forFriends)
        case .community: return challenge.community.map { TChal.format(.forCommunity, $0.name) }
        case .public: return TChal.text(.forEveryone)
        case .other: return nil
        }
    }

    func challengeGameName(_ game: TogetherChallenge.Game) -> String {
        games.first { $0.titleID == game.titleId }?.name ?? game.name(in: T.language.rawValue)
    }

    // MARK: Previews

    func previewChallenges(_ list: [TogetherChallenge], onStrip: Bool, index: Int = 0) {
        social.challenges = list
        social.boardOnChallenges = onStrip
        social.challengeStripIndex = index
    }

    func previewChallenge(_ shown: TogetherChallenge, detail: TogetherChallengeDetail?, index: Int = 0, card: Bool = false, button: Int = 0, failed: Bool = false) {
        overlay = .leaderboard
        social.challengeId = shown.id
        social.challengeShown = shown
        social.challengeDetail = detail
        social.challengeFailed = failed
        social.challengeIndex = index
        social.challengeColumn = card ? 1 : 0
        social.challengeButton = button
    }
}

extension TogetherChallenge {
    /// Still to join or leave, by the server's state: not over, not called off.
    var isOpen: Bool { state == .upcoming || state == .active }

    /// The winner's side of things: over, and final.
    var decided: Bool { state == .ended && final }
}

// MARK: - The strip

/// The challenges over a board, one card each; hidden when there are none.
struct ChallengeStrip: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        let social = model.social
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 10 * scale) {
                Image(systemName: "flag.2.crossed.fill").foregroundStyle(model.accent)
                Text(TChal.text(.title))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(social.challenges.count)").monospacedDigit().foregroundStyle(.white.opacity(0.35))
            }
            .font(.display(13 * scale, .semibold))
            if previewRender {
                // Room for the focus ring, as the scroll view below leaves it.
                cards.padding(.vertical, 8 * scale).padding(.horizontal, 6 * scale)
                    .frame(maxWidth: .infinity, alignment: .leading).clipped()
                    .padding(.vertical, -8 * scale).padding(.horizontal, -6 * scale)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { cards.padding(.vertical, 8 * scale).padding(.horizontal, 6 * scale) }
                        .padding(.vertical, -8 * scale)
                        .padding(.horizontal, -6 * scale)
                        .onChange(of: social.challengeStripIndex) { _, index in
                            guard social.challenges.indices.contains(index) else { return }
                            withAnimation(Motion.focus) { proxy.scrollTo(social.challenges[index].id, anchor: .center) }
                        }
                }
            }
        }
    }

    private var cards: some View {
        let social = model.social
        return HStack(spacing: 16 * scale) {
            ForEach(Array(social.challenges.enumerated()), id: \.element.id) { index, challenge in
                ChallengeCard(challenge: challenge, focused: social.boardOnChallenges && index == social.challengeStripIndex)
                    .id(challenge.id)
                    .onTapGesture {
                        model.social.boardOnChallenges = true
                        model.social.challengeStripIndex = index
                        model.openChallenge(challenge.id, shown: challenge)
                    }
            }
        }
    }
}

/// One challenge on the strip: what counts, the time left, its title and game, who leads and the
/// user's place.
struct ChallengeCard: View {
    let challenge: TogetherChallenge
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
        VStack(alignment: .leading, spacing: 9 * scale) {
            HStack(spacing: 8 * scale) {
                Image(systemName: AppModel.challengeSymbol(challenge.metric))
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundStyle(model.accent)
                    .frame(width: 24 * scale, height: 24 * scale)
                    .background(Circle().fill(model.accent.opacity(0.18)))
                Text(AppModel.challengeMetric(challenge.metric))
                    .font(.display(12 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 6 * scale)
                ChallengeClockChip(challenge: challenge)
            }
            Text(challenge.title)
                .font(.display(19 * scale, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text([model.challengeGameName(challenge.game), TChal.format(.entrants, challenge.entrants)].joined(separator: " · "))
                .font(.display(13 * scale, .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            HStack(spacing: 8 * scale) {
                if let leader = challenge.leader {
                    Image(systemName: "crown.fill").font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(TrophySet.Grade.gold.color)
                    Text(leader.user?.displayName ?? TChal.text(.hidden)).foregroundStyle(.white.opacity(leader.user == nil ? 0.55 : 0.9)).lineLimit(1)
                    Text(AppModel.challengeValue(leader.value, metric: challenge.metric)).monospacedDigit().foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                } else {
                    Text(TChal.text(.noLeader)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 6 * scale)
                if let place = challenge.myStanding {
                    Text("\(TChal.text(.yourPlace)) #\(place.rank)")
                        .font(.display(12 * scale, .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(Capsule().fill(model.accent.opacity(0.6)))
                } else if challenge.joined {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(model.accent)
                }
            }
            .font(.display(13 * scale, .semibold))
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 16 * scale)
        .frame(width: 360 * scale, alignment: .leading)
        .background(shape.fill(challenge.joined ? model.accent.opacity(focused ? 0.26 : 0.16) : Color.white.opacity(focused ? 0.13 : 0.06)))
        .overlay(shape.strokeBorder(Color.white.opacity(focused ? 0 : 0.09), lineWidth: 1))
        .focusRing(focused, radius: 20 * scale, width: 2)
        .scaleEffect(focused ? 1.02 : 1)
        .animation(Motion.focus, value: focused)
    }
}

/// "Ends in 2 days" in a small capsule: the accent while it runs, quieter before and after.
struct ChallengeClockChip: View {
    let challenge: TogetherChallenge
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let clock = challenge.clock()
        let running: Bool = { if case .endsIn = clock { return true } else { return false } }()
        Label(AppModel.challengeClock(clock), systemImage: running ? "timer" : (challenge.isOpen ? "calendar" : "flag.checkered"))
            .font(.display(12 * scale, .semibold))
            .monospacedDigit()
            .foregroundStyle(running ? Color.white : .white.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 9 * scale)
            .padding(.vertical, 4 * scale)
            .background(Capsule().fill(running ? model.accent.opacity(0.45) : Color.white.opacity(0.1)))
    }
}

// MARK: - The page

/// A challenge's page inside the leaderboard: what it is, its window as a track from start flag
/// to finish flag, the standings, and the card with the user's place, the leader and Join or
/// Leave.
struct ChallengePage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let social = model.social
        VStack(alignment: .leading, spacing: 26 * scale) {
            header
            if let challenge = social.challengeShown {
                ChallengeTrack(challenge: challenge)
                HStack(alignment: .top, spacing: 36 * scale) {
                    standings(challenge).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    card(challenge).frame(width: 330 * scale)
                }
            } else {
                standingsState
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let challenge = model.social.challengeShown
        return HStack(alignment: .center, spacing: 26 * scale) {
            let size = 104 * scale
            Group {
                if let challenge, let icon = model.localIcon(challenge.game.titleId) {
                    ArtworkImage(url: icon, maxPixels: 400)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                } else {
                    Image(systemName: "flag.2.crossed.fill")
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(model.accent)
                        .frame(width: size, height: size)
                        .background(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(model.accent.opacity(0.16)))
                }
            }
            .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack(spacing: 8 * scale) {
                    Text(TChal.text(.kicker))
                    if let challenge {
                        Text("·")
                        Label(AppModel.challengeMetric(challenge.metric), systemImage: AppModel.challengeSymbol(challenge.metric)).foregroundStyle(model.accent)
                    }
                }
                .font(.display(13 * scale, .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
                Text(challenge?.title ?? TChal.text(.title))
                    .font(.display(38 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let challenge {
                    Text(subline(challenge))
                        .font(.display(15 * scale, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 22 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                if model.challengeActions.contains(.join) || model.challengeActions.contains(.leave) {
                    Hint(keys: "O / △", label: TChal.text(.hintJoin))
                }
                Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
    }

    /// "Stray · For friends · by Mira".
    private func subline(_ challenge: TogetherChallenge) -> String {
        let maker = challenge.mine ? TChal.text(.byYou) : challenge.creator.map { TChal.format(.by, $0.displayName) }
        return [model.challengeGameName(challenge.game), AppModel.challengeAudience(challenge), maker].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Standings

    @ViewBuilder private func standings(_ challenge: TogetherChallenge) -> some View {
        let social = model.social
        if let detail = social.challengeDetail {
            let lines = detail.lines
            if lines.isEmpty {
                ProfileNotice(symbol: challenge.state == .upcoming || challenge.clock().isBefore ? "flag" : "list.number",
                              text: TChal.text(challenge.clock().isBefore ? .notStarted : .noScores))
            } else {
                ProfileColumn(title: TChal.text(challenge.decided ? .finalStandings : .standings), count: nil,
                              focusedIndex: social.challengeColumn == 0 ? social.challengeIndex : nil, ids: lines.indices.map { "standing-\($0)" }) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Group {
                            switch line {
                            case .standing(let standing):
                                ChallengeRow(standing: standing, metric: challenge.metric, focused: social.challengeColumn == 0 && index == social.challengeIndex)
                            case .gap:
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18 * scale, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 26 * scale)
                            }
                        }
                        .id("standing-\(index)")
                        .onTapGesture {
                            model.social.challengeColumn = 0
                            model.social.challengeIndex = index
                        }
                    }
                }
            }
        } else {
            standingsState
        }
    }

    @ViewBuilder private var standingsState: some View {
        let social = model.social
        if social.challengeGone {
            ProfileNotice(symbol: "flag.slash", text: TChal.text(.gone))
        } else if social.challengeFailed {
            ProfileNotice(symbol: "wifi.exclamationmark", text: TChal.text(.failed))
        } else {
            VStack(spacing: 18 * scale) {
                IndeterminateLine(color: model.accent).frame(width: 260 * scale)
                Text(TChal.text(.loading)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60 * scale)
        }
    }

    // MARK: The card

    private func card(_ challenge: TogetherChallenge) -> some View {
        let social = model.social
        let actions = model.challengeActions
        return VStack(alignment: .leading, spacing: 14 * scale) {
            kicker(TChal.text(.yourPlace))
            HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                Text(challenge.myStanding.map { "#\($0.rank)" } ?? "—")
                    .font(.display(56 * scale, .light))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if challenge.myStanding != nil, challenge.entrants > 0 {
                    Text(TS.format(.boardOf, challenge.entrants)).font(.display(17 * scale, .medium)).foregroundStyle(.white.opacity(0.55))
                }
            }
            if let place = challenge.myStanding {
                Text(AppModel.challengeValue(place.value, metric: challenge.metric))
                    .font(.display(20 * scale, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(model.accent)
            } else if !challenge.joined {
                Text(TChal.text(.notIn)).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.55))
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.vertical, 2 * scale)
            kicker(TChal.text(challenge.decided ? .winner : .leading))
            if let leader = challenge.leader {
                HStack(spacing: 12 * scale) {
                    ChallengeAvatar(user: leader.user, size: 40 * scale)
                        .overlay(Circle().strokeBorder(TrophySet.Grade.gold.color, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text(leader.user?.displayName ?? TChal.text(.hidden)).font(.display(16 * scale, .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(AppModel.challengeValue(leader.value, metric: challenge.metric)).font(.display(13 * scale, .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    if challenge.decided { Image(systemName: "crown.fill").foregroundStyle(TrophySet.Grade.gold.color) }
                }
            } else {
                Text(TChal.text(.noLeader)).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.5))
            }
            Label(TChal.format(.entrants, challenge.entrants), systemImage: "person.3.fill")
                .font(.display(13 * scale, .medium))
                .foregroundStyle(.white.opacity(0.55))
            if let description = challenge.description, !description.isEmpty {
                Text(description)
                    .font(.display(13 * scale))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12 * scale) {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    let focused = social.challengeColumn == 1 && social.challengeButton == index
                    switch action {
                    case .join, .leave:
                        ConsoleButton(title: TChal.text(action == .join ? .join : .leave), symbol: action == .join ? "flag.fill" : "flag.slash", focused: focused,
                                      prominent: action == .join, destructive: action == .leave, minWidth: 282) { model.challengeAction(action) }
                            .opacity(social.challengeBusy ? 0.6 : 1)
                        if action == .join {
                            Text(TChal.text(.joinNote))
                                .font(.display(12 * scale))
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .website:
                        let shape = RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                        Label(TChal.text(.makeOnWeb), systemImage: "safari")
                            .font(.display(13 * scale, .semibold))
                            .foregroundStyle(.white.opacity(focused ? 1 : 0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14 * scale)
                            .padding(.vertical, 10 * scale)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(shape.fill(Color.white.opacity(focused ? 0.16 : 0.06)))
                            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                            .focusRing(focused, radius: 14 * scale, width: 2)
                            .onTapGesture { model.openChallengeWebsite() }
                            .animation(Motion.focus, value: focused)
                    }
                }
            }
            .padding(.top, 4 * scale)
        }
        .padding(24 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(22 * scale, opacity: 0.3)
    }

    private func kicker(_ text: String) -> some View {
        Text(text)
            .font(.display(13 * scale, .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.55))
    }
}

extension TogetherChallenge.Clock {
    /// Not started yet.
    var isBefore: Bool { if case .startsIn = self { return true } else { return false } }
}

/// The window as a race track: the start flag, the stretch gone in the accent up to a glowing
/// marker for now, the finish flag; the days under its ends, the time left over it.
struct ChallengeTrack: View {
    let challenge: TogetherChallenge
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let progress = challenge.progress()
        let clock = challenge.clock()
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack {
                Label(AppModel.challengeClock(clock), systemImage: clock.isBefore ? "calendar" : (challenge.isOpen ? "timer" : "flag.checkered"))
                    .font(.display(15 * scale, .semibold))
                    .foregroundStyle(challenge.isOpen ? model.accent : .white.opacity(0.7))
                Spacer()
            }
            HStack(spacing: 14 * scale) {
                Image(systemName: "flag.fill").font(.system(size: 14 * scale, weight: .semibold)).foregroundStyle(.white.opacity(progress > 0 ? 0.9 : 0.5))
                GeometryReader { proxy in
                    let width = proxy.size.width, height = 6 * scale
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14)).frame(height: height)
                        // The track's lanes: a tick each day for a window of a few weeks at most.
                        HStack(spacing: 0) {
                            ForEach(0 ..< ticks, id: \.self) { _ in
                                Spacer(minLength: 0)
                                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: height * 2.2)
                            }
                            Spacer(minLength: 0)
                        }
                        Capsule().fill(LinearGradient(colors: [model.accent.opacity(0.6), model.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(height, width * progress), height: height)
                            .shadow(color: model.accent.opacity(0.55), radius: 8)
                        if progress > 0, progress < 1 {
                            Circle().fill(Color.white)
                                .frame(width: height * 2.6, height: height * 2.6)
                                .shadow(color: model.accent.opacity(0.9), radius: 10)
                                .offset(x: width * progress - height * 1.3)
                        }
                    }
                    .frame(height: proxy.size.height)
                }
                .frame(height: 20 * scale)
                Image(systemName: "flag.checkered").font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(.white.opacity(progress >= 1 ? 0.95 : 0.5))
            }
            HStack {
                Text(Self.when(challenge.startsAt))
                Spacer()
                Text(Self.when(challenge.endsAt))
            }
            .font(.display(12 * scale, .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 28 * scale)
        }
        .padding(.horizontal, 22 * scale)
        .padding(.vertical, 16 * scale)
        .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// Whole days between the ends, for windows up to a month; none past that.
    private var ticks: Int {
        let days = Int(challenge.endsAt.timeIntervalSince(challenge.startsAt) / 86400)
        return days >= 2 && days <= 31 ? days - 1 : 0
    }

    /// "Fri 6 Nov, 14:00" in the user's time zone and language.
    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = T.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return formatter.string(from: date)
    }
}

/// Someone's picture, or a hidden player's veiled circle.
struct ChallengeAvatar: View {
    let user: TogetherPerson?
    let size: CGFloat
    @Environment(\.scale) private var scale

    var body: some View {
        if let user {
            ProfileAvatar(url: user.avatar, name: user.displayName, size: size, glow: false)
        } else {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
    }
}

/// One place in a challenge: rank (gold, silver and bronze for the first three), avatar, name and
/// value; the user's own line in the accent; a hidden player without a name.
struct ChallengeRow: View {
    let standing: TogetherChallenge.Standing
    let metric: TogetherChallenge.Metric
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 18 * scale) {
            Text("\(standing.rank)")
                .font(.display(22 * scale, .semibold))
                .monospacedDigit()
                .foregroundStyle(medal ?? .white.opacity(0.7))
                .frame(width: 56 * scale)
            ChallengeAvatar(user: standing.user, size: 44 * scale)
                .overlay(Circle().strokeBorder(standing.user == nil ? .clear : (medal ?? .clear), lineWidth: 2))
            VStack(alignment: .leading, spacing: 3 * scale) {
                HStack(spacing: 8 * scale) {
                    Text(standing.user?.displayName ?? TChal.text(.hidden))
                        .font(.display(17 * scale, .semibold))
                        .foregroundStyle(.white.opacity(standing.user == nil ? 0.55 : 1))
                        .lineLimit(1)
                    if standing.me {
                        Text(TS.text(.boardYou))
                            .font(.display(11 * scale, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8 * scale)
                            .padding(.vertical, 2 * scale)
                            .background(Capsule().fill(model.accent.opacity(0.6)))
                    }
                }
                if let user = standing.user {
                    Text("@\(user.handle)").font(.display(13 * scale)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 12 * scale)
            Text(AppModel.challengeValue(standing.value, metric: metric))
                .font(.display(18 * scale, .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
        .frame(minHeight: 64 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(standing.me ? model.accent.opacity(focused ? 0.32 : 0.2) : Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 16 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    private var medal: Color? {
        switch standing.rank {
        case 1: return TrophySet.Grade.gold.color
        case 2: return TrophySet.Grade.silver.color
        case 3: return TrophySet.Grade.bronze.color
        default: return nil
        }
    }
}
