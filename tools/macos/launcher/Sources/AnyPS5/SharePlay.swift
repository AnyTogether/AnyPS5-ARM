import AnyPS5Core
import AnyPS5SharePlay
import AppKit
import SwiftUI

/// What the friends panel shows of share play.
struct ShareState {
    /// The share play the user hosts now.
    var hosting: TogetherSharePlay?
    /// Friends asking the user to watch.
    var invites: [TogetherShareInvite] = []
    var starting = false
    /// Each viewer's link, by user ID.
    var links: [String: SharePlayHost.Link] = [:]
}

/// A running share play's pieces: the WebRTC host, the capture feeding it, and the router that
/// lets only viewers with a pad reach the game.
@MainActor
final class ShareSession {
    let id: String
    let host: SharePlayHost
    let router: SharePadRouter
    let capture = SharePlayCapture()
    var viewers: [TogetherSharePlay.Viewer] = []
    var renewal: Task<Void, Never>?

    init(id: String, host: SharePlayHost, router: SharePadRouter) {
        self.id = id
        self.host = host
        self.router = router
    }
}

/// Bridges for a launcher without its phone server: pads go nowhere.
private final class NoBridges: SharePadBridges, @unchecked Sendable {
    func reservePadBridge() -> Int? { nil }
    func releasePadBridge(_ bridge: Int) {}
    func sendPad(_ data: Data, bridge: Int) {}
}

/// Share play, like Remote Play Together: while a game runs, the user shares it with friends, who
/// watch it live in a browser, on their phone or in their launcher; a viewer the user lets play
/// joins in as player 2, 3 or 4 with their own pad, while the user's pad stays player 1. The
/// picture and sound go from this Mac straight to each viewer (WebRTC); AnyTogether introduces
/// them.
extension AppModel {
    private static let openKey = "sharePlayOpen"
    private static let viewersKey = "sharePlayViewers"

    /// Friends may walk in without an invite.
    var shareOpensToFriends: Bool {
        get { UserDefaults.standard.object(forKey: AppModel.openKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: AppModel.openKey) }
    }

    /// How many may watch at once (the Mac uploads a stream each).
    var shareMaxViewers: Int {
        get { min(SharePlayRoster.maxViewers, max(1, UserDefaults.standard.object(forKey: AppModel.viewersKey) as? Int ?? 2)) }
        set { UserDefaults.standard.set(newValue, forKey: AppModel.viewersKey) }
    }

    // MARK: Hosting

