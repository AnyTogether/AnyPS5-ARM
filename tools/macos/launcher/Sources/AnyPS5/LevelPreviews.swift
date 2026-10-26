import AnyPS5Core
import AppKit
import SwiftUI

/// Trophy levels, showcases, compared trophies and appearing offline drawn offscreen for
/// `--render-preview`, with made-up friends.
@MainActor
enum LevelPreviews {
    static func level(_ level: Int, points: Int, start: Int, next: Int?) -> TogetherTrophyLevel {
        let progress = next.map { min(99, (points - start) * 100 / max(1, $0 - start)) } ?? 100
        return TogetherTrophyLevel(badge: TogetherLevelBadge(level: level), points: points, levelPoints: start, nextLevelPoints: next, progress: progress)
    }

    static let mine = level(42, points: 2_520, start: 2_460, next: 2_520 + 45)
    static let miras = level(318, points: 52_200, start: 51_300, next: 52_200 + 630)

    static func own(appearOffline: Bool) -> TogetherOwnProfile {
        TogetherOwnProfile(handle: "robin", displayName: "Robin", bio: "Platinum hunter", avatar: nil, country: "TR", handleChangeAt: nil, privacy: .standard,
                           trophyLevel: mine, appearOffline: appearOffline)
    }

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.togetherConnected = true
                model.togetherProfile = own(appearOffline: false)
                configure(model)
            }
        }
        let ago = { (hours: Double) in Date().addingTimeInterval(-hours * 3600) }
        // Five names at least, a library with fewer games (or none) filled up with made-up ones.
        let names = found.prefix(4).map { ($0.titleID, $0.name) } + [("PPSA09999", "Astro Bot"), ("PPSA08888", "Stray"), ("PPSA07777", "Returnal"), ("PPSA06666", "Sackboy"), ("PPSA05555", "Kena")]
        let library: [TogetherPlayedGame] = names.prefix(4).enumerated().map { index, game in
            TogetherPlayedGame(titleId: game.0, names: ["en": game.1], iconUrl: nil, lastPlayedAt: ago(Double(index * 30 + 2)), secondsPlayed: [151_200, 26_100, 2_700, 72_000][index],
                               trophiesEarned: [31, 9, 1, 12][index], trophiesTotal: [48, 40, nil, 41][index], progress: [64, 22, nil, 29][index], points: [1_830, 420, 15, 600][index])
        }
        let earned: [TogetherEarnedTrophy] = [
            ("Every Last One", "platinum", 0.008, "ultra_rare"), ("Against All Odds", "gold", 0.031, "very_rare"), ("Night Walker", "silver", 0.12, "rare"),
            ("Curious Cat", "bronze", 0.34, "uncommon"), ("First Steps", "bronze", 0.92, "common"), ("No Damage", "gold", 0.05, "very_rare"),
        ].enumerated().map { index, item in
            let game = library[min(index / 2, library.count - 1)]
            return TogetherEarnedTrophy(titleId: game.titleId, gameNames: game.names, trophyId: index, grade: item.1, hidden: false,
                                        texts: ["en": .init(name: item.0)], earnedAt: ago(Double(index * 20 + 1)), rarity: item.2, rarityLabel: item.3)
        }
        let showcase = TogetherShowcase(trophies: Array(earned.prefix(6)),
                                        games: library.map { TogetherShowcaseGame(titleId: $0.titleId, names: $0.names, iconUrl: nil, secondsPlayed: $0.secondsPlayed,
                                                                                  trophiesEarned: $0.trophiesEarned, trophiesTotal: $0.trophiesTotal, progress: $0.progress) })
        let mira = TogetherProfile(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, bio: "Souls games, slowly. Platinum hunter on weekends.", country: "TR",
                                   friendship: "friends", trophyLevel: miras)
        let me = TogetherProfile(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil, bio: "Platinum hunter", country: "TR", friendship: "me", trophyLevel: mine)

        render("levels-profile-mine") { model in
            model.togetherProfile = own(appearOffline: true)
            model.previewProfile(TogetherProfilePage(profile: me, library: .shown(library), trophies: .shown(earned)), column: 0, index: 0,
                                 showcase: TogetherShowcase(trophies: Array(earned.prefix(3)), games: Array(showcase.games?.prefix(2) ?? [])))
        }
        render("levels-profile-friend") { model in
            model.previewProfile(TogetherProfilePage(profile: mira, library: .shown(library), trophies: .shown(earned)), column: 0, index: 1, showcase: showcase)
            model.social.profileActivity = SocialPreviews.activity(found).filter { $0.actor.userId == "f1" }
        }
        render("levels-profile-private") { model in
            let kenji = TogetherProfile(userId: "f2", handle: "kenji", displayName: "Kenji", avatar: nil, bio: nil, country: nil, friendship: "friends")
            model.previewProfile(TogetherProfilePage(profile: kenji, library: .private, trophies: .private), showcase: TogetherShowcase(trophies: nil, games: nil))
        }
        render("levels-friends") { model in
            let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-25 * 60))
            model.togetherFriends = [
                TogetherFriend(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, presence: .init(state: "in_game", titleId: found.first?.titleID ?? "PPSA01234", since: since),
                               level: miras.badge),
                TogetherFriend(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil), level: TogetherLevelBadge(level: 127)),
                TogetherFriend(userId: "f3", handle: "kenji", displayName: "Kenji", avatar: nil, presence: nil),
                TogetherFriend(userId: "f4", handle: "ines", displayName: "Ines", avatar: nil, presence: nil, level: TogetherLevelBadge(level: 731)),
                TogetherFriend(userId: "f5", handle: "theo", displayName: "Theo", avatar: nil, presence: nil, level: TogetherLevelBadge(level: 999)),
            ]
            model.overlay = .friends
            model.panelInRows = true
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "friend-f2" } ?? 0
        }
        let side = { (earned: Int, total: Int?, points: Int) in TogetherCompareSide(earned: earned, total: total, progress: total.map { earned * 100 / $0 }, points: points) }
        let games = [
            TogetherCompareGame(titleId: names[0].0, names: ["en": names[0].1], iconUrl: nil, mine: side(31, 48, 1_830), theirs: side(48, 48, 3_210)),
            TogetherCompareGame(titleId: names[1].0, names: ["en": names[1].1], iconUrl: nil, mine: side(9, 40, 420), theirs: side(17, 40, 780)),
            TogetherCompareGame(titleId: names[3].0, names: ["en": names[3].1], iconUrl: nil, mine: side(12, 41, 600), theirs: side(3, 41, 90)),
            TogetherCompareGame(titleId: names[2].0, names: ["en": names[2].1], iconUrl: nil, mine: side(1, nil, 15), theirs: nil),
            TogetherCompareGame(titleId: names[4].0, names: ["en": names[4].1], iconUrl: nil, mine: nil, theirs: side(22, 30, 1_140)),
        ]
        let miraCard = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
        render("levels-compare-games") { model in
            model.previewProfile(TogetherProfilePage(profile: mira, library: .shown(library), trophies: .shown(earned)))
            model.previewCompare(with: miraCard, games: games, index: 1)
        }
        let texts = { (name: String, detail: String) in ["en": TogetherEarnedTrophy.Text(name: name, detail: detail)] }
        let trophies: [TogetherCompareView.Trophy] = [
            .init(id: 0, grade: "platinum", hidden: false, texts: texts("Every Last One", "Earn every other trophy"), rarity: 0.008, rarityLabel: "ultra_rare", mine: nil, theirs: ago(30)),
            .init(id: 1, grade: "gold", hidden: false, texts: texts("Against All Odds", "Beat the last boss without healing"), rarity: 0.031, rarityLabel: "very_rare", mine: ago(50), theirs: ago(80)),
            .init(id: 2, grade: "silver", hidden: false, texts: texts("Night Walker", "Finish a night in the city"), rarity: 0.12, rarityLabel: "rare", mine: ago(120), theirs: nil),
            .init(id: 3, grade: "bronze", hidden: false, texts: texts("Curious Cat", "Look in every box"), rarity: 0.34, rarityLabel: "uncommon", mine: ago(200), theirs: ago(150)),
            .init(id: 4, grade: "bronze", hidden: false, texts: texts("First Steps", "Leave the first room"), rarity: 0.92, rarityLabel: "common", mine: ago(300), theirs: ago(400)),
            .init(id: 5, grade: "gold", hidden: true, texts: nil, rarity: nil, rarityLabel: nil, mine: nil, theirs: nil),
            .init(id: 6, grade: "silver", hidden: false, texts: texts("Speedrunner", "Finish in under three hours"), rarity: 0.06, rarityLabel: "very_rare", mine: nil, theirs: ago(10)),
        ]
        let view = TogetherCompareView(titleId: names[1].0, game: .init(names: ["en": names[1].1], iconUrl: nil),
                                       me: .init(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil, level: mine.badge),
                                       them: .init(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, level: miras.badge),
                                       trophies: trophies, totals: .init(mine: 4, theirs: 5, both: 3, total: 40))
        render("levels-compare-trophies") { model in
            model.previewProfile(TogetherProfilePage(profile: mira, library: .shown(library), trophies: .shown(earned)))
            model.previewCompare(with: miraCard, games: games, index: 1, view: view, trophyIndex: 1)
        }
        render("levels-compare-private") { model in
            let kenji = TogetherProfile(userId: "f2", handle: "kenji", displayName: "Kenji", avatar: nil, bio: nil, country: nil, friendship: "friends")
            model.previewProfile(TogetherProfilePage(profile: kenji, library: .private, trophies: .private))
            model.previewCompare(with: TogetherPerson(userId: "f2", handle: "kenji", displayName: "Kenji", avatar: nil), games: [], load: .hidden)
        }
        render("levels-presence") { model in
            model.previewOwnProfile(own(appearOffline: true))
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "together" } ?? 0
            model.panelInRows = true
            model.panelRow = model.panelCategories()[model.panelCategory].rows.firstIndex { $0.id == "together-presence" } ?? 0
        }
        render("levels-home") { model in
            PreviewRenderer.signedIn(model)
            model.togetherProfile = own(appearOffline: true)
        }
        render("levels-notifications") { model in
            var details = TogetherNotification.Details()
            details.level = 42
            details.tier = "bronze"
            details.frame = 1
            let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            model.previewNotifications([
                TogetherNotification(id: "0009", kind: .levelUp, actor: robin, subjectId: "level", data: details, createdAt: ago(0.2)),
                TogetherNotification(id: "0005", kind: .friendRequest, actor: TogetherPerson(userId: "f9", handle: "ines", displayName: "Ines", avatar: nil), createdAt: ago(2)),
                TogetherNotification(id: "0004", kind: .missedCall, actor: SocialPreviews.sol, read: true, createdAt: ago(5)),
            ], unread: 2, row: 1)
        }
        renderBanner(TogetherLevelBadge(level: 42), output.appendingPathComponent("levels-banner.png"))
        renderBanner(TogetherLevelBadge(level: 600), output.appendingPathComponent("levels-banner-platinum.png"))
        renderBadges(output.appendingPathComponent("levels-badges.png"))
    }

    /// The level-up card over a game, on a picture of one (ANYPS5_PREVIEW_BANNER_BACKDROP) or grey.
    static func renderBanner(_ badge: TogetherLevelBadge, _ file: URL) {
        snapshot(file) {
            ZStack(alignment: .top) {
                if let backdrop = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_BANNER_BACKDROP"].flatMap({ NSImage(contentsOfFile: $0) }) {
                    Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).frame(width: PreviewRenderer.size.width, height: PreviewRenderer.size.height)
                } else {
                    Color(white: 0.15)
                }
                LevelUpToast(badge: badge, still: true) {}
            }
            .frame(width: PreviewRenderer.size.width, height: PreviewRenderer.size.height)
            .clipped()
        }
    }

    /// Every tier and frame, small and large, for checking the drawing.
    static func renderBadges(_ file: URL) {
        let levels = [1, 12, 99, 100, 150, 299, 300, 450, 599, 600, 777, 999]
        snapshot(file) {
            VStack(spacing: 40) {
                ForEach([28.0, 56.0, 96.0], id: \.self) { size in
                    HStack(spacing: 24) {
                        ForEach(levels, id: \.self) { level in LevelBadgeView(badge: TogetherLevelBadge(level: level), size: size) }
                    }
                }
            }
            .frame(width: PreviewRenderer.size.width, height: PreviewRenderer.size.height)
            .background(Color(red: 0.06, green: 0.07, blue: 0.1))
        }
    }

    private static func snapshot<Content: View>(_ file: URL, @ViewBuilder _ content: () -> Content) {
        if let only = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"]?.split(separator: ","), !only.contains(where: { file.lastPathComponent.hasPrefix($0) }) { return }
        let renderer = ImageRenderer(content: content())
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    }
}
