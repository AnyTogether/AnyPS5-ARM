import AnyPS5Core
import AppKit
import UserNotifications

/// The launcher's notifications in Notification Center, as AnyPS5 Desktop gives them on Windows
/// (a toast) and Linux (notify-send): what the card says while the launcher is behind other
/// windows and no game is playing, where the card would cover someone else's app and then be
/// gone. Over a game the card stays (SystemNotice.route). The callers keep their own rules:
/// nothing when the launcher is in front, nothing social on Do Not Disturb.
@MainActor
final class SystemNotices: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotices()

    /// Whether a game is playing (or starting): the card is seen over it.
    var gamePlaying: () -> Bool = { false }
    /// Whether the launcher is in front.
    var launcherInFront: () -> Bool = { NSApp?.isActive ?? true }
    /// A click on a notification: the launcher in front.
    var opened: () -> Void = {}
    /// What macOS was told; refreshed as the launcher comes back to the front.
    var permission: SystemNotice.Permission
    /// Hands a notification to the centre; tests take it instead.
    var deliver: (UNNotificationRequest) -> Void
    /// Asks macOS whether the launcher may notify; tests count it.
    var askPermission: () -> Void = {}
    private var asked = false
    private var center: UNUserNotificationCenter?

    override init() {
        let available = SystemNotice.available(bundlePath: Bundle.main.bundlePath, bundleIdentifier: Bundle.main.bundleIdentifier)
        permission = available ? .undecided : .unavailable
        deliver = { _ in }
        super.init()
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        self.center = center
        deliver = { request in center.add(request) { _ in } }
        askPermission = { [weak self] in
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
    }

    /// Called once by the launcher's model: what is playing, what a click does, and the answer
    /// macOS already has.
    func start(gamePlaying: @escaping () -> Bool, opened: @escaping () -> Void) {
        self.gamePlaying = gamePlaying
        self.opened = opened
        guard let center else { return }
        center.delegate = self
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // Changed in System Settings meanwhile.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        center?.getNotificationSettings { [weak self] settings in
            let permission: SystemNotice.Permission = switch settings.authorizationStatus {
            case .authorized, .provisional: .allowed
            case .notDetermined: .undecided
            default: .denied
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.permission = permission } }
        }
    }

    /// Says it as a notification when that is where it goes; false when the card should be drawn
    /// instead. The first time away with no game it asks macOS, and the card says this one.
    func take(_ title: String, detail: String, icon: URL?) -> Bool {
        switch SystemNotice.route(launcherInFront: launcherInFront(), gamePlaying: gamePlaying(), permission: permission) {
        case .card:
            return false
        case .cardAndAsk:
            if !asked {
                asked = true
                askPermission()
            }
            return false
        case .system:
            let lines = SystemNotice.lines(title: title, detail: detail)
            let content = UNMutableNotificationContent()
            content.title = lines.title
            content.body = lines.body
            // The launcher's own cue plays, as with the card.
            content.sound = nil
            if let attachment = Self.attachment(icon) { content.attachments = [attachment] }
            deliver(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return true
        }
    }

    /// A game's icon beside the words: a copy, as the centre moves the file it is given.
    private static func attachment(_ icon: URL?) -> UNNotificationAttachment? {
        guard let icon, FileManager.default.fileExists(atPath: icon.path) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5 notices", isDirectory: true)
        let copy = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(icon.pathExtension.isEmpty ? "png" : icon.pathExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: icon, to: copy)
            return try UNNotificationAttachment(identifier: "icon", url: copy)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// In front the launcher says it in its own toast: nothing from the centre then.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { SystemNotices.shared.opened() }
            completionHandler()
        }
    }
}
