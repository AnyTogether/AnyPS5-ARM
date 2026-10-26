import AnyPS5Core
import AppKit
import SwiftUI

/// Play Together: in a party, the host picks a game and starts it for the party; the others get
/// "<host> started <game> — Join", Join checks they have the same game and version (unlocking or
/// updating it first where that helps) and starts it here in the same session with online play
/// on, so the WebRTC mesh joins the virtual LAN and the host's game finds them by broadcast. The
/// party panel shows who plays and how each player is reached; it ends when the host quits.
extension AppModel {
    /// How many play together at most: the party's size.
    static let togetherCapacity = TogetherParty.maxSize

    /// This Mac's copies of every game, for the join check.
    func togetherCopies() -> [PlayTogetherCheck.Copy] {
        games.map { game in
            let unlocked = installedRecords[game.id] != nil
            let current = engineBuild(for: game)
            let next = engineVersion(for: game).map(TogetherGameSession.engineBuild)
            return PlayTogetherCheck.Copy(id: game.id, titleId: game.titleID, gameVersion: gameVersion(for: game), engineBuild: current, unlocked: unlocked,
                                          nextEngineBuild: unlocked && next != current ? next : nil)
        }
    }

    /// The party's Play Together game as an offer to join.
    func togetherOffer(_ together: TogetherPartyTogether, in party: TogetherParty) -> PlayTogetherOffer {
        let host = party.members.first { $0.userId == together.hostId }
        return PlayTogetherOffer(sessionId: together.sessionId, hostId: together.hostId, hostName: host.map { shown($0).name } ?? "", titleId: together.titleId,
                                 gameVersion: together.gameVersion, engineBuild: together.engineBuild, versionRule: together.versionRule,
                                 players: together.players.count, capacity: together.capacity)
    }

    // MARK: Hosting

