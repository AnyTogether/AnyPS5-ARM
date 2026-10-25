import AnyPS5Core
import AppKit
import Combine
import SwiftUI

/// Cloud saves and media on AnyTogether, the launcher's side: whether the server keeps files,
/// Save Sync through the cloud (with the player asked about conflicts and a full quota), and
/// Settings → Cloud Storage with the usage, every game's saves (restore, delete) and the media.
@MainActor
final class CloudState: ObservableObject {
    /// What the server said of storage; nil until asked (or unreachable): everything hides.
    @Published var info: TogetherStorageInfo?
    @Published var overview: TogetherStorageOverview?
    @Published var failed = false
    /// A delete row pressed once: the next press deletes.
    @Published var armed: String?
    /// The save version whose Restore and Delete show.
    @Published var expanded: String?
    /// Something going up or down, so it is not started twice.
    @Published var working = false
    /// The share list over the gallery, and its focused row.
    @Published var sharing = false
    @Published var shareIndex = 0
    /// A photo or clip shown over the whole screen (from a message or a profile's gallery).
    @Published var viewing: TogetherMedia?
    /// The profile on screen's gallery; nil while read or when the server keeps no files.
    @Published var profileGallery: TogetherSection<[TogetherMedia]>?
    var task: Task<Void, Never>?
    var galleryTask: Task<Void, Never>?

    private var forward: AnyCancellable?

    init(owner: AppModel) {
        forward = objectWillChange.sink { [weak owner] _ in owner?.objectWillChange.send() }
    }

    var enabled: Bool { info?.enabled == true }
}

extension AppModel {
    static let syncThroughTogether = "together"

    /// Signed in to a server that keeps files.
    var cloudAvailable: Bool { togetherUser != nil && cloud.enabled }

    /// Save Sync goes through the AnyTogether cloud (and it can now).
    var cloudSaveSync: Bool { preferences.saveSync == true && preferences.syncThrough == Self.syncThroughTogether && cloudAvailable }

    /// Asks the server whether it keeps files; on sign-in, at launch and when the server changes.
    func refreshStorageInfo() {
        let client = together
        Task {
            do {
                let info = try await client.storageInfo()
                withAnimation(Motion.overlay) { cloud.info = info }
            } catch {
                // Unreachable now: what was known stays.
            }
        }
    }

    // MARK: Save Sync through the cloud

    func cloudSave(for game: Game) -> TogetherCloudSave? {
        guard cloudSaveSync, let user = togetherUser, let folder = gameFolder(game) else { return nil }
        let name = game.name
        let questions = TogetherCloudSave.Questions(conflict: { latest in
            await MainActor.run { AppModel.askConflict(game: name, latest: latest) }
        }, replaceLatest: { latest, _ in
            await MainActor.run { AppModel.askReplace(game: name, latest: latest) }
        })
        return TogetherCloudSave(client: together, game: folder, titleID: game.titleID, backups: SaveBackup.folder(for: game),
                                 workspace: TogetherCloudSave.workspace(for: user.id), device: Host.current().localizedName ?? "Mac",
                                 launcherVersion: AppModel.runningVersion, questions: questions)
    }

