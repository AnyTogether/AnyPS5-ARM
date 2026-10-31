import AnyPS5Core
import AppKit
import SwiftUI

/// AnyTogether in the launcher's settings: signing in with an email code or with a code approved
/// on the website, who is signed in, signing out; and the socket that keeps the session live.
extension AppModel {
    enum TogetherStep: Equatable {
        case idle
        case busy
        case codeSent(email: String)
        case deviceCode(code: String, url: URL)
        /// Waiting for the paired phone, signed in to AnyTogether, to approve this launcher.
        case phone(name: String, handoff: String)
    }

    static func makeTogetherClient(base: URL, store: TokenStore) -> TogetherClient {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return TogetherClient(base: base, store: store, clientName: "launcher-macos/\(runningVersion) (macOS \(os.majorVersion).\(os.minorVersion))")
    }

    // MARK: Server

    /// The server row: which AnyTogether this launcher uses. ANYTOGETHER_URL, when set, decides.
    func serverRows() -> [PanelRow] {
        if let forced = ProcessInfo.processInfo.environment["ANYTOGETHER_URL"] {
            return [PanelRow(id: "together-server", title: T.text(.togetherServer), detail: T.text(.togetherServerForced), symbol: "server.rack", kind: .info(forced))]
        }
        let current = together.base.absoluteString
        return [
            PanelRow(id: "together-server-\(current)", title: T.text(.togetherServer), detail: T.text(.togetherServerDetail), symbol: "server.rack",
                     kind: .text(current) { [weak self] text in self?.serverDraft = text }),
            PanelRow(id: "together-server-use", title: T.text(.togetherServerUse), symbol: "arrow.right.circle", kind: .action(destructive: false) { [weak self] in
                self?.useServer(self?.serverDraft ?? "")
            }),
        ]
    }

    /// Another server: a session belongs to one server, so this one is signed out first.
    func useServer(_ text: String) {
        guard ProcessInfo.processInfo.environment["ANYTOGETHER_URL"] == nil else { return }
        guard let url = TogetherServer.address(text.isEmpty ? together.base.absoluteString : text) else {
            return show(T.text(.togetherServerInvalid), symbol: "exclamationmark.triangle.fill")
        }
        guard url != together.base else { return }
        togetherCancel()
        let switchOver = { [weak self] in
            guard let self else { return }
            self.preferences.togetherServer = url == TogetherServer.standard ? nil : url.absoluteString
            self.together = self.wireTogether(AppModel.makeTogetherClient(base: url, store: self.sessionStore(for: self.sessionProfileID)))
            self.remote?.togetherServer = url.absoluteString
            self.togetherSync = TogetherSync(client: self.together, deviceName: Host.current().localizedName ?? "Mac", model: AppModel.machineModel)
            self.serverDraft = ""
            self.cloud.info = nil
            self.cloud.overview = nil
            self.refreshStorageInfo()
            self.show(T.format(.togetherServerNow, url.host() ?? url.absoluteString), symbol: "server.rack")
        }
        if togetherUser != nil { togetherSignOut(then: switchOver) } else { switchOver() }
    }

    // MARK: Rows

