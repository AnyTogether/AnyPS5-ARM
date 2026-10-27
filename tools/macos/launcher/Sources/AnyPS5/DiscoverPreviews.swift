import AnyPS5Core
import AppKit
import SwiftUI

/// Find players, a game's hub, the post form and the public toggles drawn offscreen for
/// `--render-preview`, with made-up people.
@MainActor
enum DiscoverPreviews {
    static func person(_ id: String, _ name: String) -> TogetherPerson { TogetherPerson(userId: id, handle: name.lowercased(), displayName: name, avatar: nil) }

    static func state(_ found: [Game]) -> DiscoverState {
        let title = found.first?.titleID ?? "PPSA01234"
        let other = found.dropFirst().first?.titleID ?? "PPSA02100"
        let now = Date()
        let mira = person("f1", "Mira"), kenji = person("f2", "Kenji"), lin = person("x1", "Lin"), ada = person("x2", "Ada"), robin = person("u1", "Robin")
        var state = DiscoverState()
        state.loaded = true
        state.board = [
            TogetherLfgPost(id: "l1", author: lin, titleId: title, purpose: .coop, languages: ["en", "tr"], slots: 2, filled: 1, note: "Chill run, no rush", expiresAt: now.addingTimeInterval(7200)),
            TogetherLfgPost(id: "l2", author: ada, titleId: other, purpose: .trophies, startsAt: now.addingTimeInterval(45 * 60), languages: ["en"], slots: 3,
                            expiresAt: now.addingTimeInterval(4 * 3600), myRequest: .init(status: "pending")),
            TogetherLfgPost(id: "l3", author: mira, titleId: title, purpose: .party, languages: ["tr"], slots: 4, filled: 2, expiresAt: now.addingTimeInterval(3600),
                            myRequest: .init(status: "accepted", invite: TogetherLfgInvite(kind: "party", id: "p7"))),
        ]
        state.more = true
        state.games = [TogetherLfgGame(titleId: title, posts: 2), TogetherLfgGame(titleId: other, posts: 1)]
        state.mine = [
            TogetherLfgPost(id: "m1", author: robin, titleId: title, purpose: .coop, languages: ["en"], slots: 3, filled: 1, note: "Looking for player 2 and 3", expiresAt: now.addingTimeInterval(9000),
                            mine: true, requests: [TogetherLfgRequest(user: kenji, status: "pending"), TogetherLfgRequest(user: ada, status: "pending"),
                                                   TogetherLfgRequest(user: mira, status: "accepted", invite: TogetherLfgInvite(kind: "share_play", id: "s1"))]),
        ]
        state.asked = [state.board[1]]
        state.shares = [
            TogetherPublicShare(id: "s9", host: lin, titleId: title, join: .open, live: true, viewers: 1, maxViewers: 3),
            TogetherPublicShare(id: "s8", host: ada, titleId: other, language: "en", join: .request, live: false, viewers: 0, maxViewers: 2),
        ]
        state.parties = [
            TogetherPublicParty(id: "p5", host: kenji, titleId: title, language: "tr", join: .open, size: 3),
            TogetherPublicParty(id: "p6", host: ada, join: .request, size: 2, requested: true),
        ]
        state.suggestions = [
            TogetherDiscoveredPerson(user: lin, presence: .init(state: "in_game", titleId: title), reasons: [.game(titleId: title, names: [:]), .friends(count: 2)]),
            TogetherDiscoveredPerson(user: ada, reasons: [.language("tr")]),
            TogetherDiscoveredPerson(user: person("x3", "Theo"), friendship: "pending_out", reasons: [.friends(count: 1)]),
        ]
        state.discovery = TogetherDiscovery(discoverable: true, chosen: nil, languages: ["tr", "en"])
        state.hubTitle = title
        state.hubName = found.first?.name ?? "Stray"
        state.hub = TogetherGameHub(game: .init(titleId: title, names: [:]), players: 128,
                                    playing: .init(total: 2, people: [.init(user: lin, since: now.addingTimeInterval(-50 * 60)), .init(user: kenji, since: now.addingTimeInterval(-8 * 60))]),
                                    lfg: [state.board[0], state.board[2]], parties: [state.parties[0]], sharePlays: [state.shares[0]],
                                    recentPlayers: [TogetherDiscoveredPerson(user: ada, lastPlayedAt: now.addingTimeInterval(-3 * 3600)), TogetherDiscoveredPerson(user: mira, friendship: "friends")])
        return state
    }

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.previewDiscover(state(found))
                configure(model)
            }
        }
        render("find-players") { model in model.overlay = .findPlayers; model.panelInRows = true; model.panelRow = 6 }
        render("find-players-mine") { model in model.overlay = .findPlayers; model.panelCategory = 1; model.panelInRows = true; model.panelRow = 2 }
        render("find-players-live") { model in model.overlay = .findPlayers; model.panelCategory = 2; model.panelInRows = true; model.panelRow = 1 }
        render("find-players-people") { model in model.overlay = .findPlayers; model.panelCategory = 3; model.panelInRows = true; model.panelRow = 1 }
        render("find-players-post") { model in
            model.discover.draft = TogetherLfgDraft(titleId: found.first?.titleID ?? "PPSA01234", purpose: .coop, slots: 2, languages: ["en", "tr"], note: "Chill run", startsIn: 30, hours: 3)
            model.discover.draftName = found.first?.name ?? "Stray"
            model.overlay = .lfgPost; model.panelInRows = true; model.panelRow = 1
        }
        render("game-hub") { model in model.overlay = .gameHub; model.panelInRows = true; model.panelRow = 1 }
        render("game-hub-posts") { model in model.overlay = .gameHub; model.panelCategory = 1; model.panelInRows = true; model.panelRow = 0 }
        render("game-hub-groups") { model in model.overlay = .gameHub; model.panelCategory = 2; model.panelInRows = false }
        render("game-settings-find") { model in
            model.overlay = .gameSettings; model.panelInRows = true
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "find-players" } ?? 0
        }
        render("friends-find") { model in model.overlay = .friends; model.panelInRows = true; model.panelRow = 1 }
        render("settings-discovery") { model in
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "together" } ?? 0
            model.panelInRows = true
            model.panelRow = model.togetherRows().firstIndex { $0.id == "discovery-show" } ?? 0
        }
        renderPublic(render, found)
    }

    /// The party and share play panels with their public listing and requests waiting.
    static func renderPublic(_ render: (String, (AppModel) -> Void) -> Void, _ found: [Game]) {
        let robin = person("u1", "Robin"), mira = person("f1", "Mira"), sol = person("f3", "Sol"), lin = person("x1", "Lin")
        render("party-public") { model in
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [robin, mira], invited: [], call: nil,
                                             listing: TogetherPartyListing(join: .request, titleId: found.first?.titleID, language: "en"), requests: [sol, lin]))
            model.overlay = .party; model.panelInRows = true
            model.panelRow = model.partyRows().firstIndex { $0.id.hasPrefix("party-request-accept") } ?? 0
        }
        render("share-public") { model in
            model.previewShare(TogetherSharePlay(id: "s1", host: robin, hostDevice: "d1", titleId: found.first?.titleID ?? "PPSA01234", title: found.first?.name, open: true, maxViewers: 3,
                                                 viewers: [.init(user: mira, device: "d2", slot: nil, joinedAt: nil)], listing: TogetherShareListing(join: .open, language: "tr", live: true),
                                                 requests: [sol]))
            model.overlay = .friends; model.panelInRows = true
            model.panelRow = model.friendRows().firstIndex { $0.id == "share-public" } ?? 0
        }
        render("party-find") { model in
            model.previewParty(nil)
            model.overlay = .party; model.panelInRows = true
            model.panelRow = model.partyRows().firstIndex { $0.id == "party-find" } ?? 0
        }
        renderCodes(render, found)
    }

    /// Join codes: the leader's code with a request that came with it, the party's Discord link,
    /// Deafen in the voice, a share play's code and "Join with a code".
    static func renderCodes(_ render: (String, (AppModel) -> Void) -> Void, _ found: [Game]) {
        let robin = person("u1", "Robin"), mira = person("f1", "Mira"), sol = person("f3", "Sol"), lin = person("x1", "Lin")
        let code = TogetherJoinCode(code: "K7QM3XPA", url: "https://anytogether.net/join/K7QM3XPA", expiresAt: Date().addingTimeInterval(20 * 3600))
        render("party-code") { model in
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [robin, mira, sol], invited: [],
                                             call: .init(id: "call1", in: ["u1", "f1", "f3"], muted: ["f3"], deafened: ["f3"]), requests: [lin], joinCode: code,
                                             discord: "https://discord.gg/anyps5"))
            model.previewVoice(call: "call1", speaking: ["f1"])
            model.codeAskers = ["x1"]
            model.mic.deafen()
            model.overlay = .party; model.panelInRows = true
            model.panelRow = model.partyRows().firstIndex { $0.id == "party-code-copy" } ?? 0
        }
        render("party-member-code") { model in
            model.previewParty(TogetherParty(id: "p1", leaderId: "f1", privacy: "invite", members: [mira, robin], invited: [], call: nil, joinCode: code, discord: "https://discord.gg/anyps5"))
            model.overlay = .party; model.panelInRows = true
            model.panelRow = model.partyRows().firstIndex { $0.id == "party-code-copy" } ?? 0
        }
        render("party-join-code") { model in
            model.previewParty(nil)
            model.previewJoinEntry(JoinEntry(text: "K7QM-3XPA", info: TogetherJoinInfo(code: "K7QM3XPA", kind: .party, id: "p7", host: .init(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil),
                                                                                       game: found.first.map { .init(titleId: $0.titleID, title: $0.name) }, size: 3, max: 8,
                                                                                       expiresAt: Date().addingTimeInterval(3600), state: .notIn)))
            model.overlay = .party; model.panelInRows = true
            model.panelRow = model.partyRows().firstIndex { $0.id == "join-code-ask" } ?? 0
        }
        render("party-join-code-wrong") { model in
            model.previewParty(nil)
            model.previewJoinEntry(JoinEntry(text: "ZZZZ-ZZZZ", message: JS.text(.noSuchCode)))
            model.overlay = .party; model.panelInRows = true
            model.panelRow = model.partyRows().firstIndex { $0.id == "join-code" } ?? 0
        }
        render("share-code") { model in
            model.previewShare(TogetherSharePlay(id: "s1", host: robin, hostDevice: "d1", titleId: found.first?.titleID ?? "PPSA01234", title: found.first?.name, open: true, maxViewers: 3,
                                                 viewers: [.init(user: mira, device: "d2", slot: nil, joinedAt: nil)], requests: [sol], joinCode: code))
            model.codeAskers = ["f3"]
            model.overlay = .friends; model.panelInRows = true
            model.panelRow = model.friendRows().firstIndex { $0.id == "share-code-copy" } ?? 0
        }
        render("call-deafened") { model in
            model.previewCall(with: mira, waiting: false, muted: ["f1"], deafened: ["f1"], deafenedHere: true)
            model.overlay = .friends; model.panelInRows = true
            model.panelRow = model.friendRows().firstIndex { $0.id == "voice-deafen" } ?? 0
        }
    }
}
