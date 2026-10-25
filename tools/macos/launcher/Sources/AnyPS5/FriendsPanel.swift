import AnyPS5Core
import SwiftUI

/// Friends on AnyTogether: who plays what, requests to answer, adding someone by handle. The
/// socket's events keep it current while it is open and the top bar's count up to date.
extension AppModel {
    func friendRows() -> [PanelRow] {
        guard togetherUser != nil else {
            return [
                PanelRow(id: "friends-out", title: T.text(.friendsSignIn), detail: T.text(.togetherIntroDetail), symbol: "person.2.circle", kind: .info("")),
                PanelRow(id: "friends-signin", title: T.text(.togetherSignIn), symbol: "person.crop.circle.badge.plus", kind: .action(destructive: false) { [weak self] in
                    self?.openTogetherSettings()
                }),
            ]
        }
        var rows: [PanelRow] = callRows()
        rows += [
            PanelRow(id: "friends-me", title: T.text(.profileMine), detail: T.text(.profileMineDetail), symbol: "person.crop.circle", kind: .action(destructive: false) { [weak self] in
                self?.openMyProfile()
            }),
        ]
        if familyAllows(.publicMatchmaking) {
            rows.append(PanelRow(id: "friends-find", title: FP.text(.findPlayers), detail: FP.text(.findPlayersDetail), symbol: "person.3.sequence",
                                 kind: .action(destructive: false) { [weak self] in self?.openFindPlayers() }))
        }
        rows += socialRows()
        for person in togetherRequests.incoming {
            rows.append(PanelRow(id: "accept-\(person.userId)", title: T.format(.friendsAccept, person.displayName), detail: "@\(person.handle) · \(T.text(.friendsWantsToBe))",
                                 symbol: "person.crop.circle.badge.checkmark", kind: .action(destructive: false) { [weak self] in self?.answerFriend(person, accept: true) },
                                 person: PanelPerson(name: person.displayName, avatar: person.avatar)))
            rows.append(PanelRow(id: "decline-\(person.userId)", title: T.format(.friendsDecline, person.displayName), symbol: "xmark.circle",
                                 kind: .action(destructive: true) { [weak self] in self?.answerFriend(person, accept: false) }))
        }
        rows += gameRows()
        rows += familyAllows(.sharePlay) ? shareRows() : []
        rows.append(PanelRow(id: "friends-handle", title: T.text(.friendsAddByHandle), symbol: "at", kind: .text(friendHandle) { [weak self] text in self?.friendHandle = text }))
        rows.append(PanelRow(id: "friends-ask", title: familyAllows(.friendRequests) ? T.text(.friendsSendRequest) : FS.text(.askFriend), symbol: "person.badge.plus", kind: .action(destructive: false) { [weak self] in self?.askFriend() }))
        if togetherFriends.isEmpty {
            rows.append(PanelRow(id: "friends-none", title: T.text(.friendsNone), detail: T.format(.friendsYourHandle, togetherUser?.handle ?? ""), symbol: "person.2", kind: .info("")))
        }
        for friend in togetherFriends {
            rows.append(PanelRow(id: "friend-\(friend.userId)", title: friend.displayName, detail: "@\(friend.handle) · \(presenceText(friend.presence))",
                                 symbol: friend.presence?.playing == true ? "gamecontroller.fill" : friend.presence?.online == true ? "circle.fill" : "circle",
                                 kind: .action(destructive: false) { [weak self] in
                                     self?.openProfile(friend.handle, card: TogetherPerson(userId: friend.userId, handle: friend.handle, displayName: friend.displayName, avatar: friend.avatar))
                                 },
                                 person: PanelPerson(name: friend.displayName, avatar: friend.avatar,
                                                     status: friend.presence?.playing == true ? .playing : friend.presence?.online == true ? .online : .offline)))
            // Online friends can be called, unless the user is in a call with them already.
            if friend.presence?.online == true, callFriend?.userId != friend.userId, familyAllows(.voiceChat) {
                let person = TogetherPerson(userId: friend.userId, handle: friend.handle, displayName: friend.displayName, avatar: friend.avatar)
                rows.append(PanelRow(id: "friend-call-\(friend.userId)", title: T.format(.callFriend, friend.displayName), symbol: "phone",
                                     kind: .action(destructive: false) { [weak self] in self?.startCall(with: person) }))
            }
        }
        for person in togetherRequests.outgoing {
            rows.append(PanelRow(id: "waiting-\(person.userId)", title: person.displayName, detail: "@\(person.handle) · \(T.text(.friendsWaiting))", symbol: "hourglass", kind: .info(""),
                                 person: PanelPerson(name: person.displayName, avatar: person.avatar)))
        }
        return rows
    }