    func togetherRows() -> [PanelRow] {
        // An offline profile that had an account (it went offline, its session kept): going online
        // is the way in. One that never had one signs in here as ever, and is online then.
        if togetherUser == nil, let profile = currentProfile, profile.mode == .offline, profile.account != nil, profileFlow.pendingID == nil, overlay != .signIn {
            return [
                PanelRow(id: "together-offline", title: TPro.text(.offlineTogether), detail: TPro.text(.offlineTogetherDetail), symbol: "wifi.slash", kind: .info(""), wraps: true),
                PanelRow(id: "together-go-online", title: TPro.text(.goOnline), detail: TPro.text(.goOnlineDetail), symbol: "wifi",
                         kind: .action(destructive: false) { [weak self] in self?.toggleProfileMode() }),
            ] + familyRows()
        }
        if let user = togetherUser {
            var rows = [
                PanelRow(id: "together-user", title: "@\(user.handle)", detail: appearingOffline ? user.displayName + " · " + TL.text(.appearingOffline) : user.displayName,
                         symbol: "person.crop.circle.badge.checkmark", kind: .info(""),
                         person: PanelPerson(name: user.displayName, avatar: user.avatar, level: togetherProfile?.trophyLevel?.badge, appearingOffline: appearingOffline)),
                PanelRow(id: "together-profile", title: T.text(.profileMine), detail: T.text(.profileMineDetail), symbol: "person.text.rectangle", kind: .action(destructive: false) { [weak self] in
                    self?.openMyProfile()
                }),
                PanelRow(id: "together-online", title: T.text(.togetherOnline), detail: togetherConnected ? T.text(.togetherConnected) : T.text(.togetherConnecting),
                         symbol: togetherConnected ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark", kind: .info("")),
            ] + presenceRows() + familyRows()
            if cloudAvailable { rows.append(cloudStorageRow()) }
            rows.append(PanelRow(id: "together-join", title: T.text(.togetherFriendsJoin), detail: T.text(.togetherFriendsJoinDetail), symbol: "person.2.wave.2",
                                 kind: .toggle(preferences.friendsJoin ?? true) { [weak self] value in self?.friendsJoinChanged(value) }))
            rows.append(PanelRow(id: "together-online-play", title: T.text(.togetherOnlinePlay), detail: T.format(.togetherOnlinePlayDetail, user.handle), symbol: "network",
                                 kind: .toggle(OnlinePlayHost.enabled) { [weak self] value in
                                     OnlinePlayHost.enabled = value
                                     self?.objectWillChange.send()
                                 }))
            rows += profileEditRows() + privateIdentityRows() + privacyRows() + (familyAllows(.discovery) ? discoveryRows() : []) + serverRows()
            rows.append(PanelRow(id: "together-signout", title: T.text(.togetherSignOut), symbol: "rectangle.portrait.and.arrow.right", kind: .action(destructive: true) { [weak self] in
                self?.togetherSignOut()
            }))
            return rows
        }
        var rows = [PanelRow(id: "together-intro", title: T.text(.togetherIntro), detail: T.text(.togetherIntroDetail), symbol: "person.2.circle", kind: .info(""))] + familyRows()
        switch togetherStep {
        case .idle, .busy:
            if let phone = connectedPhoneName {
                rows.append(PanelRow(id: "together-phone", title: T.text(.togetherWithPhone), detail: T.format(.togetherWithPhoneDetail, phone), symbol: "iphone.radiowaves.left.and.right",
                                     kind: .action(destructive: false) { [weak self] in self?.togetherWithPhone() }))
            }
            rows += [
                PanelRow(id: "together-email", title: T.text(.togetherEmail), symbol: "envelope", kind: .text(togetherEmail) { [weak self] text in self?.togetherEmail = text }),
                PanelRow(id: "together-send", title: T.text(.togetherSendCode), symbol: "paperplane", kind: .action(destructive: false) { [weak self] in self?.togetherSendCode() }),
                PanelRow(id: "together-web", title: T.text(.togetherWithWebsite), detail: T.text(.togetherWithWebsiteDetail), symbol: "safari", kind: .action(destructive: false) { [weak self] in
                    self?.togetherStartDeviceCode()
                }),
            ]
        case .codeSent(let email):
            rows += [
                PanelRow(id: "together-sent", title: T.format(.togetherCodeSent, email), symbol: "envelope.badge", kind: .info("")),
                PanelRow(id: "together-code", title: T.text(.togetherCode), symbol: "number", kind: .text(togetherCode) { [weak self] text in
                    self?.togetherCode = text
                    if text.filter(\.isNumber).count == 6 { self?.togetherVerify() }
                }),
                PanelRow(id: "together-verify", title: T.text(.togetherSignIn), symbol: "checkmark.circle", kind: .action(destructive: false) { [weak self] in self?.togetherVerify() }),
                PanelRow(id: "together-other", title: T.text(.togetherOtherEmail), symbol: "arrow.uturn.backward", kind: .action(destructive: false) { [weak self] in
                    self?.togetherStep = .idle
                    self?.togetherCode = ""
                }),
            ]
        case .deviceCode(let code, let url):
            rows += [
                PanelRow(id: "together-device", title: code, detail: T.format(.togetherTypeCode, url.host() ?? ""), symbol: "qrcode", kind: .info("")),
                PanelRow(id: "together-open", title: T.text(.togetherOpenWebsite), symbol: "safari", kind: .action(destructive: false) {
                    NSWorkspace.shared.open(url)
                }),
                PanelRow(id: "together-cancel", title: T.text(.cancel), symbol: "xmark", kind: .action(destructive: false) { [weak self] in self?.togetherCancel() }),
            ]
        case .phone(let name, _):
            rows += [
                PanelRow(id: "together-onphone", title: T.format(.togetherOnPhone, name), symbol: "iphone.radiowaves.left.and.right", kind: .info("")),
                PanelRow(id: "together-cancel", title: T.text(.cancel), symbol: "xmark", kind: .action(destructive: false) { [weak self] in self?.togetherCancel() }),
            ]
        }
        if togetherStep == .idle { rows += serverRows() }
        return rows
    }

    // MARK: Profile and privacy

    /// Name, bio, country and handle as typed, until saved. `loads` renews the text fields when
    /// the profile comes back from the server.
    struct ProfileDraft {
        var name = ""
        var bio = ""
        var country = ""
        var handle = ""
        var loads = 0
    }

    private func profileEditRows() -> [PanelRow] {
        guard let profile = togetherProfile else { return [] }
        let version = profileDraft.loads
        let handleDetail = profile.handleChangeAt.map { T.format(.togetherHandleAgain, ProfileView.day($0)) } ?? T.text(.togetherHandleDetail)
        return [
            PanelRow(id: "together-edit", title: T.text(.togetherEditProfile), symbol: "pencil", kind: .info("")),
            PanelRow(id: "together-name-\(version)", title: T.text(.togetherName), symbol: "textformat", kind: .text(profileDraft.name) { [weak self] text in self?.profileDraft.name = text }),
            PanelRow(id: "together-bio-\(version)", title: T.text(.togetherBio), symbol: "text.quote", kind: .text(profileDraft.bio) { [weak self] text in self?.profileDraft.bio = text }),
            PanelRow(id: "together-country-\(version)", title: T.text(.togetherCountry), detail: T.text(.togetherCountryDetail), symbol: "flag",
                     kind: .text(profileDraft.country) { [weak self] text in self?.profileDraft.country = text }),
            PanelRow(id: "together-save", title: T.text(.togetherSaveProfile), symbol: "checkmark.circle", kind: .action(destructive: false) { [weak self] in self?.saveTogetherProfile() }),
            PanelRow(id: "together-handle-\(version)", title: T.text(.togetherHandle), detail: handleDetail, symbol: "at", kind: .text(profileDraft.handle) { [weak self] text in self?.profileDraft.handle = text }),
            PanelRow(id: "together-handle-save", title: T.text(.togetherChangeHandle), symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in self?.changeTogetherHandle() }),
        ]
    }

