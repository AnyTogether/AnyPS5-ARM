import AnyPS5Core
import AppKit
import SwiftUI

/// End-to-end encrypted direct messages drawn offscreen for `--render-preview`: an encrypted
/// thread with a sealed photo (sealed and opened for real, with throwaway keys), the encryption
/// sheet before and after comparing, the devices-changed notice, a conversation that is not
/// encrypted, one whose other person has no device, messages that cannot be read here, the list's
/// previews, and reporting a sealed message.
@MainActor
enum E2EEPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let ago = { (minutes: Double) in Date().addingTimeInterval(-minutes * 60) }
        let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
        let sol = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)
        let mac = TogetherE2EE.DeviceSecrets.generate(), phone = TogetherE2EE.DeviceSecrets.generate(), miraPC = TogetherE2EE.DeviceSecrets.generate()
        func listed(_ device: TogetherE2EE.DeviceSecrets, _ user: String, _ name: String) -> TogetherE2EE.Device {
            var record = try! device.publicDevice(for: user)
            record.name = name
            return record
        }
        let robinDevices = [listed(mac, "u1", "Robin's MacBook Pro · AnyPS5"), listed(phone, "u1", "Robin's iPhone · AnyPS5 Remote")]
        let miraDevices = [listed(miraPC, "f1", "MIRA-DESKTOP · AnyPS5")]
        let everyone = (robinDevices + miraDevices).map(TogetherE2EE.Recipient.init)

        func sealed(_ seq: Int, from author: String, _ payload: TogetherE2EE.Payload, minutes: Double, attachments: [TogetherAttachment]? = nil,
                    recipients: [TogetherE2EE.Recipient]? = nil) -> TogetherMessage {
            let id = "0190f1a2-0000-7000-8000-0000000e\(String(format: "%04d", seq))"
            let sender = author == "u1" ? mac : miraPC
            let seal = try! TogetherE2EE.seal(payload, conversationId: "c1", messageId: id, senderUserId: author, sender: sender, recipients: recipients ?? everyone).sealed
            return TogetherMessage(id: id, conversationId: "c1", seq: seq, authorId: author, text: "[encrypted message]", createdAt: ago(minutes),
                                   kind: attachments == nil ? "text" : "image", attachments: attachments, sealed: seal)
        }
        let photo = TogetherMedia(id: "md-photo", kind: "image", contentType: "application/octet-stream", url: "https://files.anytogether.test/md-photo", sealed: true)
        var thread = [
            sealed(1, from: "f1", TogetherE2EE.Payload(text: "From before your Mac had keys"), minutes: 2000, recipients: [everyone[1], everyone[2]]),
            sealed(2, from: "f1", TogetherE2EE.Payload(text: "Did you beat the Moorwing yet?"), minutes: 14),
            sealed(3, from: "u1", TogetherE2EE.Payload(text: "Third try. Send me your route?"), minutes: 12),
            sealed(4, from: "f1", TogetherE2EE.Payload(text: "This ledge, then dash left 👇",
                                                      attachment: .init(mediaId: photo.id, kind: "image", type: "image/png", size: 1, key: "", nonce: "", width: 1920, height: 1080)),
                   minutes: 10, attachments: [TogetherAttachment(media: photo)]),
            sealed(5, from: "u1", TogetherE2EE.Payload(text: "Oh! That's the trick. GG 🏆"), minutes: 2),
        ]
        thread[1].reactions = [TogetherReactionCount(reaction: .fire, count: 1, userIds: ["u1"])]
        let solLast = TogetherMessage(id: "k3", conversationId: "c2", seq: 3, authorId: "f2", text: "Party tonight?", createdAt: ago(180))
        let conversations = [
            TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, mira], lastSeq: 5, readSeq: 5, unread: 0, lastMessage: thread.last, updatedAt: ago(2),
                                 receipts: [TogetherReceipt(userId: "f1", readSeq: 5, deliveredSeq: 5)], encrypted: true),
            TogetherConversation(id: "c2", kind: "direct", title: nil, members: [robin, sol], lastSeq: 3, readSeq: 1, unread: 2, lastMessage: solLast, updatedAt: ago(180)),
        ]
        var inbox = TogetherInbox(me: "u1", conversations: conversations)
        inbox.threads["c1"] = thread
        inbox.threads["c2"] = [TogetherMessage(id: "k2", conversationId: "c2", seq: 2, authorId: "u1", text: "Up for some co-op later?", createdAt: ago(190)), solLast]

        var book = TogetherE2EEBook(me: "u1", device: mac)
        book.availability = .on
        book.learn([TogetherE2EEPerson(userId: "u1", devices: robinDevices), TogetherE2EEPerson(userId: "f1", devices: miraDevices), TogetherE2EEPerson(userId: "f2", devices: [])])
        for conversation in conversations { book.noteDevices(conversation) }
        for message in thread { book.open(message) }

        // The sealed photo, opened: shown from a file as the launcher does.
        var opened: [String: TogetherMedia] = [:]
        if let still, let tiff = still.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-e2ee-photo.png")
            try? png.write(to: file)
            opened[photo.id] = TogetherMedia(id: photo.id, kind: "image", contentType: "image/png", width: 1920, height: 1080, url: file.absoluteString, sealed: true)
        }

        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.previewMessages(inbox, index: 0, inThread: true)
                model.e2ee = book
                model.e2eeMedia = opened
                configure(model)
            }
        }
        render("e2ee-thread") { _ in }
        render("e2ee-thread-compared") { model in
            model.e2ee?.markCompared(conversations[0])
        }
        render("e2ee-sheet") { model in
            model.messageActions.menu = .init(target: .encryption("c1"))
        }
        render("e2ee-sheet-compared") { model in
            model.e2ee?.markCompared(conversations[0])
            model.messageActions.menu = .init(target: .encryption("c1"))
        }
        render("e2ee-notice") { model in
            model.e2ee?.remembered.notices["c1"] = .init(mine: false, theirs: true)
        }
        render("e2ee-notice-sheet") { model in
            model.e2ee?.remembered.notices["c1"] = .init(mine: false, theirs: true)
            model.messageActions.menu = .init(target: .encryption("c1"))
        }
        render("e2ee-undecryptable") { model in
            var broken = thread
            let body = "AAAA" + (broken[2].sealed?.body.dropFirst(4) ?? "")
            broken[2].sealed?.body = body
            var book = book
            book.open(broken[2])
            model.inbox?.threads["c1"] = broken
            model.e2ee = book
        }
        render("e2ee-off") { model in
            model.messagesIndex = 1
        }
        render("e2ee-off-sheet") { model in
            model.messagesIndex = 1
            model.messageActions.menu = .init(target: .encryption("c2"))
        }
        render("e2ee-nodevice") { model in
            model.messagesIndex = 0
            model.e2ee?.learn([TogetherE2EEPerson(userId: "f1", devices: [])])
        }
        render("e2ee-list") { model in
            model.messagesInThread = false
            model.messagesIndex = 0
        }
        render("e2ee-conversation-menu") { model in
            model.e2ee?.remembered.notices["c1"] = .init(mine: false, theirs: true)
            model.messagesInThread = false
            model.messageActions.menu = .init(target: .conversation("c1"), row: 2)
        }
        render("e2ee-report") { model in
            model.messageActions.picked = 2
            model.messageActions.menu = .init(target: .report(conversation: "c1", seq: 2), row: 1)
        }
    }
}
