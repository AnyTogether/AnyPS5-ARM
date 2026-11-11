import AnyPS5Core
import AppKit
import SwiftUI

/// What holds a join back, said whole in its own panel (a toast has two lines): what differs
/// (the game version or the engine build), the host's and this copy's, each untruncated on its
/// own line, and what gets past it.
struct JoinBlock {
    enum Kind: Equatable {
        case engine(EngineAdvice)
        case gameVersion(youUpdate: Bool)
    }

    var kind: Kind
    var hostName: String
    var gameName: String
    /// The host's engine build or game version, and this copy's, as they are.
    var host: String
    var yours: String
    /// Rebuilds this copy and joins again, when that gets past it.
    var rebuild: (() -> Void)?
    /// Joins with the game version as it is, when the host's rule lets a player try.
    var tryAnyway: (() -> Void)?
}

/// A game being started from the library while someone the user knows plays it.
struct JoinChoice {
    var game: Game
    var other: JoinableGame
    /// Whose game it is, as the user knows them.
    var name: String
}

/// Being in a party is not being in the same game: the party is voice and chat, the game session
/// is what connects the games. Play on a game a party member or friend already hosts asks whether
/// to join theirs; the party and the quick menu say for each member whether they are in the
/// user's game; and a join that cannot go on says why in full.
extension AppModel {
    // MARK: Join theirs, or start your own

    /// How the user knows someone by ID: a party member or friend's shown name.
    func knownName(_ userId: String) -> String {
        if let member = party?.members.first(where: { $0.userId == userId }) { return shown(member).name }
        if let friend = togetherFriends.first(where: { $0.userId == userId }) { return shown(friend).name }
        return gameSession?.players.first { $0.userId == userId }?.displayName ?? ""
    }

    /// The game someone the user knows hosts that `game` could join instead of starting alone.
    func joinableGame(for game: Game) -> JoinableGame? {
        guard let me = togetherUser else { return nil }
        return JoinableGame.find(titleId: game.titleID, me: me.id, mine: gameSession?.id, party: party, friends: togetherFriends)
    }

    /// Play from the library: a game someone the user knows already hosts asks first, so the two
    /// do not end up in separate sessions without a word; anything else starts.
    func playOrJoin(_ game: Game) {
        guard let other = joinableGame(for: game) else { return play(game) }
        joinChoice = JoinChoice(game: game, other: other, name: knownName(other.personId))
        Sounds.shared.play(.select)
        open(.joinOrHost)
    }

    /// Joins the game a choice or a member's row names: the party's Play Together game as one,
    /// a friend's own session as a friend's game.
    func join(_ other: JoinableGame, name: String) {
        if other.together, let party, let together = party.together, together.sessionId == other.sessionId {
            joinPlayTogether(togetherOffer(together, in: party))
        } else {
            joinFriendGame(other.sessionId, titleId: other.titleId, host: name)
        }
    }

    /// The question's rows: Join first (the default), then a game of one's own.
    func joinOrHostRows(_ choice: JoinChoice) -> [PanelRow] {
        [
            PanelRow(id: "choice-join", title: PT.format(.joinRow, choice.name, choice.game.name), detail: PT.text(.joinDetail), symbol: "person.2.wave.2.fill",
                     kind: .action(destructive: false) { [weak self] in
                         self?.closeOverlay()
                         self?.joinChoice = nil
                         self?.join(choice.other, name: choice.name)
                     }),
            PanelRow(id: "choice-own", title: PT.text(.askOwn), detail: PT.format(.askOwnDetail, choice.name), symbol: "play.fill",
                     kind: .action(destructive: false) { [weak self] in
                         self?.closeOverlay()
                         self?.joinChoice = nil
                         self?.show(PT.format(.separate, choice.name), symbol: "person.2.slash")
                         self?.play(choice.game)
                     }, wraps: true),
        ]
    }

    // MARK: A join held back

    /// The engine build unlocking `titleId`'s copy again would give, when that differs from the
    /// one it was made with.
    func rebuildGives(_ titleId: String) -> String? {
        togetherCopies().first { $0.titleId == titleId && $0.nextEngineBuild != nil }?.nextEngineBuild
    }

    /// The block a different engine build makes: who is behind is read from the two releases.
    func engineBlock(hostName: String, titleId: String, host: String, yours: String, rebuild: (() -> Void)? = nil) -> JoinBlock {
        let advice = EngineAdvice.of(yours: yours, host: host, rebuildGives: rebuildGives(titleId))
        return JoinBlock(kind: .engine(advice), hostName: hostName, gameName: gameName(titleId), host: host, yours: yours, rebuild: advice == .rebuild ? rebuild : nil)
    }

    /// Says a held-back join whole, in its panel.
    func tell(_ block: JoinBlock) {
        joinBlock = block
        Sounds.shared.play(.back)
        Feel.shared.vibrate(.error)
        open(.joinBlocked)
    }

    /// What differs, the sentence that says so, and what gets past it.
    static func joinBlockTexts(_ block: JoinBlock) -> (title: String, detail: String, advice: String) {
        switch block.kind {
        case .engine(let advice):
            let action: String
            switch advice {
            case .rebuild: action = PT.text(.adviceRebuild)
            case .updateYours: action = PT.format(.adviceUpdateYours, block.hostName)
            case .hostNightly: action = PT.format(.adviceHostNightly, block.hostName)
            case .updateHost: action = PT.format(.adviceUpdateHost, block.hostName)
            case .sameEngine: action = PT.text(.adviceSameEngine)
            }
            return (PT.text(.blockedEngine), PT.format(.blockedEngineDetail, block.hostName, block.gameName), action)
        case .gameVersion(let youUpdate):
            return (PT.text(.blockedVersion), PT.format(.blockedVersionDetail, block.hostName, block.gameName),
                    youUpdate ? PT.format(.versionYou, block.gameName, block.host, block.yours) : PT.format(.versionHost, block.hostName, block.host, block.yours))
        }
    }

