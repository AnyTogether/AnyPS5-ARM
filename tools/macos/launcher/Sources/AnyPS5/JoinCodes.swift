import AnyPS5Core
import AppKit
import SwiftUI

/// "Join with a code": what was typed, what the code opens, and what asking with it did.
struct JoinEntry {
    var text = ""
    var info: TogetherJoinInfo?
    var looking = false
    /// Why there is nothing to show (no such code, family settings…), or what asking did.
    var message: String?
    var asked: TogetherJoinInfo.State?
}

/// Join codes: the party's leader and the share play's host make one, copy it or its link, make a
/// new one or stop it; members see the party's. Anyone types a code to see what it opens and ask
/// to join; the leader or host still says yes (the existing request rows). The party's Discord
/// link goes here too.
extension AppModel {
    // MARK: The party's code and Discord link

    func partyCodeRows(_ party: TogetherParty, leader: Bool) -> [PanelRow] {
        var rows: [PanelRow] = []
        if let code = party.joinCode, code.works() {
            rows += codeRows(code, prefix: "party")
            if leader {
                rows.append(PanelRow(id: "party-code-new", title: JS.text(.newCode), detail: JS.text(.newCodeDetail), symbol: "arrow.clockwise",
                                     kind: .action(destructive: false) { [weak self] in self?.makePartyCode() }))
                rows.append(PanelRow(id: "party-code-stop", title: JS.text(.stopCode), symbol: "xmark.octagon",
                                     kind: .action(destructive: true) { [weak self] in self?.stopPartyCode() }))
            }
        } else if leader, familyAllows(.publicMatchmaking) {
            rows.append(PanelRow(id: "party-code-make", title: JS.text(.makeCode), detail: JS.text(.makeCodeDetail), symbol: "number",
                                 kind: .action(destructive: false) { [weak self] in self?.makePartyCode() }))
        }
        if leader {
            rows.append(PanelRow(id: "party-discord", title: JS.text(.discordLink), detail: JS.text(.discordLinkDetail), symbol: "link",
                                 kind: .text(party.discord ?? "") { [weak self] value in self?.discordLinkTyped(value) }))
        }
        if let link = party.discord, let url = URL(string: link) {
            rows.append(PanelRow(id: "party-discord-open", title: JS.text(.openDiscord), detail: link.replacingOccurrences(of: "https://", with: ""), symbol: "bubble.left.and.bubble.right",
                                 kind: .action(destructive: false) { NSWorkspace.shared.open(url) }))
        }
        return rows
    }

    /// The code, then Copy code and Copy link.
    private func codeRows(_ code: TogetherJoinCode, prefix: String) -> [PanelRow] {
        [
            PanelRow(id: "\(prefix)-code", title: JS.text(.codeTitle), detail: JS.format(.codeDetail, JS.until(code.expiresAt)), symbol: "number", kind: .info(code.display)),
            PanelRow(id: "\(prefix)-code-copy", title: JS.text(.copyCode), detail: code.display, symbol: "doc.on.doc",
                     kind: .action(destructive: false) { [weak self] in self?.copy(code.display, said: JS.text(.codeCopied)) }),
            PanelRow(id: "\(prefix)-code-link", title: JS.text(.copyLink), detail: code.url.replacingOccurrences(of: "https://", with: ""), symbol: "link",
                     kind: .action(destructive: false) { [weak self] in self?.copy(code.url, said: JS.text(.linkCopied)) }),
        ]
    }

    func copy(_ text: String, said: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show(said, symbol: "doc.on.doc")
    }

