import AnyPS5Core
import AVFoundation
import AppKit
import SwiftUI

/// End-to-end encrypted direct messages (AnyTogether's docs/e2ee.md, "What every client does"):
/// this Mac's keys made once and registered, both people's devices fetched and checked when a
/// direct conversation opens (and again on `e2ee.devices` and on 409 e2ee_devices), every message
/// sealed when both have a device, sealed messages and attachments opened here, and the lock
/// state, the safety number and the devices-changed notice per conversation. A server without
/// the routes means no encryption: everything works as before.
extension AppModel {
    /// The Keychain items for the device keys: this Mac only, never synchronised.
    static let e2eeKeychain = KeychainVault(service: TogetherE2EEKeys.service, thisDeviceOnly: true)

    /// Where opened attachments are shown from while the launcher runs (only this user reads it).
    static var e2eeFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-E2EE", isDirectory: true) }

    /// Refused before anything went: why a sealed message cannot be sent now.
    enum E2EERefusal: Error {
        case noDevice
        case waiting
    }

    func e2eeRememberedFile(_ userId: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnyPS5/Together/E2EE/\(sessionProfileID)-\(userId).json")
    }

    // MARK: Keys and registration

    /// Signed in (the socket starts): this Mac's keys for the person, made once and kept in the
    /// Keychain, and registered for this session.
    func startE2EE() {
        guard persists, let user = togetherUser else { return }
        if e2ee?.me != user.id {
            resetE2EE()
            let account = TogetherE2EEKeys.account(profile: sessionProfileID, userId: user.id)
            e2ee = TogetherE2EEBook(me: user.id, device: TogetherE2EEKeys.loadOrMake(in: Self.e2eeKeychain, account: account),
                                    remembered: .load(e2eeRememberedFile(user.id)))
        }
        prepareE2EE()
    }

    /// Asks the server for this session's device, registering the keys when it has none or other
    /// ones. Not reached: asked again the next time a direct conversation opens or sends.
    func prepareE2EE() {
        guard persists, e2eePreparing == nil, let book = e2ee, book.availability == .unknown, let device = book.device else { return }
        let client = together, me = book.me
        // What it is, never the Mac's own name: friends' device lists read it (docs/e2ee.md).
        let name = TogetherE2EE.macDeviceName
        e2eePreparing = Task {
            defer { e2eePreparing = nil }
            do {
                try await client.prepareE2EE(device, userId: me, name: name)
                guard e2ee?.me == me else { return }
                e2ee?.availability = .on
                await refreshE2EEDevices(e2eePeople())
            } catch is TogetherE2EEUnsupported {
                if e2ee?.me == me { e2ee?.availability = .off }
            } catch {}
        }
    }

    /// Signed out or another profile: nothing of the person's stays in memory or on disk but
    /// the keys in the Keychain and what is remembered per conversation.
    func resetE2EE() {
        e2eePreparing?.cancel()
        e2eePreparing = nil
        e2ee = nil
        e2eeMedia = [:]
        e2eeMediaLoading = []
        e2eeFetching = []
        try? FileManager.default.removeItem(at: Self.e2eeFolder)
    }

    func saveE2EE() {
        guard persists, let book = e2ee else { return }
        book.remembered.save(e2eeRememberedFile(book.me))
    }

    // MARK: Devices

    /// The user and the other person of every direct conversation in the list.
    func e2eePeople() -> [String] {
        guard let inbox else { return e2ee.map { [$0.me] } ?? [] }
        return [inbox.me] + inbox.conversations.compactMap { $0.kind == "direct" ? $0.others(than: inbox.me).first?.userId : nil }
    }

    /// Fetches these people's devices, keeps the ones that check out, notes changes in their
    /// conversations and opens the messages that waited for them.
    func refreshE2EEDevices(_ users: [String]) async {
        guard let book = e2ee, book.availability == .on, !users.isEmpty else { return }
        let wanted = Array(Set(users))
        e2eeFetching.formUnion(wanted)
        defer { e2eeFetching.subtract(wanted) }
        guard let people = try? await together.e2eeDevices(of: wanted), e2ee?.me == book.me else { return }
        withAnimation(Motion.focus) {
            e2ee?.learn(people)
            noteE2EEDevices()
        }
        openSealedMessages()
    }

    /// Someone's devices changed (the gateway's `e2ee.devices`).
    func e2eeDevicesChanged(_ userId: String?) {
        guard let userId else { return }
        Task { await refreshE2EEDevices([userId]) }
    }

