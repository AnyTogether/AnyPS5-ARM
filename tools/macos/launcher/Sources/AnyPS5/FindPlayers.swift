import AnyPS5Core
import AppKit
import SwiftUI

/// What "Find players", a game's hub and the post form show.
struct DiscoverState {
    var filter = TogetherLfgFilter()
    var board: [TogetherLfgPost] = []
    var more = false
    var loaded = false
    var failed = false
    /// Games with open posts, for the game filter.
    var games: [TogetherLfgGame] = []
    var mine: [TogetherLfgPost] = []
    var asked: [TogetherLfgPost] = []
    var shares: [TogetherPublicShare] = []
    var parties: [TogetherPublicParty] = []
    var suggestions: [TogetherDiscoveredPerson] = []
    /// Friend requests sent from here, so the row says so at once.
    var askedFriends: Set<String> = []
    var discovery: TogetherDiscovery?
    /// The hub open: its game, what came back, and whether reading it failed.
    var hubTitle: String?
    var hubName = ""
    var hub: TogetherGameHub?
    var hubFailed = false
    /// The post being written, and the game's name to show.
    var draft: TogetherLfgDraft?
    var draftName = ""
    var posting = false
    /// Where the post form and the hub go back to.
    var returnTo: Overlay?
    var returnCategory = 0
    var reload: Task<Void, Never>?
}

/// Finding people beyond friends on AnyTogether: the looking-for-group board with its filters,
/// posting from a game's options, "I'm in", one's own posts and their requests, Live now, public
/// parties, people to meet, and a game's hub. The board and the lists are read again when the
/// gateway's public topics say they changed.
extension AppModel {
    static let startChoices = [0, 15, 30, 60, 120]

    var lang: String { T.language.rawValue }

    // MARK: Opening

    func openFindPlayers(category: Int = 0) {
        guard togetherUser != nil else { return openTogetherSettings() }
        guard familyPermits(.publicMatchmaking) else { return }
        open(.findPlayers)
        panelCategory = category
        panelInRows = true
        loadDiscover()
    }

    /// "Find players for <game>": the form, back to where it was opened.
    func openLfgPost(titleId: String, name: String) {
        guard togetherUser != nil else { return openTogetherSettings() }
        guard familyPermits(.publicMatchmaking) else { return }
        let languages = discover.discovery?.languages.isEmpty == false ? Array(discover.discovery!.languages.prefix(2)) : [lang]
        discover.returnTo = overlay
        discover.returnCategory = panelCategory
        discover.draft = TogetherLfgDraft(titleId: titleId, purpose: .coop, slots: 1, languages: languages)
        discover.draftName = name
        open(.lfgPost)
        panelInRows = true
    }

    func openHub(titleId: String, name: String) {
        guard togetherUser != nil else { return openTogetherSettings() }
        guard familyPermits(.discovery) else { return }
        if overlay != .gameHub {
            discover.returnTo = overlay
            discover.returnCategory = panelCategory
        }
        if discover.hubTitle != titleId { discover.hub = nil }
        discover.hubTitle = titleId
        discover.hubName = name
        discover.hubFailed = false
        open(.gameHub)
        panelInRows = true
        loadHub(titleId)
    }

    /// Back from the form or the hub to the panel it was opened from.
    func backFromDiscover() {
        guard let back = discover.returnTo, back != overlay else { return closeOverlay() }
        let category = discover.returnCategory
        discover.returnTo = nil
        withAnimation(Motion.overlay) { overlay = back }
        panelCategory = category
        panelRow = 0
        panelInRows = true
        Sounds.shared.play(.back)
        if back == .findPlayers { loadDiscover() }
    }

    /// Which public topics the socket listens to: the board and the lists while they are open.
    func discoverOverlayChanged() {
        switch overlay {
        case .findPlayers: togetherSocket?.watch(TogetherTopics.discovery(titleId: discover.filter.titleId))
        case .gameHub: togetherSocket?.watch(TogetherTopics.discovery(titleId: discover.hubTitle))
        default: togetherSocket?.watch([])
        }
    }

    // MARK: Reading

    func loadDiscover() {
        guard togetherUser != nil else { return }
        let client = together
        let filter = discover.filter
        Task {
            async let board = client.lfgBoard(filter)
            async let games = client.lfgGames()
            async let mine = client.myLfg()
            async let shares = client.publicSharePlays()
            async let parties = client.publicParties()
            async let suggestions = client.suggestions()
            do {
                let page = try await board
                guard discover.filter == filter else { return }
                withAnimation(Motion.overlay) {
                    discover.board = page.posts
                    discover.more = page.more
                    discover.loaded = true
                    discover.failed = false
                }
            } catch {
                withAnimation(Motion.overlay) { discover.failed = true }
            }
            if let games = try? await games { discover.games = games }
            if let mine = try? await mine { withAnimation(Motion.overlay) { discover.mine = mine.posts; discover.asked = mine.asked } }
            if let shares = try? await shares { withAnimation(Motion.overlay) { discover.shares = shares.sorted { $0.live && !$1.live } } }
            if let parties = try? await parties { withAnimation(Motion.overlay) { discover.parties = parties } }
            if let suggestions = try? await suggestions { withAnimation(Motion.overlay) { discover.suggestions = suggestions } }
        }
    }

    func loadMoreBoard() {
        guard let last = discover.board.last?.id else { return }
        let filter = discover.filter
        Task {
            guard let page = try? await together.lfgBoard(filter, before: last), discover.filter == filter else { return }
            withAnimation(Motion.overlay) {
                discover.board += page.posts.filter { post in !discover.board.contains { $0.id == post.id } }
                discover.more = page.more
            }
        }
    }

