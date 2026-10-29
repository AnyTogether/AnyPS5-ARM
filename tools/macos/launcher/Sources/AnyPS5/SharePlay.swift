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
    /// The friend's share play the user watches here, whether its picture comes, and how well.
    var watching: TogetherSharePlay?
    var watchConnected = false
    var watchStats: WatchStats?

    struct WatchStats: Equatable {
        var roundTrip: Double?
        var fps: Double?
        var height: Int?
    }
}

/// A running share play's pieces: the WebRTC host, the capture feeding it, and the router that
/// lets only viewers with a pad reach the game.
@MainActor
final class ShareSession {
    let id: String
    let host: SharePlayHost
    let router: SharePadRouter
    let capture = SharePlayCapture()
    let awake = Awake("Share play")
    var viewers: [TogetherSharePlay.Viewer] = []
    var renewal: Task<Void, Never>?

    init(id: String, host: SharePlayHost, router: SharePadRouter) {
        self.id = id
        self.host = host
        self.router = router
        awake.hold()
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
        guard let running, togetherUser != nil, shareSession == nil, !share.starting, familyPermits(.sharePlay) else { return }
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
        session.awake.release()
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

    func sharePlayEvent(_ event: TogetherSocket.Event) {
        if watchEvent(event) { return }
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
            discoverEvent(event)
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
        rows += shareRequestRows(hosting)
        rows += shareCodeRows(hosting)
        for viewer in hosting.viewers {
            let name = viewer.user.displayName
            let person = PanelPerson(name: name, avatar: viewer.user.avatar, status: viewer.slot == nil ? .online : .playing)
            let link = share.links[viewer.user.userId]
            if let pad = viewer.slot {
                let bridge = shareSession?.router.bridge(of: viewer.user.userId)
                let player = bridge.flatMap { remote?.padPlayer(bridge: $0) }
                rows.append(PanelRow(id: "share-stop-\(viewer.user.userId)", title: SP.format(.stopPlaying, name), detail: SP.linkText(link, pad: player ?? pad, seated: player != nil),
                                     symbol: "gamecontroller.fill", kind: .action(destructive: false) { [weak self] in self?.stopPlaying(viewer) }, person: person))
                if let assist = shareAssistRow(viewer.user.userId, name: name) { rows.append(assist) }
            } else {
                rows.append(PanelRow(id: "share-play-\(viewer.user.userId)", title: SP.format(.letPlay, name, SharePlayRoster.freePad(hosting.viewers) ?? 0),
                                     detail: SP.linkText(link, pad: nil, seated: false), symbol: "gamecontroller",
                                     kind: .action(destructive: false) { [weak self] in self?.letPlay(viewer) }, person: person))
            }
            rows += askingFirst(PanelRow(id: "share-remove-\(viewer.user.userId)", title: SP.format(.remove, name), symbol: "person.crop.circle.badge.xmark",
                                         kind: .action(destructive: true) { [weak self] in self?.removeShareViewer(viewer) }),
                                question: TK.format(.askRemoveViewer, name))
        }
        rows.append(PanelRow(id: "share-open", title: SP.text(.openToFriends), detail: SP.text(.openToFriendsDetail), symbol: "person.2",
                             kind: .toggle(hosting.open) { [weak self] on in self?.setShareOpen(on) }))
        rows.append(PanelRow(id: "share-max", title: SP.text(.maxViewers), detail: SP.text(.maxViewersDetail), symbol: "person.3.sequence",
                             kind: .stepper(value: hosting.maxViewers, range: max(1, hosting.viewers.count) ... SharePlayRoster.maxViewers, step: 1, format: { "\($0)" }) { [weak self] count in
                                 self?.setShareMaxViewers(count)
                             }))
        rows += shareListingRows(hosting)
        let watching = Set(hosting.viewers.map(\.user.userId))
        let invited = Set((hosting.invited ?? []).map(\.userId))
        for friend in togetherFriends where friend.presence?.online == true && !watching.contains(friend.userId) {
            rows.append(PanelRow(id: "share-invite-\(friend.userId)", title: SP.format(.invite, friend.displayName),
                                 detail: invited.contains(friend.userId) ? SP.text(.invitedAlready) : presenceText(friend.presence), symbol: "paperplane",
                                 kind: .action(destructive: false) { [weak self] in self?.inviteToWatch(friend) },
                                 person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: friend.presence?.playing == true ? .playing : .online)))
        }
        rows += askingFirst(PanelRow(id: "share-stop", title: SP.text(.stop), symbol: "stop.circle", kind: .action(destructive: true) { [weak self] in self?.stopSharePlay() }),
                            question: TK.text(.askStopShare))
        return rows
    }
}