    /// Each direct conversation's devices against the ones last seen there.
    func noteE2EEDevices() {
        guard var book = e2ee, let inbox else { return }
        var changed = false
        for conversation in inbox.conversations where conversation.kind == "direct" {
            if book.noteDevices(conversation) { changed = true }
        }
        guard changed else { return }
        e2ee = book
        saveE2EE()
    }

    /// A direct conversation opened: both people's devices fetched and checked.
    func e2eeConversationOpened(_ conversation: TogetherConversation) {
        guard conversation.kind == "direct", let me = inbox?.me, let other = conversation.others(than: me).first?.userId else { return }
        prepareE2EE()
        Task { await refreshE2EEDevices([me, other]) }
    }

    /// The list read: what it says about encryption, and its last messages opened for the previews.
    func e2eeInboxArrived() {
        guard e2ee != nil else { return }
        noteE2EEDevices()
        openSealedMessages()
        if e2ee?.availability == .on { Task { await refreshE2EEDevices(e2eePeople()) } }
    }

    /// Opens the sealed messages loaded (the threads and the list's last messages); the authors'
    /// devices still waited for are fetched, at most every half minute.
    func openSealedMessages() {
        guard var book = e2ee, let inbox else { return }
        let messages = inbox.threads.values.flatMap { $0 } + inbox.conversations.compactMap(\.lastMessage)
        let sealed = messages.filter { $0.sealed != nil && $0.deletedAt == nil && book.opened($0) == nil }
        var remember = false
        for conversation in inbox.conversations where conversation.kind == "direct" && !book.remembered.encrypted.contains(conversation.id) {
            if conversation.encrypted || inbox.threads[conversation.id]?.contains(where: { $0.sealed != nil }) == true || conversation.lastMessage?.sealed != nil {
                book.sawEncrypted(conversation.id)
                remember = true
            }
        }
        guard !sealed.isEmpty || remember else { return }
        for message in sealed { book.open(message) }
        e2ee = book
        if remember { saveE2EE() }
        guard book.availability == .on else { return }
        let soon = Date().addingTimeInterval(-30)
        let waiting = book.waitingAuthors(sealed).filter { (book.fetched[$0] ?? .distantPast) < soon && !e2eeFetching.contains($0) }
        if !waiting.isEmpty { Task { await refreshE2EEDevices(Array(waiting)) } }
    }

    func e2eeLock(_ conversation: TogetherConversation) -> TogetherE2EEBook.Lock? { e2ee?.lock(conversation) }

    /// The other person's name in a direct conversation.
    func e2eeName(_ conversation: TogetherConversation) -> String {
        conversation.others(than: inbox?.me ?? "").first?.displayName ?? conversation.name(for: inbox?.me ?? "")
    }

    // MARK: Sending

    /// Seals `payload` for every device of both people and sends it (or `edit`s that message),
    /// sealing again when the server says the devices changed. Refused when the other person has
    /// no device, or the devices are not known even after fetching them.
    func sealAndSend(_ payload: TogetherE2EE.Payload, in conversation: TogetherConversation, replyTo: Int? = nil, mediaId: String? = nil,
                     edit: (seq: Int, id: String)? = nil) async throws -> TogetherMessage {
        if e2ee?.availability == .unknown {
            prepareE2EE()
            await e2eePreparing?.value
        }
        guard let book = e2ee, book.availability == .on, let device = book.device, let other = conversation.others(than: book.me).first?.userId else { throw E2EERefusal.waiting }
        let me = book.me
        if book.lock(conversation) != .on { await refreshE2EEDevices([me, other]) }
        switch e2ee?.lock(conversation) {
        case .on: break
        case .noDevice, .off: throw E2EERefusal.noDevice
        default: throw E2EERefusal.waiting
        }
        let message = try await together.sendSealed(payload, in: conversation.id, messageId: edit?.id ?? UUID().uuidString.lowercased(), replyTo: replyTo, mediaId: mediaId,
                                                    edit: edit?.seq, from: me, device: device) { attempt in
            // 409 e2ee_devices: the lists anew, the change shown, sealed again.
            if attempt > 0 { await self.refreshE2EEDevices([me, other]) }
            guard let recipients = self.e2ee?.recipients(conversation) else { throw E2EERefusal.noDevice }
            return recipients
        }
        e2ee?.sawEncrypted(conversation.id)
        e2ee?.open(message)
        saveE2EE()
        return message
    }

