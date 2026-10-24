import AnyPS5Core
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
            rows.append(PanelRow(id: "party-accept-\(invite.partyId)", title: T.format(.partyJoinOf, name), detail: T.format(.partySize, invite.size, TogetherParty.maxSize),
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
            rows.append(PanelRow(id: "party-find", title: FP.text(.findParty), detail: FP.text(.findPartyDetail), symbol: "person.3.sequence",
                                 kind: .action(destructive: false) { [weak self] in self?.openFindPlayers(category: 2) }))
            return rows
        }
        let leader = party.isLeader(me.id)
        rows += voiceRows(party)
        if leader { rows += partyRequestRows(party) }
        rows.append(PanelRow(id: "party-members", title: T.format(.partyMembers, party.members.count, TogetherParty.maxSize), symbol: "person.3.fill", kind: .info("")))
        for member in party.members {
            var details: [String] = ["@\(member.handle)"]
            if party.isLeader(member.userId) { details.append(T.text(.partyLeader)) }
            if party.call?.in.contains(member.userId) == true { details.append(T.text(.partyInVoice)) }
            if party.call?.muted.contains(member.userId) == true || (voiceCall == party.call?.id && voiceMuted.contains(member.userId)) {
                details.append(T.text(.voiceMuted))
            }
            rows.append(PanelRow(id: "party-member-\(member.userId)", title: member.userId == me.id ? "\(member.displayName) (\(T.text(.profileYou)))" : member.displayName,
                                 detail: details.joined(separator: " · "), symbol: "person", kind: .info(""),
                                 person: PanelPerson(name: member.displayName, avatar: member.avatar,
                                                     status: party.call?.in.contains(member.userId) == true ? .online : nil, speaking: voiceSpeaking.contains(member.userId))))
        }
        if leader {
            // The leader may remove someone or hand the lead over.
            for member in party.members where party.canManage(member.userId, me: me.id) {
                rows.append(PanelRow(id: "party-lead-\(member.userId)", title: T.format(.partyMakeLeader, member.displayName), symbol: "crown",
                                     kind: .action(destructive: false) { [weak self] in self?.makePartyLeader(member) }))
                rows.append(PanelRow(id: "party-kick-\(member.userId)", title: T.format(.partyRemove, member.displayName), symbol: "person.badge.minus",
                                     kind: .action(destructive: true) { [weak self] in self?.removeFromParty(member) }))
            }
            rows.append(PanelRow(id: "party-privacy", title: T.text(.partyOpen), detail: T.text(.partyOpenDetail), symbol: "door.left.hand.open", kind: .toggle(party.open) { [weak self] value in
                self?.setPartyOpen(value)
            }))
            rows += partyListingRows(party)
        }
        let inside = Set(party.members.map(\.userId))
        let invited = Set(party.invited.map(\.userId))
        let invitable = togetherFriends.filter { !inside.contains($0.userId) }
        if !invitable.isEmpty, party.members.count < TogetherParty.maxSize {
            rows.append(PanelRow(id: "party-invite-title", title: T.text(.partyInviteFriends), symbol: "person.badge.plus", kind: .info("")))
            for friend in invitable {
                let status: PanelPerson.Status = friend.presence?.playing == true ? .playing : friend.presence?.online == true ? .online : .offline
                if invited.contains(friend.userId) {
                    rows.append(PanelRow(id: "party-invited-\(friend.userId)", title: friend.displayName, detail: T.text(.partyInvited), symbol: "hourglass", kind: .info(""),
                                         person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: status)))
                } else {
                    rows.append(PanelRow(id: "party-invite-\(friend.userId)", title: T.format(.partyInvite, friend.displayName), detail: presenceText(friend.presence),
                                         symbol: "person.badge.plus", kind: .action(destructive: false) { [weak self] in self?.inviteToParty(friend) },
                                         person: PanelPerson(name: friend.displayName, avatar: friend.avatar, status: status)))
                }
            }
        }
        rows.append(PanelRow(id: "party-leave", title: T.text(.partyLeave), symbol: "rectangle.portrait.and.arrow.right", kind: .action(destructive: true) { [weak self] in
            self?.leaveParty()
        }))
        return rows
    }

    // MARK: In public

    /// Strangers who asked to join, for the leader to let in (an invite) or not.
    func partyRequestRows(_ party: TogetherParty) -> [PanelRow] {
        (party.requests ?? []).flatMap { person -> [PanelRow] in
            [
                PanelRow(id: "party-request-accept-\(person.userId)", title: FP.format(.letIn, person.displayName), detail: "@\(person.handle) · " + FP.text(.letInParty),
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
        if let party { return T.format(.partySize, party.members.count, TogetherParty.maxSize) }
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
            if !NSApp.isActive { TrophyBanner.shared.notice(T.format(.partyInvitedYou, name), detail: T.text(.partyTitle), symbol: "person.3.fill", sounds: preferences.sounds) }
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

/// The party's voice: joining and leaving the call, the microphone, push-to-talk on ⌥V (a global
/// hot key, so it works with a game in front), and who is speaking.
extension AppModel {
    func voiceRows(_ party: TogetherParty) -> [PanelRow] {
        guard voiceCall != nil, callFriend == nil else {
            let others = party.call?.in.filter { $0 != togetherUser?.id }.count ?? 0
            return [PanelRow(id: "voice-join", title: T.text(.voiceJoin), detail: others > 0 ? T.format(.voiceInCall, others) : T.text(.voiceJoinDetail), symbol: "waveform",
                             kind: .action(destructive: false) { [weak self] in self?.joinVoice() })]
        }
        return voiceControlRows()
    }

    /// The microphone, push-to-talk and leaving: the same in the party's voice and a friend's call.
    func voiceControlRows() -> [PanelRow] {
        let pushToTalk = preferences.pushToTalk ?? false
        var rows: [PanelRow] = []
        if !pushToTalk {
            rows.append(PanelRow(id: "voice-mic", title: T.text(.voiceMic), detail: T.text(.voicePushToTalkOff), symbol: micOn ? "mic.fill" : "mic.slash.fill",
                                 kind: .toggle(micOn) { [weak self] value in self?.setMic(value) }))
        }
        rows.append(PanelRow(id: "voice-ptt", title: T.text(.voicePushToTalk), detail: pushToTalk ? T.text(.voicePushToTalkOn) : nil, symbol: "keyboard",
                             kind: .toggle(pushToTalk) { [weak self] value in self?.setPushToTalk(value) }))
        rows.append(PanelRow(id: "voice-leave", title: T.text(callFriend == nil ? .voiceLeave : .callHangUp), symbol: "phone.down.fill",
                             kind: .action(destructive: true) { [weak self] in self?.leaveVoice() }))
        return rows
    }

    /// The microphone sends: on (open mic), or ⌥V held (push-to-talk).
    var micSending: Bool { voiceCall != nil && ((preferences.pushToTalk ?? false) ? talkHeld : micOn) }

    func joinVoice() {
        guard let party, togetherUser != nil else { return }
        if callFriend != nil { leaveVoice() }
        guard voiceCall == nil else { return }
        Task {
            guard await PartyVoice.microphoneAllowed() else {
                return show(T.text(.voiceNoMic), symbol: "mic.slash.fill")
            }
            do {
                startVoice(try await together.joinCall(party: party.id))
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
        let voice = PartyVoice(me: me.id, call: call, iceServers: joined.iceServers, send: { [weak self] to, device, kind, data in
            self?.togetherSocket?.signal(to: to, device: device, call: call, kind: kind, data: data)
        }, changed: { [weak self] in self?.voiceChanged() })
        partyVoice = voice
        voiceSentMuted = false
        withAnimation(Motion.overlay) {
            voiceCall = call
            callFriend = friend
            callWaiting = waiting
            voiceMuted = Set(joined.call.in.filter(\.muted).map(\.userId))
        }
        micOn = true
        for peer in joined.peersToCall(me: me.id) { voice.connect(to: peer) }
        Input.shared.registerHotKey(id: Input.talkKey, keyCode: kVK_ANSI_V, modifiers: optionKey) { [weak self] pressed in self?.talkKey(pressed) }
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

    /// Out of the call here; `tellServer` false when the server ended it already.
    func leaveVoice(tellServer: Bool = true) {
        guard let call = voiceCall else { return }
        partyVoice?.close()
        partyVoice = nil
        iceRenewal?.cancel()
        iceRenewal = nil
        Input.shared.unregisterHotKey(id: Input.talkKey)
        withAnimation(Motion.overlay) {
            voiceCall = nil
            voiceSpeaking = []
            voiceMuted = []
            callFriend = nil
            callWaiting = false
            talkHeld = false
        }
        if tellServer {
            let client = together
            Task { try? await client.leaveCall(call) }
        }
    }

    func setMic(_ on: Bool) {
        micOn = on
        voiceChanged()
    }

    func setPushToTalk(_ on: Bool) {
        preferences.pushToTalk = on
        talkHeld = false
        voiceChanged()
    }

    /// ⌥V: held to talk in push-to-talk, else it turns the microphone on and off.
    private func talkKey(_ pressed: Bool) {
        if preferences.pushToTalk ?? false {
            talkHeld = pressed
        } else if pressed {
            micOn.toggle()
            Sounds.shared.play(.move)
        }
        voiceChanged()
    }

    func voiceChanged() {
        partyVoice?.talking = micSending
        // The others see the user muted when the open microphone is off (push-to-talk is not muted).
        let muted = voiceCall != nil && !(preferences.pushToTalk ?? false) && !micOn
        if let call = voiceCall, muted != voiceSentMuted {
            voiceSentMuted = muted
            let client = together
            Task { try? await client.setMuted(muted, in: call) }
        }
        let speaking = partyVoice?.speaking ?? []
        if speaking != voiceSpeaking { voiceSpeaking = speaking }
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
            }
            loadParty()
        case "call.joined":
            loadParty()
        case "call.updated":
            // Someone muted or unmuted themselves (the party's view follows with party.updated).
            guard let change = event.decode(TogetherMuteChange.self), change.callId == voiceCall else { return }
            if change.muted { voiceMuted.insert(change.userId) } else { voiceMuted.remove(change.userId) }
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
