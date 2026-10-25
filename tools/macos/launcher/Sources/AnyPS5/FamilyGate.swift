import AnyPS5Core
import AppKit
import SwiftUI

/// What the family watch keeps between ticks: the refresh loop, the running game's timer and
/// what was asked a parent lately (so the same ask is not sent again and again).
@MainActor
final class FamilyWatch {
    var loop: Task<Void, Never>?
    var tick: Task<Void, Never>?
    var timer: FamilyPlayTimer?
    var refreshed: Date?
    var asked: [String: Date] = [:]
}

/// Family limits in the launcher. A child's parents decide on the AnyTogether website; the
/// launcher keeps the last signed status (FamilyCache) and applies it whoever is signed in, even
/// offline: games above the age limit stay closed with "Ask a parent", play time is counted
/// against today's limit and hours, warned about while a game runs and, if the parents chose,
/// the game is closed after a grace period to save. Social features a parent turned off are
/// hidden here as the server refuses them anyway.
extension AppModel {
    /// The status is read again this often while signed in.
    static let familyRefreshEvery: Duration = .seconds(300)
    /// Before a game starts, a status read this recently is good enough.
    static let familyFreshFor: TimeInterval = 60

    // MARK: Status

    /// The kept status at launch, then a refresh every five minutes while signed in (signing in,
    /// and the launch signed in, refresh at once: startTogetherSocket).
    func startFamily() {
        family = familyCache.standing()
        familyWatch.loop?.cancel()
        familyWatch.loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppModel.familyRefreshEvery)
                guard let self else { return }
                if self.togetherUser != nil { await self.refreshFamilyNow() } else { self.family = self.familyCache.standing() }
            }
        }
    }

    func refreshFamily() {
        Task { await refreshFamilyNow() }
    }

    /// Reads the status from the server and keeps it; offline, the kept one stays.
    func refreshFamilyNow() async {
        guard togetherUser != nil else { return }
        do {
            let standing = try await familyCache.refresh(from: together)
            familyWatch.refreshed = Date()
            if standing != family { withAnimation(Motion.overlay) { family = standing } }
        } catch FamilyCacheError.otherServer {
            family = familyCache.standing()
        } catch {
            family = familyCache.standing()
        }
    }

    /// A refresh that gives up after a few seconds: a game should not wait long for it.
    private func refreshBeforePlaying() async {
        guard togetherUser != nil, familyWatch.refreshed.map({ Date().timeIntervalSince($0) > AppModel.familyFreshFor }) ?? true else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshFamilyNow() }
            group.addTask { try? await Task.sleep(for: .seconds(4)) }
            await group.next()
            group.cancelAll()
        }
    }

    var familyRules: FamilyRestrictions? {
        switch family {
        case .free: return nil
        case .limited(let status, _): return status.effectiveRestrictions
        // While the kept status cannot be trusted, social features are as careful as for a new child.
        case .locked: return .careful()
        }
    }

    // MARK: Play time

    /// Today's allowance on this Mac: the server's count, the games played here it does not have
    /// yet, and the game running now. nil without limits.
    func familyAllowance(now: Date = Date()) -> FamilyAllowance? {
        guard case .limited(let status, _) = family, let rules = status.effectiveRestrictions else { return nil }
        let zone = rules.playTime.timeZone
        let played = FamilyPolicy.playedToday(status: status, records: familyCache.records, pending: togetherSync.pendingSessionIDs,
                                              running: running == nil ? nil : sessionStart, now: now, timeZone: zone)
        return FamilyPolicy.allowance(rules.playTime, now: now, playedSeconds: played, bonusMinutes: FamilyPolicy.bonusToday(status: status, now: now, timeZone: zone))
    }

    /// Why the game may not start now; nil when it may.
    func familyBlock(_ game: Game, now: Date = Date()) -> FamilyBlock? {
        switch family {
        case .free: return nil
        case .locked: return .locked
        case .limited(let status, _):
            guard let rules = status.effectiveRestrictions else { return nil }
            switch FamilyPolicy.titleVerdict(rules, titleId: game.titleID, levels: game.ageLevels) {
            case .age: return .age(FamilyPolicy.ageLevel(game.ageLevels, region: rules.ageRegion))
            case .unknown: return .unknownAge
            case .allowed: break
            }
            guard let allowance = familyAllowance(now: now), !allowance.allowed else { return nil }
            return allowance.reason == .window ? .window(from: allowance.from, until: allowance.until) : .limit
        }
    }

    /// The age rating keeps this game closed (the lock on its tile).
    func familyAgeLocked(_ game: Game) -> Bool {
        guard let rules = familyRules, case .limited = family else { return false }
        return FamilyPolicy.titleVerdict(rules, titleId: game.titleID, levels: game.ageLevels) != .allowed
    }

    static func familyBlockText(_ block: FamilyBlock) -> String {
        switch block {
        case .age(let level): return level.map { FS.format(.ratedAbove, $0) } ?? FS.text(.refusedAge)
        case .unknownAge: return FS.text(.ratedUnknown)
        case .limit: return FS.text(.startLimit)
        case .window(let from, let until): return from.flatMap { from in until.map { FS.format(.startWindow, from, $0) } } ?? FS.text(.startLimit)
        case .locked: return FS.text(.lockedDetail)
        }
    }

    /// Plays only what the family allows: the status read again first when online, then the age
    /// rating and today's time checked.
    func familyGate(_ game: Game, then go: @escaping @MainActor () -> Void) {
        if family == .free, togetherUser == nil { return go() }
        Task {
            await refreshBeforePlaying()
            if let block = familyBlock(game) {
                Sounds.shared.play(.back)
                return show(AppModel.familyBlockText(block), symbol: "hand.raised.fill")
            }
            go()
        }
    }

    /// The main button's text and symbol for a game the family keeps closed now.
    func familyPrimary(_ game: Game, _ state: GameState) -> (title: String, symbol: String)? {
        guard case .installed = state, let block = familyBlock(game) else { return nil }
        switch block {
        case .age, .unknownAge: return (FS.text(.askParent), "hand.raised.fill")
        case .limit, .window: return (FS.text(.askMoreTime), "hourglass")
        case .locked: return (FS.text(.locked), "lock.fill")
        }
    }

    /// The main button on a closed game: asks a parent instead of playing.
    func familyPrimaryAction(_ game: Game) -> Bool {
        guard case .installed = state(of: game), let block = familyBlock(game) else { return false }
        switch block {
        case .age, .unknownAge: askFamily(.playGame(titleId: game.titleID, name: game.name), key: "game-\(game.titleID)", told: FS.format(.askedGame, game.name))
        case .limit, .window: askFamily(.moreTime(minutes: 30, titleId: game.titleID), key: "time")
        case .locked:
            show(FS.text(.lockedDetail), symbol: "lock.fill")
            refreshFamily()
        }
        return true
    }

    /// Sends an ask to the parents, once in a while for the same thing.
    func askFamily(_ ask: FamilyAsk, key: String, told: String? = nil) {
        guard togetherUser != nil else { return show(FS.text(.signInToAsk), symbol: "person.crop.circle.badge.questionmark") }
        if let last = familyWatch.asked[key], Date().timeIntervalSince(last) < 10 * 60 {
            return show(FS.text(.askedAlready), symbol: "hourglass")
        }
        Task {
            do {
                try await together.askFamily(ask)
                familyWatch.asked[key] = Date()
                Sounds.shared.play(.select)
                show(told ?? FS.text(.asked), symbol: "hand.raised.fill")
            } catch let problem as TogetherProblem where problem.status == 409 || problem.code == "rate_limited" {
                show(FS.text(.askedAlready), symbol: "hourglass")
            } catch {
                show(FS.text(.askFailed), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// A game ended: kept here until a status counts it (`session` is its ID in the outbox).
    func familyPlayed(_ game: Game, from start: Date, session: String?) {
        let end = Date()
        guard end > start.addingTimeInterval(5) else { return }
        familyCache.record(FamilyPlayRecord(id: session ?? UUID().uuidString.lowercased(), titleId: game.titleID, startedAt: start, endedAt: end, queued: session != nil))
    }

    // MARK: While a game runs

    /// The running game is watched every two seconds against today's allowance.
    func familyGameStarted() {
        familyWatch.tick?.cancel()
        familyWatch.timer = nil
        familyWatch.tick = Task { [weak self] in
            while !Task.isCancelled {
                self?.familyTick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func familyGameEnded() {
        familyWatch.tick?.cancel()
        familyWatch.tick = nil
        familyWatch.timer = nil
        FamilyNotice.shared.hide()
    }

    private func familyTick(now: Date = Date()) {
        guard let running else { return familyGameEnded() }
        let remaining: Int?
        let allowed: Bool
        var rules: FamilyRestrictions?
        switch family {
        case .free:
            remaining = nil
            allowed = true
        case .locked:
            remaining = 0
            allowed = false
        case .limited(let status, _):
            rules = status.effectiveRestrictions
            let allowance = familyAllowance(now: now)
            remaining = allowance?.remainingSeconds
            allowed = allowance?.allowed ?? true
        }
        let playTime = rules?.playTime ?? .careful()
        if familyWatch.timer == nil || familyWatch.timer?.action != playTime.whenLimitReached || familyWatch.timer?.graceMinutes != playTime.graceMinutes {
            // A new game, or the parents changed what happens at the limit.
            let wasReached = familyWatch.timer?.limitReached ?? false
            familyWatch.timer = FamilyPlayTimer(action: family == .locked ? .close : playTime.whenLimitReached, graceMinutes: playTime.graceMinutes)
            if wasReached { FamilyNotice.shared.hide() }
        }
        guard var timer = familyWatch.timer else { return }
        let events = timer.tick(remaining: remaining, allowed: allowed, now: now)
        familyWatch.timer = timer
        for event in events {
            switch event {
            case .warn(let minutes):
                TrophyBanner.shared.notice(minutes <= 1 ? FS.text(.warnOne) : FS.format(.warnMinutes, minutes), detail: FS.text(.warnDetail), symbol: "hourglass", sounds: preferences.sounds)
            case .limitReached(let closesAt):
                FamilyNotice.shared.show(closesAt: closesAt, sounds: preferences.sounds)
                if playTime.notifyParents, togetherUser != nil {
                    let titleId = running.game.titleID
                    Task { try? await together.familyLimitReached(titleId: titleId) }
                }
            case .quit:
                running.app.terminate()
            case .forceQuit:
                running.app.forceTerminate()
            case .resumed:
                FamilyNotice.shared.hide()
                if let remaining { TrophyBanner.shared.notice(FS.format(.moreTime, FS.duration(remaining)), detail: "", symbol: "hourglass", sounds: preferences.sounds) }
            }
        }
    }

    // MARK: Social features

    /// Whether the family lets the user use a feature; true without limits.
    func familyAllows(_ feature: FamilyFeature) -> Bool {
        guard let rules = familyRules else { return true }
        switch feature {
        case .voiceChat: return rules.voiceChat
        case .sharePlay: return rules.sharePlay
        case .publicMatchmaking: return rules.publicMatchmaking
        case .discovery: return rules.discovery
        case .communities: return rules.communities
        case .mediaSharing: return rules.mediaSharing
        case .messages: return rules.messages != .nobody
        // Asking anyone directly; otherwise a parent is asked.
        case .friendRequests: return rules.friendRequests == .everyone || rules.friendRequests == .friendsOfFriends
        case .profileVisibility, .ageRating, .family: return true
        }
    }

    /// The same, saying why not.
    func familyPermits(_ feature: FamilyFeature) -> Bool {
        guard familyAllows(feature) else {
            show(FS.refusal(feature), symbol: "hand.raised.fill")
            return false
        }
        return true
    }

    /// A refusal from the server, in words, when a parent's settings were the reason.
    func familyMessage(_ error: Error) -> String? {
        guard let problem = error as? TogetherProblem, let feature = problem.familyFeature else { return nil }
        // The server may know a newer status than the one kept here.
        refreshFamily()
        return FS.refusal(feature)
    }

    /// Adding a friend the rules keep for a parent to approve: the parent is asked instead.
    func askParentToAdd(_ handle: String) {
        askFamily(.addFriend(handle: handle), key: "friend-\(handle.lowercased())", told: FS.format(.askedFriend, handle))
    }

    // MARK: Rows

    /// The Together panel's family rows for a child: today's time, a stale or locked status, and
    /// asking for more time.
    func familyRows() -> [PanelRow] {
        familyStandingRows() + familyServerRows()
    }

    /// Limits kept from another server than the one used now.
    private func familyServerRows() -> [PanelRow] {
        guard family != .free, let server = familyCache.limitsServer, server != together.base.absoluteString else { return [] }
        return [PanelRow(id: "family-server", title: FS.format(.otherServer, URL(string: server)?.host() ?? server), symbol: "server.rack", kind: .info(""))]
    }

    private func familyStandingRows() -> [PanelRow] {
        switch family {
        case .free:
            return []
        case .locked:
            return [PanelRow(id: "family-locked", title: FS.text(.locked), detail: FS.text(.lockedDetail), symbol: "lock.fill", kind: .info(""))]
        case .limited(let status, let stale):
            var rows: [PanelRow] = []
            if let allowance = familyAllowance() {
                let title: String
                if !allowance.allowed {
                    title = allowance.reason == .window ? allowance.from.flatMap { from in allowance.until.map { FS.format(.outsideHours, from, $0) } } ?? FS.text(.timeUp) : FS.text(.timeUp)
                } else if let remaining = allowance.remainingSeconds {
                    title = FS.format(.leftToday, FS.duration(remaining))
                } else {
                    title = FS.text(.noLimitToday)
                }
                let detail = allowance.limitMinutes.map { FS.format(.limitToday, FS.duration($0 * 60), FS.duration(allowance.playedSeconds)) }
                    ?? FS.format(.playedToday, FS.duration(allowance.playedSeconds))
                rows.append(PanelRow(id: "family-today", title: title, detail: detail, symbol: allowance.allowed ? "hourglass" : "hourglass.bottomhalf.filled", kind: .info(FS.text(.family))))
                if allowance.remainingSeconds != nil, togetherUser != nil {
                    for minutes in [15, 30, 60] {
                        rows.append(PanelRow(id: "family-ask-\(minutes)", title: FS.format(.askMinutes, minutes), detail: FS.text(.askMinutesDetail), symbol: "hand.raised",
                                             kind: .action(destructive: false) { [weak self] in
                                                 self?.askFamily(.moreTime(minutes: minutes, titleId: self?.running?.game.titleID), key: "time-\(minutes)")
                                             }))
                    }
                }
            }
            if stale {
                rows.append(PanelRow(id: "family-stale", title: FS.text(.stale), detail: FS.format(.staleDetail, ProfileView.day(status.issuedAt)), symbol: "arrow.clockwise", kind: .info("")))
            }
            return rows
        }
    }
}

/// The badge on the tile of a game the age rating keeps closed.
struct FamilyTileBadge: View {
    let game: Game
    let size: CGFloat
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.familyAgeLocked(game) {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.42)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: size * 0.13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(size * 0.08)
                    .background(Circle().fill(Color.black.opacity(0.55)).padding(size * 0.035))
            }
        }
    }
}

/// The big notice over the game when today's time is up: what happens and, with "close", the
/// countdown to the game closing. Like the trophy banner it never takes the keyboard or the
/// mouse from the game, so the child can save.
@MainActor
final class FamilyNotice {
    static let shared = FamilyNotice()
    static let size = CGSize(width: 620, height: 230)

    private var panel: NSPanel?

    func show(closesAt: Date?, sounds: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = FamilyNotice.size
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let top = screen.frame.maxY - screen.safeAreaInsets.top
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height - 40, width: size.width, height: size.height), display: false)
        panel.contentView = NSHostingView(rootView: FamilyNoticeCard(closesAt: closesAt))
        panel.orderFrontRegardless()
        if sounds { Sounds.shared.play(.back) }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}

struct FamilyNoticeCard: View {
    let closesAt: Date?
    var still = false
    @State private var shown = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 8) {
                    Text(FS.text(.noticeTitle)).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    Text(line(at: context.date)).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.85)).monospacedDigit()
                    Text(FS.text(.noticeAsk)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.07).opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
            .scaleEffect(shown || still ? 1 : 0.94)
            .opacity(shown || still ? 1 : 0)
        }
        .frame(width: FamilyNotice.size.width, height: FamilyNotice.size.height)
        .onAppear {
            guard !still else { return }
            withAnimation(Motion.reduced ? .easeOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.8)) { shown = true }
        }
    }

    private func line(at now: Date) -> String {
        guard let closesAt else { return FS.text(.noticeNotify) }
        let left = Int(closesAt.timeIntervalSince(now).rounded(.up))
        guard left > 0 else { return FS.text(.noticeClosing) }
        return FS.format(.noticeCloses, String(format: "%d:%02d", left / 60, left % 60))
    }
}