    /// Whether this message must go sealed (or not at all): a direct conversation that is or will
    /// be encrypted.
    func sendsSealed(_ conversation: TogetherConversation) -> Bool {
        guard conversation.kind == "direct", let lock = e2eeLock(conversation) else { return false }
        return lock != .off
    }

    /// Text into an end-to-end encrypted conversation; the draft comes back if it does not go.
    func sendSealedText(_ text: String, raw: String, in conversation: TogetherConversation, replyTo: Int?) {
        Task {
            do {
                let sent = try await sealAndSend(TogetherE2EE.Payload(text: text), in: conversation, replyTo: replyTo)
                withAnimation(Motion.focus) { _ = inbox?.apply(sent, open: conversation.id) }
                keepSelection(conversation.id)
            } catch {
                if messageActions.replyTo == nil, selectedConversation?.id == conversation.id { messageActions.replyTo = replyTo }
                if messageDraft.isEmpty, !AppModel.quickReplies.contains(raw) { messageDraft = raw }
                showSealedFailure(error, in: conversation)
            }
        }
    }

    func showSealedFailure(_ error: Error, in conversation: TogetherConversation) {
        if case E2EERefusal.noDevice = error {
            show(TChat.format(.e2eeNoDevice, e2eeName(conversation)), symbol: "lock.trianglebadge.exclamationmark")
        } else {
            show(T.text(.messagesFailed), symbol: "exclamationmark.bubble.fill")
        }
    }

    /// The server refused a plain message (409 e2ee_required): the conversation is encrypted.
    func e2eeRequired(_ conversation: TogetherConversation) async {
        e2ee?.sawEncrypted(conversation.id)
        saveE2EE()
        if let me = inbox?.me, let other = conversation.others(than: me).first?.userId { await refreshE2EEDevices([me, other]) }
    }

