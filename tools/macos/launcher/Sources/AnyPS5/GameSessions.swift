import AnyPS5Core
import AppKit
import SwiftUI

/// Joining a friend's game: while a game runs, the launcher opens an AnyTogether game session for
/// it (when the user lets friends join), so friends see it as joinable; a friend's Join starts the
/// same game here when the game version and engine build match. The session is written for the
/// engine's online bridge (ANYPS5_TOGETHER_SESSION), which does the playing together.
extension AppModel {
    /// How many can play in a session the launcher opens; the game itself may take fewer.
    static let sessionCapacity = 4

    /// The engine a game was unlocked with: only the same build is relied on to talk to itself.
    func engineBuild(for game: Game) -> String {
        TogetherGameSession.engineBuild(installedRecords[game.id]?.toolkit ?? toolkit?.version ?? AppModel.runningVersion)
    }

    func gameVersion(for game: Game) -> String { TogetherGameSession.gameVersion(game.version) }

    /// A session while a game runs, none after; called whenever what runs changes.
    func followGameSession() {
        guard let me = togetherUser else { return }
        if let running {
            guard preferences.friendsJoin ?? true, gameSession == nil, !openingSession else { return }
            let game = running.game
            openingSession = true
            Task {
                defer { openingSession = false }
                guard let session = try? await together.openGameSession(titleId: game.titleID, gameVersion: gameVersion(for: game), engineBuild: engineBuild(for: game),
                                                                         capacity: AppModel.sessionCapacity) else { return }
                guard self.running?.game.id == game.id else {
                    try? await together.endGameSession(session.id)
                    return
                }
                keepSession(session, me: me.id)
            }
        } else if gameSession == nil {
            // Left from a launcher that stopped without ending it.
            try? TogetherGameSession.write(nil, me: me.id, to: TogetherGameSession.bridgeFile)
        } else if let session = gameSession {
            let client = together
            keepSession(nil, me: me.id)
            Task {
                if session.host?.userId == me.id { try? await client.endGameSession(session.id) } else { try? await client.leaveGameSession(session.id) }
            }
        }
    }

    private func keepSession(_ session: TogetherGameSession?, me: String) {
        withAnimation(Motion.overlay) { gameSession = session }
        try? TogetherGameSession.write(session, me: me, to: TogetherGameSession.bridgeFile)
    }

    /// "Let friends join my game" turned on or off: a session open now follows.
    func friendsJoinChanged(_ on: Bool) {
        preferences.friendsJoin = on
        guard let session = gameSession, session.host?.userId == togetherUser?.id else { return followGameSession() }
        if on {
            Task { if let next = try? await together.updateGameSession(session.id, joinable: true) { keepSession(next, me: togetherUser?.id ?? "") } }
        } else {
            Task { if let next = try? await together.updateGameSession(session.id, joinable: false) { keepSession(next, me: togetherUser?.id ?? "") } }
        }
    }