    /// "Playing Hollow Knight: Silksong · 25 min", "Online", "Offline", with the party they are in.
    func presenceText(_ presence: TogetherFriend.Presence?) -> String {
        var text = stateText(presence)
        guard presence?.online == true else { return text }
        if presence?.game?.joinable == true { text += " · " + T.text(.gameJoinable) }
        if let party = presence?.party { text += " · " + T.format(.friendsInParty, party.size, party.max) }
        return text
    }

    private func stateText(_ presence: TogetherFriend.Presence?) -> String {
        guard let presence, presence.online else { return T.text(.friendsOffline) }
        guard presence.playing, let title = presence.titleId else { return presence.state == "away" ? T.text(.friendsAway) : T.text(.friendsOnline) }
        let name = games.first { $0.titleID == title }?.name ?? title
        let minutes = presence.since.flatMap { ISO8601DateFormatter().date(from: $0) }.map { max(1, Int(Date().timeIntervalSince($0) / 60)) }
        return minutes.map { T.format(.friendsPlayingFor, name, $0) } ?? T.format(.friendsPlaying, name)
    }

    var friendsOnline: Int { togetherFriends.filter { $0.presence?.online == true }.count }

    func refreshFriends() {
        guard togetherUser != nil else { return }
        Task {
            async let friends = together.friends()
            async let requests = together.friendRequests()
            if let friends = try? await friends { withAnimation(Motion.overlay) { togetherFriends = friends } }
            if let requests = try? await requests { withAnimation(Motion.overlay) { togetherRequests = requests } }
        }
    }

    func askFriend() {
        let handle = friendHandle.trimmingCharacters(in: .whitespaces)
        guard !handle.isEmpty else { return }
        Task {
            do {
                let state = try await together.askFriend(handle)
                friendHandle = ""
                show(T.format(state == "accepted" ? .friendsNowFriends : .friendsRequestSent, handle), symbol: "person.badge.plus")
                refreshFriends()
            } catch let problem as TogetherProblem where problem.familyFeature == .friendRequests && !problem.byOthersFamily {
                // Not someone the child may add: a parent is asked instead.
                friendHandle = ""
                askParentToAdd(handle)
            } catch let problem as TogetherProblem where problem.status == 404 {
                show(T.format(.friendsNoOne, handle), symbol: "person.crop.circle.badge.questionmark")
            } catch {
                show(T.text(.togetherUnreachable), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func answerFriend(_ person: TogetherPerson, accept: Bool) {
        Task {
            try? await together.answerFriend(person.userId, accept: accept)
            if accept { show(T.format(.friendsNowFriends, person.displayName), symbol: "person.2.fill") }
            refreshFriends()
        }
    }

    func openTogetherSettings() {
        open(.settings)
        if let index = panelCategories().firstIndex(where: { $0.id == "together" }) {
            panelCategory = index
            panelInRows = true
            panelRow = 1
        }
    }

    /// What the socket says that concerns friends: requests and answers as cards, presence as it changes.
    func togetherEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "friend.request":
            let name = event.data["displayName"] ?? event.data["handle"] ?? ""
            show(T.format(.friendsAsked, name), symbol: "person.badge.plus")
            if !NSApp.isActive { TrophyBanner.shared.notice(T.format(.friendsAsked, name), detail: "@\(event.data["handle"] ?? "")", symbol: "person.badge.plus", sounds: preferences.sounds) }
            refreshFriends()
        case "friend.accepted":
            show(T.format(.friendsNowFriends, event.data["displayName"] ?? ""), symbol: "person.2.fill")
            refreshFriends()
        case "friend.removed", "presence.updated":
            refreshFriends()
        case let type where type.hasPrefix("message.") || type.hasPrefix("conversation.") || type == "typing":
            messageEvent(event)
        case let type where type.hasPrefix("lfg.") || type == "discover.changed":
            discoverEvent(event)
        case let type where type.hasPrefix("party."):
            partyEvent(event)
        case let type where type.hasPrefix("game_session."):
            gameSessionEvent(event)
        case let type where type.hasPrefix("share_play."):
            sharePlayEvent(event)
        case let type where type == "signal" || type.hasPrefix("call."):
            callEvent(event)
        case "family.updated":
            // A parent changed the limits or gave extra time: read them again now.
            refreshFamily()
        default:
            socialEvent(event)
        }
    }
}
