import AnyPS5Core
import AppKit
import SwiftUI

/// Draws the launcher's screens into PNG files offscreen: no window opens, nothing is saved.
@MainActor
enum PreviewRenderer {
    static let size = CGSize(width: 1600, height: 900)
    static var stills: [Theme: NSImage] = [:]

    static func run(output: URL, games root: URL) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let found = GameLibrary.scan(root)
        for game in found {
            Artwork.shared.prepare(game.icon, maxPixels: 400)
            Artwork.shared.prepare(game.background, maxPixels: Int(max(size.width, size.height) * 1.6))
        }
        var preferences = Preferences()
        preferences.onboarded = true
        preferences.gamesFolder = root.path
        preferences.sounds = false
        preferences.profileName = "Utku"
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
        let forest = ThemeDesign(id: "forest", name: "Forest", author: "Utku", style: 1, deep: "#02100A", middle: "#0E4A2C", bright: "#9BFFC4", accent: "#5CEB9F")
        for (name, overlay, row) in [("themes", Overlay.themes, 4), ("studio", Overlay.studio, 3)] {
            let palette = overlay == .studio ? neon.palette : forest.palette
            let tinted = BackgroundView.still(theme: overlay == .studio ? .cosmic : .aurora, palette: palette, width: Int(size.width), height: Int(size.height), time: 260)
            render(preferences, found, root, tinted, output.appendingPathComponent("\(name).png")) { model in
                model.previewThemes([forest, neon], active: overlay == .studio ? neon : forest, hub: [neon, ThemeDesign(id: "mono", name: "Monochrome", author: "Lin", style: 2, deep: "#050505", middle: "#2A2A2A", bright: "#E6E6E6", accent: "#FFFFFF")])
                model.overlay = overlay; model.panelInRows = true; model.panelRow = row
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
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.togetherConnected = true
            model.overlay = .settings; model.panelCategory = 4; model.panelInRows = true; model.panelRow = 2
        }
        for (name, row) in [("together-edit", 4), ("together-privacy", 11)] {
            render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
                model.togetherConnected = true
                model.previewOwnProfile(TogetherOwnProfile(handle: "utku", displayName: "Utku", bio: "Platinum hunter", avatar: nil, country: "TR",
                                                           handleChangeAt: Date().addingTimeInterval(12 * 86_400), privacy: .standard))
                model.overlay = .settings; model.panelCategory = 4; model.panelInRows = true; model.panelRow = row
            }
        }
        render(preferences, found, root, still, output.appendingPathComponent("friends.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-25 * 60))
            model.togetherFriends = [
                TogetherFriend(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: since)),
                TogetherFriend(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil)),
                TogetherFriend(userId: "f3", handle: "mert", displayName: "Mert", avatar: nil, presence: nil),
            ]
            model.togetherRequests = TogetherRequests(incoming: [TogetherPerson(userId: "f4", handle: "zeynep", displayName: "Zeynep", avatar: nil)], outgoing: [])
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
        let ayse = TogetherProfile(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, bio: "Souls games, slowly. Platinum hunter on weekends.", country: "TR", friendship: "friends")
        render(preferences, found, root, still, output.appendingPathComponent("profile.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.previewProfile(TogetherProfilePage(profile: ayse, library: .shown(library), trophies: .shown(earned)), column: 0, index: 1)
        }
        render(preferences, found, root, still, output.appendingPathComponent("profile-trophies.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            let me = TogetherProfile(userId: "u1", handle: "utku", displayName: "Utku", avatar: nil, bio: nil, country: nil, friendship: "me")
            model.previewProfile(TogetherProfilePage(profile: me, library: .shown(library), trophies: .shown(earned)), column: 1, index: 1)
        }
        render(preferences, found, root, still, output.appendingPathComponent("profile-private.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            let mert = TogetherProfile(userId: "f3", handle: "mert", displayName: "Mert", avatar: nil, bio: nil, country: nil, friendship: "none")
            model.previewProfile(TogetherProfilePage(profile: mert, library: .private, trophies: .private))
        }
        render(preferences, found, root, still, output.appendingPathComponent("profile-loading.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.previewProfile(nil)
            model.profileCard = TogetherPerson(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil)
        }
        let utku = TogetherPerson(userId: "u1", handle: "utku", displayName: "Utku", avatar: nil)
        let people = [TogetherPerson(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil), TogetherPerson(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil)]
        let lines: [(String, String)] = [("f1", "Are you still on the Silksong boss?"), ("u1", "Yes, third try. The second phase is brutal"), ("f1", "Dash through the spikes, not over them"),
                                         ("u1", "Oh! Trying that now"), ("f1", "GG when you get it 🏆"), ("u1", "On my way")]
        let thread = lines.enumerated().map { index, line in
            TogetherMessage(id: "m\(index)", conversationId: "c1", seq: index + 1, authorId: line.0, text: line.1, createdAt: ago(Double(lines.count - index) * 0.1))
        }
        var inbox = TogetherInbox(me: "u1", conversations: [
            TogetherConversation(id: "c1", kind: "direct", title: nil, members: [utku, people[0]], lastSeq: 6, readSeq: 6, unread: 0, lastMessage: thread.last, updatedAt: ago(0.1)),
            TogetherConversation(id: "c2", kind: "direct", title: nil, members: [utku, people[1]], lastSeq: 3, readSeq: 1, unread: 2,
                                 lastMessage: TogetherMessage(id: "k3", conversationId: "c2", seq: 3, authorId: "f2", text: "Party tonight?", createdAt: ago(3)), updatedAt: ago(3)),
            TogetherConversation(id: "c3", kind: "group", title: "Souls club", members: [utku] + people, lastSeq: 40, readSeq: 40, unread: 0,
                                 lastMessage: TogetherMessage(id: "g40", conversationId: "c3", seq: 40, authorId: "f2", text: "Who has the platinum?", createdAt: ago(30)), updatedAt: ago(30)),
        ])
        inbox.threads["c1"] = thread
        for (name, inThread, focus) in [("messages", false, nil), ("messages-thread", true, 2)] as [(String, Bool, Int?)] {
            render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
                model.togetherFriends = [TogetherFriend(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: nil)),
                                         TogetherFriend(userId: "f5", handle: "deniz", displayName: "Deniz", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil))]
                model.previewMessages(inbox, index: 0, inThread: inThread, focus: focus)
            }
        }
        render(preferences, found, root, still, output.appendingPathComponent("messages-group.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.togetherFriends = [TogetherFriend(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil)),
                                     TogetherFriend(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil, presence: nil),
                                     TogetherFriend(userId: "f5", handle: "deniz", displayName: "Deniz", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil))]
            model.previewMessages(inbox, index: 3, inThread: true)
            model.previewGroup(picked: ["f1", "f5"], name: "Co-op night", focus: 2)
        }
        render(preferences, found, root, still, output.appendingPathComponent("home-messages.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.inbox = inbox
            model.focus = .top(3)
        }
        let partyFriends = [
            TogetherFriend(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: nil)),
            TogetherFriend(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil, party: .init(id: "p7", size: 3, max: 8, open: true))),
            TogetherFriend(userId: "f3", handle: "mert", displayName: "Mert", avatar: nil, presence: nil),
        ]
        render(preferences, found, root, still, output.appendingPathComponent("party.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [utku, people[0]], invited: [TogetherPerson(userId: "f3", handle: "mert", displayName: "Mert", avatar: nil)],
                                             call: .init(id: "call1", in: ["u1", "f1"])))
            model.overlay = .party; model.panelInRows = true; model.panelRow = 4
        }
        render(preferences, found, root, still, output.appendingPathComponent("party-voice.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "friends", members: [utku, people[0], people[1]], invited: [], call: .init(id: "call1", in: ["u1", "f1", "f2"])))
            model.previewVoice(call: "call1", speaking: ["f1"])
            model.overlay = .party; model.panelInRows = true; model.panelRow = 0
        }
        render(preferences, found, root, still, output.appendingPathComponent("party-none.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            model.togetherFriends = partyFriends
            model.previewParty(nil, invites: [TogetherPartyInvite(partyId: "p9", from: people[0], size: 2)])
            model.overlay = .party; model.panelInRows = true; model.panelRow = 0
        }
        render(preferences, found, root, still, output.appendingPathComponent("friends-games.png")) { model in
            model.togetherUser = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
            let title = found.first?.titleID ?? "PPSA01234"
            model.togetherFriends = [
                TogetherFriend(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil,
                               presence: .init(state: "in_game", titleId: title, since: nil, game: .init(sessionId: "s1", titleId: title, joinable: true, players: 1, capacity: 4))),
                TogetherFriend(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil, party: .init(id: "p7", size: 3, max: 8, open: true))),
            ]
            model.previewGameSession(nil, invites: [TogetherGameInvite(sessionId: "s2", from: TogetherPerson(userId: "f2", handle: "kral", displayName: "Kral", avatar: nil),
                                                                       titleId: found.last?.titleID ?? title, gameVersion: "01.000.000", engineBuild: "0.2.13-abc")])
            model.overlay = .friends; model.panelInRows = true; model.panelRow = 3
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
            model.panelCategory = 5
            model.panelInRows = true
            model.panelRow = 2
        }
        render(preferences, found, root, still, output.appendingPathComponent("gallery.png")) { model in model.open(.gallery); model.galleryIndex = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("gallery-viewer.png")) { model in model.open(.gallery); model.galleryViewing = true }
        render(preferences, found, root, still, output.appendingPathComponent("game-settings-saves.png")) { model in model.overlay = .gameSettings; model.panelInRows = true; model.panelRow = 10 }
        render(preferences, found, root, still, output.appendingPathComponent("library.png")) { model in model.overlay = .library; model.libraryIndex = 1 }
        renderBanner(preferences, found, root, output.appendingPathComponent("trophy-banner.png"))
        var fresh = preferences
        fresh.onboarded = false
        fresh.gamesFolder = nil
        for step in 0..<3 {
            if step == 2 { fresh.gamesFolder = root.path }
            render(fresh, step == 2 ? found : [], root, still, output.appendingPathComponent("onboarding\(step).png")) { model in model.onboardingStep = step }
        }
        print("rendered into \(output.path)")
    }

    /// The trophy card over a picture of a game (ANYPS5_PREVIEW_BANNER_BACKDROP), with the selected
    /// game's first earned trophy.
    static func renderBanner(_ preferences: Preferences, _ games: [Game], _ root: URL, _ file: URL) {
        let model = AppModel(preferences: preferences)
        model.preview(games: games, root: root)
        let pick = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SELECT"].flatMap { id in games.first { $0.titleID == id } } ?? games.first
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

    static func render(_ preferences: Preferences, _ games: [Game], _ root: URL, _ still: NSImage?, _ file: URL, configure: (AppModel) -> Void = { _ in }) {
        // ANYPS5_PREVIEW_ONLY=party,messages draws only the screens whose file names start so.
        if let only = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"]?.split(separator: ","), !only.contains(where: { file.lastPathComponent.hasPrefix($0) }) { return }
        let model = AppModel(preferences: preferences)
        model.preview(games: games, root: root)
        // ANYPS5_PREVIEW_SELECT=<title ID> picks the game the screens show.
        let pick = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SELECT"].flatMap { id in games.firstIndex { $0.titleID == id } }
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
