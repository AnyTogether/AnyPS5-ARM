import AnyPS5Core
import AnyPS5MediaServer
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Parties on AnyTogether: start one (invite only, or open to friends), invite friends, see who
/// is in it, accept an invite or walk into a friend's open party, leave. The socket's party
/// events keep it current; friends see the party in presence.
extension AppModel {
    func partyRows() -> [PanelRow] {
        guard let me = togetherUser else {
            return [
                PanelRow(id: "party-out", title: T.text(.friendsSignIn), detail: T.text(.togetherIntroDetail), symbol: "person.3", kind: .info("")),
                PanelRow(id: "party-signin", title: T.text(.togetherSignIn), symbol: "person.crop.circle.badge.plus", kind: .action(destructive: false) { [weak self] in
                    self?.openTogetherSettings()
                }),
            ]
        }
        var rows: [PanelRow] = []
        for invite in partyInvites where invite.partyId != party?.id {
            let name = invite.from?.displayName ?? "?"
            rows.append(PanelRow(id: "party-accept-\(invite.partyId)", title: T.format(.partyJoinOf, name), detail: T.format(.partySize, invite.size, max(invite.size, mediaLimits?.sfu == true ? mediaLimits?.maxPartySize ?? TogetherParty.maxSize : TogetherParty.maxSize)),
                                 symbol: "person.3.fill", kind: .action(destructive: false) { [weak self] in self?.joinParty(invite.partyId) },
                                 person: invite.from.map { PanelPerson(name: $0.displayName, avatar: $0.avatar) }))
            rows.append(PanelRow(id: "party-decline-\(invite.partyId)", title: T.format(.partyDecline, name), symbol: "xmark.circle",
                                 kind: .action(destructive: true) { [weak self] in self?.declineParty(invite.partyId) }))
        }
        guard let party else {
            rows.append(PanelRow(id: "party-start", title: T.text(.partyStart), detail: T.text(.partyStartDetail), symbol: "plus.circle", kind: .action(destructive: false) { [weak self] in
                self?.startParty()
            }))
            rows.append(PanelRow(id: "party-open", title: T.text(.partyOpen), detail: T.text(.partyOpenDetail), symbol: "door.left.hand.open", kind: .toggle(partyStartsOpen) { [weak self] value in
                self?.partyStartsOpen = value
            }))
            // Friends whose party is open to them.
            for friend in togetherFriends {
                guard let open = friend.presence?.party, open.open, open.size < open.max else { continue }
                rows.append(PanelRow(id: "party-walkin-\(open.id)", title: T.format(.partyJoinOf, friend.displayName), detail: T.format(.partySize, open.size, open.max),
                                     symbol: "person.3", kind: .action(destructive: false) { [weak self] in self?.joinParty(open.id) },
                                     person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: .online)))
            }
            if rows.count == 2 { rows.append(PanelRow(id: "party-none", title: T.text(.partyNone), symbol: "person.3", kind: .info(""))) }
            if familyAllows(.publicMatchmaking) {
                rows.append(PanelRow(id: "party-find", title: FP.text(.findParty), detail: FP.text(.findPartyDetail), symbol: "person.3.sequence",
                                     kind: .action(destructive: false) { [weak self] in self?.openFindPlayers(category: 2) }))
            }
            rows += joinCodeEntryRows()
            return rows
        }
        let leader = party.isLeader(me.id)
        rows += voiceRows(party)
        rows += togetherRows(party, me: me.id)
        if leader { rows += partyRequestRows(party) }
        rows += partyCodeRows(party, leader: leader)
        rows.append(PanelRow(id: "party-members", title: T.format(.partyMembers, party.members.count, party.capacity), symbol: "person.3.fill", kind: .info("")))
        for member in party.members {
            let identity = shown(member)
            var details: [String] = [handleLine(member)]
            if party.isLeader(member.userId) { details.append(T.text(.partyLeader)) }
            if party.call?.in.contains(member.userId) == true { details.append(T.text(.partyInVoice)) }
            if let state = voiceState(of: member.userId, in: party) { details.append(state) }
            rows.append(PanelRow(id: "party-member-\(member.userId)", title: member.userId == me.id ? "\(member.displayName) (\(T.text(.profileYou)))" : identity.name,
                                 detail: details.joined(separator: " · "), symbol: "person", kind: .info(""),
                                 person: member.userId == me.id ? PanelPerson(name: member.displayName, avatar: member.avatar, status: party.call?.in.contains(member.userId) == true ? .online : nil,
                                                                             speaking: voiceSpeaking.contains(member.userId))
                                     : panelPerson(member, status: party.call?.in.contains(member.userId) == true ? .online : nil, speaking: voiceSpeaking.contains(member.userId))))
        }
        if leader {
            // The leader may remove someone or hand the lead over.
            for member in party.members where party.canManage(member.userId, me: me.id) {
                rows.append(PanelRow(id: "party-lead-\(member.userId)", title: T.format(.partyMakeLeader, shown(member).name), symbol: "crown",
                                     kind: .action(destructive: false) { [weak self] in self?.makePartyLeader(member) }))
                rows += askingFirst(PanelRow(id: "party-kick-\(member.userId)", title: T.format(.partyRemove, shown(member).name), symbol: "person.badge.minus",
                                             kind: .action(destructive: true) { [weak self] in self?.removeFromParty(member) }),
                                    question: TK.format(.askKick, shown(member).name))
            }
            rows.append(PanelRow(id: "party-privacy", title: T.text(.partyOpen), detail: T.text(.partyOpenDetail), symbol: "door.left.hand.open", kind: .toggle(party.open) { [weak self] value in
                self?.setPartyOpen(value)
            }))
            rows += partyListingRows(party)
        }
        let inside = Set(party.members.map(\.userId))
        let invited = Set(party.invited.map(\.userId))
        let invitable = togetherFriends.filter { !inside.contains($0.userId) }
        if !invitable.isEmpty, party.members.count < party.capacity {
            rows.append(PanelRow(id: "party-invite-title", title: T.text(.partyInviteFriends), symbol: "person.badge.plus", kind: .info("")))
            for friend in invitable {
                let status = PanelPerson.Status(friend.presence)
                if invited.contains(friend.userId) {
                    rows.append(PanelRow(id: "party-invited-\(friend.userId)", title: shown(friend).name, detail: handleLine(friend) + " · " + T.text(.partyInvited), symbol: "hourglass", kind: .info(""),
                                         person: panelPerson(friend, status: status)))
                } else {
                    rows.append(PanelRow(id: "party-invite-\(friend.userId)", title: T.format(.partyInvite, shown(friend).name), detail: handleLine(friend) + " · " + presenceText(friend.presence),
                                         symbol: "person.badge.plus", kind: .action(destructive: false) { [weak self] in self?.inviteToParty(friend) },
                                         person: panelPerson(friend, status: status)))
                }
            }
        }
        rows += joinCodeEntryRows()
        rows += askingFirst(PanelRow(id: "party-leave", title: T.text(.partyLeave), symbol: "rectangle.portrait.and.arrow.right", kind: .action(destructive: true) { [weak self] in
            self?.leaveParty()
        }), question: TK.text(.askLeaveParty))
        return rows
    }

    /// "deafened" or "muted" for someone in the call, as the server or the call's own events say.
    func voiceState(of userId: String, in party: TogetherParty) -> String? {
        let live = voiceCall != nil && voiceCall == party.call?.id
        if party.call?.deafened.contains(userId) == true || (live && voiceDeafened.contains(userId)) { return JS.text(.deafened) }
        if party.call?.muted.contains(userId) == true || (live && voiceMuted.contains(userId)) { return T.text(.voiceMuted) }
        return nil
    }

    // MARK: In public

    /// Strangers who asked to join, for the leader to let in (an invite) or not.
    func partyRequestRows(_ party: TogetherParty) -> [PanelRow] {
        (party.requests ?? []).flatMap { person -> [PanelRow] in
            [
                PanelRow(id: "party-request-accept-\(person.userId)", title: FP.format(.letIn, person.displayName),
                         detail: (["@\(person.handle)", FP.text(.letInParty)] + (codeAskers.contains(person.userId) ? [JS.text(.withCode)] : [])).joined(separator: " · "),
                         symbol: "person.crop.circle.badge.checkmark", kind: .action(destructive: false) { [weak self] in self?.answerPartyRequest(person, accept: true) },
                         person: PanelPerson(name: person.displayName, avatar: person.avatar)),
                PanelRow(id: "party-request-decline-\(person.userId)", title: FP.format(.notNow, person.displayName), symbol: "xmark.circle",
                         kind: .action(destructive: true) { [weak self] in self?.answerPartyRequest(person, accept: false) }),
            ]
        }
    }

    /// The game a public party or share play is about: the one running, else the one selected.
    var listingGame: Game? { running?.game ?? selectedGame }

    /// Listing the party in public: off, anyone may ask, anyone may walk in; its game and language.
    func partyListingRows(_ party: TogetherParty) -> [PanelRow] {
        guard familyAllows(.publicMatchmaking) else { return [] }
        let joins: [TogetherPublicJoin?] = [nil, .request, .open]
        let listing = party.listing
        var rows = [
            PanelRow(id: "party-public", title: FP.text(.listPublic), detail: FP.text(.listPublicDetail), symbol: "globe",
                     kind: .choice(options: [FP.text(.listOff), FP.text(.listAsk), FP.text(.listOpen)], selected: joins.firstIndex(of: listing?.join) ?? 0) { [weak self] index in
                         self?.listParty(joins[index].map { TogetherPartyListing(join: $0, titleId: listing?.titleId ?? self?.listingGame?.titleID, language: listing?.language) })
                     }),
        ]
        guard let listing else { return rows }
        var titles: [String?] = [nil]
        if let game = listingGame { titles.append(game.titleID) }
        if let title = listing.titleId, !titles.contains(title) { titles.append(title) }
        let languages: [String?] = [nil] + TogetherLanguages.common
        rows.append(PanelRow(id: "party-public-game", title: FP.text(.listGame), symbol: "gamecontroller",
                             kind: .choice(options: titles.map { $0.map(gameName) ?? FP.text(.listNoGame) }, selected: titles.firstIndex(of: listing.titleId) ?? 0) { [weak self] index in
                                 self?.listParty(TogetherPartyListing(join: listing.join, titleId: titles[index], language: listing.language))
                             }))
        rows.append(PanelRow(id: "party-public-language", title: FP.text(.listLanguage), symbol: "character.bubble",
                             kind: .choice(options: languages.map { $0.map { TogetherLanguages.name($0, in: lang) } ?? FP.text(.anyLanguage) },
                                           selected: languages.firstIndex(of: listing.language) ?? 0) { [weak self] index in
                                 self?.listParty(TogetherPartyListing(join: listing.join, titleId: listing.titleId, language: languages[index]))
                             }))
        return rows
    }

    func listParty(_ listing: TogetherPartyListing?) {
        guard let id = party?.id else { return }
        partyAction { try await $0.setPartyListing(id, listing) }
    }

    func answerPartyRequest(_ person: TogetherPerson, accept: Bool) {
        guard let id = party?.id else { return }
        partyAction { client in
            let next = try await client.answerPartyRequest(id, user: person.userId, accept: accept)
            if accept { await MainActor.run { self.show(FP.format(.letInDone, person.displayName), symbol: "person.badge.plus") } }
            return next
        }
    }

    var partySubtitle: String? {
        guard togetherUser != nil else { return nil }
        if let party { return T.format(.partySize, party.members.count, party.capacity) }
        return partyInvites.isEmpty ? T.text(.partyStartDetail) : T.format(.partyInvites, partyInvites.count)
    }

    func loadParty() {
        guard togetherUser != nil else { return }
        Task {
            guard let mine = try? await together.myParty() else { return }
            withAnimation(Motion.overlay) {
                party = mine.party
                partyInvites = mine.invites
            }
        }
    }

    func startParty() {
        let open = partyStartsOpen
        partyAction { try await $0.startParty(open: open) }
    }

    func joinParty(_ id: String) {
        partyAction { client in
            do {
                return try await client.joinParty(id)
            } catch let problem as TogetherProblem where problem.code == "full" {
                await MainActor.run { self.show(T.text(.partyFull), symbol: "person.3.fill") }
                return nil
            }
        }
    }

    func setPartyOpen(_ open: Bool) {
        guard let id = party?.id else { return }
        partyAction { try await $0.setParty(id, open: open) }
    }

    func inviteToParty(_ friend: TogetherFriend) {
        guard let id = party?.id else { return }
        partyAction { try await $0.invite([friend.userId], to: id) }
    }

    /// The lead to another member (leader only).
    func makePartyLeader(_ member: TogetherPerson) {
        guard let id = party?.id else { return }
        partyAction { client in
            let next = try await client.makeLeader(member.userId, of: id)
            await MainActor.run { self.show(T.format(.partyNowLeads, member.displayName), symbol: "crown.fill") }
            return next
        }
    }

    /// Someone out of the party (leader only).
    func removeFromParty(_ member: TogetherPerson) {
        guard let id = party?.id else { return }
        let client = together
        Task {
            do {
                try await client.kick(member.userId, from: id)
                withAnimation(Motion.overlay) {
                    if let current = party, current.id == id {
                        party = current.with(members: current.members.filter { $0.userId != member.userId },
                                             call: current.call.map { .init(id: $0.id, in: $0.in.filter { $0 != member.userId }) })
                    }
                }
                show(T.format(.partyRemoved, member.displayName), symbol: "person.badge.minus")
                loadParty()
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func declineParty(_ id: String) {
        Task {
            try? await together.declineParty(id)
            withAnimation(Motion.overlay) { partyInvites.removeAll { $0.partyId == id } }
        }
    }

    func leaveParty() {
        guard let id = party?.id else { return }
        leaveVoice()
        Task {
            try? await together.leaveParty(id)
            withAnimation(Motion.overlay) { party = nil }
            Sounds.shared.play(.back)
        }
    }

    /// A call that returns the party as it is now; a refusal shows as a card.
    private func partyAction(_ call: @escaping (TogetherClient) async throws -> TogetherParty?) {
        let client = together
        Task {
            do {
                guard let next = try await call(client) else { return }
                withAnimation(Motion.overlay) {
                    party = next
                    partyInvites.removeAll { $0.partyId == next.id }
                }
                    Sounds.shared.play(.select)
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// What the socket says about parties.
    func partyEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "party.invite":
            let name = event.decode(InviteData.self)?.from.displayName ?? ""
            show(T.format(.partyInvitedYou, name), symbol: "person.3.fill")
            inviteRing()
            if !NSApp.isActive, !doNotDisturb { TrophyBanner.shared.notice(T.format(.partyInvitedYou, name), detail: T.text(.partyTitle), symbol: "person.3.fill", sounds: preferences.sounds) }
            loadParty()
        case "party.updated":
            guard let next = event.decode(TogetherParty.self), next.id == party?.id || party == nil else { return }
            if let me = togetherUser?.id, let before = party, !before.isLeader(me), next.isLeader(me) {
                show(T.text(.partyYouLead), symbol: "crown.fill")
            }
            withAnimation(Motion.overlay) { party = next }
        case "party.member_joined":
            if let name = event.decode(JoinedData.self)?.member.displayName { show(T.format(.partyJoined, name), symbol: "person.badge.plus") }
            loadParty()
        case "party.member_left":
            let data = event.data
            if data["userId"] == togetherUser?.id, data["reason"] == "kicked" {
                show(T.text(.partyKicked), symbol: "person.badge.minus")
            } else if let name = party?.members.first(where: { $0.userId == data["userId"] })?.displayName {
                show(T.format(.partyLeft, name), symbol: "person.badge.minus")
            }
            loadParty()
        case "party.ended":
            voiceElsewhere = nil
            guard event.data["partyId"] == party?.id else { return loadParty() }
            leaveVoice(tellServer: false)
                withAnimation(Motion.overlay) { party = nil }
            show(T.text(.partyEnded), symbol: "person.3")
        default:
            discoverEvent(event)
        }
    }

    private struct InviteData: Decodable { let from: TogetherPerson }
    private struct JoinedData: Decodable { let member: TogetherPerson }

    func previewVoice(call: String, speaking: Set<String>) {
        voiceCall = call
        voiceSpeaking = speaking
    }

    func previewParty(_ party: TogetherParty?, invites: [TogetherPartyInvite] = []) {
        self.party = party
        partyInvites = invites
    }
}

/// The party's voice: joining and leaving the call, the microphone, push-to-talk on the talk key
/// (⌥V unless the user chose another; a global hot key, so it works with a game in front), and
/// who is speaking.
extension AppModel {
    func voiceRows(_ party: TogetherParty) -> [PanelRow] {
        guard familyAllows(.voiceChat) else { return [] }
        guard voiceCall != nil, callFriend == nil else {
            // The voice went to the phone (or another device): joining here takes it back.
            if let elsewhere = voiceElsewhere, party.call?.in.contains(togetherUser?.id ?? "") == true {
                return [PanelRow(id: "voice-join", title: T.text(.voiceTakeBack), detail: T.text(elsewhere.toPhone ? .voiceOnPhone : .voiceOnOtherDevice),
                                 symbol: elsewhere.toPhone ? "iphone" : "laptopcomputer",
                                 kind: .action(destructive: false) { [weak self] in self?.joinVoice() })]
            }
            let others = party.call?.in.filter { $0 != togetherUser?.id }.count ?? 0
            return [PanelRow(id: "voice-join", title: T.text(.voiceJoin), detail: others > 0 ? T.format(.voiceInCall, others) : T.text(.voiceJoinDetail), symbol: "waveform",
                             kind: .action(destructive: false) { [weak self] in self?.joinVoice() })]
        }
        return voiceControlRows()
    }

    /// The microphone, push-to-talk and leaving: the same in the party's voice and a friend's call.
    func voiceControlRows() -> [PanelRow] {
        let pushToTalk = preferences.pushToTalk ?? false
        let key = talkChord.display
        var rows: [PanelRow] = []
        if !pushToTalk {
            rows.append(PanelRow(id: "voice-mic", title: T.text(.voiceMic), detail: T.format(.voicePushToTalkOff, key), symbol: micOn ? "mic.fill" : "mic.slash.fill",
                                 kind: .toggle(micOn) { [weak self] value in self?.setMic(value) }))
        }
        // Beside the microphone, as on the website.
        let noise = preferences.noiseSuppression ?? true
        rows.append(PanelRow(id: "voice-noise", title: TChat.text(.noiseSuppression), detail: TChat.text(noise ? .noiseSuppressionOnHint : .noiseSuppressionOffHint), symbol: "waveform.path",
                             kind: .toggle(noise) { [weak self] value in self?.setNoiseSuppression(value) }))
        rows.append(PanelRow(id: "voice-deafen", title: JS.text(.deafen), detail: JS.text(.deafenDetail), symbol: deafened ? "headphones.slash" : "headphones",
                             kind: .toggle(deafened) { [weak self] value in self?.setDeafened(value) }))
        rows.append(PanelRow(id: "voice-ptt", title: T.text(.voicePushToTalk), detail: pushToTalk ? T.format(.voicePushToTalkOn, key) : nil, symbol: "keyboard",
                             kind: .toggle(pushToTalk) { [weak self] value in self?.setPushToTalk(value) }))
        // The key itself, chosen as on Windows and Linux.
        rows.append(PanelRow(id: "voice-key", title: T.text(.voiceTalkKey), detail: T.text(.voiceTalkKeyDetail), symbol: "command",
                             kind: .keys([key], capturing: capturingTalkKey) { [weak self] in self?.captureTalkKey() }))
        rows.append(PanelRow(id: "voice-leave", title: T.text(callFriend == nil ? .voiceLeave : .callHangUp), symbol: "phone.down.fill",
                             kind: .action(destructive: true) { [weak self] in self?.leaveVoice() }))
        return rows
    }

    /// The microphone sends: on (open mic), or the talk key held (push-to-talk).
    var micSending: Bool { voiceCall != nil && mic.sending(pushToTalk: preferences.pushToTalk ?? false, held: talkHeld) }

    func joinVoice() {
        guard let party, togetherUser != nil, familyPermits(.voiceChat) else { return }
        if callFriend != nil { leaveVoice() }
        guard voiceCall == nil else { return }
        Task {
            guard await PartyVoice.microphoneAllowed() else {
                return show(T.text(.voiceNoMic), symbol: "mic.slash.fill")
            }
            do {
                startVoice(try await together.joinCall(party: party.id))
                voiceElsewhere = nil
                Sounds.shared.play(.select)
                show(T.text(.voiceJoined), symbol: "waveform")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Into a call joined on the server: the party's voice, or a friend's call (`friend`).
    func startVoice(_ joined: TogetherCallJoin, friend: TogetherPerson? = nil, waiting: Bool = false) {
        guard let me = togetherUser else { return }
        let call = joined.call.id
        let voice = PartyVoice(me: me.id, call: call, iceServers: joined.iceServers, noiseSuppression: preferences.noiseSuppression ?? true, send: { [weak self] to, device, kind, data in
            self?.togetherSocket?.signal(to: to, device: device, call: call, kind: kind, data: data)
        }, changed: { [weak self] in self?.voiceChanged() })
        partyVoice = voice
        voiceSent = TogetherVoiceMic.State(muted: false, deafened: false)
        withAnimation(Motion.overlay) {
            voiceCall = call
            callFriend = friend
            callWaiting = waiting
            voiceMuted = Set(joined.call.in.filter(\.muted).map(\.userId))
            voiceDeafened = Set(joined.call.in.filter(\.deafened).map(\.userId))
        }
        mic = TogetherVoiceMic()
        if joined.call.media == .sfu, joined.call.partyId != nil {
            // Through the media server from the start: no mesh connections.
            moveVoiceToMediaServer(call, access: joined.sfu)
        } else {
            for peer in joined.peersToCall(me: me.id) { voice.connect(to: peer) }
        }
        registerTalkKey()
        voiceChanged()
        renewIceServers(at: TogetherVoice.renewal(expiresAt: joined.expiresAt), call: call)
    }

    /// The relay's credentials last hours: new ones before they end keep a long call through it.
    private func renewIceServers(at time: Date?, call: String) {
        iceRenewal?.cancel()
        guard let time else { return }
        iceRenewal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, time.timeIntervalSinceNow)))
            guard let self, !Task.isCancelled, self.voiceCall == call else { return }
            do {
                let fresh = try await self.together.iceServers()
                guard self.voiceCall == call else { return }
                self.partyVoice?.renew(fresh.iceServers)
                self.renewIceServers(at: TogetherVoice.renewal(expiresAt: fresh.expiresAt), call: call)
            } catch {
                // Offline for a moment: try again in a minute.
                self.renewIceServers(at: Date().addingTimeInterval(60), call: call)
            }
        }
    }

    /// Out of the call here; `tellServer` false when the server ended it already, `sayBye` false
    /// when the voice moved to another of the user's devices.
    func leaveVoice(tellServer: Bool = true, sayBye: Bool = true) {
        guard let call = voiceCall else { return }
        partyVoice?.close(sayBye: sayBye)
        partyVoice = nil
        if let sfu = sfuVoice {
            sfuVoice = nil
            Task { await sfu.close() }
        }
        iceRenewal?.cancel()
        iceRenewal = nil
        Input.shared.unregisterHotKey(id: Input.talkKey)
        withAnimation(Motion.overlay) {
            voiceCall = nil
            voiceSpeaking = []
            voiceMuted = []
            voiceDeafened = []
            mic = TogetherVoiceMic()
            callFriend = nil
            callWaiting = false
            talkHeld = false
        }
        if tellServer {
            let client = together
            Task { try? await client.leaveCall(call) }
        }
    }

    /// The microphone on or off; on while deafened undeafens.
    func setMic(_ on: Bool) {
        mic.set(on: on)
        voiceChanged()
    }

    /// Deafened: nobody is heard and the microphone is off; undeafened, it is as it was before.
    func setDeafened(_ on: Bool) {
        if on { mic.deafen() } else { mic.undeafen() }
        voiceChanged()
    }

    /// Noise suppression on or off: kept for next time, and changed in the mesh call now (the
    /// microphone's track is replaced on every connection, nothing reconnects). In a call on the
    /// media server it applies from the next join, as on the website.
    func setNoiseSuppression(_ on: Bool) {
        preferences.noiseSuppression = on
        partyVoice?.noiseSuppression = on
    }

    func setPushToTalk(_ on: Bool) {
        preferences.pushToTalk = on
        talkHeld = false
        voiceChanged()
    }

    /// The talk key: held to talk in push-to-talk, else it turns the microphone on and off.
    private func talkKey(_ pressed: Bool) {
        if preferences.pushToTalk ?? false {
            talkHeld = pressed
        } else if pressed {
            mic.set(on: !mic.on)
            Sounds.shared.play(.move)
        }
        voiceChanged()
    }

    /// The key that talks: the chosen one, else ⌥V.
    var talkChord: KeyChord { preferences.talkKey ?? TalkKey.standard }

    /// The talk key as a hot key from any app, while in a call.
    func registerTalkKey() {
        let chord = talkChord
        Input.shared.registerHotKey(id: Input.talkKey, keyCode: Int(chord.keyCode), modifiers: Input.carbon(chord.modifiers)) { [weak self] pressed in self?.talkKey(pressed) }
    }

    /// The Talk key row waits for a key (Esc, ○ or Back cancels).
    func captureTalkKey() {
        capturingTalkKey = true
        Sounds.shared.play(.select)
        Input.shared.capture = { [weak self] event in
            guard let self, event.type == .keyDown else { return true }
            if event.keyCode == KeyChord.escape && Input.modifiers(event.modifierFlags).isEmpty {
                self.endTalkKeyCapture()
                Sounds.shared.play(.back)
            } else if let chord = Input.chord(of: event) {
                self.chooseTalkKey(chord)
            }
            return true
        }
    }

    func endTalkKeyCapture() {
        capturingTalkKey = false
        Input.shared.capture = nil
    }

    /// The new talk key, refused (the old one stays) when it cannot be one.
    func chooseTalkKey(_ chord: KeyChord) {
        endTalkKeyCapture()
        if let refusal = TalkKey.refusal(chord, shortcuts: shortcutMap) {
            Sounds.shared.play(.bump)
            let reason: String
            switch refusal {
            case .navigationKey: reason = TH.text(.conflictNavigationKey)
            case .needsModifier: reason = TH.text(.conflictNeedsModifier)
            case .reservedKey: reason = TH.text(.conflictReservedKey)
            case .sameKey(let action): reason = TH.format(.conflictSame, TH.name(action))
            }
            return show(TH.format(.refused, reason), symbol: "exclamationmark.triangle.fill")
        }
        preferences.talkKey = chord == TalkKey.standard ? nil : chord
        talkHeld = false
        if voiceCall != nil { registerTalkKey() }
        Sounds.shared.play(.select)
        show(T.format(.voiceTalkKeySet, chord.display), symbol: "keyboard")
    }

    func voiceChanged() {
        partyVoice?.talking = micSending
        partyVoice?.deafened = deafened
        sfuVoice?.talking = micSending
        sfuVoice?.deafened = deafened
        // The others see the user muted when deafened or the open microphone is off (push-to-talk
        // is not muted), and deafened as it is; both go each time, as the server takes them.
        let state = mic.state(pushToTalk: preferences.pushToTalk ?? false)
        if let call = voiceCall, state != voiceSent {
            voiceSent = state
            let client = together
            Task { try? await client.setMuted(state.muted, deafened: state.deafened, in: call) }
        }
        let speaking = sfuVoice?.speaking ?? partyVoice?.speaking ?? []
        if speaking != voiceSpeaking { voiceSpeaking = speaking }
    }

    /// The party's call moved to the media server (more voices than the mesh holds): every mesh
    /// connection of it goes, no more mesh signals are answered, and the voice joins the call's
    /// room with the access the join gave or a fresh one. Mute and deafen go on as before.
    func moveVoiceToMediaServer(_ call: String, access: TogetherSfuAccess? = nil) {
        guard voiceCall == call, callFriend == nil, sfuVoice == nil, let me = togetherUser?.id else { return }
        partyVoice?.close()
        partyVoice = nil
        iceRenewal?.cancel()
        iceRenewal = nil
        let voice = SfuVoice(me: me, call: call, noiseSuppression: preferences.noiseSuppression ?? true) { [weak self] in self?.voiceChanged() }
        sfuVoice = voice
        voiceChanged()
        Task {
            do {
                let given: TogetherSfuAccess
                if let access { given = access } else { given = try await together.callSfu(call) }
                guard sfuVoice === voice else { return }
                try await voice.start(given)
                voiceChanged()
            } catch {
                RemoteServer.log.error("party voice: media server: \(String(describing: error), privacy: .public)")
                guard sfuVoice === voice else { return }
                show(SP.text(.mediaServerFailed), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Signals and call changes from the socket.
    func callEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "signal":
            if let signal = event.decode(TogetherSignal.self) { partyVoice?.receive(signal) }
        case "call.left":
            if let userId = event.data["userId"] {
                partyVoice?.drop(userId, sayBye: false)
                voiceMuted.remove(userId)
                voiceDeafened.remove(userId)
            }
            loadParty()
        case "call.joined":
            loadParty()
        case "call.media":
            // The party's call moved to the media server.
            guard let moved = event.decode(TogetherCallMedia.self), moved.callId == voiceCall, moved.media == .sfu else { return }
            moveVoiceToMediaServer(moved.callId)
        case "call.moved":
            // Joined on the phone (it is the controller, and the headset now): quiet here, still
            // in the party, and no echo of the same voice from two devices.
            guard let moved = event.decode(TogetherVoiceMoved.self), moved.callId == voiceCall else { return }
            leaveVoice(tellServer: false, sayBye: false)
            voiceElsewhere = moved
            show(T.text(moved.toPhone ? .voiceMovedPhone : .voiceMovedAway), symbol: moved.toPhone ? "iphone" : "laptopcomputer")
            loadParty()
        case "call.updated":
            // Someone muted or unmuted themselves (the party's view follows with party.updated).
            guard let change = event.decode(TogetherMuteChange.self), change.callId == voiceCall else { return }
            if change.muted { voiceMuted.insert(change.userId) } else { voiceMuted.remove(change.userId) }
            if change.deafened { voiceDeafened.insert(change.userId) } else { voiceDeafened.remove(change.userId) }
        case "call.ringing", "call.answered":
            directCallEvent(event)
        case "call.ended":
            directCallEvent(event)
            if event.data["callId"] == voiceCall { leaveVoice(tellServer: false) }
            loadParty()
        default:
            break
        }
    }
}
