import AnyPS5Core
import AppKit
import SwiftUI

/// Profiles wearing a theme or a cover, Edit showcase, Profile theme and the Hub's Wear on my
/// profile, drawn offscreen for `--render-preview` (ANYPS5_PREVIEW_ONLY=look).
@MainActor
enum ProfileLookPreviews {
    static let themeID = "01928c3e-7a4b-7c3d-9e2f-0a1b2c3d4e5f"

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        // A game's artwork stands in for the server's pictures: an offscreen render loads no web address.
        let art = found.compactMap(\.background)
        for url in art { Artwork.shared.prepare(url, maxPixels: 1800) }
        let picture = art.first?.absoluteString ?? ""
        let otherPicture = (art.dropFirst().first ?? art.first)?.absoluteString ?? ""

        let neon = TogetherProfileTheme(id: themeID, name: "Neon Nights", colors: .init(deep: "#12021f", middle: "#5a1478", bright: "#ff5edb", accent: "#ff4fd8"),
                                        preview: picture, thumb: picture, maker: .init(handle: "ada", displayName: "Ada"))
        let others = [
            TogetherProfileTheme(id: "11111111-2222-4333-8444-555555555555", name: "Glacier", colors: .init(deep: "#02131f", middle: "#0b4a6b", bright: "#8fe3ff", accent: "#5cd2ff"),
                                 preview: otherPicture, thumb: otherPicture, maker: .init(handle: "sol", displayName: "Sol")),
            TogetherProfileTheme(id: "22222222-3333-4444-8555-666666666666", name: "Ember Road", colors: .init(deep: "#1a0602", middle: "#7a2a0b", bright: "#ffb36b", accent: "#ff8a3d"),
                                 preview: otherPicture, thumb: otherPicture, maker: .init(handle: "kenji", displayName: "Kenji")),
            TogetherProfileTheme(id: "33333333-4444-4555-8666-777777777777", name: "Moss Garden", colors: .init(deep: "#03100a", middle: "#1d5236", bright: "#a6f5c4", accent: "#5cebbd"),
                                 preview: otherPicture, thumb: otherPicture, maker: nil),
        ]
        let wearing = TogetherProfileLook(cover: nil, accent: nil, theme: neon)
        let covered = TogetherProfileLook(cover: .init(kind: "game", id: found.first?.titleID ?? "PPSA01234", url: otherPicture), accent: "gold", theme: nil)

