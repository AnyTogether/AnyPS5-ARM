import AnyPS5Core
import AppKit
import SwiftUI

/// Cloud saves and media drawn offscreen for `--render-preview`: Settings with Save Sync through
/// AnyTogether, Settings → Cloud Storage, photos, clips and voice notes in a thread, a photo over
/// the whole screen, the gallery's share list and a profile's gallery. Pictures come from the
/// games' own artwork. ANYPS5_PREVIEW_ONLY=cloud draws only these.
@MainActor
enum CloudPreviews {
    static let mib = 1_048_576

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        var preferences = preferences
        preferences.saveSync = true
        preferences.syncThrough = AppModel.syncThroughTogether
        // A screenshot and a clip of the selected game for the gallery: its artwork as the picture.
        let shots = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-cloud-shots")
        try? FileManager.default.removeItem(at: shots)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let game = PreviewRenderer.selectedTitle.flatMap { id in found.first { $0.titleID == id } } ?? (found.isEmpty ? nil : found[min(1, found.count - 1)])
        if let game, let art = game.background ?? game.icon {
            for stamp in ["20261025-211502", "20261024-193010", "20261023-120001"] {
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

        let overview = overview(found, picture: picture)
        render("cloud-settings") { model in
            model.cloud.overview = overview
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "behaviour" } ?? 0
            model.panelInRows = true
            model.panelRow = model.panelCategories()[model.panelCategory].rows.firstIndex { $0.id == "syncThrough" } ?? 0
        }
        render("cloud-storage") { model in model.previewCloudStorage(overview, row: 2) }
        if let first = overview.saves.first, first.versions.count > 1 {
            let older = first.versions[1]
            render("cloud-storage-restore") { model in
                model.previewCloudStorage(overview, expanded: older.id)
                model.panelRow = model.cloudStorageRows().firstIndex { $0.id == "restore-\(older.id)" } ?? 0
            }
            render("cloud-storage-delete") { model in
                model.previewCloudStorage(overview, armed: "deleteslot-\(first.id)")
                model.panelRow = model.cloudStorageRows().firstIndex { $0.id == "deleteslot-\(first.id)" } ?? 0
            }
        }
        render("cloud-storage-empty") { model in
            model.previewCloudStorage(TogetherStorageOverview(enabled: true, usage: TogetherStorageUsage(used: 0, limit: 100 * mib, saves: 0, media: 0)), row: 1)
        }
        render("cloud-storage-full") { model in
            var full = overview
            full = TogetherStorageOverview(enabled: true, usage: TogetherStorageUsage(used: 97 * mib, limit: 100 * mib, saves: 88 * mib, media: 9 * mib), saves: full.saves, media: full.media)
            model.previewCloudStorage(full, row: 2)
        }

        let thread = messages(picture: picture)
        let mira = SocialPreviews.mira
        let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let conversation = TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, mira], lastSeq: thread.count, readSeq: thread.count, unread: 0,
                                                lastMessage: thread.last, updatedAt: Date())
        let kenji = TogetherConversation(id: "c2", kind: "direct", title: nil, members: [robin, SocialPreviews.kenji], lastSeq: 4, readSeq: 2, unread: 2,
                                         lastMessage: TogetherMessage(id: "k4", conversationId: "c2", seq: 4, authorId: "f2", text: "[clip]", createdAt: Date().addingTimeInterval(-600), kind: "clip",
                                                                      attachments: [TogetherAttachment(media: TogetherMedia(id: "x", kind: "clip", url: nil))]),
                                         updatedAt: Date().addingTimeInterval(-600))
        var inbox = TogetherInbox(me: "u1", conversations: [conversation, kenji])
        inbox.threads["c1"] = thread
        render("cloud-messages") { model in model.previewMessages(inbox, index: 0, inThread: true) }
        if let photo = thread.first(where: { $0.kind == "image" })?.attachment?.media {
            render("cloud-messages-viewer") { model in
                model.previewMessages(inbox, index: 0, inThread: true)
                model.cloud.viewing = photo
            }
        }
        render("cloud-gallery-share") { model in
            model.inbox = inbox
            model.open(.gallery)
            model.galleryIndex = 0
            model.cloud.sharing = true
            model.cloud.shareIndex = 0
        }
        render("cloud-gallery-viewer-share") { model in
            model.inbox = inbox
            model.open(.gallery)
            model.galleryViewing = true
            model.cloud.sharing = true
            model.cloud.shareIndex = 2
        }
        var items: [TogetherMedia] = []
        for index in 0 ..< 5 {
            let clip = index == 1
            let link: String? = picture(index)
            let made: Date = SocialPreviews.ago(Double(index) * 20)
            items.append(TogetherMedia(id: "g\(index)", kind: clip ? "clip" : "image", size: 2 * mib, width: 1920, height: 1080, durationMs: clip ? 30000 : nil,
                                       url: link, thumb: link, poster: clip ? link : nil, gallery: index, createdAt: made))
        }
        let miraProfile = TogetherProfile(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil, bio: "Souls games, slowly.", country: "TR", friendship: "friends")
        let library = found.prefix(3).map { TogetherPlayedGame(titleId: $0.titleID, names: ["en": $0.name], iconUrl: nil, lastPlayedAt: SocialPreviews.ago(30), secondsPlayed: 26_100, trophiesEarned: 9, trophiesTotal: 40, progress: 22, points: 420) }
        render("cloud-profile-gallery") { model in
            model.previewProfile(TogetherProfilePage(profile: miraProfile, library: .shown(library), trophies: .shown([])))
            model.cloud.profileGallery = .shown(items)
        }
        render("cloud-profile-gallery-private") { model in
            model.previewProfile(TogetherProfilePage(profile: miraProfile, library: .shown(library), trophies: .shown([])))
            model.cloud.profileGallery = .private
        }
    }

    static func overview(_ found: [Game], picture: (Int) -> String?) -> TogetherStorageOverview {
        let sha = { (n: Int) in String(repeating: String(n), count: 64) }
        let games = found.prefix(3)
        let slots = games.enumerated().map { index, game -> TogetherSaveSlot in
            let versions = (0 ..< (index == 0 ? 3 : index == 1 ? 2 : 1)).map { v in
                TogetherSaveVersion(id: "v\(index)-\(v)", version: 7 - v, size: (12 - index * 4 - v) * mib / 2, sha256: sha(index * 3 + v), device: v == 1 ? "Mac mini" : "MacBook Air",
                                    createdAt: SocialPreviews.ago(Double(v) * 26 + Double(index) * 3))
            }
            return TogetherSaveSlot(id: "s\(index)", titleId: game.titleID, game: game.name, slot: TogetherCloudSave.slot, updatedAt: SocialPreviews.ago(Double(index)), versions: versions)
        }
        let media = [
            TogetherMedia(id: "m1", kind: "image", size: 1_400_000, width: 1920, height: 1080, url: picture(0), thumb: picture(0), gallery: 0, createdAt: SocialPreviews.ago(2)),
            TogetherMedia(id: "m2", kind: "clip", size: 18 * mib, width: 1280, height: 720, durationMs: 30_000, url: nil, poster: picture(1), createdAt: SocialPreviews.ago(20)),
            TogetherMedia(id: "m3", kind: "voice", size: 180_000, durationMs: 9_000, url: nil, createdAt: SocialPreviews.ago(30)),
        ]
        let saves = slots.reduce(0) { $0 + $1.size }
        let mediaBytes = media.reduce(0) { $0 + $1.size }
        return TogetherStorageOverview(enabled: true, usage: TogetherStorageUsage(used: saves + mediaBytes, limit: 100 * mib, saves: saves, media: mediaBytes), saves: slots, media: media)
    }

    static func messages(picture: (Int) -> String?) -> [TogetherMessage] {
        let at = { (minutes: Double) in Date().addingTimeInterval(-minutes * 60) }
        let photo = TogetherMedia(id: "p1", kind: "image", size: 900_000, width: 1920, height: 1080, url: picture(0), thumb: picture(0), createdAt: at(30))
        let clip = TogetherMedia(id: "p2", kind: "clip", size: 14 * mib, width: 1280, height: 720, durationMs: 27_000, url: nil, poster: picture(1), createdAt: at(20))
        let voice = TogetherMedia(id: "p3", kind: "voice", size: 120_000, durationMs: 8_000, url: nil, createdAt: at(12))
        return [
            TogetherMessage(id: "m1", conversationId: "c1", seq: 1, authorId: "f1", text: "did you beat the boss?", createdAt: at(34)),
            TogetherMessage(id: "m2", conversationId: "c1", seq: 2, authorId: "u1", text: "finally. look", createdAt: at(31), kind: "image", caption: "finally. look",
                            attachments: [TogetherAttachment(media: photo)]),
            TogetherMessage(id: "m3", conversationId: "c1", seq: 3, authorId: "f1", text: "[clip]", createdAt: at(20), kind: "clip", attachments: [TogetherAttachment(media: clip)]),
            TogetherMessage(id: "m4", conversationId: "c1", seq: 4, authorId: "f1", text: "[voice note]", createdAt: at(12), kind: "voice", attachments: [TogetherAttachment(media: voice)]),
            TogetherMessage(id: "m5", conversationId: "c1", seq: 5, authorId: "u1", text: "[photo]", createdAt: at(5), kind: "image", attachments: [TogetherAttachment(id: "gone", kind: "image", removed: true)]),
            TogetherMessage(id: "m6", conversationId: "c1", seq: 6, authorId: "u1", text: "GG", createdAt: at(4)),
        ]
    }
}