    /// The host's Play Together: a LAN session in the party, then the game with online play on.
    func startPlayTogether(_ game: Game) {
        guard togetherUser != nil, party != nil else { return }
        if let running { return show(PT.format(.closeFirst, running.game.name), symbol: "xmark.app") }
        guard case .installed = state(of: game) else { return show(T.format(.gameUnlockFirst, game.name), symbol: "lock.fill") }
        show(PT.format(.starting, game.name), symbol: "person.2.wave.2.fill")
        Task {
            do {
                let session = try await together.startPlayTogether(titleId: game.titleID, gameVersion: gameVersion(for: game), engineBuild: engineBuild(for: game),
                                                                   capacity: AppModel.togetherCapacity)
                enterTogether(session, game: game)
                show(PT.format(.started, game.name), symbol: "person.2.wave.2.fill")
            } catch let problem as TogetherProblem where problem.code == "conflict" {
                show(PT.text(.alreadyRunning), symbol: "person.3.fill")
            } catch {
                show(PT.text(.startFailed) + ": " + togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// In the session: the engine bridge and the mesh follow it, online play is on for the next
    /// start only, and the game starts. A session whose game never ran ends again.
    private func enterTogether(_ session: TogetherGameSession, game: Game) {
        guard let me = togetherUser?.id else { return }
        keepSession(session, me: me)
        OnlinePlayHost.playTogether(sessionId: session.id)
        playTogetherOffers.removeAll { $0.sessionId == session.id }
        if overlay != nil { closeOverlay() }
        selected = games.firstIndex(of: game) ?? selected
        play(game)
        pollTogetherLinks()
        Task {
            try? await Task.sleep(for: .seconds(120))
            guard gameSession?.id == session.id, running == nil, starting == nil else { return }
            OnlinePlayHost.stop()
            followGameSession()
        }
    }

    // MARK: Joining

    /// Join from the party or the offer: the check first, then the game in the same session. After
    /// Try anyway the check looks past the game version (never the engine).
    func joinPlayTogether(_ offer: PlayTogetherOffer, afterUnlock: Bool = false) {
        let verdict = PlayTogetherCheck.verdict(offer, signedIn: togetherUser != nil, copies: togetherCopies(), running: running?.game.name,
                                                overrideVersion: togetherTryAnyway.contains(offer.sessionId))
        switch verdict {
        case .join(let id):
            guard let game = games.first(where: { $0.id == id }) else { return }
            joinTogether(offer, game: game)
        case .unlockAndPlay(let id), .updateAndPlay(let id):
            guard !afterUnlock, let game = games.first(where: { $0.id == id }) else {
                return show(PT.text(.startFailed), symbol: "exclamationmark.triangle.fill")
            }
            togetherAfterUnlock = (id, offer)
            if case .unlockAndPlay = verdict { show(PT.format(.unlockingFirst, game.name), symbol: "lock.open") } else { show(PT.format(.updatingFirst, game.name), symbol: "arrow.triangle.2.circlepath") }
            unlock(game)
        default:
            show(verdictText(verdict, offer: offer) ?? "", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// An unlock finished: the join waiting on it goes on (or is dropped when it failed).
    func togetherUnlockDone(_ id: String, succeeded: Bool) {
        guard let (waiting, offer) = togetherAfterUnlock, waiting == id else { return }
        togetherAfterUnlock = nil
        if succeeded { joinPlayTogether(offer, afterUnlock: true) }
    }

    /// Try anyway: the user chose to join with a game version that does not fit; the server
    /// records it and still checks the engine.
    func tryAnywayPlayTogether(_ offer: PlayTogetherOffer) {
        togetherTryAnyway.insert(offer.sessionId)
        joinPlayTogether(offer)
    }

    /// Only the game version keeps this Mac out, here or as the server said.
    func canTryAnyway(_ offer: PlayTogetherOffer) -> Bool {
        if PlayTogetherCheck.tryAnyway(offer, signedIn: togetherUser != nil, copies: togetherCopies(), running: running?.game.name) != nil { return true }
        guard togetherVersionRefused.contains(offer.sessionId) else { return false }
        switch PlayTogetherCheck.verdict(offer, signedIn: togetherUser != nil, copies: togetherCopies(), running: running?.game.name, overrideVersion: true) {
        case .join, .unlockAndPlay, .updateAndPlay: return true
        default: return false
        }
    }

    /// The engine build this Mac would play a title with (previews match it to show Try Anyway).
    func previewEngineBuild(_ titleId: String) -> String? {
        togetherCopies().first { $0.titleId == titleId }?.engineBuild
    }

    /// The Try Anyway row for an offer, when it can help.
    func tryAnywayRow(_ offer: PlayTogetherOffer, id: String) -> PanelRow? {
        guard canTryAnyway(offer) else { return nil }
        return PanelRow(id: id, title: PT.text(.tryAnyway), detail: PT.text(.tryAnywayDetail), symbol: "exclamationmark.arrow.triangle.2.circlepath",
                        kind: .action(destructive: false) { [weak self] in self?.tryAnywayPlayTogether(offer) })
    }

    private func joinTogether(_ offer: PlayTogetherOffer, game: Game) {
        let anyway = togetherTryAnyway.contains(offer.sessionId)
        show(anyway ? PT.format(.tryingAnyway, game.name) : PT.format(.joined, offer.hostName, game.name), symbol: "person.2.wave.2.fill")
        Task {
            do {
                let joined = try await together.joinGameSession(offer.sessionId, gameVersion: gameVersion(for: game), engineBuild: engineBuild(for: game),
                                                                overrideVersion: anyway)
                togetherTryAnyway.remove(offer.sessionId)
                enterTogether(joined, game: game)
            } catch let problem as TogetherProblem {
                if let refusal = problem.joinRefusal {
                    // The party panel offers Try Anyway for a version the server would let by on request.
                    if refusal.overridable, !anyway { togetherVersionRefused.insert(offer.sessionId) }
                    let verdict: PlayTogetherVerdict = refusal.reason == .engine
                        ? .engine(have: refusal.actual, need: refusal.expected, youUpdate: refusal.youUpdate)
                        : .gameVersion(have: refusal.actual, need: refusal.expected, youUpdate: refusal.youUpdate)
                    show(verdictText(verdict, offer: offer) ?? problem.title, symbol: "exclamationmark.triangle.fill")
                } else if problem.code == "full" {
                    show(PT.text(.full), symbol: "person.3.fill")
                } else {
                    show(togetherMessage(problem), symbol: "exclamationmark.triangle.fill")
                }
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// What blocks a join, in words; nil for a way in.
    func verdictText(_ verdict: PlayTogetherVerdict, offer: PlayTogetherOffer) -> String? {
        let name = gameName(offer.titleId)
        switch verdict {
        case .join, .unlockAndPlay, .updateAndPlay: return nil
        case .signIn: return PT.text(.signIn)
        case .missing: return PT.format(.missing, name)
        case .gameVersion(let have, let need, let you):
            return you ? PT.format(.versionYou, name, need, have) : PT.format(.versionHost, offer.hostName, need, have)
        case .engine(let have, let need, let you):
            return you ? PT.format(.engineYou, offer.hostName, AppModel.release(need), AppModel.release(have))
                : PT.format(.engineHost, offer.hostName, AppModel.release(need), AppModel.release(have))
        case .closeFirst(let running): return PT.format(.closeFirst, running)
        case .full: return PT.text(.full)
        }
    }

    // MARK: Leaving

    /// The host ends it for everyone; a player leaves it (their game keeps running, alone).
    func leavePlayTogether() {
        guard let session = gameSession, session.together, let me = togetherUser?.id else { return }
        let client = together
        keepSession(nil, me: me)
        peerLinks = [:]
        Task {
            if session.host?.userId == me { try? await client.endGameSession(session.id) } else { try? await client.leaveGameSession(session.id) }
        }
        show(PT.text(.endedYours), symbol: "gamecontroller")
    }

    /// The host's join code for the game, copied for someone outside the party.
    func shareTogetherCode() {
        guard let session = gameSession, session.together else { return }
        Task {
            do {
                let code = try await together.gameSessionCode(session.id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.url, forType: .string)
                show(PT.format(.codeCopied, code.display), symbol: "doc.on.doc")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Peers

    /// How each other player is reached, every few seconds while the user plays together.
    func pollTogetherLinks() {
        togetherLinkPoll?.cancel()
        togetherLinkPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.gameSession?.together == true else { break }
                if let play = OnlinePlayHost.running {
                    let links = await withCheckedContinuation { (done: CheckedContinuation<[OnlinePeerLinkInfo], Never>) in play.links { done.resume(returning: $0) } }
                    self.peerLinks = Dictionary(links.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
                }
                try? await Task.sleep(for: .seconds(3))
            }
            self?.peerLinks = [:]
        }
    }

    /// "Direct · 23 ms", "Relay · 80 ms", "Connecting…" for another player in the session.
    func linkText(_ userId: String) -> String {
        guard let link = peerLinks[userId] else { return PT.text(.connecting) }
        let route: String
        switch link.route {
        case .connecting: return PT.text(.connecting)
        case .failed: return PT.text(.unreachable)
        case .direct: route = PT.text(.direct)
        case .relay: route = PT.text(.relay)
        }
        return link.rttMs.map { route + " · " + PT.format(.ms, $0) } ?? route
    }

    // MARK: Rows

    /// The party panel's Play Together: the game running (who plays, how each is reached, Join,
    /// Leave or End, the host's code), or Play Together for the game selected on Home.
    func togetherRows(_ party: TogetherParty, me: String) -> [PanelRow] {
        guard let together = party.together else {
            guard let game = selectedGame, running == nil else {
                return [PanelRow(id: "together-pick", title: PT.text(.pickGame), detail: PT.text(.pickGameDetail), symbol: "person.2.wave.2", kind: .info(""))]
            }
            return [PanelRow(id: "together-start", title: PT.format(.start, game.name), detail: PT.text(.startDetail), symbol: "person.2.wave.2.fill",
                             kind: .action(destructive: false) { [weak self] in self?.startPlayTogether(game) })]
        }
        let offer = togetherOffer(together, in: party)
        let mine = gameSession?.id == together.sessionId
        let hosting = together.hostId == me
        var rows = [PanelRow(id: "together-title", title: PT.format(.title, gameName(together.titleId), together.players.count, together.capacity),
                             detail: PT.format(.titleDetail, offer.hostName, together.gameVersion), symbol: "person.2.wave.2.fill", kind: .info(""))]
        let byId = Dictionary(party.members.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
        for userId in together.players {
            guard let person = byId[userId] ?? gameSession?.players.first(where: { $0.userId == userId }) else { continue }
            var details: [String] = []
            if userId == together.hostId { details.append(PT.text(.host)) }
            details.append(userId == me ? PT.text(.you) : mine ? linkText(userId) : PT.text(.inGame))
            if together.versionOverrides.contains(userId) { details.append(PT.text(.triedAnyway)) }
            // A friend's private name with their handle; the user's own and strangers' public ones.
            let identity = userId == me ? nil : shown(person)
            if let identity { details.insert(handleLine(person), at: 0) }
            rows.append(PanelRow(id: "together-player-\(userId)", title: identity?.name ?? person.displayName, detail: details.joined(separator: " · "), symbol: "gamecontroller",
                                 kind: .info(""), person: identity == nil ? PanelPerson(name: person.displayName, avatar: person.avatar, status: .playing) : panelPerson(person, status: .playing)))
        }
        if !mine {
            let verdict = PlayTogetherCheck.verdict(offer, signedIn: true, copies: togetherCopies(), running: running?.game.name)
            let title: String
            switch verdict {
            case .unlockAndPlay: title = PT.text(.unlockAndPlay)
            case .updateAndPlay: title = PT.text(.updateAndPlay)
            default: title = PT.format(.joinRow, offer.hostName, gameName(together.titleId))
            }
            rows.append(PanelRow(id: "together-join", title: title, detail: verdictText(verdict, offer: offer) ?? PT.text(.joinDetail), symbol: "play.circle.fill",
                                 kind: .action(destructive: false) { [weak self] in self?.joinPlayTogether(offer) }))
            if let anyway = tryAnywayRow(offer, id: "together-try-anyway") { rows.append(anyway) }
        } else {
            if hosting {
                rows.append(PanelRow(id: "together-code", title: PT.text(.code), detail: PT.text(.codeDetail), symbol: "ticket",
                                     kind: .action(destructive: false) { [weak self] in self?.shareTogetherCode() }))
            }
            rows += askingFirst(PanelRow(id: "together-leave", title: hosting ? PT.text(.end) : PT.text(.leave), symbol: "xmark.circle",
                                         kind: .action(destructive: true) { [weak self] in self?.leavePlayTogether() }),
                                question: TK.text(hosting ? .askEndTogether : .askLeaveTogether))
        }
        return rows
    }

    /// The friends panel's offers: "<host> started <game> — Join".
    func togetherOfferRows() -> [PanelRow] {
        playTogetherOffers.filter { $0.sessionId != gameSession?.id }.flatMap { offer in
            [PanelRow(id: "together-offer-\(offer.sessionId)", title: PT.format(.offer, offer.hostName, gameName(offer.titleId)), detail: PT.text(.joinDetail),
                      symbol: "person.2.wave.2.fill", kind: .action(destructive: false) { [weak self] in self?.joinPlayTogether(offer) })]
                + [tryAnywayRow(offer, id: "together-offer-anyway-\(offer.sessionId)")].compactMap { $0 }
        }
    }

    // MARK: Events

    /// game_session.started: someone in the party started Play Together.
    func togetherStarted(_ event: TogetherSocket.Event) {
        struct Started: Decodable { let partyId: String; let session: TogetherGameSession }
        guard let started = event.decode(Started.self), started.session.host?.userId != togetherUser?.id else { return }
        let offer = PlayTogetherOffer(session: started.session)
        withAnimation(Motion.overlay) {
            playTogetherOffers.removeAll { $0.sessionId == offer.sessionId }
            playTogetherOffers.append(offer)
        }
        let text = PT.format(.offer, offer.hostName, gameName(offer.titleId))
        show(text, symbol: "person.2.wave.2.fill")
        if !NSApp.isActive { TrophyBanner.shared.notice(text, detail: PT.text(.offerDetail), symbol: "person.2.wave.2.fill", sounds: preferences.sounds) }
        loadParty()
    }

    /// game_session.ended: the offer goes; in it, the host's game is gone (the game keeps running).
    func togetherEnded(_ sessionId: String?) {
        withAnimation(Motion.overlay) { playTogetherOffers.removeAll { $0.sessionId == sessionId } }
        if gameSession?.id == sessionId { peerLinks = [:] }
    }
}
