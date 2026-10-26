import AnyPS5Core
import AppKit
import SwiftUI

/// Where the profile screens are: the picker's focus, adding a profile (offline or signing in),
/// and the sign-in that a profile going online waits on.
struct ProfileFlow: Equatable {
    enum Origin: Equatable {
        /// The first start: no profile yet.
        case firstStart
        /// A new profile from the picker, the menus or Settings.
        case adding
        /// The profile playing goes online.
        case goingOnline
        /// A profile picked whose session ended: it signs in again.
        case signingInAgain
    }

    /// The picker's focused tile (the last one is Add Profile).
    var pickerIndex = 0
    /// The picker came up at start: a profile has to be picked.
    var atLaunch = false
    /// Offline (0) or Online (1) on the welcome cards; the name typed for a new profile.
    var modeChoice = 0
    var name = ""
    var origin = Origin.adding
    /// A new online profile's ID while it signs in, and the profile to go back to on Cancel.
    var pendingID: String?
    var returnTo: String?
    /// The profile deleting asks about (Settings → Profiles), focused on Cancel.
    var deleting: String?
}

extension AppModel {
    /// The settings that are each profile's own; the rest (games folder, engine, Steam, the
    /// server…) belong to the Mac.
    static let personalKeys: Set<String> = [
        "language", "theme", "accent", "customTheme", "backdrop", "backdropFile", "gameArtwork", "glassTransparency", "glassArtwork", "reducedMotion",
        "sounds", "soundVolume", "musicVolume", "hideWhilePlaying", "pushToTalk", "friendsJoin", "discordPresence", "discordJoin", "clips", "clipLength",
        "saveSync", "syncFolder", "syncThrough", "profileName", "alwaysShowHiddenTrophies", "controllerVibration", "controllerLight", "confirmCircle",
        "stickDeadzone", "pauseOnMenu", "shortcuts", "lastPlayed",
    ]

    /// The tiles' colours for a profile without a picture.
    static let profilePalette: [Color] = [
        Color(red: 0.36, green: 0.42, blue: 0.98), Color(red: 0.12, green: 0.72, blue: 0.68), Color(red: 0.98, green: 0.45, blue: 0.36),
        Color(red: 0.96, green: 0.70, blue: 0.20), Color(red: 0.66, green: 0.40, blue: 0.95), Color(red: 0.30, green: 0.80, blue: 0.45),
        Color(red: 0.93, green: 0.36, blue: 0.62), Color(red: 0.25, green: 0.62, blue: 0.95),
    ]

    static func profileColor(_ profile: LauncherProfile) -> Color { profilePalette[profile.avatar.color % profilePalette.count] }

    var currentProfile: LauncherProfile? { profileBook.currentProfile }

    /// The profile whose session the client uses: the one signing in, else the one playing.
    var sessionProfileID: String { profileFlow.pendingID ?? profiles.book.currentProfile?.id ?? LauncherProfile.legacyID }

    /// The first profile's session stays in the old file only where the Keychain said no.
    func sessionStore(for id: String) -> TokenStore {
        guard persists else { return ProfileSessions.store(for: id, in: vault) }
        if id == profiles.book.legacyOwner, FileManager.default.fileExists(atPath: TokenStore.legacyFile.path) { return TokenStore(file: TokenStore.legacyFile) }
        return ProfileSessions.store(for: id, in: vault)
    }

    /// Save Sync's folder of a profile after the first.
    var saveSyncProfile: String? {
        guard let id = currentProfile?.id, id != profiles.book.legacyOwner else { return nil }
        return id
    }

    func profilesChanged() { profileBook = profiles.book }

    /// Every profile's tokens, for a crash report to take out.
    var allSecrets: [String] {
        ProfileSessions.secrets(in: vault, accounts: profiles.book.profiles.map { ProfileSessions.account(for: $0.id) }) + together.secrets
    }

    // MARK: Saves