    func startSharePlay() {
        guard let running, togetherUser != nil, shareSession == nil, !share.starting else { return }
        let game = running.game
        let pid = running.app.processIdentifier
        share.starting = true
        Task {
            defer { share.starting = false }
            do {
                let joined = try await together.startSharePlay(titleId: game.titleID, title: game.name, open: shareOpensToFriends, maxViewers: shareMaxViewers)
                guard self.running?.app.processIdentifier == pid else {
                    try? await together.endSharePlay(joined.sharePlay.id)
                    return
                }
                let session = makeShareSession(joined)
                shareSession = session
                applyShare(joined.sharePlay)
                renewShareRelays(session, expiresAt: joined.expiresAt)
                do {
                    try await session.capture.start(pid: pid, host: session.host)
                } catch RemotePlay.Failure.noPermission {
                    TrophyBanner.shared.notice(T.text(.remotePlayPermissionTitle), detail: T.text(.remotePlayNeedsPermission), symbol: "rectangle.on.rectangle", sounds: preferences.sounds)
                } catch {
                    RemoteServer.log.error("share play capture: \(String(describing: error), privacy: .public)")
                }
                show(SP.format(.started, game.name), symbol: "shareplay")
            } catch {
                show(SP.text(.couldNotStart) + ": \(error)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func makeShareSession(_ joined: TogetherSharePlayJoin) -> ShareSession {
        let id = joined.sharePlay.id
        let bridges: SharePadBridges = remote ?? NoBridges()
        let router = SharePadRouter(bridges: bridges)
        let host = SharePlayHost(iceServers: joined.iceServers, send: { [weak self] to, device, signal in
            self?.togetherSocket?.signal(to: to, device: device, share: id, kind: signal.kind, data: signal.data)
        }, onPad: { userId, packet in
            router.receive(packet, from: userId)
        }, changed: { [weak self] in
            guard let self, let session = self.shareSession, session.id == id else { return }
            self.share.links = session.host.links
        })
        // The game's vibration and light bar on a viewer's pad go back to that viewer.
        remote?.padOutput = { [weak host] bridge, data in
            guard let userId = router.viewer(onBridge: bridge) else { return }
            Task { @MainActor in host?.sendPadOutput(data, to: userId) }
        }
        return ShareSession(id: id, host: host, router: router)
    }

    /// The share play as the server has it now: newcomers are called, leavers hung up on, and the
    /// pads follow who holds them.
    func applyShare(_ sharePlay: TogetherSharePlay) {
        guard let session = shareSession, session.id == sharePlay.id else { return }
        let plan = SharePlayRoster.plan(from: session.viewers, to: sharePlay.viewers)
        for userId in plan.hangUp { session.host.hangUp(userId, sayBye: false) }
        for viewer in plan.call { session.host.call(viewer.user.userId, device: viewer.device) }
        session.router.update(pads: SharePlayRoster.pads(sharePlay.viewers))
        session.viewers = sharePlay.viewers
        withAnimation(Motion.overlay) { share.hosting = sharePlay }
    }

    /// New relay credentials ten minutes before the old ones end, for a long evening.
    private func renewShareRelays(_ session: ShareSession, expiresAt: Date?) {
        session.renewal?.cancel()
        guard let when = TogetherVoice.renewal(expiresAt: expiresAt) else { return }
        session.renewal = Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(max(1, when.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, let session, let renewed = try? await self.together.shareIceServers(session.id) else { return }
            session.host.renew(renewed.iceServers)
            self.renewShareRelays(session, expiresAt: renewed.expiresAt)
        }
    }

    func stopSharePlay() {
        guard let session = shareSession else { return }
        let client = together
        Task { try? await client.endSharePlay(session.id) }
        endShareSession()
        show(SP.text(.stopped), symbol: "shareplay.slash")
    }

    /// Everything of the share play here goes: connections, capture, the pads' bridges.
    func endShareSession() {
        guard let session = shareSession else { return }
        session.renewal?.cancel()
        session.capture.stop()
        session.host.close()
        session.router.releaseAll()
        remote?.padOutput = nil
        shareSession = nil
        withAnimation(Motion.overlay) {
            share.hosting = nil
            share.links = [:]
        }
    }

    /// A share play only while its game runs.
    func followSharePlay() {
        guard let session = shareSession else { return }
        if running == nil || session.capture.pid.map({ $0 != running?.app.processIdentifier }) == true { stopSharePlay() }
    }

    func letPlay(_ viewer: TogetherSharePlay.Viewer) {
        guard let session = shareSession, let pad = SharePlayRoster.freePad(session.viewers) else { return show(SP.text(.noPadFree), symbol: "gamecontroller") }
        Task {
            do {
                applyShare(try await together.setSharePad(viewer.user.userId, slot: pad, in: session.id))
                show(SP.format(.nowPlays, viewer.user.displayName, pad), symbol: "gamecontroller.fill")
            } catch {
                show("\(error)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func stopPlaying(_ viewer: TogetherSharePlay.Viewer) {
        guard let session = shareSession else { return }
        Task { if let updated = try? await together.setSharePad(viewer.user.userId, slot: nil, in: session.id) { applyShare(updated) } }
    }

    func removeShareViewer(_ viewer: TogetherSharePlay.Viewer) {
        guard let session = shareSession else { return }
        Task { try? await together.removeShareViewer(viewer.user.userId, from: session.id) }
    }

    func inviteToWatch(_ friend: TogetherFriend) {
        guard let session = shareSession else { return }
        Task {
            do {
                try await together.inviteToSharePlay([friend.userId], share: session.id)
                show(SP.format(.invited, friend.displayName), symbol: "paperplane.fill")
            } catch {
                show("\(error)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func setShareOpen(_ open: Bool) {
        shareOpensToFriends = open
        guard let session = shareSession else { return objectWillChange.send() }
        Task { if let updated = try? await together.updateSharePlay(session.id, open: open) { applyShare(updated) } }
    }

    func setShareMaxViewers(_ count: Int) {
        shareMaxViewers = count
        guard let session = shareSession, count >= session.viewers.count else { return objectWillChange.send() }
        Task { if let updated = try? await together.updateSharePlay(session.id, maxViewers: count) { applyShare(updated) } }
    }

    // MARK: Invites and events

    /// Invites waiting, and a share play a launcher that quit left behind.
    func loadShareInvites() {
        guard togetherUser != nil else { return }
        Task {
            guard let mine = try? await together.mySharePlay() else { return }
            withAnimation(Motion.overlay) { share.invites = mine.invites }
            if let stale = mine.hosting, stale.id != shareSession?.id { try? await together.endSharePlay(stale.id) }
        }
    }

    func declineShare(_ invite: TogetherShareInvite) {
        withAnimation(Motion.overlay) { share.invites.removeAll { $0.sharePlayId == invite.sharePlayId } }
        Task { try? await together.declineSharePlay(invite.sharePlayId) }
    }

    /// Watching happens on the website (or the phone): the share play's page opens in the browser.
    func watchShare(_ id: String) {
        let url = together.base.appendingPathComponent("watch").appendingPathComponent(id)
        NSWorkspace.shared.open(url)
    }

    func sharePlayEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "share_play.updated":
            guard let sharePlay = event.decode(TogetherSharePlay.self) else { return }
            applyShare(sharePlay)
        case "share_play.signal":
            guard let raw = event.decode(TogetherShareSignal.self), let session = shareSession, raw.sharePlayId == session.id,
                  let signal = ShareSignal(raw) else { return }
            session.host.receive(signal, from: raw.from, device: raw.device)
        case "share_play.invite":
            guard let invite = event.decode(TogetherShareInvite.self) else { return }
            share.invites.removeAll { $0.sharePlayId == invite.sharePlayId }
            withAnimation(Motion.overlay) { share.invites.append(invite) }
            let text = SP.format(.invitedYou, invite.from?.displayName ?? "", invite.title ?? gameName(invite.titleId))
            show(text, symbol: "shareplay")
            if !NSApp.isActive { TrophyBanner.shared.notice(text, detail: T.text(.friendsTitle), symbol: "shareplay", sounds: preferences.sounds) }
        case "share_play.ended":
            let id = event.data["sharePlayId"]
            withAnimation(Motion.overlay) { share.invites.removeAll { $0.sharePlayId == id } }
            // Ended from elsewhere (the website, another launcher): this one lets go too.
            if let session = shareSession, session.id == id { endShareSession() }
        default:
            break
        }
    }

    /// For the headless previews: a share play hosted, its links, and invites.
    func previewShare(_ hosting: TogetherSharePlay?, links: [String: SharePlayHost.Link] = [:], invites: [TogetherShareInvite] = []) {
        share = ShareState(hosting: hosting, invites: invites, starting: false, links: links)
    }

    // MARK: Panel rows

    /// Friends panel rows: share the game that runs, who watches and who plays, friends to invite;
    /// invites and friends' share plays to watch.
    func shareRows() -> [PanelRow] {
        var rows: [PanelRow] = []
        for invite in share.invites {
            let from = invite.from?.displayName ?? ""
            rows.append(PanelRow(id: "share-watch-\(invite.sharePlayId)", title: SP.format(.watchFriend, from, invite.title ?? gameName(invite.titleId)), detail: SP.text(.watchDetail),
                                 symbol: "play.tv", kind: .action(destructive: false) { [weak self] in self?.watchShare(invite.sharePlayId) },
                                 person: invite.from.map { PanelPerson(name: $0.displayName, avatar: $0.avatar, status: .playing) }))
            rows.append(PanelRow(id: "share-decline-\(invite.sharePlayId)", title: SP.format(.decline, from), symbol: "xmark.circle",
                                 kind: .action(destructive: true) { [weak self] in self?.declineShare(invite) }))
        }
        for friend in togetherFriends {
            guard let shared = friend.presence?.share, shared.open, !share.invites.contains(where: { $0.sharePlayId == shared.sharePlayId }) else { continue }
            rows.append(PanelRow(id: "share-friend-\(shared.sharePlayId)", title: SP.format(.watchFriend, friend.displayName, shared.title ?? gameName(shared.titleId)),
                                 detail: SP.format(.watching, shared.viewers, shared.maxViewers), symbol: "play.tv",
                                 kind: .action(destructive: false) { [weak self] in self?.watchShare(shared.sharePlayId) },
                                 person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: .playing)))
        }
        guard let hosting = share.hosting else {
            if let running {
                rows.append(PanelRow(id: "share-start", title: share.starting ? SP.text(.starting) : SP.format(.start, running.game.name), detail: SP.text(.startDetail),
                                     symbol: "shareplay", kind: .action(destructive: false) { [weak self] in self?.startSharePlay() }))
            }
            return rows
        }
        rows.append(PanelRow(id: "share-on", title: SP.format(.sharing, hosting.title ?? gameName(hosting.titleId)), detail: SP.format(.watching, hosting.viewers.count, hosting.maxViewers),
                             symbol: "shareplay", kind: .info("")))
        for viewer in hosting.viewers {
            let name = viewer.user.displayName
            let person = PanelPerson(name: name, avatar: viewer.user.avatar, status: viewer.slot == nil ? .online : .playing)
            let link = share.links[viewer.user.userId]
            if let pad = viewer.slot {
                let bridge = shareSession?.router.bridge(of: viewer.user.userId)
                let player = bridge.flatMap { remote?.padPlayer(bridge: $0) }
                rows.append(PanelRow(id: "share-stop-\(viewer.user.userId)", title: SP.format(.stopPlaying, name), detail: SP.linkText(link, pad: player ?? pad, seated: player != nil),
                                     symbol: "gamecontroller.fill", kind: .action(destructive: false) { [weak self] in self?.stopPlaying(viewer) }, person: person))
            } else {
                rows.append(PanelRow(id: "share-play-\(viewer.user.userId)", title: SP.format(.letPlay, name, SharePlayRoster.freePad(hosting.viewers) ?? 0),
                                     detail: SP.linkText(link, pad: nil, seated: false), symbol: "gamecontroller",
                                     kind: .action(destructive: false) { [weak self] in self?.letPlay(viewer) }, person: person))
            }
            rows.append(PanelRow(id: "share-remove-\(viewer.user.userId)", title: SP.format(.remove, name), symbol: "person.crop.circle.badge.xmark",
                                 kind: .action(destructive: true) { [weak self] in self?.removeShareViewer(viewer) }))
        }
        rows.append(PanelRow(id: "share-open", title: SP.text(.openToFriends), detail: SP.text(.openToFriendsDetail), symbol: "person.2",
                             kind: .toggle(hosting.open) { [weak self] on in self?.setShareOpen(on) }))
        rows.append(PanelRow(id: "share-max", title: SP.text(.maxViewers), detail: SP.text(.maxViewersDetail), symbol: "person.3.sequence",
                             kind: .stepper(value: hosting.maxViewers, range: max(1, hosting.viewers.count) ... SharePlayRoster.maxViewers, step: 1, format: { "\($0)" }) { [weak self] count in
                                 self?.setShareMaxViewers(count)
                             }))
        let watching = Set(hosting.viewers.map(\.user.userId))
        let invited = Set((hosting.invited ?? []).map(\.userId))
        for friend in togetherFriends where friend.presence?.online == true && !watching.contains(friend.userId) {
            rows.append(PanelRow(id: "share-invite-\(friend.userId)", title: SP.format(.invite, friend.displayName),
                                 detail: invited.contains(friend.userId) ? SP.text(.invitedAlready) : presenceText(friend.presence), symbol: "paperplane",
                                 kind: .action(destructive: false) { [weak self] in self?.inviteToWatch(friend) },
                                 person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: friend.presence?.playing == true ? .playing : .online)))
        }
        rows.append(PanelRow(id: "share-stop", title: SP.text(.stop), symbol: "stop.circle", kind: .action(destructive: true) { [weak self] in self?.stopSharePlay() }))
        return rows
    }
}

/// Share play's texts, in both languages.
enum SP {
    enum Key {
        case start, startDetail, starting, started, couldNotStart, sharing, watching, letPlay, stopPlaying, remove, invite, invitedAlready, invited
        case openToFriends, openToFriendsDetail, maxViewers, maxViewersDetail, stop, stopped, noPadFree, nowPlays, invitedYou, watchFriend, watchDetail, decline
        case player, onlyWatches, connecting, direct, relayed, roundTrip
    }

    static func text(_ key: Key) -> String { (T.language == .turkish ? turkish : english)[key] ?? english[key] ?? "" }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// A viewer's line: player or watching, the path and its round trip.
    static func linkText(_ link: SharePlayHost.Link?, pad: Int?, seated: Bool) -> String {
        var parts = [pad.map { format(.player, $0) } ?? text(.onlyWatches)]
        guard let link, link.state == .connected else { return (parts + [text(.connecting)]).joined(separator: " · ") }
        if let relayed = link.relayed { parts.append(text(relayed ? .relayed : .direct)) }
        if let roundTrip = link.roundTrip { parts.append(format(.roundTrip, Int(roundTrip.rounded()))) }
        if let fps = link.framesPerSecond, let height = link.frameHeight { parts.append("\(height)p\(Int(fps.rounded()))") }
        return parts.joined(separator: " · ")
    }

    static let english: [Key: String] = [
        .start: "Share play: %@",
        .startDetail: "Friends watch live; let one play as player 2, 3 or 4",
        .starting: "Starting share play…",
        .started: "Sharing %@",
        .couldNotStart: "Share play did not start",
        .sharing: "Sharing %@",
        .watching: "%d of %d watching",
        .letPlay: "Let %@ play as player %d",
        .stopPlaying: "Stop %@ playing",
        .remove: "Take %@ out",
        .invite: "Invite %@ to watch",
        .invitedAlready: "Invited",
        .invited: "%@ is invited to watch",
        .openToFriends: "Friends can walk in",
        .openToFriendsDetail: "Off: only friends you invite",
        .maxViewers: "Viewers at most",
        .maxViewersDetail: "Your Mac uploads a stream to each; from 3 on each gets 540p",
        .stop: "Stop share play",
        .stopped: "Share play stopped",
        .noPadFree: "Players 2 to 4 are all taken",
        .nowPlays: "%@ plays as player %d",
        .invitedYou: "%@ shares %@ with you",
        .watchFriend: "Watch %@ play %@",
        .watchDetail: "Opens in your browser",
        .decline: "Not now, %@",
        .player: "Player %d",
        .onlyWatches: "Watching",
        .connecting: "Connecting",
        .direct: "Direct",
        .relayed: "Through the relay",
        .roundTrip: "%d ms",
    ]

    static let turkish: [Key: String] = [
        .start: "Birlikte oyna: %@",
        .startDetail: "Arkadaşların canlı izler; birini 2., 3. ya da 4. oyuncu yap",
        .starting: "Birlikte oyna başlıyor…",
        .started: "%@ paylaşılıyor",
        .couldNotStart: "Birlikte oyna başlamadı",
        .sharing: "%@ paylaşılıyor",
        .watching: "%d/%d izliyor",
        .letPlay: "%@, %d. oyuncu olsun",
        .stopPlaying: "%@ artık oynamasın",
        .remove: "%@ kişisini çıkar",
        .invite: "%@ kişisini izlemeye davet et",
        .invitedAlready: "Davet edildi",
        .invited: "%@ izlemeye davet edildi",
        .openToFriends: "Arkadaşlar davetsiz girebilir",
        .openToFriendsDetail: "Kapalıyken yalnızca davet ettiklerin",
        .maxViewers: "En çok izleyici",
        .maxViewersDetail: "Mac her birine ayrı yayın gönderir; 3 ve üstünde her biri 540p alır",
        .stop: "Birlikte oynamayı durdur",
        .stopped: "Birlikte oyna durdu",
        .noPadFree: "2. ile 4. oyuncu arası dolu",
        .nowPlays: "%@ artık %d. oyuncu",
        .invitedYou: "%@ seninle %@ paylaşıyor",
        .watchFriend: "İzle: %@, %@",
        .watchDetail: "Tarayıcında açılır",
        .decline: "Şimdi değil, %@",
        .player: "%d. oyuncu",
        .onlyWatches: "İzliyor",
        .connecting: "Bağlanıyor",
        .direct: "Doğrudan",
        .relayed: "Aktarıcı üzerinden",
        .roundTrip: "%d ms",
    ]
}
