import AnyPS5Core
import AppKit
import SwiftUI

/// AnyTogether's notifications: the bell in the top bar with the unread count, the list (choosing
/// one reads it and goes where it points), and a toast for a new one while the launcher is in front.
extension AppModel {
    func openNotifications() {
        open(.notifications)
        panelInRows = true
        // The first unread one, past "mark all as read".
        panelRow = notificationRows().firstIndex { $0.id.hasPrefix("note-") } ?? 0
        loadNotifications()
    }

    /// The list and the badge, read again.
    func loadNotifications() {
        guard togetherUser != nil else { return }
        social.follow(togetherUser?.id)
        social.notificationsTask?.cancel()
        social.notificationsTask = Task {
            do {
                let page = try await together.notifications()
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.notifications.load(page)
                    social.notificationsFailed = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { social.notificationsFailed = !social.notifications.loaded }
            }
        }
    }

    func loadOlderNotifications() {
        guard let before = social.notifications.items.last?.id, social.notifications.more else { return }
        Task {
            guard let page = try? await together.notifications(before: before) else { return }
            withAnimation(Motion.overlay) { social.notifications.loadOlder(page) }
        }
    }

    var notificationsSubtitle: String? {
        guard togetherUser != nil else { return nil }
        let unread = social.notifications.unread
        return unread > 0 ? TS.format(.notifUnread, unread) : TS.text(.notifEmpty)
    }

    func notificationRows() -> [PanelRow] {
        guard togetherUser != nil else {
            return [
                PanelRow(id: "notes-out", title: TS.text(.notifSignIn), symbol: "bell.slash", kind: .info("")),
                PanelRow(id: "notes-signin", title: T.text(.togetherSignIn), symbol: "person.crop.circle.badge.plus", kind: .action(destructive: false) { [weak self] in
                    self?.openTogetherSettings()
                }),
            ]
        }
        let center = social.notifications
        var rows: [PanelRow] = []
        if center.unread > 0 {
            rows.append(PanelRow(id: "notes-all", title: TS.text(.notifMarkAll), symbol: "checkmark.circle", kind: .action(destructive: false) { [weak self] in self?.readAllNotifications() }))
        }
        if !center.loaded {
            rows.append(PanelRow(id: "notes-state", title: TS.text(social.notificationsFailed ? .notifFailed : .notifLoading), symbol: social.notificationsFailed ? "wifi.exclamationmark" : "hourglass", kind: .info("")))
        } else if center.items.isEmpty {
            rows.append(PanelRow(id: "notes-none", title: TS.text(.notifEmpty), symbol: "bell", kind: .info("")))
        }
        for note in center.items {
            // An unread one starts with a dot.
            let detail = (note.read ? "" : "● ") + [notificationDetail(note), ProfileView.relative(note.updatedAt)].compactMap { $0 }.joined(separator: " · ")
            rows.append(PanelRow(id: "note-\(note.id)", title: notificationText(note), detail: detail, symbol: Self.notificationSymbol(note.kind),
                                 kind: .action(destructive: false) { [weak self] in self?.openNotification(note) },
                                 person: note.actor.map { PanelPerson(name: $0.displayName, avatar: $0.avatar) }))
        }
        if center.more {
            rows.append(PanelRow(id: "notes-more", title: TS.text(.notifMore), symbol: "chevron.down.circle", kind: .action(destructive: false) { [weak self] in self?.loadOlderNotifications() }))
        }
        return rows
    }

    /// Reads it (here at once, then on the server) and goes where it points.
    func openNotification(_ note: TogetherNotification) {
        if !note.read {
            withAnimation(Motion.overlay) { social.notifications.markRead(note.id) }
            Task {
                if let unread = try? await together.readNotification(note.id) { social.notifications.setUnread(unread) }
            }
        }
        switch note.kind {
        case .friendRequest, .friendAccepted, .gameInvite, .missedCall: open(.friends)
        case .partyInvite: open(.party)
        case .lfgRequest: openFindPlayers(category: 1)
        case .lfgAccepted: followInvite(note.data.invite)
        case .message: openMessages()
        case .warning, .other: break
        }
    }

