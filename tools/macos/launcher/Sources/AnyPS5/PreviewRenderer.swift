import AnyPS5Core
import AppKit
import SwiftUI

/// Draws the launcher's screens into PNG files offscreen: no window opens, nothing is saved.
@MainActor
enum PreviewRenderer {
    static let size = CGSize(width: 1600, height: 900)
    static var stills: [Theme: NSImage] = [:]

    /// The game ANYPS5_PREVIEW_SELECT picks: the first title ID in it.
    static var selectedTitle: String? {
        ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SELECT"]?.split(separator: ",").first.map(String.init)
    }

    static func run(output: URL, games root: URL) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // ANYPS5_PREVIEW_SELECT=<title ID>[,<title ID>…] puts those games first, in that order: the
        // first is selected and is the one friends play.
        let chosen = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SELECT"]?.split(separator: ",").map(String.init) ?? []
        let scanned = GameLibrary.scan(root)
        let found = chosen.compactMap { id in scanned.first { $0.titleID == id } } + scanned.filter { !chosen.contains($0.titleID) }
        for game in found {
            Artwork.shared.prepare(game.icon, maxPixels: 400)
            Artwork.shared.prepare(game.background, maxPixels: Int(max(size.width, size.height) * 1.6))
        }
        var preferences = Preferences()
        preferences.onboarded = true
        preferences.gamesFolder = root.path
        preferences.sounds = false
        preferences.profileName = "Robin"
        // ANYPS5_PREVIEW_LANGUAGE=tr draws the screens in Turkish.
        preferences.language = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_LANGUAGE"].flatMap(Language.init(rawValue:)) ?? .english
        // ANYPS5_PREVIEW_SCREENSHOTS=<folder> is where the gallery looks.
        if let shots = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SCREENSHOTS"] { preferences.screenshotsFolder = shots }

