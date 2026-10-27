import AnyPS5Core
import AppKit
import SwiftUI

/// The social screens drawn offscreen for `--render-preview`, with made-up friends.
@MainActor
enum SocialPreviews {
    static let me = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
    static let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
    static let kenji = TogetherPerson(userId: "f2", handle: "kenji", displayName: "Kenji", avatar: nil)
    static let sol = TogetherPerson(userId: "f3", handle: "sol", displayName: "Sol", avatar: nil)

    static func ago(_ hours: Double) -> Date { Date().addingTimeInterval(-hours * 3600) }

    static func activity(_ found: [Game]) -> [TogetherActivity] {
        let first = found.first.map { TogetherActivity.Game(titleId: $0.titleID, names: ["en": $0.name]) } ?? .init(titleId: "PPSA01234", names: ["en": "Stray"])
        let second = found.dropFirst().first.map { TogetherActivity.Game(titleId: $0.titleID, names: ["en": $0.name]) } ?? first
        let unknown = TogetherActivity.Game(titleId: "PPSA09999", names: ["en": "Astro Bot", "tr": "Astro Bot"])
        let text = { (name: String) in ["en": TogetherEarnedTrophy.Text(name: name)] }
        return [
            TogetherActivity(id: "0009", kind: .platinum, createdAt: ago(0.3), actor: mira, game: first, highlight: "platinum",
                             trophies: [.init(trophyId: 0, grade: "platinum", texts: text("Every Last One"), rarity: 0.008, rarityLabel: "ultra_rare")], trophyCount: 1,
                             reactions: .init(counts: [.fire: 3, .clap: 2], mine: .fire)),
            TogetherActivity(id: "0008", kind: .trophy, createdAt: ago(1.2), actor: kenji, game: second, highlight: "rare",
                             trophies: [.init(trophyId: 4, grade: "gold", texts: text("Against All Odds"), rarity: 0.031, rarityLabel: "very_rare"),
                                        .init(trophyId: 7, grade: "silver", texts: text("Night Walker"), rarity: 0.4, rarityLabel: "uncommon"),
                                        .init(trophyId: 9, grade: "bronze", hidden: true, texts: nil)], trophyCount: 5,
                             reactions: .init(counts: [.wow: 1])),
            TogetherActivity(id: "0007", kind: .longSession, createdAt: ago(3), actor: sol, game: unknown, seconds: 3 * 3600 + 25 * 60),
            TogetherActivity(id: "0006", kind: .friendship, createdAt: ago(5), actor: mira, friend: sol, reactions: .init(counts: [.heart: 2])),
            TogetherActivity(id: "0005", kind: .firstPlay, createdAt: ago(9), actor: kenji, game: first),
            TogetherActivity(id: "0004", kind: .milestone, createdAt: ago(26), actor: sol, milestone: .init(kind: "hours", value: 100)),
        ]
    }

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = me
                configure(model)
            }
        }
        let items = activity(found)
        render("feed") { model in model.previewFeed(items, index: 1, reaction: 3) }
        render("feed-empty") { model in model.previewFeed([]) }
        let person = { (id: String, name: String) in TogetherPerson(userId: id, handle: name.lowercased(), displayName: name, avatar: nil) }
        let names = ["Mira", "Kenji", "Sol", "Ines", "Theo", "Noor", "Lena", "Felix"]
        let top = names.enumerated().map { index, name in TogetherLeaderboard.Entry(rank: index + 1, user: person("p\(index)", name), value: 9_400 - index * 870) }
        let robin = TogetherLeaderboard.Entry(rank: 41, user: person("u1", "Robin"), value: 1_830)
        let around = [TogetherLeaderboard.Entry(rank: 40, user: person("x1", "Lin"), value: 1_905), robin, TogetherLeaderboard.Entry(rank: 42, user: person("x2", "Ada"), value: 1_790)]
        render("leaderboard-game") { model in
            model.previewLeaderboard(TogetherLeaderboard(board: "points", scope: .global, game: nil, entries: Array(top.prefix(4)), me: .init(rank: 41, value: 1_830, listed: true), around: around, total: 312),
                                     game: found.first, index: 6)
        }
        render("leaderboard-time") { model in
            let friends = [TogetherLeaderboard.Entry(rank: 1, user: person("p0", "Mira"), value: 151_200), TogetherLeaderboard.Entry(rank: 2, user: person("u1", "Robin"), value: 26_100),
                           TogetherLeaderboard.Entry(rank: 3, user: person("p2", "Sol"), value: 2_700)]
            model.previewLeaderboard(TogetherLeaderboard(board: "time", scope: .friends, game: nil, entries: friends, me: .init(rank: 2, value: 26_100, listed: true), total: 3),
                                     game: found.first, kind: .time, index: 1)
        }
        render("leaderboard-overall") { model in
            model.previewLeaderboard(TogetherLeaderboard(board: "points", scope: .global, game: nil, entries: Array(top.prefix(5)), me: .init(rank: 57, value: 1_830, listed: false), total: 312),
                                     game: nil, index: 0)
        }
        render("leaderboard-missing") { model in model.previewLeaderboard(nil, game: found.first, missing: true) }
        var details = TogetherNotification.Details()
        details.count = 3
        details.text = "on tonight? raid at nine"
        var invite = TogetherNotification.Details()
        invite.titleId = found.first?.titleID
        var warning = TogetherNotification.Details()
        warning.reason = "Keep the group chats friendly"
        let notes = [
            TogetherNotification(id: "0007", kind: .message, actor: mira, data: details, createdAt: ago(0.1)),
            TogetherNotification(id: "0006", kind: .gameInvite, actor: kenji, data: invite, createdAt: ago(0.5)),
            TogetherNotification(id: "0005", kind: .friendRequest, actor: TogetherPerson(userId: "f9", handle: "ines", displayName: "Ines", avatar: nil), createdAt: ago(2)),
            TogetherNotification(id: "0004", kind: .missedCall, actor: sol, read: true, createdAt: ago(5)),
            TogetherNotification(id: "0003", kind: .partyInvite, actor: mira, read: true, createdAt: ago(26)),
            TogetherNotification(id: "0002", kind: .warning, actor: nil, data: warning, read: true, createdAt: ago(50)),
        ]
        render("notifications") { model in model.previewNotifications(notes, unread: 3, more: true) }
        render("notifications-bell") { model in
            model.social.notifications.load(TogetherNotificationPage(notifications: notes, unread: 3, more: false))
            model.focus = .top(5)
            model.show(model.notificationText(notes[0]) + " · " + (model.notificationDetail(notes[0]) ?? ""), symbol: "bubble.left.fill")
        }
        // The still "Share on the Hub" sends with a theme that has no picture of its own.
        if ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"].map({ $0.split(separator: ",").contains { "hub-still".hasPrefix($0) } }) ?? true {
            let neon = ThemeDesign(id: "neon", name: "Neon Nights", author: "Ada", style: 1, deep: "#0A0014", middle: "#4A0E6B", bright: "#FF5EDB", accent: "#FF4FD8")
            try? AppModel.themeStill(neon)?.write(to: output.appendingPathComponent("hub-still.png"))
        }
        render("compat-ask") { model in model.previewCompat(found.first, row: 1) }
        render("compat-card") { model in
            if let game = model.selectedGame { model.social.compat[game.titleID] = .some(TogetherCompatSummary(status: .ingame, version: "0.2.14", reports: 7)) }
        }
        render("compat-options") { model in
            if let game = model.selectedGame { model.social.compat[game.titleID] = .some(TogetherCompatSummary(status: .playable, version: "0.2.14", reports: 12)) }
            model.overlay = .gameSettings; model.panelInRows = true
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "compat" } ?? 0
        }
        render("trophies-board") { model in
            if let index = model.games.firstIndex(where: { model.trophies[$0.id] != nil }) { model.selected = index }
            model.overlay = .trophies; model.trophyIndex = 1
        }
        render("profile-activity") { model in
            let miraProfile = TogetherProfile(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, bio: "Souls games, slowly.", country: "TR", friendship: "friends")
            let library = found.prefix(3).map { TogetherPlayedGame(titleId: $0.titleID, names: ["en": $0.name], iconUrl: nil, lastPlayedAt: ago(30), secondsPlayed: 26_100, trophiesEarned: 9, trophiesTotal: 40, progress: 22, points: 420) }
            model.previewProfile(TogetherProfilePage(profile: miraProfile, library: .shown(library), trophies: .shown([])), column: 2, index: 0)
            model.social.profileActivity = items.filter { $0.actor.userId == "f1" } + items.suffix(2)
        }
    }
}