    func loadHub(_ titleId: String) {
        Task {
            do {
                let hub = try await together.gameHub(titleId)
                guard discover.hubTitle == titleId else { return }
                withAnimation(Motion.overlay) {
                    discover.hub = hub
                    discover.hubFailed = false
                }
            } catch {
                guard discover.hubTitle == titleId else { return }
                withAnimation(Motion.overlay) { discover.hubFailed = true }
            }
        }
        loadCompat(titleId)
    }

    func loadDiscovery() {
        guard togetherUser != nil else { return }
        Task { if let discovery = try? await together.discovery() { discover.discovery = discovery } }
    }

    /// The lists again, a moment after the last "changed" (a busy board sends many).
    func reloadDiscoverSoon() {
        discover.reload?.cancel()
        discover.reload = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            switch overlay {
            case .findPlayers: loadDiscover()
            case .gameHub: if let title = discover.hubTitle { loadHub(title) }
            default: break
            }
        }
    }

    func setBoardFilter(_ change: (inout TogetherLfgFilter) -> Void) {
        change(&discover.filter)
        discover.loaded = false
        discoverOverlayChanged()
        loadDiscover()
    }

    // MARK: Board

    private func purposeName(_ purpose: TogetherLfgPurpose) -> String {
        switch purpose {
        case .coop: return FP.text(.purposeCoop)
        case .online: return FP.text(.purposeOnline)
        case .party: return FP.text(.purposeParty)
        case .trophies: return FP.text(.purposeTrophies)
        }
    }

    private func languageList(_ codes: [String]) -> String { codes.map { TogetherLanguages.name($0, in: lang) }.joined(separator: ", ") }

    func postName(_ post: TogetherLfgPost) -> String { games.first { $0.titleID == post.titleId }?.name ?? post.name(in: lang) }

    /// "Mira · Now · English, Türkçe · 1 of 3 in", then what pressing does (or the post's state)
    /// and the note: a row shows two lines.
    private func postDetail(_ post: TogetherLfgPost, author: Bool = true, then status: String) -> String {
        var parts: [String] = []
        if author { parts.append(post.author.displayName) }
        switch post.when() {
        case .now: parts.append(FP.text(.now))
        case .inMinutes(let minutes): parts.append(minutes < 120 ? FP.format(.inMinutes, minutes) : FP.format(.inHours, (minutes + 30) / 60))
        }
        parts.append(languageList(post.languages))
        parts.append(FP.format(.filled, post.filled, post.slots))
        let second = [status] + (post.note.flatMap { $0.isEmpty ? nil : ["“\($0)”"] } ?? [])
        return parts.joined(separator: " · ") + "\n" + second.joined(separator: " · ")
    }

    /// A post on the board: what pressing it does follows where the user stands with it.
    func postRow(_ post: TogetherLfgPost, prefix: String = "post") -> PanelRow {
        let title = "\(postName(post)) · \(purposeName(post.purpose))"
        let person = PanelPerson(name: post.author.displayName, avatar: post.author.avatar)
        let detail = { (status: String) in self.postDetail(post, then: status) }
        switch post.standing() {
        case .canAsk:
            return PanelRow(id: "\(prefix)-\(post.id)", title: title, detail: detail(FP.text(.selectImIn)), symbol: "hand.raised",
                            kind: .action(destructive: false) { [weak self] in self?.imIn(post) }, person: person)
        case .waiting:
            return PanelRow(id: "\(prefix)-\(post.id)", title: title, detail: detail(FP.format(.waitingFor, post.author.displayName)), symbol: "hourglass",
                            kind: .action(destructive: false) { [weak self] in self?.takeBack(post) }, person: person)
        case .accepted(let invite):
            return PanelRow(id: "\(prefix)-\(post.id)", title: title, detail: detail(FP.text(invite?.isSharePlay == true ? .inSharePlay : .inParty)), symbol: "checkmark.circle.fill",
                            kind: .action(destructive: false) { [weak self] in self?.followInvite(invite) }, person: person)
        case .declined:
            return PanelRow(id: "\(prefix)-\(post.id)", title: title, detail: detail(FP.format(.saidNo, post.author.displayName)), symbol: "xmark.circle", kind: .info(""), person: person)
        case .closed:
            return PanelRow(id: "\(prefix)-\(post.id)", title: title, detail: detail(FP.text(.closed)), symbol: "lock", kind: .info(""), person: person)
        case .own:
            return PanelRow(id: "\(prefix)-\(post.id)", title: title, detail: postDetail(post, author: false, then: FP.format(.waitingCount, post.pending.count)), symbol: "person.crop.circle",
                            kind: .action(destructive: false) { [weak self] in self?.showMyPosts() })
        }
    }

    private func showMyPosts() {
        guard overlay == .findPlayers else { return openFindPlayers(category: 1) }
        panelCategory = 1
        panelRow = 0
        Sounds.shared.play(.move)
    }

    func boardRows() -> [PanelRow] {
        let filter = discover.filter
        // The game filter: all, the selected game, then games with open posts.
        var titles: [(String?, String)] = [(nil, FP.text(.allGames))]
        if let game = selectedGame { titles.append((game.titleID, game.name)) }
        for game in discover.games where !titles.contains(where: { $0.0 == game.titleId }) {
            titles.append((game.titleId, "\(games.first { $0.titleID == game.titleId }?.name ?? game.name(in: lang)) (\(game.posts))"))
        }
        if let chosen = filter.titleId, !titles.contains(where: { $0.0 == chosen }) { titles.append((chosen, gameName(chosen))) }
        let purposes: [TogetherLfgPurpose?] = [nil] + TogetherLfgPurpose.allCases
        let languages: [String?] = [nil] + TogetherLanguages.common
        var rows: [PanelRow] = [
            PanelRow(id: "lfg-game", title: FP.text(.game), symbol: "gamecontroller",
                     kind: .choice(options: titles.map(\.1), selected: titles.firstIndex { $0.0 == filter.titleId } ?? 0) { [weak self] index in
                         self?.setBoardFilter { $0.titleId = titles[index].0 }
                     }),
            PanelRow(id: "lfg-purpose", title: FP.text(.purpose), symbol: "target",
                     kind: .choice(options: purposes.map { $0.map(purposeName) ?? FP.text(.anyPurpose) }, selected: purposes.firstIndex(of: filter.purpose) ?? 0) { [weak self] index in
                         self?.setBoardFilter { $0.purpose = purposes[index] }
                     }),
            PanelRow(id: "lfg-language", title: FP.text(.language), symbol: "globe",
                     kind: .choice(options: languages.map { $0.map { TogetherLanguages.name($0, in: lang) } ?? FP.text(.anyLanguage) }, selected: languages.firstIndex(of: filter.language) ?? 0) { [weak self] index in
                         self?.setBoardFilter { $0.language = languages[index] }
                     }),
            PanelRow(id: "lfg-now", title: FP.text(.startingSoon), detail: FP.text(.startingSoonDetail), symbol: "clock",
                     kind: .toggle(filter.now) { [weak self] value in self?.setBoardFilter { $0.now = value } }),
        ]
        if let game = filter.titleId.map({ ($0, gameName($0)) }) ?? selectedGame.map({ ($0.titleID, $0.name) }) {
            rows.append(PanelRow(id: "lfg-post", title: FP.format(.findFor, game.1), detail: FP.text(.findForDetail), symbol: "plus.bubble",
                                 kind: .action(destructive: false) { [weak self] in self?.openLfgPost(titleId: game.0, name: game.1) }))
            rows.append(PanelRow(id: "lfg-hub", title: FP.format(.hubOf, game.1), detail: FP.text(.hubDetail), symbol: "square.grid.3x1.below.line.grid.1x2",
                                 kind: .action(destructive: false) { [weak self] in self?.openHub(titleId: game.0, name: game.1) }))
        }
        if !discover.loaded {
            rows.append(PanelRow(id: "lfg-loading", title: discover.failed ? T.text(.togetherUnreachable) : FP.text(.loading), symbol: discover.failed ? "wifi.exclamationmark" : "ellipsis", kind: .info("")))
            return rows
        }
        if discover.board.isEmpty {
            rows.append(PanelRow(id: "lfg-empty", title: FP.text(.noPosts), detail: FP.text(.noPostsDetail), symbol: "person.3.sequence", kind: .info("")))
        }
        rows += discover.board.map { postRow($0) }
        if discover.more {
            rows.append(PanelRow(id: "lfg-more", title: FP.text(.more), symbol: "chevron.down.circle", kind: .action(destructive: false) { [weak self] in self?.loadMoreBoard() }))
        }
        return rows
    }

    // MARK: My posts

    func myPostRows() -> [PanelRow] {
        var rows: [PanelRow] = []
        let open = discover.mine.filter { $0.isOpen() }
        if let game = selectedGame, open.count < 3 {
            rows.append(PanelRow(id: "mine-post", title: FP.format(.findFor, game.name), detail: FP.text(.findForDetail), symbol: "plus.bubble",
                                 kind: .action(destructive: false) { [weak self] in self?.openLfgPost(titleId: game.titleID, name: game.name) }))
        }
        if discover.mine.isEmpty && discover.asked.isEmpty {
            rows.append(PanelRow(id: "mine-none", title: FP.text(.noMine), detail: FP.text(.noMineDetail), symbol: "text.bubble", kind: .info("")))
            return rows
        }
        for post in discover.mine {
            let status = post.isOpen() ? FP.format(.waitingCount, post.pending.count) : FP.text(post.status == "full" ? .full : .closed)
            rows.append(PanelRow(id: "mine-\(post.id)", title: "\(postName(post)) · \(purposeName(post.purpose))", detail: postDetail(post, author: false, then: status),
                                 symbol: post.isOpen() ? "megaphone.fill" : "megaphone", kind: .info("")))
            for request in post.requests ?? [] {
                let name = request.user.displayName
                let person = PanelPerson(name: name, avatar: request.user.avatar)
                switch request.status {
                case "pending" where post.isOpen():
                    rows.append(PanelRow(id: "mine-accept-\(post.id)-\(request.user.userId)", title: FP.format(.letIn, name),
                                         detail: "@\(request.user.handle) · " + FP.text(post.purpose == .coop ? .letInCoop : .letInParty), symbol: "person.crop.circle.badge.checkmark",
                                         kind: .action(destructive: false) { [weak self] in self?.answer(post, request.user, accept: true) }, person: person))
                    rows.append(PanelRow(id: "mine-decline-\(post.id)-\(request.user.userId)", title: FP.format(.notNow, name), symbol: "xmark.circle",
                                         kind: .action(destructive: true) { [weak self] in self?.answer(post, request.user, accept: false) }))
                case "accepted":
                    rows.append(PanelRow(id: "mine-in-\(post.id)-\(request.user.userId)", title: name, detail: FP.text(request.invite?.isSharePlay == true ? .theyShare : .theyParty),
                                         symbol: "checkmark.circle.fill", kind: .info(""), person: person))
                default:
                    break
                }
            }
            if post.isOpen() {
                rows += askingFirst(PanelRow(id: "mine-close-\(post.id)", title: FP.text(.closePost), symbol: "xmark.bin", kind: .action(destructive: true) { [weak self] in self?.closePost(post) }),
                                    question: TK.text(.askClosePost))
            }
        }
        if !discover.asked.isEmpty {
            rows.append(PanelRow(id: "asked-title", title: FP.text(.askedTitle), symbol: "hand.raised", kind: .info("")))
            rows += discover.asked.map { postRow($0, prefix: "asked") }
        }
        return rows
    }

    // MARK: Live now and public parties

    func shareRow(_ share: TogetherPublicShare, prefix: String = "live") -> PanelRow {
        let host = share.host?.displayName ?? "?"
        let name = games.first { $0.titleID == share.titleId }?.name ?? share.name(in: lang)
        var detail = [FP.format(.viewers, share.viewers, share.maxViewers)]
        if let language = share.language { detail.append(TogetherLanguages.name(language, in: lang)) }
        let person = share.host.map { PanelPerson(name: $0.displayName, avatar: $0.avatar, status: .playing) }
        if share.join == .open {
            return PanelRow(id: "\(prefix)-\(share.id)", title: SP.format(.watchFriend, host, name), detail: ((share.live ? [FP.text(.liveNow)] : []) + detail).joined(separator: " · "),
                            symbol: share.live ? "dot.radiowaves.left.and.right" : "play.tv", kind: .action(destructive: false) { [weak self] in self?.watchShare(share.id) }, person: person)
        }
        if share.requested {
            return PanelRow(id: "\(prefix)-\(share.id)", title: FP.format(.askedToWatch, host, name), detail: detail.joined(separator: " · "), symbol: "hourglass", kind: .info(""), person: person)
        }
        return PanelRow(id: "\(prefix)-\(share.id)", title: FP.format(.askToWatch, host, name), detail: detail.joined(separator: " · "), symbol: "hand.raised",
                        kind: .action(destructive: false) { [weak self] in self?.askToWatch(share) }, person: person)
    }

    func partyRow(_ listed: TogetherPublicParty, prefix: String = "pub") -> PanelRow {
        let host = listed.host?.displayName ?? "?"
        var detail = [T.format(.partySize, listed.size, listed.max)]
        if let title = listed.titleId { detail.insert(games.first { $0.titleID == title }?.name ?? listed.game?.name(in: lang) ?? title, at: 0) }
        if let language = listed.language { detail.append(TogetherLanguages.name(language, in: lang)) }
        let person = listed.host.map { PanelPerson(name: $0.displayName, avatar: $0.avatar, status: .online) }
        if party?.id == listed.id {
            return PanelRow(id: "\(prefix)-\(listed.id)", title: FP.text(.yourParty), detail: detail.joined(separator: " · "), symbol: "person.3.fill", kind: .info(""), person: person)
        }
        if listed.full {
            return PanelRow(id: "\(prefix)-\(listed.id)", title: T.format(.partyJoinOf, host), detail: (detail + [T.text(.partyFull)]).joined(separator: " · "), symbol: "person.3", kind: .info(""), person: person)
        }
        if listed.join == .open {
            return PanelRow(id: "\(prefix)-\(listed.id)", title: T.format(.partyJoinOf, host), detail: detail.joined(separator: " · "), symbol: "person.3",
                            kind: .action(destructive: false) { [weak self] in self?.joinParty(listed.id) }, person: person)
        }
        if listed.requested {
            return PanelRow(id: "\(prefix)-\(listed.id)", title: FP.format(.askedParty, host), detail: (detail + [FP.text(.selectTakeBack)]).joined(separator: " · "), symbol: "hourglass",
                            kind: .action(destructive: false) { [weak self] in self?.cancelPartyRequest(listed) }, person: person)
        }
        return PanelRow(id: "\(prefix)-\(listed.id)", title: FP.format(.askParty, host), detail: detail.joined(separator: " · "), symbol: "hand.raised",
                        kind: .action(destructive: false) { [weak self] in self?.askToJoin(listed) }, person: person)
    }

    func liveRows() -> [PanelRow] {
        var rows: [PanelRow] = []
        rows.append(PanelRow(id: "live-title", title: FP.text(.liveNow), detail: FP.text(.liveDetail), symbol: "dot.radiowaves.left.and.right", kind: .info("")))
        if discover.shares.isEmpty { rows.append(PanelRow(id: "live-none", title: FP.text(.noLive), symbol: "play.slash", kind: .info(""))) }
        rows += discover.shares.map { shareRow($0) }
        rows.append(PanelRow(id: "pub-title", title: FP.text(.publicParties), detail: FP.text(.publicPartiesDetail), symbol: "person.3", kind: .info("")))
        if discover.parties.isEmpty { rows.append(PanelRow(id: "pub-none", title: FP.text(.noParties), symbol: "person.3", kind: .info(""))) }
        rows += discover.parties.map { partyRow($0) }
        return rows
    }

    // MARK: People

    func reasonText(_ reasons: [TogetherDiscoveredPerson.Reason]) -> String {
        reasons.compactMap { reason -> String? in
            switch reason {
            case .game(let titleId, let names): return FP.format(.bothPlay, games.first { $0.titleID == titleId }?.name ?? TogetherGameNames(names: names).name(in: lang) ?? titleId)
            case .friends(let count): return FP.format(.friendsInCommon, count)
            case .language(let code): return FP.format(.speaks, TogetherLanguages.name(code, in: lang))
            case .other: return nil
            }
        }.joined(separator: " · ")
    }

    func personRow(_ found: TogetherDiscoveredPerson, prefix: String, detail: String) -> PanelRow {
        let user = found.user
        let status: PanelPerson.Status? = found.presence.map { $0.state == "in_game" ? .playing : $0.state == "offline" ? .offline : .online }
        let person = PanelPerson(name: user.displayName, avatar: user.avatar, status: status)
        let text = ["@\(user.handle)", detail].filter { !$0.isEmpty }.joined(separator: " · ")
        if found.canAsk && !discover.askedFriends.contains(user.userId) {
            return PanelRow(id: "\(prefix)-\(user.userId)", title: FP.format(.addFriend, user.displayName), detail: text, symbol: "person.badge.plus",
                            kind: .action(destructive: false) { [weak self] in self?.addFriend(user) }, person: person)
        }
        let state = found.friendship == "friends" ? FP.text(.alreadyFriends) : found.friendship == "pending_in" ? T.text(.friendsWantsToBe) : T.text(.friendsWaiting)
        return PanelRow(id: "\(prefix)-\(user.userId)", title: user.displayName, detail: text + " · " + state, symbol: "person",
                        kind: .action(destructive: false) { [weak self] in self?.openProfile(user.handle, card: user) }, person: person)
    }

    func peopleRows() -> [PanelRow] {
        var rows: [PanelRow] = []
        let shown = discover.discovery?.discoverable
        rows.append(PanelRow(id: "people-discovery", title: FP.text(.discoverySettings), detail: shown.map { FP.text($0 ? .youShow : .youHide) } ?? FP.text(.discoveryDetail),
                             symbol: "eye", kind: .action(destructive: false) { [weak self] in self?.openDiscoverySettings() }))
        if discover.suggestions.isEmpty {
            rows.append(PanelRow(id: "people-none", title: FP.text(.noSuggestions), detail: FP.text(.noSuggestionsDetail), symbol: "person.2.slash", kind: .info("")))
        }
        rows += discover.suggestions.map { personRow($0, prefix: "people", detail: reasonText($0.reasons)) }
        return rows
    }

    func findPlayersCategories() -> [PanelCategory] {
        let waiting = discover.mine.reduce(0) { $0 + $1.pending.count }
        return [
            PanelCategory(id: "board", title: FP.text(.board), symbol: "person.3.sequence", rows: boardRows()),
            PanelCategory(id: "mine", title: waiting > 0 ? "\(FP.text(.myPosts)) (\(waiting))" : FP.text(.myPosts), symbol: "megaphone", rows: myPostRows()),
            PanelCategory(id: "live", title: FP.text(.liveAndParties), symbol: "dot.radiowaves.left.and.right", rows: liveRows()),
            PanelCategory(id: "people", title: FP.text(.people), symbol: "person.2.wave.2", rows: peopleRows()),
        ]
    }

    // MARK: A game's hub

    func hubCategories() -> [PanelCategory] {
        guard let titleId = discover.hubTitle else { return [] }
        let name = discover.hubName
        let local = games.first { $0.titleID == titleId }
        var now: [PanelRow] = []
        if let hub = discover.hub {
            now.append(PanelRow(id: "hub-count", title: FP.format(.playingNow, hub.playing.total), detail: FP.format(.players, hub.players), symbol: "gamecontroller.fill", kind: .info("")))
            for player in hub.playing.people {
                let minutes = player.since.map { max(1, Int(Date().timeIntervalSince($0) / 60)) }
                now.append(PanelRow(id: "hub-playing-\(player.user.userId)", title: player.user.displayName, detail: "@\(player.user.handle)" + (minutes.map { " · " + FP.format(.forMinutes, $0) } ?? ""),
                                    symbol: "person", kind: .action(destructive: false) { [weak self] in self?.openProfile(player.user.handle, card: player.user) },
                                    person: PanelPerson(name: player.user.displayName, avatar: player.user.avatar, status: .playing)))
            }
        } else {
            now.append(PanelRow(id: "hub-loading", title: discover.hubFailed ? T.text(.togetherUnreachable) : FP.text(.loading), symbol: discover.hubFailed ? "wifi.exclamationmark" : "ellipsis", kind: .info("")))
        }
        now.append(PanelRow(id: "hub-post", title: FP.format(.findFor, name), detail: FP.text(.findForDetail), symbol: "plus.bubble",
                            kind: .action(destructive: false) { [weak self] in self?.openLfgPost(titleId: titleId, name: name) }))
        if let local {
            now.append(PanelRow(id: "hub-board", title: TS.text(.boardTitle), detail: TS.text(.boardGameRowDetail), symbol: "list.number",
                                kind: .action(destructive: false) { [weak self] in self?.openLeaderboard(local) }))
        }
        now.append(PanelRow(id: "hub-compat", title: TS.text(.compatCommunity), detail: compatSummary(titleId).map(compatText) ?? TS.text(.compatNone), symbol: "person.3.sequence",
                            kind: local.map { game in .action(destructive: false) { [weak self] in self?.openCompat(game) } } ?? .info("")))

        let hub = discover.hub
        var posts = (hub?.lfg ?? []).map { postRow($0, prefix: "hub-post") }
        if posts.isEmpty { posts = [PanelRow(id: "hub-noposts", title: FP.text(.noPosts), detail: FP.text(.noPostsDetail), symbol: "person.3.sequence", kind: .info(""))] }
        var groups = (hub?.sharePlays ?? []).map { shareRow($0, prefix: "hub-live") } + (hub?.parties ?? []).map { partyRow($0, prefix: "hub-party") }
        if groups.isEmpty { groups = [PanelRow(id: "hub-nogroups", title: FP.text(.noGroups), symbol: "person.3", kind: .info(""))] }
        var players = (hub?.recentPlayers ?? []).map { found -> PanelRow in
            let played = found.lastPlayedAt.map { FP.format(.played, RelativeDateTimeFormatter.short.localizedString(for: $0, relativeTo: Date())) } ?? ""
            return personRow(found, prefix: "hub-player", detail: played)
        }
        if players.isEmpty { players = [PanelRow(id: "hub-noplayers", title: FP.text(.noPlayers), detail: FP.text(.noPlayersDetail), symbol: "person.2.slash", kind: .info(""))] }
        return [
            PanelCategory(id: "hub-now", title: FP.text(.overview), symbol: "gamecontroller", rows: now),
            PanelCategory(id: "hub-posts", title: FP.text(.board), symbol: "person.3.sequence", rows: posts),
            PanelCategory(id: "hub-groups", title: FP.text(.liveAndParties), symbol: "dot.radiowaves.left.and.right", rows: groups),
            PanelCategory(id: "hub-players", title: FP.text(.people), symbol: "person.2.wave.2", rows: players),
        ]
    }

    // MARK: The post form

    func lfgPostRows() -> [PanelRow] {
        guard let draft = discover.draft else { return [] }
        let purposes = TogetherLfgPurpose.allCases
        let languages = TogetherLanguages.common
        let first = draft.languages.first ?? lang
        let second = draft.languages.dropFirst().first
        let alsoOptions: [String?] = [nil] + languages.filter { $0 != first }
        let starts = Self.startChoices
        return [
            PanelRow(id: "post-purpose", title: FP.text(.purpose), detail: FP.text(draft.purpose == .coop ? .coopDetail : .partyDetail), symbol: "target",
                     kind: .choice(options: purposes.map(purposeName), selected: purposes.firstIndex(of: draft.purpose) ?? 0) { [weak self] index in
                         self?.discover.draft?.setPurpose(purposes[index])
                     }),
            PanelRow(id: "post-slots", title: FP.text(.slots), symbol: "person.2",
                     kind: .stepper(value: draft.slots, range: draft.slotRange, step: 1, format: { FP.format(.slotsCount, $0) }) { [weak self] value in self?.discover.draft?.slots = value }),
            PanelRow(id: "post-language", title: FP.text(.language), symbol: "globe",
                     kind: .choice(options: languages.map { TogetherLanguages.name($0, in: lang) }, selected: languages.firstIndex(of: first) ?? 0) { [weak self] index in
                         let pick = languages[index]
                         self?.discover.draft?.languages = [pick] + (second.map { $0 == pick ? [] : [$0] } ?? [])
                     }),
            PanelRow(id: "post-also", title: FP.text(.alsoIn), symbol: "globe.badge.chevron.backward",
                     kind: .choice(options: alsoOptions.map { $0.map { TogetherLanguages.name($0, in: lang) } ?? FP.text(.noOther) }, selected: alsoOptions.firstIndex(of: second) ?? 0) { [weak self] index in
                         self?.discover.draft?.languages = [first] + (alsoOptions[index].map { [$0] } ?? [])
                     }),
            PanelRow(id: "post-start", title: FP.text(.starts), symbol: "clock",
                     kind: .choice(options: starts.map { $0 == 0 ? FP.text(.now) : $0 < 60 ? FP.format(.inMinutes, $0) : FP.format(.inHours, $0 / 60) },
                                   selected: starts.firstIndex(of: draft.startsIn) ?? 0) { [weak self] index in
                         self?.discover.draft?.startsIn = starts[index]
                         if let draft = self?.discover.draft { self?.discover.draft?.hours = min(draft.hours, draft.hourRange.upperBound) }
                     }),
            PanelRow(id: "post-hours", title: FP.text(.staysUp), detail: FP.text(.staysUpDetail), symbol: "timer",
                     kind: .stepper(value: draft.hours, range: draft.hourRange, step: 1, format: { FP.format(.hours, $0) }) { [weak self] value in self?.discover.draft?.hours = value }),
            PanelRow(id: "post-note", title: FP.text(.note), detail: FP.text(.noteDetail), symbol: "text.quote",
                     kind: .text(draft.note) { [weak self] text in self?.discover.draft?.note = String(text.prefix(TogetherLfgDraft.maxNote)) }),
            PanelRow(id: "post-send", title: discover.posting ? FP.text(.posting) : FP.text(.post), detail: FP.text(.postDetail), symbol: "paperplane.fill",
                     kind: .action(destructive: false) { [weak self] in self?.sendPost() }),
            PanelRow(id: "post-cancel", title: T.text(.cancel), symbol: "xmark", kind: .action(destructive: false) { [weak self] in self?.backFromDiscover() }),
        ]
    }

    // MARK: Actions

    func sendPost() {
        guard let draft = discover.draft, !discover.posting else { return }
        discover.posting = true
        Task {
            defer { discover.posting = false }
            do {
                _ = try await together.postLfg(draft)
                show(FP.format(.posted, discover.draftName), symbol: "megaphone.fill")
                discover.draft = nil
                if discover.returnTo == .findPlayers || discover.returnTo == nil {
                    discover.returnTo = nil
                    openFindPlayers(category: 1)
                } else {
                    backFromDiscover()
                }
            } catch {
                show(discoverMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func imIn(_ post: TogetherLfgPost) {
        Task {
            do {
                let updated = try await together.joinLfg(post.id)
                replacePost(updated)
                show(FP.format(.toldThem, post.author.displayName), symbol: "hand.raised.fill")
            } catch {
                show(discoverMessage(error), symbol: "exclamationmark.triangle.fill")
                reloadDiscoverSoon()
            }
        }
    }

    func takeBack(_ post: TogetherLfgPost) {
        Task {
            try? await together.cancelLfgRequest(post.id)
            if let updated = try? await together.lfgPost(post.id) { replacePost(updated) }
            Sounds.shared.play(.back)
        }
    }

    func answer(_ post: TogetherLfgPost, _ user: TogetherPerson, accept: Bool) {
        Task {
            do {
                let updated = try await together.answerLfg(post.id, user: user.userId, accept: accept)
                replacePost(updated)
                if accept {
                    show(FP.format(post.purpose == .coop ? .letInDoneCoop : .letInDone, user.displayName), symbol: "person.crop.circle.badge.checkmark")
                    loadParty()
                }
            } catch {
                show(discoverMessage(error), symbol: "exclamationmark.triangle.fill")
                reloadDiscoverSoon()
            }
        }
    }

    func closePost(_ post: TogetherLfgPost) {
        Task {
            try? await together.closeLfg(post.id)
            if let mine = try? await together.myLfg() { withAnimation(Motion.overlay) { discover.mine = mine.posts; discover.asked = mine.asked } }
            Sounds.shared.play(.back)
        }
    }

    /// A post as it is now, wherever it shows.
    private func replacePost(_ post: TogetherLfgPost) {
        withAnimation(Motion.overlay) {
            if let index = discover.board.firstIndex(where: { $0.id == post.id }) { discover.board[index] = post }
            if let index = discover.mine.firstIndex(where: { $0.id == post.id }) { discover.mine[index] = post }
            if let index = discover.asked.firstIndex(where: { $0.id == post.id }) {
                discover.asked[index] = post
            } else if post.myRequest != nil {
                discover.asked.insert(post, at: 0)
            }
            if let hub = discover.hub, let index = hub.lfg.firstIndex(where: { $0.id == post.id }) {
                var posts = hub.lfg
                posts[index] = post
                discover.hub = TogetherGameHub(game: hub.game, players: hub.players, playing: hub.playing, lfg: posts, parties: hub.parties, sharePlays: hub.sharePlays, recentPlayers: hub.recentPlayers)
            }
        }
    }

    /// Accepted: to the party (its invite waits there) or the share play to watch.
    func followInvite(_ invite: TogetherLfgInvite?) {
        guard let invite else { return }
        if invite.isSharePlay { return watchShare(invite.id) }
        if party?.id == invite.id { return open(.party) }
        joinParty(invite.id)
    }

    func askToWatch(_ share: TogetherPublicShare) {
        Task {
            do {
                try await together.askToWatch(share.id)
                show(FP.format(.askedToWatchToast, share.host?.displayName ?? ""), symbol: "hand.raised.fill")
                reloadDiscoverSoon()
            } catch {
                show(discoverMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func askToJoin(_ listed: TogetherPublicParty) {
        Task {
            do {
                try await together.askToJoinParty(listed.id)
                show(FP.format(.askedPartyToast, listed.host?.displayName ?? ""), symbol: "hand.raised.fill")
                reloadDiscoverSoon()
            } catch {
                show(discoverMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func cancelPartyRequest(_ listed: TogetherPublicParty) {
        Task {
            try? await together.cancelPartyRequest(listed.id)
            reloadDiscoverSoon()
            Sounds.shared.play(.back)
        }
    }

    func addFriend(_ user: TogetherPerson) {
        Task {
            do {
                let state = try await together.askFriend(user.handle)
                withAnimation(Motion.overlay) { _ = discover.askedFriends.insert(user.userId) }
                show(T.format(state == "accepted" ? .friendsNowFriends : .friendsRequestSent, user.displayName), symbol: "person.badge.plus")
                refreshFriends()
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func discoverMessage(_ error: Error) -> String {
        guard let problem = error as? TogetherProblem else { return T.text(.togetherUnreachable) }
        switch problem.code {
        case "full": return FP.text(.full)
        case "rate_limited": return FP.text(.slowDown)
        case "conflict" where problem.title.contains("open posts"): return FP.text(.tooManyPosts)
        case "conflict" where problem.title.contains("closed"): return FP.text(.closed)
        default: return togetherMessage(error)
        }
    }

    // MARK: Events

    /// The board and public lists changed, or someone asked, took it back or answered.
    func discoverEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "lfg.changed", "discover.changed":
            reloadDiscoverSoon()
        case "lfg.request":
            let name = event.decode(AskData.self)?.from.displayName ?? ""
            let game = event.decode(AskData.self).map { gameName($0.titleId) } ?? ""
            let text = FP.format(.wantsIn, name, game)
            show(text, symbol: "hand.raised.fill")
            if !NSApp.isActive { TrophyBanner.shared.notice(text, detail: FP.text(.findPlayers), symbol: "hand.raised.fill", sounds: preferences.sounds) }
            refreshMine()
        case "lfg.request_cancelled":
            refreshMine()
        case "lfg.answered":
            if event.data["answer"] == "accepted" {
                let text = FP.text(event.decode(AnswerData.self)?.invite?.isSharePlay == true ? .youreInShare : .youreInParty)
                show(text, symbol: "checkmark.circle.fill")
                if !NSApp.isActive { TrophyBanner.shared.notice(text, detail: FP.text(.findPlayers), symbol: "checkmark.circle.fill", sounds: preferences.sounds) }
                loadParty()
                loadShareInvites()
            } else {
                show(FP.text(.notThisTime), symbol: "xmark.circle")
            }
            refreshMine()
        case "party.request":
            noteJoinRequest(event)
            let name = event.decode(AskData.self)?.from.displayName ?? ""
            show(FP.format(.asksParty, name), symbol: "hand.raised.fill")
            if !NSApp.isActive { TrophyBanner.shared.notice(FP.format(.asksParty, name), detail: T.text(.partyTitle), symbol: "hand.raised.fill", sounds: preferences.sounds) }
            loadParty()
        case "party.request_cancelled":
            loadParty()
        case "party.request_answered":
            show(FP.text(event.data["answer"] == "accepted" ? .partyLetYouIn : .notThisTime), symbol: event.data["answer"] == "accepted" ? "person.3.fill" : "xmark.circle")
            loadParty()
            reloadDiscoverSoon()
        case "share_play.request":
            noteJoinRequest(event)
            let name = event.decode(AskData.self)?.from.displayName ?? ""
            show(FP.format(.asksWatch, name), symbol: "hand.raised.fill")
            if !NSApp.isActive { TrophyBanner.shared.notice(FP.format(.asksWatch, name), detail: T.text(.friendsTitle), symbol: "hand.raised.fill", sounds: preferences.sounds) }
        case "share_play.request_answered":
            if event.data["answer"] != "accepted" { show(FP.text(.notThisTime), symbol: "xmark.circle") }
            reloadDiscoverSoon()
        default:
            break
        }
    }

    private struct AskData: Decodable { let from: TogetherPerson; let titleId: String? }
    private struct AnswerData: Decodable { let invite: TogetherLfgInvite? }

    private func refreshMine() {
        Task { if let mine = try? await together.myLfg() { withAnimation(Motion.overlay) { discover.mine = mine.posts; discover.asked = mine.asked } } }
        reloadDiscoverSoon()
    }

    private func gameName(_ titleId: String?) -> String { titleId.map { gameName($0) } ?? "" }

    // MARK: Discovery settings

    /// Settings → AnyTogether: whether people who don't know the user find them, and their languages.
    func discoveryRows() -> [PanelRow] {
        guard let discovery = discover.discovery else { return [] }
        let choices = TogetherDiscovery.Choice.allCases
        let names = [FP.text(.followLibrary), FP.text(.on), FP.text(.off)]
        var rows = [
            PanelRow(id: "discovery-title", title: FP.text(.discoveryTitle), detail: FP.text(discovery.discoverable ? .youShow : .youHide), symbol: "eye", kind: .info("")),
            PanelRow(id: "discovery-show", title: FP.text(.showMe), detail: FP.text(.showMeDetail), symbol: "person.crop.circle.badge.questionmark",
                     kind: .choice(options: names, selected: choices.firstIndex(of: discovery.choice) ?? 0) { [weak self] index in self?.setDiscovery(choices[index]) }),
            PanelRow(id: "discovery-languages", title: FP.text(.languagesTitle), detail: FP.text(.languagesDetail), symbol: "globe", kind: .info("")),
        ]
        // The usual languages, then any other the user chose.
        let offered = Array(TogetherLanguages.common.prefix(8))
        for code in offered + discovery.languages.filter({ !offered.contains($0) }) {
            rows.append(PanelRow(id: "discovery-language-\(code)", title: TogetherLanguages.name(code, in: lang), symbol: "character.bubble",
                                 kind: .toggle(discovery.languages.contains(code)) { [weak self] _ in self?.toggleDiscoveryLanguage(code) }))
        }
        return rows
    }

    func openDiscoverySettings() {
        openTogetherSettings()
        if let index = togetherRows().firstIndex(where: { $0.id == "discovery-show" }) { panelRow = index }
    }

    func setDiscovery(_ choice: TogetherDiscovery.Choice) {
        Task {
            do {
                let updated = try await together.setDiscovery(choice)
                withAnimation(Motion.overlay) { discover.discovery = updated }
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func toggleDiscoveryLanguage(_ code: String) {
        guard let discovery = discover.discovery else { return }
        guard let languages = discovery.toggling(code) else { return show(FP.text(.languagesFull), symbol: "globe") }
        // At once here; the server's answer follows.
        discover.discovery = TogetherDiscovery(discoverable: discovery.discoverable, chosen: discovery.chosen, languages: languages)
        Task {
            do {
                let updated = try await together.setDiscovery(languages: languages)
                discover.discovery = updated
            } catch {
                discover.discovery = discovery
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Previews

    func previewDiscover(_ state: DiscoverState) {
        discover = state
    }
}

extension RelativeDateTimeFormatter {
    static var short: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: T.language.rawValue)
        return formatter
    }
}