        for theme in Theme.allCases {
            stills[theme] = BackgroundView.still(theme: theme, width: 660, height: 372, time: 200)
        }
        for theme in Theme.allCases {
            preferences.theme = theme
            let still = BackgroundView.still(theme: theme, width: Int(size.width), height: Int(size.height), time: 260)
            preferences.gameArtwork = false
            render(preferences, found, root, still, output.appendingPathComponent("home-theme\(theme.rawValue).png"))
        }
        preferences.theme = .cosmic
        preferences.gameArtwork = true
        let still = BackgroundView.still(theme: .cosmic, width: Int(size.width), height: Int(size.height), time: 260)
        render(preferences, found, root, still, output.appendingPathComponent("home-artwork.png"))
        render(preferences, found, root, still, output.appendingPathComponent("home-actions.png")) { model in model.focus = .actions(0) }
        render(preferences, found, root, still, output.appendingPathComponent("home-unlocking.png")) { model in
            if let game = model.selectedGame { model.previewProgress(game, step: .copy, fraction: 0.4) }
        }
        render(preferences, found, root, still, output.appendingPathComponent("starting.png")) { model in
            if let game = model.selectedGame { model.previewStarting(game) }
        }
        render(preferences, found, root, still, output.appendingPathComponent("game-settings.png")) { model in model.overlay = .gameSettings; model.panelInRows = true; model.panelRow = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("controls.png")) { model in model.overlay = .controls; model.panelInRows = true; model.panelRow = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("controls-game.png")) { model in
            model.previewGameControls([.cross: ["Jump"], .circle: ["Cancel", "Drop"], .square: ["Interact primary"], .triangle: ["Meow"], .r2: ["Sprint"],
                                       .leftStickUp: ["Move forward"], .options: ["Open menu"]])
            model.overlay = .controls; model.panelInRows = true; model.panelRow = 1
        }
        let neon = ThemeDesign(id: "neon", name: "Neon Nights", author: "Ada", style: 0, deep: "#0A0014", middle: "#4A0E6B", bright: "#FF5EDB", accent: "#FF4FD8")
        let forest = ThemeDesign(id: "forest", name: "Forest", author: "Robin", style: 1, deep: "#02100A", middle: "#0E4A2C", bright: "#9BFFC4", accent: "#5CEB9F")
        for (name, overlay, row) in [("themes", Overlay.themes, 4), ("studio", Overlay.studio, 3)] {
            let palette = overlay == .studio ? neon.palette : forest.palette
            let tinted = BackgroundView.still(theme: overlay == .studio ? .cosmic : .aurora, palette: palette, width: Int(size.width), height: Int(size.height), time: 260)
            var plain = preferences
            plain.gameArtwork = false
            render(plain, found, root, tinted, output.appendingPathComponent("\(name).png")) { model in
                model.previewThemes([forest, neon], active: overlay == .studio ? neon : forest, hub: [neon, ThemeDesign(id: "mono", name: "Monochrome", author: "Lin", style: 2, deep: "#050505", middle: "#2A2A2A", bright: "#E6E6E6", accent: "#FFFFFF")])
                model.overlay = overlay; model.panelInRows = true; model.panelRow = row
            }
        }
        do {
            var plain = preferences
            plain.gameArtwork = false
            let hub = [neon,
                       ThemeDesign(id: "mono", name: "Monochrome", author: "Lin", style: 2, deep: "#050505", middle: "#2A2A2A", bright: "#E6E6E6", accent: "#FFFFFF"),
                       ThemeDesign(id: "deepsea", name: "Deep Sea", author: "Kenji", style: 0, deep: "#00121C", middle: "#0B3D5C", bright: "#7FE3FF", accent: "#3DC8FF"),
                       ThemeDesign(id: "ember", name: "Ember", author: "Sol", style: 1, deep: "#140400", middle: "#5C1A06", bright: "#FFB070", accent: "#FF7A3D"),
                       forest]
            let tinted = BackgroundView.still(theme: .cosmic, palette: neon.palette, width: Int(size.width), height: Int(size.height), time: 260)
            render(plain, found, root, tinted, output.appendingPathComponent("themes-hub.png")) { model in
                model.previewThemes([neon], active: neon, hub: hub)
                model.overlay = .themes; model.panelInRows = true; model.panelRow = 10
            }
        }
        render(preferences, found, root, still, output.appendingPathComponent("together.png")) { model in
            model.overlay = .settings; model.panelCategory = 4; model.panelInRows = true; model.panelRow = 2
        }
        render(preferences, found, root, still, output.appendingPathComponent("together-code.png")) { model in
            model.togetherStep = .deviceCode(code: "K7QM-2XZP", url: URL(string: "https://anytogether.kodla.agency/link?code=K7QM-2XZP")!)
            model.overlay = .settings; model.panelCategory = 4; model.panelInRows = true; model.panelRow = 2
        }
        render(preferences, found, root, still, output.appendingPathComponent("together-in.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherConnected = true
            model.overlay = .settings; model.panelCategory = 4; model.panelInRows = true; model.panelRow = 2
        }
        for (name, row) in [("together-edit", 4), ("together-privacy", 11)] {
            render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
                model.togetherConnected = true
                model.previewOwnProfile(TogetherOwnProfile(handle: "robin", displayName: "Robin", bio: "Platinum hunter", avatar: nil, country: "TR",
                                                           handleChangeAt: Date().addingTimeInterval(12 * 86_400), privacy: .standard))
                model.overlay = .settings; model.panelCategory = 4; model.panelInRows = true; model.panelRow = row
            }
        }
        render(preferences, found, root, still, output.appendingPathComponent("friends.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-25 * 60))
            model.togetherFriends = [
                TogetherFriend(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: since)),
                TogetherFriend(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil)),
                TogetherFriend(userId: "f3", handle: "kenji", displayName: "Kenji", avatar: nil, presence: nil),
            ]
            model.togetherRequests = TogetherRequests(incoming: [TogetherPerson(userId: "f4", handle: "ines", displayName: "Ines", avatar: nil)], outgoing: [])
            model.overlay = .friends; model.panelInRows = true; model.panelRow = 0
        }
        let ago = { (hours: Double) in Date().addingTimeInterval(-hours * 3600) }
        let library: [TogetherPlayedGame] = found.prefix(3).enumerated().map { index, game in
            TogetherPlayedGame(titleId: game.titleID, names: ["en": game.name], iconUrl: nil, lastPlayedAt: ago(Double(index * 30 + 2)),
                               secondsPlayed: [151_200, 26_100, 2_700][index], trophiesEarned: [31, 9, 1][index], trophiesTotal: [48, 40, nil][index], progress: [64, 22, nil][index], points: [1_830, 420, 15][index])
        } + [TogetherPlayedGame(titleId: "PPSA09999", names: ["en": "Stray"], iconUrl: nil, lastPlayedAt: ago(400), secondsPlayed: 72_000, trophiesEarned: 12, trophiesTotal: 41, progress: 29, points: 600)]
        let earned: [TogetherEarnedTrophy] = [
            ("Platinum", "platinum", 0.008, "ultra_rare"), ("Against All Odds", "gold", 0.031, "very_rare"), ("Night Walker", "silver", 0.12, "rare"),
            ("Curious Cat", "bronze", 0.34, "uncommon"), ("First Steps", "bronze", 0.92, "common"), ("Secret", "bronze", 0.4, "uncommon"),
        ].enumerated().map { index, item in
            let game = library[min(index / 2, library.count - 1)]
            return TogetherEarnedTrophy(titleId: game.titleId, gameNames: game.names, trophyId: index, grade: item.1, hidden: index == 5,
                                        texts: index == 5 ? nil : ["en": .init(name: item.0)], earnedAt: ago(Double(index * 20 + 1)), rarity: item.2, rarityLabel: item.3)
        }
        let mira = TogetherProfile(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, bio: "Souls games, slowly. Platinum hunter on weekends.", country: "TR", friendship: "friends")
        render(preferences, found, root, still, output.appendingPathComponent("profile.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.previewProfile(TogetherProfilePage(profile: mira, library: .shown(library), trophies: .shown(earned)), column: 0, index: 1)
            model.social.profileActivity = SocialPreviews.activity(found).filter { $0.actor.userId == "f1" }
        }
        render(preferences, found, root, still, output.appendingPathComponent("profile-trophies.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            let me = TogetherProfile(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil, bio: nil, country: nil, friendship: "me")
            model.previewProfile(TogetherProfilePage(profile: me, library: .shown(library), trophies: .shown(earned)), column: 1, index: 1)
        }
        render(preferences, found, root, still, output.appendingPathComponent("profile-private.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            let kenji = TogetherProfile(userId: "f3", handle: "kenji", displayName: "Kenji", avatar: nil, bio: nil, country: nil, friendship: "none")
            model.previewProfile(TogetherProfilePage(profile: kenji, library: .private, trophies: .private))
        }
        render(preferences, found, root, still, output.appendingPathComponent("profile-loading.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.previewProfile(nil)
            model.profileCard = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)
        }
        let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let people = [TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil), TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)]
        let lines: [(String, String)] = [("f1", "Are you still on the Silksong boss?"), ("u1", "Yes, third try. The second phase is brutal"), ("f1", "Dash through the spikes, not over them"),
                                         ("u1", "Oh! Trying that now"), ("f1", "GG when you get it 🏆"), ("u1", "On my way")]
        let thread = lines.enumerated().map { index, line in
            TogetherMessage(id: "m\(index)", conversationId: "c1", seq: index + 1, authorId: line.0, text: line.1, createdAt: ago(Double(lines.count - index) * 0.1))
        }
        var inbox = TogetherInbox(me: "u1", conversations: [
            TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, people[0]], lastSeq: 6, readSeq: 6, unread: 0, lastMessage: thread.last, updatedAt: ago(0.1)),
            TogetherConversation(id: "c2", kind: "direct", title: nil, members: [robin, people[1]], lastSeq: 3, readSeq: 1, unread: 2,
                                 lastMessage: TogetherMessage(id: "k3", conversationId: "c2", seq: 3, authorId: "f2", text: "Party tonight?", createdAt: ago(3)), updatedAt: ago(3)),
            TogetherConversation(id: "c3", kind: "group", title: "Souls club", members: [robin] + people, lastSeq: 40, readSeq: 40, unread: 0,
                                 lastMessage: TogetherMessage(id: "g40", conversationId: "c3", seq: 40, authorId: "f2", text: "Who has the platinum?", createdAt: ago(30)), updatedAt: ago(30)),
        ])
        inbox.threads["c1"] = thread
        for (name, inThread, focus) in [("messages", false, nil), ("messages-thread", true, 2)] as [(String, Bool, Int?)] {
            render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
                model.togetherFriends = [TogetherFriend(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: nil)),
                                         TogetherFriend(userId: "f5", handle: "theo", displayName: "Theo", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil))]
                model.previewMessages(inbox, index: 0, inThread: inThread, focus: focus)
            }
        }
        render(preferences, found, root, still, output.appendingPathComponent("messages-typing.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.previewMessages(inbox, index: 0, inThread: true)
            model.typing.typing("f1", in: "c1")
        }
        render(preferences, found, root, still, output.appendingPathComponent("messages-group.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = [TogetherFriend(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil)),
                                     TogetherFriend(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil, presence: nil),
                                     TogetherFriend(userId: "f5", handle: "theo", displayName: "Theo", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil))]
            model.previewMessages(inbox, index: 3, inThread: true)
            model.previewGroup(picked: ["f1", "f5"], name: "Co-op night", focus: 2)
        }
        render(preferences, found, root, still, output.appendingPathComponent("home-messages.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.inbox = inbox
            model.focus = .top(3)
        }
        let partyFriends = [
            TogetherFriend(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: nil)),
            TogetherFriend(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil, party: .init(id: "p7", size: 3, max: 8, open: true))),
            TogetherFriend(userId: "f3", handle: "kenji", displayName: "Kenji", avatar: nil, presence: nil),
        ]
        render(preferences, found, root, still, output.appendingPathComponent("party.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [robin, people[0]], invited: [TogetherPerson(userId: "f3", handle: "kenji", displayName: "Kenji", avatar: nil)],
                                             call: .init(id: "call1", in: ["u1", "f1"])))
            model.overlay = .party; model.panelInRows = true; model.panelRow = 4
        }
        render(preferences, found, root, still, output.appendingPathComponent("party-voice.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "friends", members: [robin, people[0], people[1]], invited: [], call: .init(id: "call1", in: ["u1", "f1", "f2"])))
            model.previewVoice(call: "call1", speaking: ["f1"])
            model.overlay = .party; model.panelInRows = true; model.panelRow = 0
        }
        render(preferences, found, root, still, output.appendingPathComponent("call-ringing.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.previewRinging(TogetherRinging(callId: "call2", from: people[0], device: "sess-f1"))
        }
        render(preferences, found, root, still, output.appendingPathComponent("call-friends.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewCall(with: people[0], waiting: false, speaking: ["f1"], muted: [])
            model.overlay = .friends; model.panelInRows = true; model.panelRow = 1
        }
        render(preferences, found, root, still, output.appendingPathComponent("party-muted.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "friends", members: [robin, people[0], people[1]], invited: [],
                                             call: .init(id: "call1", in: ["u1", "f1", "f2"], muted: ["f2"])))
            model.previewVoice(call: "call1", speaking: ["f1"])
            model.overlay = .party; model.panelInRows = true; model.panelRow = 0
        }
        render(preferences, found, root, still, output.appendingPathComponent("party-none.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(nil, invites: [TogetherPartyInvite(partyId: "p9", from: people[0], size: 2)])
            model.overlay = .party; model.panelInRows = true; model.panelRow = 0
        }
        render(preferences, found, root, still, output.appendingPathComponent("friends-games.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            let title = found.first?.titleID ?? "PPSA01234"
            model.togetherFriends = [
                TogetherFriend(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil,
                               presence: .init(state: "in_game", titleId: title, since: nil, game: .init(sessionId: "s1", titleId: title, joinable: true, players: 1, capacity: 4))),
                TogetherFriend(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil, party: .init(id: "p7", size: 3, max: 8, open: true))),
            ]
            model.previewGameSession(nil, invites: [TogetherGameInvite(sessionId: "s2", from: TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil),
                                                                       titleId: found.last?.titleID ?? title, gameVersion: "01.000.000", engineBuild: "0.2.13-abc")])
            model.overlay = .friends; model.panelInRows = true; model.panelRow = 3
        }
        render(preferences, found, root, still, output.appendingPathComponent("friends-share.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            let viewers = [TogetherSharePlay.Viewer(user: people[0], device: "web1", slot: 2, joinedAt: nil), TogetherSharePlay.Viewer(user: people[1], device: "phone1", slot: nil, joinedAt: nil)]
            model.previewShare(TogetherSharePlay(id: "sp1", host: robin, hostDevice: "mac", titleId: found.first?.titleID ?? "PPSA01234", title: found.first?.name, open: true, maxViewers: 3,
                                                 viewers: viewers, invited: []),
                               links: ["f1": .init(state: .connected, roundTrip: 38, sendRate: 9_000_000, relayed: false, framesPerSecond: 60, frameHeight: 720),
                                       "f2": .init(state: .connected, roundTrip: 71, sendRate: 4_000_000, relayed: true, framesPerSecond: 60, frameHeight: 720)])
            model.overlay = .friends; model.panelInRows = true; model.panelRow = 4
        }
        render(preferences, found, root, still, output.appendingPathComponent("friends-share-invite.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewShare(nil, invites: [TogetherShareInvite(sharePlayId: "sp9", from: people[0], titleId: found.first?.titleID ?? "PPSA01234", title: "Cat Quest III")])
            model.overlay = .friends; model.panelInRows = true; model.panelRow = 2
        }
        render(preferences, found, root, still, output.appendingPathComponent("share-watch.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.share.watching = TogetherSharePlay(id: "sp9", host: people[0], hostDevice: "mac9", titleId: "PPSA01234", title: "Cat Quest III", open: true, maxViewers: 2,
                                                     viewers: [TogetherSharePlay.Viewer(user: robin, device: "mac", slot: nil, joinedAt: nil)])
            model.share.watchConnected = true
            model.share.watchStats = .init(roundTrip: 42, fps: 60, height: 720)
        }
        render(preferences, found, root, still, output.appendingPathComponent("controls-capture.png")) { model in model.overlay = .controls; model.panelInRows = true; model.panelRow = 3; model.capturing = .square }
        render(preferences, found, root, still, output.appendingPathComponent("pairing.png")) { model in model.previewPairing(PairingRequest(id: UUID(), deviceName: "Pixel 8", code: "4821")) }
        render(preferences, found, root, still, output.appendingPathComponent("home-phone.png")) { model in model.previewPhone("Pixel 8", latency: 9) }
        render(preferences, found, root, still, output.appendingPathComponent("home-phone-connecting.png")) { model in model.previewPhoneConnecting("Pixel 8") }
        render(preferences, found, root, still, output.appendingPathComponent("home-phones.png")) { model in
            model.previewPhones([PhoneBadge(id: "a", name: "Pixel 8", number: 1), PhoneBadge(id: "b", name: "Galaxy", number: 2), PhoneBadge(id: "c", name: "iPhone", number: nil)])
        }
        render(preferences, found, root, still, output.appendingPathComponent("advanced.png")) { model in model.overlay = .advanced; model.panelInRows = true; model.panelRow = 4 }
        render(preferences, found, root, still, output.appendingPathComponent("update-choice.png")) { model in model.overlay = .updateChoice; model.panelInRows = true; model.panelRow = 0 }
        renderCrashReport(preferences, found, root, still, output)
        render(preferences, found, root, still, output.appendingPathComponent("home-trophies.png")) { model in model.focus = .actions(1) }
        render(preferences, found, root, still, output.appendingPathComponent("trophies.png")) { model in model.overlay = .trophies; model.trophyIndex = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("trophies-r1.png")) { model in model.overlay = .trophies; model.trophyIndex = 5; model.switchGame(1) }
        render(preferences, found, root, still, output.appendingPathComponent("game-settings-r1.png")) { model in model.overlay = .gameSettings; model.panelInRows = true; model.panelRow = 1; model.switchGame(1) }
        render(preferences, found, root, still, output.appendingPathComponent("settings.png")) { model in model.overlay = .settings; model.panelInRows = true; model.panelRow = 0 }
        for category in 1..<6 {
            render(preferences, found, root, still, output.appendingPathComponent("settings\(category).png")) { model in model.overlay = .settings; model.panelCategory = category }
        }
        render(preferences, found, root, still, output.appendingPathComponent("about-update.png")) { model in
            model.previewUpdate(Updates.Release(tag: "v0.2.6-arm", version: "0.2.6", page: URL(string: "https://github.com/utkuhalis/AnyPS5-ARM/releases/tag/v0.2.6-arm")!, download: nil, size: nil), progress: 0.42)
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "about" } ?? 0
            model.panelInRows = true
            model.panelRow = 2
        }
        renderEngines(preferences, found, root, still, output)
        render(preferences, found, root, still, output.appendingPathComponent("gallery.png")) { model in model.open(.gallery); model.galleryIndex = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("gallery-viewer.png")) { model in model.open(.gallery); model.galleryViewing = true }
        render(preferences, found, root, still, output.appendingPathComponent("game-settings-saves.png")) { model in model.overlay = .gameSettings; model.panelInRows = true; model.panelRow = 10 }
        render(preferences, found, root, still, output.appendingPathComponent("library.png")) { model in model.overlay = .library; model.libraryIndex = 1 }
        renderBanner(preferences, found, root, output.appendingPathComponent("trophy-banner.png"))
        renderRingBanner(TogetherRinging(callId: "call2", from: people[0], device: "sess-f1"), output.appendingPathComponent("call-banner.png"))
        var fresh = preferences
        fresh.onboarded = false
        fresh.gamesFolder = nil
        for step in 0..<3 {
            if step == 2 { fresh.gamesFolder = root.path }
            render(fresh, step == 2 ? found : [], root, still, output.appendingPathComponent("onboarding\(step).png")) { model in model.onboardingStep = step }
        }
        SocialPreviews.run(preferences, found, root, still, output)
        DiscoverPreviews.run(preferences, found, root, still, output)
        print("rendered into \(output.path)")
    }

    /// The trophy card over a picture of a game (ANYPS5_PREVIEW_BANNER_BACKDROP), with the selected
    /// game's first earned trophy.
    static func renderBanner(_ preferences: Preferences, _ games: [Game], _ root: URL, _ file: URL) {
        let model = AppModel(preferences: preferences)
        model.preview(games: games, root: root)
        let pick = selectedTitle.flatMap { id in games.first { $0.titleID == id } } ?? games.first
        guard let game = pick, let trophy = model.trophies[game.id]?.trophies.first(where: { $0.unlocked != nil }) else { return }
        let backdrop = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_BANNER_BACKDROP"].flatMap { NSImage(contentsOfFile: $0) }
        let view = ZStack(alignment: .top) {
            if let backdrop {
                Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height)
            } else {
                Color.black
            }
            TrophyToast(trophy: trophy, still: true) {}
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    }

    /// The ringing card over a game, on a picture of one (ANYPS5_PREVIEW_BANNER_BACKDROP) or black.
    static func renderRingBanner(_ call: TogetherRinging, _ file: URL) {
        if let only = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"]?.split(separator: ","), !only.contains(where: { file.lastPathComponent.hasPrefix($0) }) { return }
        let backdrop = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_BANNER_BACKDROP"].flatMap { NSImage(contentsOfFile: $0) }
        let view = ZStack(alignment: .top) {
            if let backdrop {
                Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height)
            } else {
                Color(white: 0.15)
            }
            RingToast(call: call, still: true)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    }

    /// The crash panel after a made-up crash, its issue text before it is shared, and the
    /// game's settings on detailed logging.
    static func renderCrashReport(_ preferences: Preferences, _ games: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        func report(for model: AppModel) -> SessionReport? {
            guard let game = model.selectedGame else { return nil }
            var settings = model.settings(for: game)
            settings.frameGeneration = true
            let log = [
                "[present] frame generation on: the game at 58.9 fps with it, 60.0 without",
                "[shader-disk-cache] (10 s): 31 hits, 2 misses, 2 writes (0.4 MiB), 0 load failures, 0 write failures",
                "[src/Open.cpp:288 sceKernelOpen] path=/app0/Media/StreamingAssets/aa/PS5/489c1db4.bundle flags=0x0 mode=00",
                "[log] 10.2 s: 32 lines (32 stdout, 0 stderr), 3.6 KiB written, 0 repeats coalesced",
                "[gpu] storage image 0x1d8d50000+0x870000: memory no longer registered; 135 pending ranges dropped",
                "[src/Texture.cpp:337 Texture] Texture address=0x1b19c1000 1024x1024 mips=1 layers=1 dim=1 tile=2 format=169",
                "[memory] map direct 0x2c0000000+0x4000000 phys=0x80000000 prot=0x3 flags=0x10",
                "[gpu] screenshot saved: /Users/someone/Pictures/AnyPS5/\(game.titleID)-20261024-214155.png",
                "[libc] abort() called from 0x80023f9c4",
            ]
            let body: [String: Any] = [
                "pid": 4242, "exception": ["type": "EXC_CRASH", "signal": "SIGABRT"], "faultingThread": 0,
                "threads": [["frames": [["imageOffset": 38_564, "imageIndex": 0, "symbol": "__pthread_kill", "symbolLocation": 8],
                                        ["imageOffset": 0x23f9c4, "imageIndex": 1]]]],
                "usedImages": [["name": "libsystem_kernel.dylib"], ["name": "eboot"]],
            ]
            let ips = #"{"app_name":"eboot","name":"eboot"}"# + "\n" + String(decoding: (try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)) ?? Data(), as: UTF8.self)
            var report = SessionReport(gameName: game.name, titleID: game.titleID, gameVersion: game.version, settings: settings,
                                       system: SystemInfo(model: "Mac15,7", chip: "Apple M3 Pro", memoryGB: 18, macOS: "15.6 (24G84)", displayHz: 120),
                                       launcherVersion: "0.2.14", session: (Array(repeating: log, count: 6).flatMap { $0.dropLast() } + log).joined(separator: "\n"),
                                       privacy: ReportPrivacy(home: "/Users/someone", names: ["someone"]))
            report.unlockedWith = "0.2.14-arm-5c0ffee12345"
            report.engineNow = report.unlockedWith
            report.diagnosis = .aborted
            report.crashReport = ips
            report.started = Date().addingTimeInterval(-25 * 60)
            report.ended = Date()
            return report
        }
        for (name, sharing) in [("crash-report", false), ("crash-report-share", true)] {
            render(preferences, games, root, still, output.appendingPathComponent("\(name).png")) { model in
                if let report = report(for: model) { model.previewSessionReport(report, sharing: sharing) }
            }
        }
        render(preferences, games, root, still, output.appendingPathComponent("game-settings-trace.png")) { model in
            model.overlay = .gameSettings
            model.panelInRows = true
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "trace" } ?? 0
        }
    }

    /// The engine picker: Settings → Engine with downloaded engines and the releases' ones, a
    /// game's own engine, and the Update and Play offer after switching it.
    static func renderEngines(_ preferences: Preferences, _ games: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        func installed(_ version: String, built: String) -> InstalledToolkit {
            InstalledToolkit(version: version, folder: URL(fileURLWithPath: "/nonexistent/\(version)"), manifest: ToolkitManifest(version: version, buildDate: built))
        }
        let downloaded = [installed("0.2.16-arm-5c0ffee12345", built: "2026-11-02T10:00:00Z"), installed("0.2.15-arm-0badc0de4321", built: "2026-10-25T10:00:00Z")]
        let page = URL(string: "https://github.com/utkuhalis/AnyPS5-ARM/releases")!
        let day = { (days: Double) in Date().addingTimeInterval(-days * 86_400) }
        let catalogue = [
            EngineCatalogue.Entry(release: "0.2.17-arm", tag: "v0.2.17-arm", title: "AnyPS5-ARM 0.2.17", summary: "Faster shader cache · Stray holds 60 FPS", date: day(1), page: page, download: page, size: 39_000_000, digest: nil, prerelease: false),
            EngineCatalogue.Entry(release: "0.2.16-arm", tag: "v0.2.16-arm", title: "AnyPS5-ARM 0.2.16", summary: "Co-op fixes", date: day(9), page: page, download: page, size: 39_000_000, digest: nil, prerelease: false),
            EngineCatalogue.Entry(release: "0.2.18-arm", tag: "v0.2.18-arm", title: "AnyPS5-ARM 0.2.18", summary: "Experimental frame generation", date: day(0.2), page: page, download: page, size: 39_000_000, digest: nil, prerelease: true),
        ]
        var chosen = preferences
        chosen.engine = downloaded[0].version
        render(chosen, games, root, still, output.appendingPathComponent("engine.png")) { model in
            model.previewEngines(installed: downloaded, catalogue: catalogue, checked: day(0.01), downloads: ["0.2.18-arm": 0.37])
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "engine" } ?? 0
            model.panelInRows = true
            model.panelRow = 0
        }
        render(chosen, games, root, still, output.appendingPathComponent("engine-offline.png")) { model in
            model.previewEngines(installed: [], catalogue: catalogue, checked: day(3))
            model.engineOffline = true
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "engine" } ?? 0
            model.panelInRows = true
            model.panelRow = model.panelCategories()[model.panelCategory].rows.firstIndex { $0.id == "engineRefresh" } ?? 0
        }
        guard let game = games.indices.contains(min(1, max(0, games.count - 1))) ? games[min(1, max(0, games.count - 1))] : nil else { return }
        var own = chosen
        own.games[game.id, default: GameSettings()].engine = downloaded[1].version
        render(own, games, root, still, output.appendingPathComponent("engine-game.png")) { model in
            model.previewEngines(installed: downloaded, catalogue: catalogue, checked: day(0.01))
            model.overlay = .gameSettings
            model.panelInRows = true
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "engine" } ?? 0
        }
        render(own, games, root, still, output.appendingPathComponent("engine-update.png")) { model in
            model.previewEngines(installed: downloaded, catalogue: catalogue, checked: day(0.01))
            model.overlay = .updateChoice
            model.panelInRows = true
        }
        render(own, games, root, still, output.appendingPathComponent("engine-home.png")) { model in
            model.previewEngines(installed: downloaded, catalogue: catalogue, checked: day(0.01))
        }
    }

    static func render(_ preferences: Preferences, _ games: [Game], _ root: URL, _ still: NSImage?, _ file: URL, configure: (AppModel) -> Void = { _ in }) {
        // ANYPS5_PREVIEW_ONLY=party,messages draws only the screens whose file names start so.
        if let only = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"]?.split(separator: ","), !only.contains(where: { file.lastPathComponent.hasPrefix($0) }) { return }
        let model = AppModel(preferences: preferences)
        model.preview(games: games, root: root)
        // ANYPS5_PREVIEW_SELECT=<title ID> picks the game the screens show.
        let pick = selectedTitle.flatMap { id in games.firstIndex { $0.titleID == id } }
        model.selected = pick ?? min(1, max(0, games.count - 1))
        configure(model)
        let view = RootView()
            .environmentObject(model)
            .environment(\.stillBackground, still)
            .environment(\.themeStills, stills)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { print("could not render \(file.lastPathComponent)"); return }
        let representation = NSBitmapImageRep(cgImage: image)
        try? representation.representation(using: .png, properties: [:])?.write(to: file)
    }
}