    private func privacyRows() -> [PanelRow] {
        guard let privacy = togetherProfile?.privacy else { return [] }
        let known: [(TogetherPrivacy.Section, T.Key, String)] = [
            (.library, .privacyLibrary, "gamecontroller"), (.trophies, .privacyTrophies, "trophy"), (.friends, .privacyFriends, "person.2"),
            (.presence, .privacyPresence, "dot.radiowaves.left.and.right"), (.search, .privacySearch, "magnifyingglass"),
        ]
        var sections = known.map { ($0.0, T.text($0.1), $0.2) }
        // The gallery's own setting, where the server keeps files.
        if cloud.enabled { sections.append((.gallery, TCloud.text(.privacyGallery), "photo.stack")) }
        let choices = sections.map { section, title, symbol in
            let names = TogetherVisibility.allCases.map { visibility -> String in
                switch visibility {
                case .everyone: return T.text(.visibilityEveryone)
                case .friends: return T.text(.visibilityFriends)
                case .nobody: return T.text(section == .search ? .visibilityNoOne : .visibilityNobody)
                }
            }
            return PanelRow(id: "privacy-\(section.rawValue)", title: title, symbol: symbol,
                            kind: .choice(options: names, selected: TogetherVisibility.allCases.firstIndex(of: privacy[section]) ?? 1) { [weak self] index in
                                self?.setPrivacy(section, TogetherVisibility.allCases[index])
                            })
        }
        return [PanelRow(id: "together-privacy", title: T.text(.togetherPrivacyTitle), symbol: "lock", kind: .info(""))] + choices + [readReceiptsRow()].compactMap { $0 }
    }

    func previewOwnProfile(_ profile: TogetherOwnProfile) {
        togetherProfile = profile
        profileDraft = ProfileDraft(name: profile.displayName, bio: profile.bio ?? "", country: profile.country ?? "", handle: profile.handle)
    }

