import AnyPS5Core
import AppKit
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
            return rows
        }
        let leader = party.isLeader(me.id)
        rows.append(PanelRow(id: "party-members", title: T.format(.partyMembers, party.members.count, TogetherParty.maxSize), symbol: "person.3.fill", kind: .info("")))
        for member in party.members {
            var details: [String] = ["@\(member.handle)"]
            if party.isLeader(member.userId) { details.append(T.text(.partyLeader)) }
            if party.call?.in.contains(member.userId) == true { details.append(T.text(.partyInVoice)) }
            rows.append(PanelRow(id: "party-member-\(member.userId)", title: member.userId == me.id ? "\(member.displayName) (\(T.text(.profileYou)))" : member.displayName,
                                 detail: details.joined(separator: " · "), symbol: "person", kind: .info(""),
                                 person: PanelPerson(name: member.displayName, avatar: member.avatar,
                                                     status: party.call?.in.contains(member.userId) == true ? .online : nil)))
        }
        if leader {
            rows.append(PanelRow(id: "party-privacy", title: T.text(.partyOpen), detail: T.text(.partyOpenDetail), symbol: "door.left.hand.open", kind: .toggle(party.open) { [weak self] value in
                self?.setPartyOpen(value)
            }))
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

    func declineParty(_ id: String) {
        Task {
            try? await together.declineParty(id)
            withAnimation(Motion.overlay) { partyInvites.removeAll { $0.partyId == id } }
        }
    }

    func leaveParty() {
        guard let id = party?.id else { return }
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
                withAnimation(Motion.overlay) { party = nil }
            show(T.text(.partyEnded), symbol: "person.3")
        default:
            break
        }
    }

    private struct InviteData: Decodable { let from: TogetherPerson }
    private struct JoinedData: Decodable { let member: TogetherPerson }

    func previewParty(_ party: TogetherParty?, invites: [TogetherPartyInvite] = []) {
        self.party = party
        partyInvites = invites
    }
}