    /// The player's choice when both this Mac and the cloud changed.
    static func askConflict(game: String, latest: TogetherSaveVersion?) -> TogetherCloudSave.ConflictChoice {
        let alert = NSAlert()
        alert.messageText = TCloud.text(.conflictTitle)
        let when = latest.map { TCloud.date($0.createdAt) } ?? "—"
        alert.informativeText = TCloud.format(.conflictDetail, game, latest?.device ?? TCloud.text(.conflictCloudUnknown), when)
        alert.addButton(withTitle: TCloud.text(.conflictTakeCloud))
        alert.addButton(withTitle: TCloud.text(.conflictKeepMine))
        alert.addButton(withTitle: TCloud.text(.notNow))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .takeCloud
        case .alertSecondButtonReturn: return .keepThisMac
        default: return .notNow
        }
    }

    /// Whether the slot's newest cloud save may make way when only that makes room.
    static func askReplace(game: String, latest: TogetherSaveVersion?) -> Bool {
        let alert = NSAlert()
        alert.messageText = TCloud.text(.quotaTitle)
        let when = latest.map { TCloud.date($0.createdAt) } ?? "—"
        alert.informativeText = TCloud.format(.quotaReplaceDetail, game, when)
        alert.addButton(withTitle: TCloud.text(.replace))
        alert.addButton(withTitle: T.text(.cancel))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Syncs through the cloud, says what happened, then goes on (a refusal never stops a game).
    func syncThroughCloud(_ sync: TogetherCloudSave, game: Game, then: @escaping @MainActor () -> Void) {
        syncing = game.id
        Task {
            let result: Result<TogetherCloudSave.Outcome, Error>
            do { result = .success(try await sync.sync()) } catch { result = .failure(error) }
            syncing = nil
            switch result {
            case .success(.downloaded(_, let from)): show(TCloud.format(.savesDownloaded, from ?? TCloud.text(.conflictCloudUnknown)), symbol: "icloud.and.arrow.down")
            case .success(.uploaded): if running == nil { show(TCloud.text(.savesUploaded), symbol: "icloud.and.arrow.up") }
            case .failure(let error): show(T.text(.saveSyncFailed) + ": " + cloudMessage(error), symbol: "exclamationmark.icloud")
            default: break
            }
            if case .success = result, overlay == .cloudStorage { loadCloudStorage() }
            then()
        }
    }

    /// A storage refusal in words.
    func cloudMessage(_ error: Error) -> String {
        if let family = familyMessage(error) { return family }
        guard let problem = error as? TogetherProblem else {
            if let failure = error as? MediaPrep.Failure { return failure.description }
            if let failure = error as? TogetherCloudSave.Failure { return failure.description }
            return (error as? URLError) != nil ? T.text(.togetherUnreachable) : "\(error)"
        }
        switch problem.code {
        case "quota_exceeded": return TCloud.text(.quotaFull)
        case "payload_too_large": return TCloud.text(.tooBig)
        case "bad_media", "bad_image": return TCloud.text(.badMedia)
        case "unsupported_media_type": return TCloud.text(.notThisKind)
        case "storage_disabled":
            cloud.info = .disabled
            return TCloud.text(.cloudOff)
        default: return togetherMessage(error)
        }
    }

    // MARK: Settings → Cloud Storage

    func openCloudStorage() {
        guard togetherUser != nil else { return }
        cloud.armed = nil
        cloud.expanded = nil
        open(.cloudStorage)
        panelInRows = true
        loadCloudStorage()
    }

    func loadCloudStorage() {
        cloud.task?.cancel()
        cloud.task = Task {
            do {
                let overview = try await together.storage()
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    cloud.overview = overview
                    cloud.failed = false
                    if !overview.enabled { cloud.info = .disabled }
                }
            } catch is CancellationError {
            } catch {
                withAnimation(Motion.overlay) { cloud.failed = true }
            }
        }
    }

    /// Back to Settings, on the row that opened it.
    func backFromCloudStorage() {
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { overlay = .settings }
        for (index, category) in panelCategories().enumerated() {
            if let row = category.rows.firstIndex(where: { $0.id == "cloudStorage" }) {
                panelCategory = index
                panelRow = row
                panelInRows = true
                return
            }
        }
    }

    /// The usage line under a title: "42 MB of 100 MB used".
    var cloudUsageText: String? {
        guard let usage = cloud.overview?.usage else { return nil }
        return TCloud.format(.storageUsed, TCloud.size(usage.used), TCloud.size(usage.limit))
    }

    func gameTitle(_ slot: TogetherSaveSlot) -> String {
        games.first { $0.titleID == slot.titleId }?.name ?? slot.game ?? slot.titleId
    }

    func cloudStorageRows() -> [PanelRow] {
        guard let overview = cloud.overview else {
            return [PanelRow(id: "cloud-state", title: TCloud.text(cloud.failed ? .storageFailed : .storageLoading), symbol: cloud.failed ? "wifi.exclamationmark" : "icloud", kind: .info(""))]
        }
        guard overview.enabled else { return [PanelRow(id: "cloud-off", title: TCloud.text(.storageOff), symbol: "icloud.slash", kind: .info(""))] }
        var rows: [PanelRow] = [PanelRow(id: "cloud-saves", title: TCloud.text(.storageSaves).uppercased(with: TCloud.locale), kind: .info(""))]
        if overview.saves.isEmpty {
            rows.append(PanelRow(id: "cloud-nosaves", title: TCloud.text(.storageNoSaves), symbol: "gamecontroller", kind: .info("")))
        }
        for slot in overview.saves {
            rows.append(PanelRow(id: "slot-\(slot.id)", title: gameTitle(slot), detail: TCloud.format(.storageGameDetail, slot.versions.count, TCloud.size(slot.size)),
                                 symbol: "gamecontroller.fill", kind: .info("")))
            for (index, version) in slot.versions.enumerated() {
                let open = cloud.expanded == version.id
                let detail = [TCloud.date(version.createdAt), version.device, TCloud.size(version.size)].compactMap { $0 }.joined(separator: " · ")
                rows.append(PanelRow(id: "version-\(version.id)", title: TCloud.format(.storageVersion, version.version) + (index == 0 ? " · " + TCloud.text(.storageNewest) : ""),
                                     detail: detail, symbol: index == 0 ? "clock.badge.checkmark" : "clock.arrow.circlepath", kind: .action(destructive: false) { [weak self] in
                    guard let self else { return }
                    withAnimation(Motion.focus) {
                        self.cloud.expanded = open ? nil : version.id
                        self.cloud.armed = nil
                    }
                }))
                guard open else { continue }
                if index > 0 {
                    rows.append(PanelRow(id: "restore-\(version.id)", title: TCloud.text(.storageRestore), detail: TCloud.text(.storageRestoreDetail), symbol: "arrow.counterclockwise",
                                         kind: .action(destructive: false) { [weak self] in self?.restoreCloudVersion(version, of: slot) }))
                }
                let armed = cloud.armed == "delete-\(version.id)"
                rows.append(PanelRow(id: "delete-\(version.id)", title: TCloud.text(.storageDelete), detail: armed ? TCloud.text(.storagePressAgain) : nil, symbol: "trash",
                                     kind: .action(destructive: true) { [weak self] in
                    guard let self else { return }
                    if armed { self.deleteCloudVersion(version, of: slot) } else { withAnimation(Motion.focus) { self.cloud.armed = "delete-\(version.id)" } }
                }))
            }
            let armed = cloud.armed == "deleteslot-\(slot.id)"
            rows.append(PanelRow(id: "deleteslot-\(slot.id)", title: TCloud.text(.storageDeleteGame), detail: armed ? TCloud.text(.storagePressAgain) : nil, symbol: "trash.slash",
                                 kind: .action(destructive: true) { [weak self] in
                guard let self else { return }
                if armed { self.deleteCloudSlot(slot) } else { withAnimation(Motion.focus) { self.cloud.armed = "deleteslot-\(slot.id)" } }
            }))
        }
        rows.append(PanelRow(id: "cloud-media", title: TCloud.text(.storageMediaTitle).uppercased(with: TCloud.locale), kind: .info("")))
        if overview.media.isEmpty {
            rows.append(PanelRow(id: "cloud-nomedia", title: TCloud.text(.storageNoMedia), symbol: "photo.on.rectangle", kind: .info("")))
        }
        for media in overview.media {
            let armed = cloud.armed == "media-\(media.id)"
            let when = media.createdAt.map(TCloud.date)
            let detail = armed ? TCloud.text(.storagePressAgain) : [when, TCloud.size(media.size), media.gallery != nil ? TCloud.text(.storagePinned) : nil].compactMap { $0 }.joined(separator: " · ")
            let symbol = media.kind == "clip" ? "film" : media.kind == "voice" ? "waveform" : "photo"
            rows.append(PanelRow(id: "media-\(media.id)", title: TCloud.kind(media.kind), detail: detail, symbol: armed ? "trash" : symbol, kind: .action(destructive: armed) { [weak self] in
                guard let self else { return }
                if armed { self.deleteCloudMedia(media) } else { withAnimation(Motion.focus) { self.cloud.armed = "media-\(media.id)" } }
            }))
        }
        return rows
    }

    /// An older version becomes the newest again and comes down to this Mac when it has the game.
    func restoreCloudVersion(_ version: TogetherSaveVersion, of slot: TogetherSaveSlot) {
        guard !cloud.working else { return }
        let game = games.first { $0.titleID == slot.titleId }
        if let game, running?.game.id == game.id || starting?.id == game.id { return show(TCloud.text(.storageRunning), symbol: "exclamationmark.triangle.fill") }
        cloud.working = true
        Task {
            defer { cloud.working = false }
            do {
                let made = try await together.restoreSaveVersion(version.id)
                cloud.expanded = nil
                if let game, slot.slot == TogetherCloudSave.slot, let sync = cloudSave(for: game) {
                    _ = try await sync.takeCloud()
                    show(TCloud.format(.storageRestoredHere, version.version), symbol: "arrow.counterclockwise.icloud")
                } else {
                    show(TCloud.format(.storageRestored, made.version), symbol: "arrow.counterclockwise.icloud")
                }
                loadCloudStorage()
            } catch {
                show(cloudMessage(error), symbol: "exclamationmark.icloud")
            }
        }
    }

    func deleteCloudVersion(_ version: TogetherSaveVersion, of slot: TogetherSaveSlot) {
        Task {
            do {
                try await together.deleteSaveVersion(version.id)
                cloud.armed = nil
                cloud.expanded = nil
                if slot.versions.count == 1 { forgetCloudSave(slot) }
                show(TCloud.text(.storageDeleted), symbol: "trash")
                loadCloudStorage()
            } catch {
                show(cloudMessage(error), symbol: "exclamationmark.icloud")
            }
        }
    }

    func deleteCloudSlot(_ slot: TogetherSaveSlot) {
        Task {
            do {
                try await together.deleteSaveSlot(slot.id)
                cloud.armed = nil
                forgetCloudSave(slot)
                show(TCloud.text(.storageDeleted), symbol: "trash")
                loadCloudStorage()
            } catch {
                show(cloudMessage(error), symbol: "exclamationmark.icloud")
            }
        }
    }

    /// This Mac forgets what it had of a slot that is gone: its saves go up afresh next time.
    private func forgetCloudSave(_ slot: TogetherSaveSlot) {
        guard let user = togetherUser else { return }
        let workspace = TogetherCloudSave.workspace(for: user.id)
        try? FileManager.default.removeItem(at: workspace.appendingPathComponent("\(slot.titleId).json"))
    }

    func deleteCloudMedia(_ media: TogetherMedia) {
        Task {
            do {
                try await together.deleteMedia(media.id)
                cloud.armed = nil
                show(TCloud.text(.storageDeleted), symbol: "trash")
                loadCloudStorage()
            } catch {
                show(cloudMessage(error), symbol: "exclamationmark.icloud")
            }
        }
    }

    // MARK: Settings rows

    /// Save Sync's destination and the storage row, in Settings → Behaviour.
    func saveSyncRows() -> [PanelRow] {
        let through = preferences.syncThrough == Self.syncThroughTogether && cloudAvailable
        var rows: [PanelRow] = [
            PanelRow(id: "saveSync", title: T.text(.saveSync),
                     detail: through ? TCloud.text(.saveSyncTogetherDetail) : syncRoot.map { T.format(.saveSyncDetail, $0.abbreviatedPath) } ?? T.text(.saveSyncNoFolder),
                     symbol: "arrow.triangle.2.circlepath.icloud",
                     kind: .toggle(preferences.saveSync == true && (through || syncRoot != nil)) { [weak self] value in
                         guard let self else { return }
                         if value && !through && self.syncRoot == nil { return self.chooseSyncFolder() }
                         self.preferences.saveSync = value
                     }),
        ]
        if cloudAvailable {
            rows.append(PanelRow(id: "syncThrough", title: TCloud.text(.syncThrough), symbol: "point.3.filled.connected.trianglepath.dotted",
                                 kind: .choice(options: [TCloud.text(.syncThroughFolder), TCloud.text(.syncThroughTogether)], selected: through ? 1 : 0) { [weak self] index in
                self?.preferences.syncThrough = index == 1 ? Self.syncThroughTogether : nil
            }))
        }
        if through {
            rows.append(cloudStorageRow())
        } else {
            rows.append(PanelRow(id: "syncFolder", title: T.text(.syncFolder), detail: preferences.syncFolder.map { URL(fileURLWithPath: $0).abbreviatedPath } ?? T.text(SaveSync.iCloudDrive != nil ? .syncFolderICloud : .syncFolderNone),
                                 symbol: "folder.badge.gearshape", kind: .action(destructive: false) { [weak self] in self?.chooseSyncFolder() }))
        }
        return rows
    }

    func cloudStorageRow() -> PanelRow {
        PanelRow(id: "cloudStorage", title: TCloud.text(.storageTitle), detail: cloudUsageText ?? TCloud.text(.storageSubtitle), symbol: "externaldrive.badge.icloud",
                 kind: .action(destructive: false) { [weak self] in self?.openCloudStorage() })
    }

    func previewCloudStorage(_ overview: TogetherStorageOverview?, row: Int = 1, expanded: String? = nil, armed: String? = nil, failed: Bool = false) {
        cloud.info = TogetherStorageInfo(enabled: true)
        cloud.overview = overview
        cloud.failed = failed
        cloud.expanded = expanded
        cloud.armed = armed
        overlay = .cloudStorage
        panelInRows = true
        panelRow = row
    }
}