    func loadTogetherProfile() {
        guard togetherUser != nil else { return }
        Task {
            guard let profile = try? await together.myProfile() else { return }
            keepProfile(profile)
        }
    }

    private func keepProfile(_ profile: TogetherOwnProfile) {
        togetherProfile = profile
        profileDraft = ProfileDraft(name: profile.displayName, bio: profile.bio ?? "", country: profile.country ?? "", handle: profile.handle, loads: profileDraft.loads + 1)
        togetherUser = together.user
        ownProfileReadAt = Date()
    }

    /// How old the own profile may get while the launcher is in front (the server sends no event
    /// when the name, handle or picture changes on the website), and when the launcher comes back
    /// in front or a screen showing them opens.
    nonisolated static let ownProfileAge: TimeInterval = 5 * 60
    nonisolated static let ownProfileAgeShown: TimeInterval = 20

    /// Reads the own profile again when it is older than [age]: a name or handle changed on the
    /// website shows here. What is being typed in Edit Profile stays.
    func refreshOwnProfile(olderThan age: TimeInterval = AppModel.ownProfileAgeShown) {
        guard togetherUser != nil, togetherConnected, !ownProfileReading else { return }
        if let read = ownProfileReadAt, Date().timeIntervalSince(read) < age { return }
        ownProfileReading = true
        let who = togetherUser?.id
        Task {
            defer { ownProfileReading = false }
            guard let profile = try? await together.myProfile(), togetherUser?.id == who else { return }
            ownProfileReadAt = Date()
            let before = togetherProfile
            let draft = profileDraft
            // An untouched draft follows the new profile; one being typed in is left alone.
            let untouched = before.map { draft.name == $0.displayName && draft.bio == ($0.bio ?? "") && draft.country == ($0.country ?? "") && draft.handle == $0.handle } ?? true
            if untouched {
                keepProfile(profile)
            } else {
                togetherProfile = profile
                togetherUser = together.user
            }
            followHandle(profile.handle)
        }
    }

    /// The handle the profile picker shows under an online profile follows the account's.
    func followHandle(_ handle: String) {
        guard let profile = currentProfile, let account = profile.account, account.userId == togetherUser?.id, account.handle != handle else { return }
        profiles.setAccount(profile.id, LauncherProfile.Account(userId: account.userId, handle: handle))
        profilesChanged()
    }