/// Listing the share play in public, and answering who asked to watch.
extension AppModel {
    func shareRequestRows(_ hosting: TogetherSharePlay) -> [PanelRow] {
        (hosting.requests ?? []).flatMap { person -> [PanelRow] in
            [
                PanelRow(id: "share-request-accept-\(person.userId)", title: FP.format(.letWatch, person.displayName),
                         detail: (["@\(person.handle)"] + (codeAskers.contains(person.userId) ? [JS.text(.withCode)] : [])).joined(separator: " · "),
                         symbol: "person.crop.circle.badge.checkmark", kind: .action(destructive: false) { [weak self] in self?.answerShareRequest(person, accept: true) },
                         person: PanelPerson(name: person.displayName, avatar: person.avatar)),
                PanelRow(id: "share-request-decline-\(person.userId)", title: FP.format(.notNow, person.displayName), symbol: "xmark.circle",
                         kind: .action(destructive: true) { [weak self] in self?.answerShareRequest(person, accept: false) }),
            ]
        }
    }

    func shareListingRows(_ hosting: TogetherSharePlay) -> [PanelRow] {
        guard familyAllows(.publicMatchmaking) else { return [] }
        let joins: [TogetherPublicJoin?] = [nil, .request, .open]
        let listing = hosting.listing
        var rows = [
            PanelRow(id: "share-public", title: FP.text(.listPublic), detail: FP.text(.listPublicDetail), symbol: "globe",
                     kind: .choice(options: [FP.text(.listOff), FP.text(.listAsk), FP.text(.listOpenWatch)], selected: joins.firstIndex(of: listing?.join) ?? 0) { [weak self] index in
                         self?.listShare(joins[index].map { TogetherShareListing(join: $0, language: listing?.language, live: listing?.live ?? ($0 == .open)) })
                     }),
        ]
        guard let listing else { return rows }
        if listing.join == .open {
            rows.append(PanelRow(id: "share-live", title: FP.text(.liveToggle), detail: FP.text(.liveToggleDetail), symbol: "dot.radiowaves.left.and.right",
                                 kind: .toggle(listing.live) { [weak self] value in self?.listShare(TogetherShareListing(join: listing.join, language: listing.language, live: value)) }))
        }
        let languages: [String?] = [nil] + TogetherLanguages.common
        rows.append(PanelRow(id: "share-language", title: FP.text(.listLanguage), symbol: "character.bubble",
                             kind: .choice(options: languages.map { $0.map { TogetherLanguages.name($0, in: lang) } ?? FP.text(.anyLanguage) },
                                           selected: languages.firstIndex(of: listing.language) ?? 0) { [weak self] index in
                                 self?.listShare(TogetherShareListing(join: listing.join, language: languages[index], live: listing.live))
                             }))
        return rows
    }

    func listShare(_ listing: TogetherShareListing?) {
        guard let session = shareSession else { return }
        Task {
            do {
                applyShare(try await together.setShareListing(session.id, listing))
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func answerShareRequest(_ person: TogetherPerson, accept: Bool) {
        guard let session = shareSession else { return }
        Task {
            do {
                applyShare(try await together.answerShareRequest(session.id, user: person.userId, accept: accept))
                if accept { show(SP.format(.invited, person.displayName), symbol: "paperplane.fill") }
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}

/// Share play's texts, from the language files (l10n).
enum SP {
    enum Key: String, CaseIterable {
        case start = "sharePlayStart", startDetail = "sharePlayStartDetail", starting = "sharePlayStarting", started = "sharePlayStarted", couldNotStart = "sharePlayCouldNotStart", sharing = "sharePlaySharing", watching = "sharePlayWatching", letPlay = "sharePlayLetPlay", stopPlaying = "sharePlayStopPlaying", remove = "sharePlayRemove", invite = "sharePlayInvite", invitedAlready = "sharePlayInvitedAlready", invited = "sharePlayInvited"
        case openToFriends = "sharePlayOpenToFriends", openToFriendsDetail = "sharePlayOpenToFriendsDetail", maxViewers = "sharePlayMaxViewers", maxViewersDetail = "sharePlayMaxViewersDetail", stop = "sharePlayStop", stopped = "sharePlayStopped", noPadFree = "sharePlayNoPadFree", nowPlays = "sharePlayNowPlays", invitedYou = "sharePlayInvitedYou", watchFriend = "sharePlayWatchFriend", watchDetail = "sharePlayWatchDetail", decline = "sharePlayDecline"
        case player = "sharePlayPlayer", onlyWatches = "sharePlayOnlyWatches", connecting = "sharePlayConnecting", direct = "sharePlayDirect", relayed = "sharePlayRelayed", roundTrip = "sharePlayRoundTrip"
        case full = "sharePlayFull", couldNotWatch = "sharePlayCouldNotWatch", youPlay = "sharePlayYouPlay", youWatch = "sharePlayYouWatch", tookYouOut = "sharePlayTookYouOut", hostStopped = "sharePlayHostStopped", leave = "sharePlayLeave"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
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
}