    /// A screenshot or clip sealed on this Mac and uploaded as ciphertext: a photo drawn again
    /// first, so no location or camera data goes along; a clip with its poster sealed too.
    func uploadSealedShot(_ file: URL) async throws -> TogetherE2EE.Attachment {
        let limits = cloud.info?.media ?? TogetherStorageInfo.MediaLimits()
        if Screenshots.isClip(file) {
            let ready = try await MediaPrep.clip(file, maxBytes: limits.clip)
            defer { if ready != file { try? FileManager.default.removeItem(at: ready) } }
            let data = try Data(contentsOf: ready, options: .mappedIfSafe)
            let asset = AVURLAsset(url: ready)
            let size = try? await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize)
            let duration = try? await asset.load(.duration)
            var poster: (data: Data, contentType: String)?
            if let still = await MediaPrep.poster(ready), still.count <= limits.poster { poster = (still, "image/jpeg") }
            return try await together.uploadSealed(kind: "clip", data: data, contentType: "video/mp4", width: size.map { Int(abs($0.width)) }, height: size.map { Int(abs($0.height)) },
                                                   durationMs: duration.map { Int($0.seconds * 1000) }, poster: poster)
        }
        let ready = try await Task.detached { try MediaPrep.sealableImage(file, maxBytes: limits.image, maxPixels: limits.pixels) }.value
        return try await together.uploadSealed(kind: "image", data: ready.data, contentType: ready.contentType, width: ready.width, height: ready.height)
    }

    // MARK: Opening

    /// The opened payload of a sealed message.
    func sealedPayload(_ message: TogetherMessage) -> TogetherE2EE.Payload? {
        if case .payload(let payload) = e2ee?.opened(message) { return payload }
        return nil
    }

    /// The words of a sealed message for a list, a quote or a notice.
    func sealedWords(_ message: TogetherMessage, preview: Bool = false) -> String {
        switch e2ee?.opened(message) {
        case .payload(let payload):
            let text = payload.text.flatMap { $0.isEmpty ? nil : $0 }
            guard let attachment = payload.attachment else { return text ?? "" }
            let kind = TCloud.kind(attachment.kind)
            return text.map { "\(kind) · \($0)" } ?? kind
        case .beforeDevice: return preview ? TChat.text(.e2eePreview) : TChat.text(.e2eeBeforeDevice)
        case .undecryptable: return preview ? TChat.text(.e2eePreview) : TChat.text(.e2eeUndecryptable)
        case nil: return TChat.text(.e2eePreview)
        }
    }

    /// Whether the user may edit the message: for a sealed one, only once it opened here.
    func canEditMessage(_ message: TogetherMessage) -> Bool {
        guard let me = chatMe else { return false }
        guard message.sealed != nil else { return message.canEdit(by: me) }
        guard let payload = sealedPayload(message), message.authorId == me, message.deletedAt == nil, message.editCount < TogetherMessage.maxEdits,
              Date().timeIntervalSince(message.createdAt) < TogetherMessage.editWindow else { return false }
        return payload.attachment == nil || !(payload.text ?? "").isEmpty
    }

    /// The words an edit starts from.
    func editableWords(_ message: TogetherMessage) -> String? {
        message.sealed != nil ? sealedPayload(message)?.text : message.words
    }

    /// A sealed attachment opened on this Mac: the media to show from its files, once there.
    func sealedMedia(_ attachment: TogetherE2EE.Attachment) -> TogetherMedia? { e2eeMedia[attachment.mediaId] }

    /// Downloads, opens and keeps a sealed attachment in files only this user reads.
    func loadSealedMedia(_ attachment: TogetherE2EE.Attachment, from media: TogetherMedia) {
        guard e2eeMedia[attachment.mediaId] == nil, !e2eeMediaLoading.contains(attachment.mediaId), persists else { return }
        e2eeMediaLoading.insert(attachment.mediaId)
        let client = together, me = e2ee?.me
        Task {
            defer { e2eeMediaLoading.remove(attachment.mediaId) }
            guard let opened = try? await client.openSealed(attachment, media: media), e2ee?.me == me else { return }
            let folder = Self.e2eeFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = folder.appendingPathComponent(UUID().uuidString + Self.fileExtension(attachment.type))
            guard FileManager.default.createFile(atPath: file.path, contents: opened.file, attributes: [.posixPermissions: 0o600]) else { return }
            var posterLink: String?
            if let poster = opened.poster {
                let still = folder.appendingPathComponent(UUID().uuidString + Self.fileExtension(attachment.poster?.type ?? "image/jpeg"))
                if FileManager.default.createFile(atPath: still.path, contents: poster, attributes: [.posixPermissions: 0o600]) { posterLink = still.absoluteString }
            }
            let shown = TogetherMedia(id: attachment.mediaId, kind: attachment.kind, contentType: attachment.type, size: attachment.size ?? opened.file.count, width: attachment.width,
                                      height: attachment.height, durationMs: attachment.durationMs, url: file.absoluteString, poster: posterLink, createdAt: media.createdAt, sealed: true)
            withAnimation(.easeOut(duration: 0.25)) { e2eeMedia[attachment.mediaId] = shown }
        }
    }

    static func fileExtension(_ type: String) -> String {
        switch type {
        case "image/png": return ".png"
        case "image/jpeg": return ".jpg"
        case "image/webp": return ".webp"
        case "video/mp4": return ".mp4"
        case "audio/ogg": return ".ogg"
        case "audio/webm": return ".webm"
        case "audio/mp4", "audio/aac", "audio/x-m4a": return ".m4a"
        default: return ""
        }
    }

    // MARK: The sheet and the notice

    func openEncryptionSheet(_ conversationId: String) {
        withAnimation(Motion.overlay) { messageActions.menu = .init(target: .encryption(conversationId)) }
        Sounds.shared.play(.select)
        if let conversation = inbox?.conversations.first(where: { $0.id == conversationId }) { e2eeConversationOpened(conversation) }
    }

    func markCompared(_ conversation: TogetherConversation, _ on: Bool) {
        withAnimation(Motion.focus) { e2ee?.markCompared(conversation, on) }
        saveE2EE()
        Sounds.shared.play(.select)
    }

    func dismissE2EENotice(_ conversationId: String) {
        withAnimation(Motion.focus) { e2ee?.dismissNotice(conversationId) }
        saveE2EE()
        Sounds.shared.play(.back)
    }

    // MARK: Reporting

    /// Reports a message; a sealed one goes with its content key, so the moderators can read it.
    func reportMessage(_ message: TogetherMessage, reason: String) {
        let key = message.sealed != nil ? e2ee?.contentKey(message) : nil
        guard message.sealed == nil || key != nil else { return show(T.text(.messagesFailed), symbol: "exclamationmark.bubble.fill") }
        Sounds.shared.play(.select)
        Task {
            do {
                try await together.reportMessage(message.id, reason: reason, contentKey: key)
                show(TChat.text(.reported), symbol: "checkmark.shield.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}
