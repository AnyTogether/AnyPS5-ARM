import AnyPS5Core
import AppKit
import SwiftUI

/// The social screens drawn offscreen for `--render-preview`, with made-up friends.
@MainActor
enum SocialPreviews {
    static let me = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
    static let ayse = TogetherPerson(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil)
    static let mert = TogetherPerson(userId: "f2", handle: "mert", displayName: "Mert", avatar: nil)
    static let kral = TogetherPerson(userId: "f3", handle: "kral", displayName: "Kral", avatar: nil)

    static func ago(_ hours: Double) -> Date { Date().addingTimeInterval(-hours * 3600) }

    static func activity(_ found: [Game]) -> [TogetherActivity] {
        let first = found.first.map { TogetherActivity.Game(titleId: $0.titleID, names: ["en": $0.name]) } ?? .init(titleId: "PPSA01234", names: ["en": "Stray"])
        let second = found.dropFirst().first.map { TogetherActivity.Game(titleId: $0.titleID, names: ["en": $0.name]) } ?? first
        let unknown = TogetherActivity.Game(titleId: "PPSA09999", names: ["en": "Astro Bot", "tr": "Astro Bot"])
        let text = { (name: String) in ["en": TogetherEarnedTrophy.Text(name: name)] }
        return [
            TogetherActivity(id: "0009", kind: .platinum, createdAt: ago(0.3), actor: ayse, game: first, highlight: "platinum",
                             trophies: [.init(trophyId: 0, grade: "platinum", texts: text("Every Last One"), rarity: 0.008, rarityLabel: "ultra_rare")], trophyCount: 1,
                             reactions: .init(counts: [.fire: 3, .clap: 2], mine: .fire)),
            TogetherActivity(id: "0008", kind: .trophy, createdAt: ago(1.2), actor: mert, game: second, highlight: "rare",
                             trophies: [.init(trophyId: 4, grade: "gold", texts: text("Against All Odds"), rarity: 0.031, rarityLabel: "very_rare"),
                                        .init(trophyId: 7, grade: "silver", texts: text("Night Walker"), rarity: 0.4, rarityLabel: "uncommon"),
                                        .init(trophyId: 9, grade: "bronze", hidden: true, texts: nil)], trophyCount: 5,
                             reactions: .init(counts: [.wow: 1])),
            TogetherActivity(id: "0007", kind: .longSession, createdAt: ago(3), actor: kral, game: unknown, seconds: 3 * 3600 + 25 * 60),
            TogetherActivity(id: "0006", kind: .friendship, createdAt: ago(5), actor: ayse, friend: kral, reactions: .init(counts: [.heart: 2])),
            TogetherActivity(id: "0005", kind: .firstPlay, createdAt: ago(9), actor: mert, game: first),
            TogetherActivity(id: "0004", kind: .milestone, createdAt: ago(26), actor: kral, milestone: .init(kind: "hours", value: 100)),
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
        render("profile-activity") { model in
            let ayseProfile = TogetherProfile(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, bio: "Souls games, slowly.", country: "TR", friendship: "friends")
            let library = found.prefix(3).map { TogetherPlayedGame(titleId: $0.titleID, names: ["en": $0.name], iconUrl: nil, lastPlayedAt: ago(30), secondsPlayed: 26_100, trophiesEarned: 9, trophiesTotal: 40, progress: 22, points: 420) }
            model.previewProfile(TogetherProfilePage(profile: ayseProfile, library: .shown(library), trophies: .shown([])), column: 2, index: 0)
            model.social.profileActivity = items.filter { $0.actor.userId == "f1" } + items.suffix(2)
        }
    }
}
