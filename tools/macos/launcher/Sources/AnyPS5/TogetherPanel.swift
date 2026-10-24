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
    }

    /// Where AnyTogether is; ANYTOGETHER_URL points the launcher at another server (staging, a local one).
    static let togetherBase = URL(string: ProcessInfo.processInfo.environment["ANYTOGETHER_URL"] ?? "https://anytogether.kodla.agency")!

    static func makeTogetherClient() -> TogetherClient {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return TogetherClient(base: togetherBase, clientName: "launcher-macos/\(runningVersion) (macOS \(os.majorVersion).\(os.minorVersion))")
    }

    // MARK: Rows

    func togetherRows() -> [PanelRow] {
        if let user = togetherUser {
            return [
                PanelRow(id: "together-user", title: "@\(user.handle)", detail: user.displayName, symbol: "person.crop.circle.badge.checkmark", kind: .info("")),
                PanelRow(id: "together-online", title: T.text(.togetherOnline), detail: togetherConnected ? T.text(.togetherConnected) : T.text(.togetherConnecting),
                         symbol: togetherConnected ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark", kind: .info("")),
                PanelRow(id: "together-signout", title: T.text(.togetherSignOut), symbol: "rectangle.portrait.and.arrow.right", kind: .action(destructive: true) { [weak self] in
                    self?.togetherSignOut()
                }),
            ]
        }
        var rows = [PanelRow(id: "together-intro", title: T.text(.togetherIntro), detail: T.text(.togetherIntroDetail), symbol: "person.2.circle", kind: .info(""))]
        switch togetherStep {
        case .idle, .busy:
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
        }
        return rows
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

    func togetherCancel() {
        togetherWait?.cancel()
        togetherWait = nil
        togetherStep = .idle
    }

    private func signedIn(_ user: TogetherUser) {
        withAnimation(Motion.overlay) {
            togetherUser = user
            togetherStep = .idle
        }
        togetherCode = ""
        Sounds.shared.play(.select)
        show(T.format(.togetherWelcome, user.displayName), symbol: "person.2.circle.fill")
        startTogetherSocket()
        // Every game's trophies go up once, the earned ones with their dates.
        for game in games { loadTrophies(game, again: true) }
    }

    func togetherSignOut() {
        let client = together
        togetherSocket?.stop()
        togetherSocket = nil
        withAnimation(Motion.overlay) {
            togetherUser = nil
            togetherConnected = false
            togetherFriends = []
            togetherRequests = TogetherRequests(incoming: [], outgoing: [])
        }
        Task { await client.signOut() }
    }

    /// Keeps the session live: friends see the launcher online, and a sign-out elsewhere ends it here.
    func startTogetherSocket() {
        guard togetherUser != nil, togetherSocket == nil else { return }
        let socket = TogetherSocket(client: together, onEvent: { event in
            Task { @MainActor [weak self] in
                self?.togetherConnected = true
                self?.togetherEvent(event)
            }
        }, onSignedOut: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.togetherSocket = nil
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
        flushTogether()
    }

    /// In a game or online, as friends will see it.
    func updateTogetherPresence() {
        guard let socket = togetherSocket else { return }
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
        guard togetherUser != nil else { return }
        togetherSync.recordSession(titleId: game.titleID, gameName: game.name, startedAt: start, endedAt: Date(), exit: "normal")
        flushTogether()
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

    private func togetherMessage(_ error: Error) -> String {
        if let problem = error as? TogetherProblem {
            switch problem.code {
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
