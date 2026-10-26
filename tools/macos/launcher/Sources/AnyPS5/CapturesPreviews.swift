import AnyPS5Core
import AppKit
import SwiftUI

/// Captures drawn offscreen for `--render-preview`: the gallery's Share to AnyTogether sheet (a
/// caption, Public picked, a clip too long, going up), the Captures feed (a picture, a clip, one's
/// own post with Delete pressed once, empty) and a post's comments with replies. Pictures come
/// from the games' own artwork. ANYPS5_PREVIEW_ONLY=captures draws only these.
@MainActor
enum CapturesPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        var preferences = preferences
        let shots = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-captures-shots")
        try? FileManager.default.removeItem(at: shots)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let game = PreviewRenderer.selectedTitle.flatMap { id in found.first { $0.titleID == id } } ?? (found.isEmpty ? nil : found[min(1, found.count - 1)])
        if let game, let art = game.background ?? game.icon {
            for stamp in ["20261026-211502", "20261025-193010", "20261024-120001", "20261023-090000"] {
                try? FileManager.default.copyItem(at: art, to: shots.appendingPathComponent("\(game.titleID)-\(stamp).png"))
            }
            preferences.screenshotsFolder = shots.path
        }
        let pictures = found.compactMap { $0.background ?? $0.icon }.map(\.absoluteString)
        let picture = { (index: Int) in pictures.isEmpty ? nil : pictures[index % pictures.count] }

        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.togetherConnected = true
                model.cloud.info = TogetherStorageInfo(enabled: true)
                configure(model)
            }
        }

        // Sharing from the gallery
        render("captures-share-menu") { model in
            model.open(.gallery)
            model.galleryIndex = 0
            model.cloud.sharing = true
            model.cloud.shareIndex = 0
        }
        render("captures-share") { model in
            model.open(.gallery)
            model.previewPostDraft(caption: T.language == .turkish ? "Çatıların üstünde gün batımı" : "Sunset over the rooftops", row: .caption)
        }
        render("captures-share-public") { model in
            model.open(.gallery)
            model.previewPostDraft(caption: "GG", visibility: .public, row: .visibility)
        }
        render("captures-share-clip-long") { model in
            model.open(.gallery)
            model.previewPostDraft(row: .post, clipMs: 84_000, check: .tooLong(ms: 84_000))
        }
        render("captures-share-clip-big") { model in
            model.open(.gallery)
            model.previewPostDraft(row: .post, clipMs: 48_000, check: .tooBig(bytes: 31 * 1_048_576))
        }
        render("captures-share-uploading") { model in
            model.open(.gallery)
            model.previewPostDraft(caption: "First try", row: .post, stage: .uploading)
        }

        // The feed
        let posts = posts(found, picture: picture)
        render("captures-feed") { model in model.previewCaptures(posts, next: "more") }
        render("captures-feed-clip") { model in model.previewCaptures(posts, index: 1, action: 1, next: "more") }
        render("captures-feed-mine") { model in model.previewCaptures([posts[2], posts[0]], index: 1, action: 3, armed: posts[2].id) }
        render("captures-feed-empty") { model in model.previewCaptures([]) }
        render("captures-feed-failed") { model in
            model.previewCaptures([])
            model.captures.feed = TogetherCaptures()
            model.captures.failed = true
        }

        // Comments
        let page = comments(on: posts[0].id)
        render("captures-comments") { model in
            model.previewCaptures(posts)
            model.previewComments(page)
        }
        render("captures-comments-quick") { model in
            model.previewCaptures(posts)
            model.previewComments(page, composer: 0)
        }
        render("captures-comments-reply") { model in
            model.previewCaptures(posts)
            model.previewComments(page, line: 0, replyTo: page.items[0], draft: T.language == .turkish ? "Hangi bölüm bu?" : "Which chapter is this?")
        }
        render("captures-comments-delete") { model in
            model.previewCaptures(posts)
            model.previewComments(page, line: 3, armed: page.items[0].replies[1].id)
        }
        render("captures-comments-empty") { model in
            model.previewCaptures(posts)
            model.previewComments(TogetherCommentPage(items: [], next: nil))
        }

        // The way in, in Friends
        render("captures-friends-row") { model in
            model.overlay = .friends
            model.panelInRows = true
            model.panelRow = model.friendRows().firstIndex { $0.id == "friends-captures" } ?? 0
        }
    }

    static func posts(_ found: [Game], picture: @escaping (Int) -> String?) -> [TogetherPost] {
        let games = found.prefix(3).map { TogetherActivity.Game(titleId: $0.titleID, names: ["en": $0.name], iconUrl: nil) }
        let game = { (index: Int) in games.isEmpty ? nil : games[index % games.count] }
        let image = { (id: String, index: Int) in
            TogetherMedia(id: id, kind: "image", width: 1920, height: 1080, url: picture(index), thumb: picture(index))
        }
        let robin = TogetherPerson(userId: SocialPreviews.me.id, handle: SocialPreviews.me.handle, displayName: SocialPreviews.me.displayName, avatar: nil)
        let turkish = T.language == .turkish
        return [
            TogetherPost(id: "p3", author: SocialPreviews.mira, caption: turkish ? "Sonunda o bulmacayı çözdüm. Işıklara bakın!" : "Finally cracked that puzzle. Look at the lights!",
                         game: game(0), visibility: .friends, media: [image("a", 0)], likes: 12, liked: false, comments: 4, createdAt: SocialPreviews.ago(0.4)),
            TogetherPost(id: "p2", author: SocialPreviews.kenji, caption: turkish ? "Son saniyede kurtardım" : "Saved it at the last second",
                         game: game(1), visibility: .public,
                         media: [TogetherMedia(id: "c", kind: "clip", width: 1280, height: 720, durationMs: 42_000, url: nil, poster: picture(1))],
                         likes: 31, liked: true, comments: 0, source: "phone", createdAt: SocialPreviews.ago(3)),
            TogetherPost(id: "p1", author: robin, caption: nil, game: game(2), visibility: .friends,
                         media: [image("b", 2), image("d", 0), image("e", 1)], likes: 0, liked: false, comments: 1, mine: true, source: "launcher", createdAt: SocialPreviews.ago(26)),
        ]
    }

    static func comments(on post: String) -> TogetherCommentPage {
        let turkish = T.language == .turkish
        let robin = TogetherPerson(userId: SocialPreviews.me.id, handle: SocialPreviews.me.handle, displayName: SocialPreviews.me.displayName, avatar: nil)
        let reply1 = TogetherComment(id: "r1", postId: post, author: SocialPreviews.mira, text: turkish ? "Üçüncü bölüm, çatıdan sonra" : "Chapter three, right after the roof",
                                     replyTo: "c2", createdAt: SocialPreviews.ago(0.2))
        let reply2 = TogetherComment(id: "r2", postId: post, author: robin, text: turkish ? "Teşekkürler, bu akşam deneyeceğim" : "Thanks, trying it tonight",
                                     replyTo: "c2", createdAt: SocialPreviews.ago(0.1), canDelete: true)
        return TogetherCommentPage(items: [
            TogetherComment(id: "c2", postId: post, author: SocialPreviews.kenji, text: turkish ? "Bu neresi? Hiç görmedim" : "Where is this? Never saw it",
                            createdAt: SocialPreviews.ago(0.3), replies: [reply1, reply2]),
            TogetherComment(id: "c1", postId: post, author: robin, text: "GG", createdAt: SocialPreviews.ago(0.35), canDelete: true),
        ], next: nil)
    }
}
