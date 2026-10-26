import AnyPS5Core
import AppKit
import SwiftUI

/// Retired launchers: when AnyTogether answers client_too_old (its MIN_LAUNCHER_VERSION is newer
/// than this copy), the launcher says Update Required once, with the update it can install itself
/// (the same download, signature check and restart as Settings → About), or the downloads page.
/// Games keep playing; only AnyTogether waits.
extension AppModel {
    /// The client with the launcher listening for client_too_old.
    func wireTogether(_ client: TogetherClient) -> TogetherClient {
        client.onClientTooOld = { [weak self] old in
            Task { @MainActor in self?.clientTooOld(old) }
        }
        return client
    }

    /// The first client_too_old opens Update Required (a toast over a game or another screen);
    /// later ones only keep the minimum current.
    func clientTooOld(_ old: TogetherClientTooOld) {
        let first = updateRequired == nil
        updateRequired = old
        guard first else { return }
        lookUpUpdateQuietly()
        if overlay == nil, running == nil, starting == nil, preferences.onboarded {
            open(.updateRequired)
        } else {
            show(TK.format(.updateRequiredToast, old.minimum), symbol: "arrow.down.circle.fill")
        }
    }

    /// What the screen offers, as the launcher's own update stands.
    func updateRequiredRows() -> [PanelRow] {
        guard let old = updateRequired else { return [] }
        var rows = [PanelRow(id: "required-why", title: old.current.map { TK.format(.updateRequiredTooOldVersion, $0) } ?? TK.text(.updateRequiredTooOld),
                             detail: TK.text(.updateRequiredDetail), symbol: "exclamationmark.arrow.triangle.2.circlepath", kind: .info(""), wraps: true)]
        if let ready = readyUpdate {
            rows.append(PanelRow(id: "required-restart", title: TK.text(.updateRequiredRestart), detail: TK.format(.updateRequiredRestartDetail, ready.release.version),
                                 symbol: "arrow.clockwise.circle.fill", kind: .action(destructive: false) { [weak self] in self?.restartForUpdate() }))
        } else if let progress = updateProgress {
            rows.append(PanelRow(id: "required-downloading", title: TK.format(.updateRequiredDownloading, Int(progress * 100)), symbol: "arrow.down.circle", kind: .info("")))
        } else if let release = availableUpdate, canReplaceItself {
            rows.append(PanelRow(id: "required-update", title: TK.format(.updateRequiredUpdate, release.version), detail: TK.text(.updateRequiredUpdateDetail),
                                 symbol: "arrow.down.circle.fill", kind: .action(destructive: false) { [weak self] in self?.installUpdate() }))
        } else if checkingUpdates {
            rows.append(PanelRow(id: "required-looking", title: TK.text(.updateRequiredLooking), symbol: "magnifyingglass", kind: .info("")))
        }
        // The downloads page, when this copy cannot update itself or found nothing to install.
        if readyUpdate == nil, updateProgress == nil, !(availableUpdate != nil && canReplaceItself), let page = old.downloadUrl {
            rows.append(PanelRow(id: "required-download", title: TK.text(.updateRequiredDownload), detail: TK.text(.updateRequiredDownloadDetail),
                                 symbol: "safari", kind: .action(destructive: false) { NSWorkspace.shared.open(page) }))
        }
        rows.append(PanelRow(id: "required-later", title: TK.text(.updateRequiredLater), symbol: "clock", kind: .action(destructive: false) { [weak self] in
            self?.closeOverlay()
        }))
        return rows
    }
}