    /// A new code for the party (replacing the old one); making one again lifts "stopped".
    func makePartyCode() {
        guard let id = party?.id else { return }
        codeStopped.remove(id)
        let client = together
        Task {
            do {
                let code = try await client.makeJoinCode(party: id)
                if let current = party, current.id == id { withAnimation(Motion.overlay) { party = current.with(joinCode: code) } }
                show(JS.format(.codeMade, code.display), symbol: "number")
            } catch {
                show(joinCodeMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The code stops working; no new one is made for Discord's button for this party this session.
    func stopPartyCode() {
        guard let id = party?.id else { return }
        codeStopped.insert(id)
        let client = together
        Task {
            do {
                try await client.stopJoinCode(party: id)
            } catch let problem as TogetherProblem where problem.status == 404 {
                // Stopped already.
            } catch {
                return show(joinCodeMessage(error), symbol: "exclamationmark.triangle.fill")
            }
            if let current = party, current.id == id { withAnimation(Motion.overlay) { party = current.with(joinCode: nil) } }
            show(JS.text(.codeStopped), symbol: "xmark.octagon")
        }
    }

    /// The Discord link as it is typed: sent once it reads as one (a moment after typing stops),
    /// removed when the field is emptied; something else is pointed out after a longer pause.
    func discordLinkTyped(_ text: String) {
        guard let id = party?.id else { return }
        discordLinkSend?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = TogetherPartyDiscord.clean(trimmed)
        discordLinkSend = Task { [weak self] in
            try? await Task.sleep(for: .seconds(clean == nil && !trimmed.isEmpty ? 2.5 : 0.8))
            guard let self, !Task.isCancelled, let current = self.party, current.id == id else { return }
            guard trimmed.isEmpty || clean != nil else { return self.show(JS.text(.discordLinkBad), symbol: "link") }
            guard clean != current.discord else { return }
            do {
                let next = try await self.together.setPartyDiscord(id, clean)
                if self.party?.id == id { withAnimation(Motion.overlay) { self.party = next } }
                self.show(JS.text(clean == nil ? .discordLinkRemoved : .discordLinkSaved), symbol: "link")
            } catch {
                self.show(self.togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: The share play's code

    func shareCodeRows(_ hosting: TogetherSharePlay) -> [PanelRow] {
        if let code = hosting.joinCode, code.works() {
            return codeRows(code, prefix: "share") + [
                PanelRow(id: "share-code-new", title: JS.text(.newCode), detail: JS.text(.newCodeDetail), symbol: "arrow.clockwise",
                         kind: .action(destructive: false) { [weak self] in self?.makeShareCode() }),
                PanelRow(id: "share-code-stop", title: JS.text(.stopCode), symbol: "xmark.octagon",
                         kind: .action(destructive: true) { [weak self] in self?.stopShareCode() }),
            ]
        }
        guard familyAllows(.publicMatchmaking) else { return [] }
        return [PanelRow(id: "share-code-make", title: JS.text(.makeCode), detail: JS.text(.makeCodeDetail), symbol: "number",
                         kind: .action(destructive: false) { [weak self] in self?.makeShareCode() })]
    }

    func makeShareCode() {
        guard let id = share.hosting?.id else { return }
        codeStopped.remove(id)
        let client = together
        Task {
            do {
                let code = try await client.makeJoinCode(sharePlay: id)
                if let hosting = share.hosting, hosting.id == id { withAnimation(Motion.overlay) { share.hosting = hosting.with(joinCode: code) } }
                show(JS.format(.codeMade, code.display), symbol: "number")
            } catch {
                show(joinCodeMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func stopShareCode() {
        guard let id = share.hosting?.id else { return }
        codeStopped.insert(id)
        let client = together
        Task {
            do {
                try await client.stopJoinCode(sharePlay: id)
            } catch let problem as TogetherProblem where problem.status == 404 {
                // Stopped already.
            } catch {
                return show(joinCodeMessage(error), symbol: "exclamationmark.triangle.fill")
            }
            if let hosting = share.hosting, hosting.id == id { withAnimation(Motion.overlay) { share.hosting = hosting.with(joinCode: nil) } }
            show(JS.text(.codeStopped), symbol: "xmark.octagon")
        }
    }

    // MARK: Join with a code

    func joinCodeEntryRows() -> [PanelRow] {
        let entry = joinEntry
        let detail = entry.looking ? JS.text(.lookingUp) : entry.info == nil ? entry.message ?? JS.text(.joinWithCodeDetail) : JS.text(.joinWithCodeDetail)
        var rows = [PanelRow(id: "join-code", title: JS.text(.joinWithCode), detail: detail, symbol: "ticket",
                             kind: .text(entry.text) { [weak self] value in self?.joinCodeTyped(value) })]
        guard let info = entry.info else { return rows }
        let host = info.host?.displayName ?? "?"
        var details: [String] = []
        if let game = info.game { details.append(game.name(in: lang)) }
        details.append(T.format(.partySize, info.size, info.max))
        rows.append(PanelRow(id: "join-code-what", title: JS.format(info.kind == .party ? .codeParty : .codeShare, host), detail: details.joined(separator: " · "),
                             symbol: info.kind == .party ? "person.3.fill" : "shareplay", kind: .info(TogetherJoinCode.display(info.code)),
                             person: info.host.map { PanelPerson(name: $0.displayName, avatar: $0.avatar, status: info.kind == .sharePlay ? .playing : nil) }))
        switch entry.asked ?? info.state {
        case .member:
            rows.append(PanelRow(id: "join-code-state", title: JS.text(.alreadyIn), symbol: "checkmark.circle", kind: .info("")))
        case .requested:
            rows.append(PanelRow(id: "join-code-state", title: JS.text(info.kind == .party ? .askedParty : .askedShare), symbol: "hourglass", kind: .info("")))
        case .invited:
            rows.append(PanelRow(id: "join-code-state", title: JS.text(info.kind == .party ? .invitedParty : .invitedShare), symbol: "envelope.open", kind: .info("")))
        case .notIn, nil:
            if info.full {
                rows.append(PanelRow(id: "join-code-state", title: info.kind == .party ? T.text(.partyFull) : FP.text(.full), symbol: "person.3.fill", kind: .info("")))
            } else {
                rows.append(PanelRow(id: "join-code-ask", title: JS.text(.askToJoin), detail: entry.message, symbol: "hand.raised.fill",
                                     kind: .action(destructive: false) { [weak self] in self?.askWithCode() }))
            }
        }
        return rows
    }

    /// A code typed or pasted: once it reads as one, what it opens is looked up (a moment after
    /// typing stops).
    func joinCodeTyped(_ text: String) {
        joinEntry.text = text
        guard let code = TogetherJoinCode.normalize(text) else {
            joinLookup?.cancel()
            let typed = text.filter { $0.isLetter || $0.isNumber }.count
            joinEntry = JoinEntry(text: text, message: typed >= TogetherJoinCode.length ? JS.text(.notACode) : nil)
            return
        }
        guard code != joinEntry.info?.code || joinEntry.message != nil else { return }
        joinLookup?.cancel()
        joinEntry.looking = true
        joinEntry.message = nil
        let client = together
        joinLookup = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let info = try await client.joinCodeInfo(code)
                guard let self, !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { self.joinEntry = JoinEntry(text: self.joinEntry.text, info: info) }
            } catch {
                guard let self, !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { self.joinEntry = JoinEntry(text: self.joinEntry.text, message: self.joinCodeMessage(error)) }
            }
        }
    }

    /// Asks with the code: the leader or host answers (an invite comes), or the user is invited at once.
    func askWithCode() {
        guard let info = joinEntry.info else { return }
        let client = together
        Task {
            do {
                let answer = try await client.redeemJoinCode(info.code)
                withAnimation(Motion.overlay) {
                    joinEntry.asked = answer.state
                    joinEntry.message = nil
                }
                switch (answer.state, answer.kind) {
                case (.invited, .party):
                    show(JS.text(.invitedParty), symbol: "envelope.open")
                    loadParty()
                case (.invited, .sharePlay):
                    show(JS.text(.invitedShare), symbol: "envelope.open")
                    loadShareInvites()
                default:
                    show(JS.text(answer.kind == .party ? .askedParty : .askedShare), symbol: "hand.raised.fill")
                }
                Sounds.shared.play(.select)
            } catch let problem as TogetherProblem where problem.code == "conflict" {
                withAnimation(Motion.overlay) { joinEntry.asked = .member }
            } catch {
                let message = joinCodeMessage(error)
                withAnimation(Motion.overlay) { joinEntry.message = message }
                show(message, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The plain words for what the server refused about a code.
    func joinCodeMessage(_ error: Error) -> String {
        guard let problem = error as? TogetherProblem else { return T.text(.togetherUnreachable) }
        switch problem.code {
        case "not_found": return JS.text(.noSuchCode)
        case "restricted_by_family": return JS.text(problem.side == "other" ? .familyBlocksOther : .familyBlocks)
        case "account_muted": return JS.text(.accountMuted)
        case "rate_limited": return JS.text(.tooMany)
        case "conflict": return JS.text(.alreadyIn)
        case "full": return T.text(.partyFull)
        default: return togetherMessage(error)
        }
    }

    /// Someone asked with the code: their request row says so.
    func noteJoinRequest(_ event: TogetherSocket.Event) {
        guard let request = event.decode(TogetherJoinRequest.self), request.withCode else { return }
        codeAskers.insert(request.from.userId)
    }

    // MARK: Previews

    func previewJoinEntry(_ entry: JoinEntry) { joinEntry = entry }
}