    func readAllNotifications() {
        withAnimation(Motion.overlay) { social.notifications.markAllRead() }
        panelRow = 0
        Sounds.shared.play(.select)
        Task {
            if let unread = try? await together.readAllNotifications() { social.notifications.setUnread(unread) }
        }
    }

    /// The gateway's notification events: the list and badge follow; a new one the launcher does
    /// not announce otherwise gets a toast while it is in front.
    func notificationEvent(_ event: TogetherNotificationEvent) {
        // A parent answered or changed something: the limits are read again.
        if case .new(let note, _) = event, note.kindName.hasPrefix("family_") { refreshFamily() }
        withAnimation(Motion.overlay) { social.notifications.apply(event) }
        guard case .new(let note, _) = event, !note.read, note.kind.toastsOnItsOwn, NSApp.isActive, overlay != .notifications else { return }
        show([notificationText(note), notificationDetail(note)].compactMap { $0 }.joined(separator: " · "), symbol: Self.notificationSymbol(note.kind))
    }

    // MARK: Texts

    func notificationText(_ note: TogetherNotification) -> String {
        let name = note.actor?.displayName ?? ""
        switch note.kind {
        case .friendRequest: return TS.format(.notifFriendRequest, name)
        case .friendAccepted: return TS.format(.notifFriendAccepted, name)
        case .message:
            let count = note.data.count ?? 1
            return count > 1 ? TS.format(.notifMessages, name, count) : TS.format(.notifMessage, name)
        case .partyInvite: return TS.format(.notifPartyInvite, name)
        case .gameInvite: return TS.format(.notifGameInvite, name, note.data.titleId.map(gameName) ?? "")
        case .missedCall: return TS.format(.notifMissedCall, name)
        case .lfgRequest: return FP.format(.notifLfgRequest, name, notificationGame(note))
        case .lfgAccepted: return FP.format(.notifLfgAccepted, name, notificationGame(note))
        case .warning: return TS.text(.notifWarning)
        case .other: return familyNotificationText(note) ?? TS.text(.notifOther)
        }
    }

    /// The game a looking-for-group notification is about, as this Mac or the server names it.
    func notificationGame(_ note: TogetherNotification) -> String {
        guard let titleId = note.data.titleId else { return "" }
        return games.first { $0.titleID == titleId }?.name ?? note.data.gameNames.flatMap { TogetherGameNames(names: $0).name(in: T.language.rawValue) } ?? titleId
    }

    /// The message's words (and its group), or the warning's reason.
    func notificationDetail(_ note: TogetherNotification) -> String? {
        switch note.kind {
        case .message:
            let text = note.data.text.map { $0.count > 80 ? String($0.prefix(80)) + "…" : $0 }
            return [note.data.group == true ? note.data.title : nil, text].compactMap { $0 }.joined(separator: ": ").nilIfEmpty
        case .warning: return note.data.reason
        default: return nil
        }
    }

    static func notificationSymbol(_ kind: TogetherNotification.Kind) -> String {
        switch kind {
        case .friendRequest: return "person.badge.plus"
        case .friendAccepted: return "person.2.fill"
        case .message: return "bubble.left.fill"
        case .partyInvite: return "person.3.fill"
        case .gameInvite: return "gamecontroller.fill"
        case .missedCall: return "phone.arrow.down.left"
        case .lfgRequest: return "hand.raised.fill"
        case .lfgAccepted: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .other: return "bell.fill"
        }
    }

    func previewNotifications(_ notes: [TogetherNotification], unread: Int, more: Bool = false, row: Int = 1) {
        social.notifications.load(TogetherNotificationPage(notifications: notes, unread: unread, more: more))
        overlay = .notifications
        panelInRows = true
        panelRow = row
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