    func saveTogetherProfile() {
        guard let profile = togetherProfile else { return }
        let draft = profileDraft
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let saved = try await together.updateProfile(displayName: name != profile.displayName && !name.isEmpty ? name : nil,
                                                             bio: draft.bio != (profile.bio ?? "") ? draft.bio : nil,
                                                             country: draft.country.uppercased() != (profile.country ?? "") ? draft.country : nil)
                keepProfile(saved)
                show(T.text(.togetherProfileSaved), symbol: "checkmark.circle.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func changeTogetherHandle() {
        let handle = profileDraft.handle.trimmingCharacters(in: .whitespaces)
        guard !handle.isEmpty, handle.lowercased() != togetherProfile?.handle else { return }
        Task {
            do {
                let saved = try await together.changeHandle(handle)
                keepProfile(saved)
                show(T.format(.togetherHandleChanged, saved.handle), symbol: "at")
            } catch let problem as TogetherProblem where problem.code == "bad_request" {
                show(T.text(.togetherHandleInvalid), symbol: "at")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Shown changed at once; put back if the server says no.
    func setPrivacy(_ section: TogetherPrivacy.Section, _ visibility: TogetherVisibility) {
        guard var profile = togetherProfile else { return }
        let before = profile.privacy
        profile.privacy[section] = visibility
        togetherProfile = profile
        Task {
            do {
                let privacy = try await together.updatePrivacy(section, to: visibility)
                togetherProfile?.privacy = privacy
            } catch {
                togetherProfile?.privacy = before
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The first connected phone's name, if one is connected.
    var connectedPhoneName: String? {
        connectedPhones.first.map { id in phones.first { $0.id == id }?.name ?? id }
    }

    // MARK: Signing in

    func togetherSendCode() {
        let email = togetherEmail.trimmingCharacters(in: .whitespaces)
        guard email.contains("@"), togetherStep != .busy else { return show(T.text(.togetherEmailInvalid), symbol: "envelope") }
        togetherStep = .busy
        Task {
            do {
                try await together.startEmail(email)
                togetherCode = ""
                withAnimation(Motion.overlay) { togetherStep = .codeSent(email: email) }
            } catch {
                togetherStep = .idle
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func togetherVerify() {
        guard case .codeSent(let email) = togetherStep else { return }
        let code = String(togetherCode.filter(\.isNumber).prefix(6))
        guard code.count == 6 else { return }
        Task {
            do {
                signedIn(try await together.verifyEmail(email, code: code))
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// A code to type on the website (on the phone or any computer): the launcher waits for it.
    func togetherStartDeviceCode() {
        togetherStep = .busy
        togetherWait?.cancel()
        togetherWait = Task {
            do {
                let device = try await together.startDeviceCode(deviceName: Host.current().localizedName ?? "Mac")
                var page = URLComponents(string: device.verificationUri)
                page?.queryItems = [URLQueryItem(name: "code", value: device.userCode)]
                let url = page?.url ?? URL(string: device.verificationUri)!
                withAnimation(Motion.overlay) { togetherStep = .deviceCode(code: device.userCode, url: url) }
                signedIn(try await together.waitForApproval(device))
            } catch is CancellationError {
                togetherStep = .idle
            } catch {
                togetherStep = .idle
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The phone signs this launcher in: the launcher starts a hand-off, the phone approves it.
    func togetherWithPhone() {
        guard let name = connectedPhoneName, let remote else { return }
        togetherStep = .busy
        togetherWait?.cancel()
        togetherWait = Task {
            do {
                let handoff = try await together.startHandoff(deviceName: Host.current().localizedName ?? "Mac")
                withAnimation(Motion.overlay) { togetherStep = .phone(name: name, handoff: handoff.handoffId) }
                remote.publish(.togetherHandoff(id: handoff.handoffId, deviceName: Host.current().localizedName ?? "Mac"))
                signedIn(try await together.waitForApproval(handoff))
            } catch is CancellationError {
                togetherStep = .idle
            } catch {
                togetherStep = .idle
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// A phone's side of a hand-off: it asks to be signed in as us, or answers ours.
    func togetherPhoneAsked(_ message: RemoteMessage) {
        switch message {
        case .togetherHandoff(let id, let deviceName):
            // Only phones paired with this launcher get here; signed in, it approves at once.
            guard togetherUser != nil else { return remote?.publish(.togetherHandoffAnswer(id: id, approved: false)) ?? () }
            Task {
                do {
                    try await together.approveHandoff(id)
                    remote?.publish(.togetherHandoffAnswer(id: id, approved: true))
                    show(T.format(.togetherPhoneSignedIn, deviceName), symbol: "iphone.radiowaves.left.and.right")
                } catch {
                    remote?.publish(.togetherHandoffAnswer(id: id, approved: false))
                    show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
                }
            }
        case .togetherHandoffAnswer(let id, false):
            guard case .phone(_, id) = togetherStep else { return }
            togetherCancel()
            show(T.text(.togetherPhoneDeclined), symbol: "iphone.slash")
        default:
            break
        }
    }

    func togetherCancel() {
        togetherWait?.cancel()
        togetherWait = nil
        togetherStep = .idle
    }

    func signedIn(_ user: TogetherUser) {
        withAnimation(Motion.overlay) {
            togetherUser = user
            togetherStep = .idle
        }
        profileSignedIn(user)
        togetherCode = ""
        Sounds.shared.play(.select)
        show(T.format(.togetherWelcome, user.displayName), symbol: "person.2.circle.fill")
        startTogetherSocket()
        // Every game's trophies go up once, the earned ones with their dates.
        for game in games { loadTrophies(game, again: true) }
    }

    /// `then` runs once the server has heard it and the session is forgotten here.
    func togetherSignOut(then: (@MainActor () -> Void)? = nil) {
        let client = together
        disconnectTogether()
        Task {
            await client.signOut()
            then?()
        }
    }

    /// Everything of the account here stops (socket, voice, share play, the social screens),
    /// its session kept: a profile switch or going offline, not a sign-out.
    func disconnectTogether() {
        leaveVoice()
        stopSharePlay()
        share.invites = []
        // What waits stays in this account's outbox, for when it signs in again.
        togetherFlush?.cancel()
        togetherSocket?.stop()
        togetherSocket = nil
        withAnimation(Motion.overlay) {
            togetherUser = nil
            togetherConnected = false
            togetherProfile = nil
            inbox = nil
            party = nil
            partyInvites = []
            gameSession = nil
            gameInvites = []
            togetherFriends = []
            togetherRequests = TogetherRequests(incoming: [], outgoing: [])
            discover = DiscoverState()
        }
    }

    /// Keeps the session live: friends see the launcher online, and a sign-out elsewhere ends it here.
    func startTogetherSocket() {
        guard togetherUser != nil, togetherSocket == nil else { return }
        refreshStorageInfo()
        let socket = TogetherSocket(client: together, onEvent: { event in
            Task { @MainActor [weak self] in
                self?.togetherConnected = true
                self?.togetherEvent(event)
            }
        }, onSignedOut: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.togetherSocket = nil
                self.endShareSession()
                if self.overlay == .compare { self.overlay = .profile }
                if self.overlay == .profile { self.closeProfile() }
                withAnimation(Motion.overlay) {
                    self.togetherUser = nil
                    self.togetherConnected = false
                }
                self.show(T.text(.togetherSignedOutElsewhere), symbol: "person.crop.circle.badge.xmark")
            }
        })
        togetherSocket = socket
        socket.start()
        togetherConnected = true
        updateTogetherPresence()
        refreshFriends()
        loadTogetherProfile()
        loadInbox()
        loadParty()
        loadGameInvites()
        loadNotifications()
        loadShareInvites()
        loadDiscovery()
        flushTogether()
        refreshFamily()
    }

    /// In a game or online, as friends will see it.
    func updateTogetherPresence() {
        guard let socket = togetherSocket else { return }
        followGameSession()
        if let running {
            socket.setPresence(.inGame(titleID: running.game.titleID, since: preferences.lastPlayed[running.game.id] ?? Date()))
        } else {
            socket.setPresence(.online)
        }
    }

    // MARK: Play and trophies

    static var machineModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    /// A game played for a while: the session goes to AnyTogether (or waits until it can).
    func recordPlay(_ game: Game, from start: Date) {
        let session = togetherUser == nil ? nil : togetherSync.recordSession(titleId: game.titleID, gameName: game.name, ageLevels: game.ageLevels, startedAt: start, endedAt: Date(), exit: "normal")
        familyPlayed(game, from: start, session: session)
        guard togetherUser != nil else { return }
        flushTogether()
        askHowItRan(game, played: Date().timeIntervalSince(start))
    }

    /// The game's trophy set as read now: new earned ones go to AnyTogether, and friends hear of them.
    func recordTrophies(_ game: Game, _ set: TrophySet) {
        guard togetherUser != nil, !set.trophies.isEmpty else { return }
        let names: [TrophySet.Grade: String] = [.platinum: "platinum", .gold: "gold", .silver: "silver", .bronze: "bronze"]
        let language = trophyLanguages(game).first.flatMap { $0.split(separator: "-").first.map(String.init) } ?? "en"
        let record = TogetherSync.TrophySetRecord(titleId: game.titleID, gameName: game.name, language: language, trophies: set.trophies.map {
            .init(id: $0.serviceLabel * 1000 + $0.number, grade: names[$0.grade] ?? "bronze", hidden: $0.hidden, name: $0.name, detail: $0.detail, earnedAt: $0.unlocked)
        })
        togetherSync.recordTrophies(record)
        flushTogether()
    }

    /// Sends what waits, a moment later so a burst of changes goes up together.
    func flushTogether() {
        togetherFlush?.cancel()
        togetherFlush = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, togetherUser != nil else { return }
            try? await togetherSync.flush()
        }
    }

    func togetherMessage(_ error: Error) -> String {
        if let family = familyMessage(error) { return family }
        if let problem = error as? TogetherProblem {
            switch problem.code {
            case "handle_taken": return T.text(.togetherHandleTaken)
            case "handle_reserved": return T.text(.togetherHandleReserved)
            case "handle_cooldown": return problem.handleChangeAt.map { T.format(.togetherHandleAgain, ProfileView.day($0)) } ?? problem.title
            case "links_not_allowed": return T.text(.togetherNoLinks)
            case "link_blocked": return T.text(.togetherLinkBlocked)
            case "code_invalid": return T.text(.togetherCodeWrong)
            case "code_expired", "expired_token": return T.text(.togetherCodeExpired)
            case "code_locked": return T.text(.togetherCodeLocked)
            case "rate_limited": return T.text(.togetherTooMany)
            default: return problem.title
            }
        }
        return T.text(.togetherUnreachable)
    }
}