    /// A friend's game, from their presence or an invite: the same game here, checked first.
    func joinFriendGame(_ sessionId: String, titleId: String, host: String) {
        guard let me = togetherUser else { return }
        guard let game = games.first(where: { $0.titleID == titleId }) else {
            return show(T.format(.gameNotHere, titleId), symbol: "questionmark.square.dashed")
        }
        if let running {
            return show(T.format(.gameCloseFirst, running.game.name), symbol: "xmark.app")
        }
        guard case .installed = state(of: game) else { return show(T.format(.gameUnlockFirst, game.name), symbol: "lock.fill") }
        let version = gameVersion(for: game), engine = engineBuild(for: game)
        Task {
            do {
                let session = try await together.gameSession(sessionId)
                switch session.mismatch(gameVersion: version, engineBuild: engine) {
                case .gameVersion?:
                    return show(T.format(.gameVersionMismatch, host, session.gameVersion, version), symbol: "exclamationmark.triangle.fill")
                case .engineBuild?:
                    return show(T.format(.gameEngineMismatch, host, AppModel.release(session.engineBuild), AppModel.release(engine)), symbol: "exclamationmark.triangle.fill")
                case nil:
                    break
                }
                let joined = try await together.joinGameSession(sessionId, gameVersion: version, engineBuild: engine)
                keepSession(joined, me: me.id)
                gameInvites.removeAll { $0.sessionId == sessionId }
                show(T.format(.gameJoined, host, game.name), symbol: "person.2.wave.2.fill")
                if overlay != nil { closeOverlay() }
                selected = games.firstIndex(of: game) ?? selected
                play(game)
            } catch let problem as TogetherProblem where problem.code == "version_mismatch" {
                show(problem.title, symbol: "exclamationmark.triangle.fill")
            } catch let problem as TogetherProblem where problem.code == "full" {
                show(T.text(.gameSessionFull), symbol: "person.3.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// "0.2.13-a1b2c3d4e5f6" → "0.2.13 (a1b2c3)": the release, then which build of it.
    static func release(_ engine: String) -> String {
        let parts = engine.split(separator: "-", maxSplits: 1).map(String.init)
        return parts.count == 2 ? "\(parts[0]) (\(parts[1].prefix(6)))" : engine
    }

    func inviteToGame(_ friend: TogetherFriend) {
        guard let session = gameSession else { return }
        Task {
            do {
                try await together.inviteToGame([friend.userId], session: session.id)
                show(T.format(.gameInvited, friend.displayName), symbol: "paperplane.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func declineGame(_ invite: TogetherGameInvite) {
        withAnimation(Motion.overlay) { gameInvites.removeAll { $0.sessionId == invite.sessionId } }
        Task { try? await together.declineGame(invite.sessionId) }
    }

    func loadGameInvites() {
        guard togetherUser != nil else { return }
        Task {
            guard let mine = try? await together.myGameSession() else { return }
            withAnimation(Motion.overlay) { gameInvites = mine.invites }
        }
    }

    func gameName(_ titleId: String) -> String { games.first { $0.titleID == titleId }?.name ?? titleId }

    /// What the socket says about game sessions.
    func gameSessionEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "game_session.invite":
            guard let invite = event.decode(TogetherGameInvite.self) else { return }
            gameInvites.removeAll { $0.sessionId == invite.sessionId }
            withAnimation(Motion.overlay) { gameInvites.append(invite) }
            let text = T.format(.gameInvitedYou, invite.from?.displayName ?? "", gameName(invite.titleId))
            show(text, symbol: "gamecontroller.fill")
            if !NSApp.isActive { TrophyBanner.shared.notice(text, detail: T.text(.friendsTitle), symbol: "gamecontroller.fill", sounds: preferences.sounds) }
        case "game_session.updated":
            guard let session = event.decode(TogetherGameSession.self), session.id == gameSession?.id, let me = togetherUser?.id else { return }
            keepSession(session, me: me)
        case "game_session.ended":
            let id = event.data["sessionId"]
            gameInvites.removeAll { $0.sessionId == id }
            guard let session = gameSession, session.id == id, let me = togetherUser?.id else { return }
            if session.host?.userId != me { show(T.format(.sessionEnded, session.host?.displayName ?? ""), symbol: "gamecontroller") }
            keepSession(nil, me: me)
        default:
            break
        }
    }

    /// Friends panel rows: invites to answer, friends' games to join, and (while hosting) friends
    /// to invite.
    func gameRows() -> [PanelRow] {
        var rows: [PanelRow] = []
        for invite in gameInvites {
            let host = invite.from?.displayName ?? ""
            rows.append(PanelRow(id: "game-accept-\(invite.sessionId)", title: T.format(.gameJoin, host, gameName(invite.titleId)), detail: T.text(.gameInvitedDetail),
                                 symbol: "gamecontroller.fill", kind: .action(destructive: false) { [weak self] in
                                     self?.joinFriendGame(invite.sessionId, titleId: invite.titleId, host: host)
                                 }, person: invite.from.map { PanelPerson(name: $0.displayName, avatar: $0.avatar, status: .playing) }))
            rows.append(PanelRow(id: "game-decline-\(invite.sessionId)", title: T.format(.gameDecline, host), symbol: "xmark.circle",
                                 kind: .action(destructive: true) { [weak self] in self?.declineGame(invite) }))
        }
        for friend in togetherFriends {
            guard let game = friend.presence?.game, game.joinable, game.sessionId != gameSession?.id, !gameInvites.contains(where: { $0.sessionId == game.sessionId }) else { continue }
            rows.append(PanelRow(id: "game-join-\(game.sessionId)", title: T.format(.gameJoin, friend.displayName, gameName(game.titleId)),
                                 detail: T.format(.gamePlayers, game.players, game.capacity), symbol: "gamecontroller.fill",
                                 kind: .action(destructive: false) { [weak self] in self?.joinFriendGame(game.sessionId, titleId: game.titleId, host: friend.displayName) },
                                 person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: .playing)))
        }
        if let session = gameSession, session.host?.userId == togetherUser?.id {
            let inside = Set(session.players.map(\.userId))
            let invitable = togetherFriends.filter { $0.presence?.online == true && !inside.contains($0.userId) }
            if !invitable.isEmpty {
                rows.append(PanelRow(id: "game-invite-title", title: T.format(.gameInviteTitle, gameName(session.titleId)), detail: T.format(.gamePlayers, session.players.count, session.capacity),
                                     symbol: "person.badge.plus", kind: .info("")))
                for friend in invitable {
                    rows.append(PanelRow(id: "game-invite-\(friend.userId)", title: T.format(.partyInvite, friend.displayName), detail: presenceText(friend.presence), symbol: "paperplane",
                                         kind: .action(destructive: false) { [weak self] in self?.inviteToGame(friend) },
                                         person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: friend.presence?.playing == true ? .playing : .online)))
                }
            }
        }
        return rows
    }

    func previewGameSession(_ session: TogetherGameSession?, invites: [TogetherGameInvite]) {
        gameSession = session
        gameInvites = invites
    }
}