    /// The profile playing has its saves in the game's folder.
    func activateProfileSaves(_ game: Game) {
        guard persists, let profile = currentProfile, let owner = profiles.book.legacyOwner, let folder = gameFolder(game) else { return }
        do {
            try ProfileSaves.activate(profile.id, in: folder, legacyOwner: owner)
        } catch {
            show(TPro.format(.savesNotSwapped, game.name), symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Switching

    /// Why the switch cannot happen now, told; nil when it can.
    func switchRefusal(to id: String) -> ProfileSwitch.Refusal? {
        ProfileSwitch.check(to: id, in: profiles.book, running: running?.game.name, starting: starting?.name, syncing: syncing != nil)
    }

    func tell(_ refusal: ProfileSwitch.Refusal) {
        switch refusal {
        case .gameRunning(let game):
            Sounds.shared.play(.bump)
            show(TPro.format(.closeGameFirst, game), symbol: "exclamationmark.triangle.fill")
        case .syncing:
            Sounds.shared.play(.bump)
            show(TPro.text(.waitForSync), symbol: "arrow.triangle.2.circlepath")
        case .alreadyCurrent, .unknown:
            break
        }
    }

    /// Plays as `id` from now on: the account, settings, picture, saves and trophies are theirs.
    func switchProfile(to id: String) {
        if let refusal = switchRefusal(to: id) {
            if refusal == .alreadyCurrent { return enterCurrentProfile() }
            return tell(refusal)
        }
        guard let next = profiles.profile(id) else { return }
        keepPersonalSettings()
        disconnectTogether()
        profiles.select(id)
        profilesChanged()
        useProfile(next)
        withAnimation(Motion.overlay) { overlay = nil }
        Sounds.shared.play(.select)
        show(TPro.format(.welcomeBack, next.name), symbol: "person.crop.circle.badge.checkmark")
        if next.mode == .online && togetherUser == nil {
            // Its session ended (signed out elsewhere, or for too long): it signs in again.
            beginSignIn(.signingInAgain)
        }
    }

    /// The picker's choice was the profile already in use: in it goes.
    func enterCurrentProfile() {
        withAnimation(Motion.overlay) { overlay = nil }
        Sounds.shared.play(.select)
        profileFlow.atLaunch = false
        if let profile = currentProfile, profile.mode == .online {
            if togetherUser == nil { togetherUser = together.user }
            if togetherUser != nil { startTogetherSocket() } else { beginSignIn(.signingInAgain) }
        }
    }

    /// The profile playing's settings go back into its record before another's come.
    func keepPersonalSettings() {
        guard let current = currentProfile, let data = try? JSONEncoder().encode(preferences) else { return }
        profiles.setSettings(current.id, ProfileSettings.pick(Self.personalKeys, from: data))
    }

    /// Settings, client, picture and saves of `profile`, the one now in the book as current.
    private func useProfile(_ profile: LauncherProfile) {
        applyProfileSettings(profile)
        profileFlow.atLaunch = false
        together = wireTogether(AppModel.makeTogetherClient(base: together.base, store: sessionStore(for: profile.id)))
        togetherSync = TogetherSync(client: together, deviceName: Host.current().localizedName ?? "Mac", model: AppModel.machineModel)
        social = SocialState(owner: self)
        cloud.info = nil
        cloud.overview = nil
        if persists { ProfilePicture.file = profiles.pictureFile(for: profile.id) }
        loadProfilePicture()
        togetherUser = profile.mode == .online ? together.user : nil
        if togetherUser != nil { startTogetherSocket() }
        // The profile's saves and trophies in every game's folder, and its trophies shown.
        if persists, let owner = profiles.book.legacyOwner {
            for game in games {
                guard let folder = gameFolder(game) else { continue }
                try? ProfileSaves.activate(profile.id, in: folder, legacyOwner: owner)
            }
        }
        forgetTrophies()
        if let game = selectedGame { loadTrophies(game) }
        if togetherUser != nil { for game in games { loadTrophies(game, again: true) } }
        objectWillChange.send()
    }

    // MARK: Online and offline

    /// The profile playing goes offline (its session kept, unused) or online (signing in when
    /// it has no session): never while a game plays.
    func toggleProfileMode() {
        guard let profile = currentProfile else { return }
        if let refusal = ProfileSwitch.checkModeChange(running: running?.game.name, starting: starting?.name) { return tell(refusal) }
        withAnimation(Motion.overlay) { overlay = nil }
        if profile.mode == .online {
            disconnectTogether()
            profiles.setMode(profile.id, .offline)
            profilesChanged()
            Sounds.shared.play(.select)
            show(TPro.text(.nowOffline), symbol: "wifi.slash")
        } else if let user = together.user {
            profiles.setMode(profile.id, .online)
            profilesChanged()
            signedIn(user)
        } else {
            beginSignIn(.goingOnline)
        }
    }

    // MARK: Signing in

    /// The sign-in screen for `origin`: the same email code, website code and phone hand-off as
    /// Settings → AnyTogether.
    func beginSignIn(_ origin: ProfileFlow.Origin) {
        profileFlow.origin = origin
        togetherStep = .idle
        panelRow = 0
        panelCategory = 0
        panelInRows = true
        panelFocusID = nil
        withAnimation(Motion.overlay) { overlay = .signIn }
    }

    /// A new profile that signs in: its own session from the start, the profile playing kept
    /// for Cancel.
    func beginOnlineProfile() {
        if let refusal = ProfileSwitch.checkModeChange(running: running?.game.name, starting: starting?.name) { return tell(refusal) }
        let first = profiles.book.profiles.isEmpty
        if !first {
            keepPersonalSettings()
            disconnectTogether()
            profileFlow.returnTo = currentProfile?.id
        }
        let id = first ? LauncherProfile.legacyID : UUID().uuidString.lowercased()
        profileFlow.pendingID = id
        together = wireTogether(AppModel.makeTogetherClient(base: together.base, store: sessionStore(for: id)))
        togetherSync = TogetherSync(client: together, deviceName: Host.current().localizedName ?? "Mac", model: AppModel.machineModel)
        togetherUser = nil
        beginSignIn(first ? .firstStart : .adding)
    }

    /// Signed in: the waiting profile is made (or the one playing is online now).
    func profileSignedIn(_ user: TogetherUser) {
        let account = LauncherProfile.Account(userId: user.id, handle: user.handle)
        if let pending = profileFlow.pendingID {
            let profile = profiles.add(name: user.displayName, mode: .online, account: account, id: pending)
            profileFlow.pendingID = nil
            profileFlow.returnTo = nil
            let first = profileFlow.origin == .firstStart
            profiles.select(profile.id)
            profilesChanged()
            if first {
                withAnimation(Motion.overlay) { overlay = nil }
                preferences.profileName = profile.name
                finishOnboarding()
            } else {
                // The new profile's own settings from the defaults, its saves its own.
                applyNewProfile(profile)
            }
            return
        }
        guard let current = currentProfile else { return }
        profiles.setMode(current.id, .online)
        profiles.setAccount(current.id, account)
        profilesChanged()
        if overlay == .signIn { withAnimation(Motion.overlay) { overlay = nil } }
    }

    /// The profile's own settings in place of the ones playing; a profile without any yet starts
    /// from the defaults, in the language in use, with its own name.
    func applyProfileSettings(_ profile: LauncherProfile) {
        guard let data = try? JSONEncoder().encode(preferences), let defaults = try? JSONEncoder().encode(Preferences()) else { return }
        var values = ProfileSettings.pick(Self.personalKeys, from: defaults)
        if let own = profile.settings {
            values.merge(own) { _, own in own }
        } else {
            values["language"] = .string(preferences.language.rawValue)
        }
        values["profileName"] = .string(profile.name)
        guard let merged = try? JSONDecoder().decode(Preferences.self, from: ProfileSettings.merge(values, keys: Self.personalKeys, into: data)) else { return }
        preferences = merged
    }

    /// The settings, picture and saves of a profile just made, without signing in again.
    private func applyNewProfile(_ profile: LauncherProfile) {
        withAnimation(Motion.overlay) { overlay = nil }
        applyProfileSettings(profile)
        if persists { ProfilePicture.file = profiles.pictureFile(for: profile.id) }
        loadProfilePicture()
        if persists, let owner = profiles.book.legacyOwner {
            for game in games {
                guard let folder = gameFolder(game) else { continue }
                try? ProfileSaves.activate(profile.id, in: folder, legacyOwner: owner)
            }
        }
        forgetTrophies()
        if let game = selectedGame { loadTrophies(game) }
    }

    /// Back on the sign-in: a profile that was waiting is not made, and the one before plays on.
    func cancelSignIn() {
        togetherCancel()
        Sounds.shared.play(.back)
        if let pending = profileFlow.pendingID {
            vault.write(nil, for: ProfileSessions.account(for: pending))
            profileFlow.pendingID = nil
            let back = profileFlow.returnTo.flatMap(profiles.profile)
            profileFlow.returnTo = nil
            together = wireTogether(AppModel.makeTogetherClient(base: together.base, store: sessionStore(for: sessionProfileID)))
            togetherSync = TogetherSync(client: together, deviceName: Host.current().localizedName ?? "Mac", model: AppModel.machineModel)
            if let back, back.mode == .online {
                togetherUser = together.user
                if togetherUser != nil { startTogetherSocket() }
            }
        }
        withAnimation(Motion.overlay) { overlay = profileFlow.origin == .adding ? .addProfile : nil }
    }

    // MARK: Adding

    func openAddProfile() {
        if let refusal = ProfileSwitch.checkModeChange(running: running?.game.name, starting: starting?.name) { return tell(refusal) }
        profileFlow.modeChoice = 0
        profileFlow.name = TPro.format(.playerNumber, profiles.book.profiles.count + 1)
        profileFlow.origin = .adding
        menuIndex = 0
        withAnimation(Motion.overlay) { overlay = .addProfile }
        Sounds.shared.play(.select)
    }

    /// Offline: made at once with the name typed, and it plays.
    func createOfflineProfile() {
        let first = profiles.book.profiles.isEmpty
        let name = first ? preferences.profileName : profileFlow.name
        if first {
            _ = profiles.add(name: name, mode: .offline)
            profilesChanged()
            return finishOnboarding()
        }
        if let refusal = ProfileSwitch.checkModeChange(running: running?.game.name, starting: starting?.name) { return tell(refusal) }
        let profile = profiles.add(name: name, mode: .offline)
        profilesChanged()
        switchProfile(to: profile.id)
    }

    /// ✕ on a welcome card.
    func confirmModeChoice() {
        // A first start cut short after its profile was made: in it goes.
        if !preferences.onboarded && !profiles.book.profiles.isEmpty { return finishOnboarding() }
        if profileFlow.modeChoice == 0 { createOfflineProfile() } else { beginOnlineProfile() }
    }

    /// The add-profile screen and the first start's last step: left and right pick the card.
    func modeChoiceCommand(_ command: Command) -> Bool {
        switch command {
        case .left, .right:
            let next = command == .left ? 0 : 1
            guard next != profileFlow.modeChoice else { Sounds.shared.play(.bump); return true }
            withAnimation(Motion.focus) { profileFlow.modeChoice = next }
            Sounds.shared.play(.move)
        case .select:
            Sounds.shared.play(.select)
            confirmModeChoice()
        case .back:
            if overlay == .addProfile {
                withAnimation(Motion.overlay) { overlay = profileFlow.atLaunch ? .profilePicker : nil }
                Sounds.shared.play(.back)
            } else {
                onboardingBack()
            }
        default:
            break
        }
        return true
    }

    // MARK: The picker

    func openProfilePicker(atLaunch: Bool = false) {
        if !atLaunch, let refusal = ProfileSwitch.checkModeChange(running: running?.game.name, starting: starting?.name) { return tell(refusal) }
        profileFlow.atLaunch = atLaunch
        profileFlow.pickerIndex = 0
        menuIndex = 0
        withAnimation(Motion.overlay) { overlay = .profilePicker }
        if !atLaunch { Sounds.shared.play(.select) }
    }

    func pickerCommand(_ command: Command) -> Bool {
        let tiles = profileBook.pickerOrder
        let count = tiles.count + 1
        switch command {
        case .left, .right:
            let next = min(count - 1, max(0, profileFlow.pickerIndex + (command == .left ? -1 : 1)))
            guard next != profileFlow.pickerIndex else { Sounds.shared.play(.bump); return true }
            withAnimation(Motion.focus) { profileFlow.pickerIndex = next }
            Sounds.shared.play(.move)
        case .select:
            if profileFlow.pickerIndex < tiles.count {
                switchProfile(to: tiles[profileFlow.pickerIndex].id)
            } else {
                openAddProfile()
            }
        case .back:
            // At start a profile has to be picked.
            if profileFlow.atLaunch { Sounds.shared.play(.bump) } else { closeOverlay() }
        case .options:
            if !profileFlow.atLaunch { openProfileSettings() }
        default:
            break
        }
        return true
    }

    // MARK: Options and the right click on Home

    struct ProfileMenuItem: Identifiable {
        enum Action { case gameSettings, switchProfile, toggleMode, profiles }
        let id: Int
        let action: Action
        let title: String
        var detail: String?
        let symbol: String
    }

    func profileMenuItems() -> [ProfileMenuItem] {
        var items: [ProfileMenuItem] = []
        if let game = selectedGame { items.append(ProfileMenuItem(id: 0, action: .gameSettings, title: T.text(.gameSettings), detail: game.name, symbol: "slider.horizontal.3")) }
        let others = profileBook.profiles.count - 1
        items.append(ProfileMenuItem(id: items.count, action: .switchProfile, title: TH.text(.switchProfile),
                                     detail: others > 0 ? TPro.format(.otherProfiles, others) : TPro.text(.addSomeone), symbol: "person.2.circle"))
        let online = currentProfile?.mode == .online
        items.append(ProfileMenuItem(id: items.count, action: .toggleMode, title: TPro.text(online ? .goOffline : .goOnline),
                                     detail: TPro.text(online ? .goOfflineDetail : .goOnlineDetail), symbol: online ? "wifi.slash" : "wifi"))
        items.append(ProfileMenuItem(id: items.count, action: .profiles, title: TPro.text(.manageProfiles), symbol: "person.crop.rectangle.stack"))
        return items
    }

    func openProfileMenu() {
        guard preferences.onboarded, overlay == nil, starting == nil, pairing == nil else { return }
        menuIndex = 0
        withAnimation(Motion.overlay) { overlay = .profileMenu }
        Sounds.shared.play(.select)
    }

    func runProfileMenu(_ action: ProfileMenuItem.Action) {
        switch action {
        case .gameSettings:
            open(.gameSettings)
        case .switchProfile:
            if profileBook.profiles.count > 1 { openProfilePicker() } else { openAddProfile() }
        case .toggleMode:
            toggleProfileMode()
        case .profiles:
            openProfileSettings()
        }
    }

    /// The right click on Home: the Options menu.
    func homeRightClick() -> Bool {
        guard preferences.onboarded, overlay == nil, starting == nil, pairing == nil, NSApp.isActive else { return false }
        openProfileMenu()
        return true
    }

    func openProfileSettings() {
        open(.settings)
        panelCategory = panelCategories().firstIndex { $0.id == "profiles" } ?? 0
        panelInRows = false
    }

    // MARK: Settings → Profiles

    func profileRows() -> [PanelRow] {
        guard let profile = currentProfile else { return [] }
        let online = profile.mode == .online
        var rows: [PanelRow] = [
            PanelRow(id: "profile-current", title: profile.name,
                     detail: online ? (togetherUser.map { TPro.format(.onlineAs, $0.handle) } ?? TPro.text(.onlineSignedOut)) : TPro.text(.offlineDetail),
                     symbol: "person.crop.circle", kind: .info(""), person: PanelPerson(name: profile.name, avatar: togetherUser?.avatar, picture: profilePicture), wraps: true),
            PanelRow(id: "name", title: T.text(.profileName), symbol: "character.cursor.ibeam", kind: .text(profile.name) { [weak self] value in self?.renameCurrentProfile(value) }),
        ] + profilePictureRows()
        rows.append(PanelRow(id: "profile-color", title: TPro.text(.tileColour), detail: TPro.text(.tileColourDetail), symbol: "paintpalette",
                             kind: .choice(options: TPro.colourNames, selected: profile.avatar.color % TPro.colourNames.count) { [weak self] index in
                                 self?.profiles.setColor(profile.id, index)
                                 self?.profilesChanged()
                             }))
        rows.append(PanelRow(id: "profile-mode", title: TPro.text(online ? .goOffline : .goOnline), detail: TPro.text(online ? .goOfflineDetail : .goOnlineDetail),
                             symbol: online ? "wifi.slash" : "wifi", kind: .action(destructive: false) { [weak self] in self?.toggleProfileMode() }))
        rows.append(PanelRow(id: "profile-ask", title: TPro.text(.askEveryTime), detail: TPro.text(.askEveryTimeDetail), symbol: "person.2.crop.square.stack",
                             kind: .toggle(profileBook.askEveryTime) { [weak self] value in
                                 self?.profiles.setAskEveryTime(value)
                                 self?.profilesChanged()
                             }))
        let others = profileBook.profiles.filter { $0.id != profile.id }
        if !others.isEmpty {
            rows.append(PanelRow(id: "profiles-others", title: TPro.text(.otherProfilesTitle), symbol: "person.2", kind: .info("")))
        }
        for other in others {
            let detail = other.mode == .online ? other.account.map { "@\($0.handle)" } ?? TPro.text(.online) : TPro.text(.offline)
            rows.append(PanelRow(id: "profile-switch-\(other.id)", title: TPro.format(.switchTo, other.name), detail: detail, symbol: "arrow.left.arrow.right",
                                 kind: .action(destructive: false) { [weak self] in self?.switchProfile(to: other.id) },
                                 person: PanelPerson(name: other.name, avatar: nil, picture: NSImage(contentsOf: profiles.pictureFile(for: other.id)))))
            rows += askingFirst(PanelRow(id: "profile-delete-\(other.id)", title: TPro.format(.deleteProfile, other.name), symbol: "trash",
                                         kind: .action(destructive: true) { [weak self] in self?.deleteProfile(other.id) }),
                                question: TPro.format(.deleteQuestion, other.name))
        }
        rows.append(PanelRow(id: "profile-add", title: TPro.text(.addProfile), detail: TPro.text(.addProfileDetail), symbol: "person.badge.plus",
                             kind: .action(destructive: false) { [weak self] in self?.openAddProfile() }))
        return rows
    }

    func renameCurrentProfile(_ name: String) {
        guard let profile = currentProfile else { return }
        profiles.rename(profile.id, to: name)
        profilesChanged()
        if preferences.profileName != name { preferences.profileName = name }
    }

    /// The profile goes: its saves and trophies on this Mac are backed up, then removed; its
    /// session ends on the server too.
    func deleteProfile(_ id: String) {
        guard let profile = profiles.profile(id) else { return }
        if let refusal = ProfileSwitch.checkModeChange(running: running?.game.name, starting: starting?.name) { return tell(refusal) }
        if persists, let owner = profiles.book.legacyOwner {
            for game in games {
                guard let folder = gameFolder(game) else { continue }
                let parked = ProfileSaves.parked(id, in: folder)
                let place = ProfileSaves.owner(of: folder, legacyOwner: owner) == id ? folder : parked
                let backups = SaveBackup.folder(for: game).appendingPathComponent(TPro.format(.backupFolder, profile.name))
                _ = try? SaveBackup.backUp(place, to: backups, date: Date())
                try? ProfileSaves.remove(id, in: folder, legacyOwner: owner)
            }
        }
        // Its session ends on the server too; the item goes once the server heard it.
        let client = AppModel.makeTogetherClient(base: together.base, store: sessionStore(for: id))
        if client.user != nil {
            let vault = self.vault
            Task {
                await client.signOut()
                vault.write(nil, for: ProfileSessions.account(for: id))
            }
        } else {
            vault.write(nil, for: ProfileSessions.account(for: id))
        }
        do {
            try profiles.remove(id)
        } catch {
            return show(TPro.text(.cannotDelete), symbol: "exclamationmark.triangle.fill")
        }
        profilesChanged()
        show(TPro.format(.deleted, profile.name), symbol: "trash")
    }

    // MARK: The friends-only name and picture

    /// Someone as the launcher shows them: their friends-only name and picture when they let
    /// this user see them, the handle beside.
    func shown(_ card: TogetherIdentityCard) -> TogetherIdentity {
        TogetherIdentity.shown(card, book: identityBook)
    }

    func panelPerson(_ card: TogetherIdentityCard, status: PanelPerson.Status? = nil, level: TogetherLevelBadge? = nil, speaking: Bool = false) -> PanelPerson {
        let identity = shown(card)
        return PanelPerson(name: identity.name, avatar: identity.avatar, status: status, speaking: speaking, level: level)
    }

    /// "@handle", with the public name too when a private one is shown.
    func handleLine(_ card: TogetherIdentityCard) -> String {
        let identity = shown(card)
        return identity.isPrivate && identity.publicName != identity.name ? "@\(identity.handle) · \(identity.publicName)" : "@\(identity.handle)"
    }

    func privateIdentityRows() -> [PanelRow] {
        guard togetherUser != nil, let own = togetherProfile else { return [] }
        let draft = privateNameDraft ?? own.privateName ?? ""
        var rows = [
            PanelRow(id: "private-title", title: TPro.text(.friendsOnlyTitle), detail: TPro.text(.friendsOnlyDetail), symbol: "lock.shield", kind: .info(""), wraps: true),
            PanelRow(id: "private-name-\(own.privateName ?? "")", title: TPro.text(.friendsOnlyName), detail: TPro.text(.friendsOnlyNameDetail), symbol: "person.text.rectangle",
                     kind: .text(draft) { [weak self] text in self?.privateNameDraft = text }),
            PanelRow(id: "private-name-save", title: TPro.text(draft.trimmingCharacters(in: .whitespaces).isEmpty && own.privateName != nil ? .friendsOnlyNameClear : .friendsOnlyNameSave),
                     symbol: "checkmark.circle", kind: .action(destructive: false) { [weak self] in self?.savePrivateName() }),
        ]
        if profilePicture != nil {
            rows.append(PanelRow(id: "private-picture-upload", title: TPro.text(.friendsOnlyPicture), detail: pictureBusy ? T.text(.profileLoading) : TPro.text(.friendsOnlyPictureDetail),
                                 symbol: "person.crop.square.badge.lock", kind: .action(destructive: false) { [weak self] in self?.uploadPrivatePicture() },
                                 person: own.privateAvatar.map { PanelPerson(name: own.privateName ?? own.displayName, avatar: $0) }))
        }
        if own.privateAvatar != nil {
            rows.append(PanelRow(id: "private-picture-remove", title: TPro.text(.friendsOnlyPictureRemove), symbol: "xmark.circle",
                                 kind: .action(destructive: true) { [weak self] in self?.removePrivatePicture() }))
        }
        return rows
    }

    func savePrivateName() {
        let text = (privateNameDraft ?? togetherProfile?.privateName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let saved = try await together.setPrivateName(text)
                togetherProfile = saved
                privateNameDraft = nil
                show(TPro.text(saved.privateName == nil ? .friendsOnlyNameCleared : .friendsOnlyNameSaved), symbol: "lock.shield.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The profile picture as the friends-only one (the public picture stays).
    func uploadPrivatePicture() {
        guard togetherUser != nil, !pictureBusy, let data = try? Data(contentsOf: ProfilePicture.file) else { return }
        if ProfilePicture.uploadProblem(data) != nil { return show(T.text(.profilePictureUploadFailed), symbol: "exclamationmark.triangle.fill") }
        pictureBusy = true
        Task { @MainActor in
            defer { self.pictureBusy = false }
            do {
                let link = try await self.together.uploadPrivateAvatar(data)
                self.togetherProfile?.privateAvatar = link
                self.show(TPro.text(.friendsOnlyPictureSaved), symbol: "lock.shield.fill")
            } catch {
                self.show(T.text(.profilePictureUploadFailed) + ": " + self.togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func removePrivatePicture() {
        Task {
            do {
                try await together.removePrivateAvatar()
                togetherProfile?.privateAvatar = nil
                show(TPro.text(.friendsOnlyPictureRemoved), symbol: "lock.open")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}

extension AppModel {
    /// The sign-in screen's rows: the ways in, without the account rows (nobody is signed in).
    func signInRows() -> [PanelRow] {
        togetherRows().filter { !$0.id.hasPrefix("together-server") && $0.id != "together-intro" }
    }

    /// ○ backs out of the sign-in (a question asked in place answers Cancel first); ← stays.
    func signInCommand(_ command: Command) -> Bool {
        switch command {
        case .back:
            if !cancelAsk() { cancelSignIn() }
            return true
        case .left:
            return true
        default:
            return panelCommand(command)
        }
    }
}