        let ago = { (hours: Double) in Date().addingTimeInterval(-hours * 3600) }
        let names = found.prefix(4).map { ($0.titleID, $0.name) } + [("PPSA09999", "Astro Bot"), ("PPSA08888", "Stray"), ("PPSA07777", "Returnal"), ("PPSA06666", "Sackboy")]
        let library: [TogetherPlayedGame] = names.prefix(4).enumerated().map { index, game in
            TogetherPlayedGame(titleId: game.0, names: ["en": game.1], iconUrl: nil, lastPlayedAt: ago(Double(index * 30 + 2)), secondsPlayed: [151_200, 26_100, 2_700, 72_000][index],
                               trophiesEarned: [31, 9, 1, 12][index], trophiesTotal: [48, 40, nil, 41][index], progress: [64, 22, nil, 29][index], points: [1_830, 420, 15, 600][index])
        }
        let earned: [TogetherEarnedTrophy] = [
            ("Every Last One", "platinum", 0.008, "ultra_rare"), ("Against All Odds", "gold", 0.031, "very_rare"), ("Night Walker", "silver", 0.12, "rare"),
            ("Curious Cat", "bronze", 0.34, "uncommon"), ("First Steps", "bronze", 0.92, "common"), ("No Damage", "gold", 0.05, "very_rare"),
            ("Long Way Home", "silver", 0.2, "uncommon"), ("Collector", "bronze", 0.4, "common"),
        ].enumerated().map { index, item in
            let game = library[min(index / 2, library.count - 1)]
            return TogetherEarnedTrophy(titleId: game.titleId, gameNames: game.names, trophyId: index, grade: item.1, hidden: false,
                                        texts: ["en": .init(name: item.0)], earnedAt: ago(Double(index * 20 + 1)), rarity: item.2, rarityLabel: item.3)
        }
        let showcaseGames = library.map { TogetherShowcaseGame(titleId: $0.titleId, names: $0.names, iconUrl: nil, secondsPlayed: $0.secondsPlayed,
                                                               trophiesEarned: $0.trophiesEarned, trophiesTotal: $0.trophiesTotal, progress: $0.progress) }
        // Saved before the shared limit: four trophies and four games, six of them shown.
        let showcase = TogetherShowcase(trophies: Array(earned.prefix(4)), games: showcaseGames)
        let me = TogetherProfile(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil, bio: "Platinum hunter", country: "TR", friendship: "me",
                                 trophyLevel: LevelPreviews.mine, look: wearing)
        let mira = TogetherProfile(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, bio: "Souls games, slowly. Platinum hunter on weekends.", country: "TR",
                                   friendship: "friends", trophyLevel: LevelPreviews.miras, look: covered)

        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.togetherConnected = true
                var own = LevelPreviews.own(appearOffline: false)
                own.look = wearing
                model.togetherProfile = own
                configure(model)
            }
        }
        let page = TogetherProfilePage(profile: me, library: .shown(library), trophies: .shown(earned))

        render("look-profile-mine-theme") { model in
            model.previewProfile(page, column: -1, index: 1, showcase: showcase)
        }
        render("look-profile-friend-cover") { model in
            model.previewProfile(TogetherProfilePage(profile: mira, library: .shown(library), trophies: .shown(earned)), column: 0, index: 1,
                                 showcase: TogetherShowcase(trophies: Array(earned.prefix(2)), games: Array(showcaseGames.prefix(3))))
            model.social.profileActivity = SocialPreviews.activity(found).filter { $0.actor.userId == "f1" }
        }
        render("look-profile-mine-plain") { model in
            model.togetherProfile = LevelPreviews.own(appearOffline: false)
            var plain = me
            plain.look = .plain
            model.previewProfile(TogetherProfilePage(profile: plain, library: .shown(library), trophies: .shown(earned)), column: -1, index: 0,
                                 showcase: TogetherShowcase(trophies: [], games: []))
        }
        render("look-showcase-edit") { model in
            model.previewProfile(page, showcase: showcase)
            model.previewShowcaseEditor(pins: TogetherShowcasePins(trophies: earned.prefix(3).map { .init(titleId: $0.titleId, trophyId: $0.trophyId) }, games: [library[0].titleId]),
                                        row: "pin-trophy-\(earned[3].id)")
        }
        render("look-showcase-edit-full") { model in
            model.previewProfile(page, showcase: showcase)
            model.previewShowcaseEditor(pins: TogetherShowcasePins(showcase), row: "pin-game-\(library[2].titleId)")
        }
        render("look-profile-theme") { model in
            model.previewProfile(page, showcase: showcase)
            model.previewProfileTheme([others[0], neon, others[1], others[2]], row: "wear-\(others[1].id)")
        }
        render("look-hub-wear") { model in
            let server = ThemeHub.base(onServer: model.together.base)
            let hub = ([neon] + others).map { theme in
                ThemeHub.Theme(design: ThemeDesign(id: theme.id, name: theme.name, author: theme.maker?.displayName ?? "AnyPS5", version: 1, style: 0,
                                                   deep: theme.colors.deep, middle: theme.colors.middle, bright: theme.colors.bright, accent: theme.colors.accent),
                               package: server.appendingPathComponent("\(theme.id).anyps5theme"), preview: nil, source: server)
            }
            model.hub = .loaded(hub)
            model.overlay = .themes
            model.panelInRows = true
            let rows = model.themeRows()
            model.focusRow(rows.firstIndex { $0.id == "hub-\(others[0].id)" } ?? 0, in: rows)
        }
    }
}