/// Settings → Cloud Storage: the quota as a bar (saves, media, free) over the rows.
struct CloudStorageView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let rows = model.panelCategories().first?.rows ?? []
        HStack(spacing: 0) {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.backFromCloudStorage() }
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text(TCloud.text(.storageTitle)).font(.display(30 * scale, .light)).foregroundStyle(.white)
                Text(TCloud.text(.storageSubtitle)).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.6))
                if let usage = model.cloud.overview?.usage {
                    UsageMeter(usage: usage).padding(.top, 18 * scale)
                }
                RowList(rows: rows, focusedRow: model.focusedRow(in: rows))
                    .padding(.top, 14 * scale)
            }
            .padding(36 * scale)
            .frame(width: 600 * scale, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .panelFrost()
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
        }
    }
}

/// How much of the quota saves and media take: one bar in two parts, and the numbers under it.
struct UsageMeter: View {
    let usage: TogetherStorageUsage
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let limit = Double(max(1, usage.limit))
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                Text(TCloud.size(usage.used)).font(.display(34 * scale, .semibold)).monospacedDigit().foregroundStyle(.white)
                Text("/ " + TCloud.size(usage.limit)).font(.display(17 * scale, .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(Int((usage.fraction * 100).rounded()))%").font(.display(15 * scale, .semibold)).monospacedDigit()
                    .foregroundStyle(usage.fraction > 0.9 ? Color(red: 1, green: 0.6, blue: 0.5) : .white.opacity(0.7))
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 2 * scale) {
                    Capsule().fill(model.accent).frame(width: max(usage.saves > 0 ? 4 * scale : 0, width * Double(usage.saves) / limit))
                    Capsule().fill(model.accent.opacity(0.45)).frame(width: max(usage.media > 0 ? 4 * scale : 0, width * Double(usage.media) / limit))
                    Spacer(minLength: 0)
                }
                .frame(width: width, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .frame(height: 10 * scale)
            HStack(spacing: 18 * scale) {
                legend(model.accent, TCloud.text(.storageSaves), usage.saves)
                legend(model.accent.opacity(0.45), TCloud.text(.storageMedia), usage.media)
                legend(Color.white.opacity(0.15), TCloud.text(.storageFree), usage.free)
            }
        }
        .padding(18 * scale)
        .glass(16 * scale, opacity: 0.3)
    }

    private func legend(_ color: Color, _ label: String, _ bytes: Int) -> some View {
        HStack(spacing: 7 * scale) {
            Circle().fill(color).frame(width: 9 * scale, height: 9 * scale)
            Text(label).font(.display(13 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
            Text(TCloud.size(bytes)).font(.display(13 * scale, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
        }
    }
}