    /// The panel's rows: what differs and what to do, the host's build and this one's whole, then
    /// the action that fits (rebuild and join, check for updates, try anyway) and Close.
    func joinBlockedRows(_ block: JoinBlock) -> [PanelRow] {
        let texts = AppModel.joinBlockTexts(block)
        var rows = [
            PanelRow(id: "blocked-what", title: texts.title, detail: texts.detail + "\n" + texts.advice, symbol: "exclamationmark.triangle.fill", kind: .info(""), wraps: true),
            PanelRow(id: "blocked-host", title: block.hostName, detail: block.host, symbol: "person.fill", kind: .info(""), wraps: true),
            PanelRow(id: "blocked-you", title: PT.text(.you), detail: block.yours, symbol: "person", kind: .info(""), wraps: true),
        ]
        if let rebuild = block.rebuild {
            rows.append(PanelRow(id: "blocked-rebuild", title: PT.text(.rebuildAndJoin), symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in
                self?.closeOverlay()
                self?.joinBlock = nil
                rebuild()
            }))
        }
        // Update is only offered when this side's release is the older one.
        if block.kind == .engine(.updateYours) {
            rows.append(PanelRow(id: "blocked-update", title: T.text(.checkForUpdatesNow), detail: T.text(.checkForUpdatesDetail), symbol: "arrow.down.circle",
                                 kind: .action(destructive: false) { [weak self] in
                                     self?.closeOverlay()
                                     self?.joinBlock = nil
                                     self?.checkForUpdatesNow()
                                 }))
        }
        if let tryAnyway = block.tryAnyway {
            rows.append(PanelRow(id: "blocked-try-anyway", title: PT.text(.tryAnyway), detail: PT.text(.tryAnywayDetail), symbol: "exclamationmark.arrow.triangle.2.circlepath",
                                 kind: .action(destructive: false) { [weak self] in
                                     self?.closeOverlay()
                                     self?.joinBlock = nil
                                     tryAnyway()
                                 }))
        }
        rows.append(PanelRow(id: "blocked-close", title: T.text(.close), symbol: "xmark.circle", kind: .action(destructive: false) { [weak self] in
            self?.closeOverlay()
            self?.joinBlock = nil
        }))
        return rows
    }

    // MARK: Who is in whose game

    /// What a party member plays next to the user's own game; nil when nothing is known of them.
    func memberGame(_ member: TogetherPerson, in party: TogetherParty) -> MemberGame? {
        let friend = togetherFriends.first { $0.userId == member.userId }
        return MemberGame.of(member.userId, mine: gameSession, together: party.together, presence: friend?.presence?.game, friend: friend != nil)
    }

    /// "In your game", "In another game of Greenhollow", "Playing Greenhollow", "Not in a game".
    static func memberGameText(_ state: MemberGame, title: (String) -> String) -> String {
        switch state {
        case .yours: return PT.text(.inYourGame)
        case .other(_, let titleId, _, _, _, let sameTitle): return sameTitle ? PT.format(.inOtherGame, title(titleId)) : T.format(.friendsPlaying, title(titleId))
        case .nothing: return PT.text(.notInGame)
        }
    }

    /// The Join row for a member in another game that takes players; nil for anyone else. The
    /// party's own Play Together game has its Join in the Play Together rows above.
    func memberJoinRow(_ member: TogetherPerson, in party: TogetherParty, id: String) -> PanelRow? {
        guard case .other(let sessionId, let titleId, let hostId, true, let together, _)? = memberGame(member, in: party) else { return nil }
        let name = shown(member).name
        return PanelRow(id: id, title: PT.format(.joinRow, name, gameName(titleId)), detail: AppModel.memberGameText(.other(sessionId: sessionId, titleId: titleId, hostId: hostId, joinable: true, together: together, sameTitle: gameSession?.titleId == titleId), title: gameName),
                        symbol: "play.circle.fill", kind: .action(destructive: false) { [weak self] in
                            self?.join(JoinableGame(sessionId: sessionId, titleId: titleId, personId: hostId, together: together), name: name)
                        }, person: panelPerson(member, status: .playing))
    }

    /// The quick menu's party: each other member with what they play; one in another game that
    /// takes players is the Join itself.
    func partyGameRows() -> [PanelRow] {
        guard let me = togetherUser, let party else { return [] }
        var joins = Set<String>()
        return party.members.filter { $0.userId != me.id }.compactMap { member in
            guard let state = memberGame(member, in: party) else { return nil }
            if case .other(let sessionId, _, _, true, _, _) = state, joins.insert(sessionId).inserted, let row = memberJoinRow(member, in: party, id: "party-game-\(member.userId)") { return row }
            return PanelRow(id: "party-game-\(member.userId)", title: shown(member).name, detail: AppModel.memberGameText(state, title: gameName), symbol: "person", kind: .info(""),
                            person: panelPerson(member, status: state == .nothing ? nil : .playing))
        }
    }
}
