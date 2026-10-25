import AnyPS5Core
import AppKit
import SwiftUI

/// Trophy levels, a profile's showcase, comparing trophies with someone, and appearing offline.
extension AppModel {
    // MARK: Appear offline

    /// Friends see the user offline (set here or on another device).
    var appearingOffline: Bool { togetherProfile?.appearOffline == true }

    /// Settings → AnyTogether: Online or Appear offline, once the profile is read.
    func presenceRows() -> [PanelRow] {
        guard togetherProfile != nil else { return [] }
        return [PanelRow(id: "together-presence", title: TL.text(.presenceTitle), detail: TL.text(.presenceHint), symbol: appearingOffline ? "moon.fill" : "circle.fill",
                         kind: .choice(options: [TL.text(.presenceOnline), TL.text(.presenceOffline)], selected: appearingOffline ? 1 : 0) { [weak self] index in
                             self?.setAppearOffline(index == 1)
                         })]
    }

    /// Shown changed at once; put back with a short note when the server says no (a server
    /// without it answers 404). The socket and its heartbeats stay as they are.
    func setAppearOffline(_ on: Bool) {
        guard togetherProfile != nil, appearingOffline != on else { return }
        let before = !on
        withAnimation(Motion.overlay) { togetherProfile?.appearOffline = on }
        Task {
            do {
                let kept = try await together.setAppearOffline(on)
                withAnimation(Motion.overlay) { togetherProfile?.appearOffline = kept }
            } catch let problem as TogetherProblem where problem.status == 404 {
                withAnimation(Motion.overlay) { togetherProfile?.appearOffline = before }
                show(TL.text(.presenceUnavailable), symbol: "moon")
            } catch {
                withAnimation(Motion.overlay) { togetherProfile?.appearOffline = before }
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Levels

    /// `level.up`: the user's own is a card over everything (a game too) with the trophy sound;
    /// a friend's moves their badge in the list, with a quiet note while the launcher is in front.
    func levelUp(_ up: TogetherLevelUp) {
        if up.isMine(togetherUser?.id) {
            withAnimation(Motion.overlay) { togetherProfile?.apply(up) }
            TrophyBanner.shared.levelUp(up.badge, sounds: preferences.sounds)
            // The points and the way to the next level, as the server has them now.
            Task {
                guard let fresh = try? await together.myProfile() else { return }
                withAnimation(Motion.overlay) { togetherProfile?.trophyLevel = fresh.trophyLevel }
            }
            return
        }
        var friends = togetherFriends
        guard friends.apply(up) else { return }
        withAnimation(Motion.overlay) { togetherFriends = friends }
        if NSApp.isActive, running == nil { show(TL.format(.friendLevelUp, up.displayName, up.badge.level), symbol: "arrow.up.circle.fill") }
    }

    /// The user's own level on the home screen, beside their avatar.
    var myLevel: TogetherTrophyLevel? { togetherUser == nil ? nil : togetherProfile?.trophyLevel }

    // MARK: Showcase

    func loadProfileShowcase(_ handle: String) {
        social.profileShowcase = nil
        social.profileShowcaseTask?.cancel()
        social.profileShowcaseTask = Task {
            // An older server has none: nothing is shown.
            guard let showcase = try? await together.showcase(of: handle), !Task.isCancelled else { return }
            withAnimation(Motion.overlay) { social.profileShowcase = showcase }
        }
    }

    // MARK: Compare

    /// Compares trophies with the person whose profile is open: the games, or one game's trophies.
    func openCompare(_ titleId: String? = nil) {
        guard let profile = profilePage?.profile, !profile.isMe else { return }
        let person = TogetherPerson(userId: profile.userId, handle: profile.handle, displayName: profile.displayName, avatar: profile.avatar)
        social.compareTask?.cancel()
        social.compareGameTask?.cancel()
        social.compareWith = person
        social.compareGames = []
        social.compareGamesLoad = .loading
        social.compareIndex = 0
        social.compareTitle = nil
        social.compareView = nil
        withAnimation(Motion.overlay) { overlay = .compare }
        Sounds.shared.play(.select)
        loadCompareGames()
        if let titleId { openCompareGame(titleId) }
    }

    func loadCompareGames() {
        guard let person = social.compareWith else { return }
        social.compareTask = Task {
            do {
                let games = try await together.compareGames(with: person.handle)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    social.compareGames = games
                    social.compareGamesLoad = .shown
                    if let title = social.compareTitle, let index = games.firstIndex(where: { $0.titleId == title }) { social.compareIndex = index }
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { social.compareGamesLoad = Self.compareLoad(error) }
            }
        }
    }

    func openCompareGame(_ titleId: String) {
        guard let person = social.compareWith else { return }
        social.compareGameTask?.cancel()
        withAnimation(Motion.overlay) {
            social.compareTitle = titleId
            social.compareView = nil
            social.compareViewLoad = .loading
            social.compareTrophyIndex = 0
        }
        social.compareGameTask = Task {
            do {
                let view = try await together.compareTrophies(with: person.handle, titleId: titleId)
                guard !Task.isCancelled, social.compareTitle == titleId else { return }
                withAnimation(Motion.overlay) {
                    social.compareView = view
                    social.compareViewLoad = .shown
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, social.compareTitle == titleId else { return }
                withAnimation(Motion.overlay) { social.compareViewLoad = Self.compareLoad(error) }
            }
        }
    }

    /// Kept private (403), a game AnyTogether does not know (404), or not read.
    static func compareLoad(_ error: Error) -> SocialState.CompareLoad {
        guard let problem = error as? TogetherProblem else { return .failed }
        if problem.isPrivate { return .hidden }
        return problem.status == 404 ? .unknown : .failed
    }

    /// Up and down through the games or the trophies; a game opens its trophies, back goes to the
    /// games and then to the profile.
    func compareCommand(_ command: Command) {
        if social.compareTitle != nil {
            switch command {
            case .up, .down:
                let count = social.compareView?.trophies.count ?? 0
                let next = min(count - 1, max(0, social.compareTrophyIndex + (command == .down ? 1 : -1)))
                guard count > 0, next != social.compareTrophyIndex else { return }
                social.compareTrophyIndex = next
                Sounds.shared.play(.move)
            case .back, .options:
                social.compareGameTask?.cancel()
                withAnimation(Motion.overlay) {
                    social.compareTitle = nil
                    social.compareView = nil
                }
                Sounds.shared.play(.back)
            default:
                break
            }
            return
        }
        switch command {
        case .up, .down:
            let count = social.compareGames.count
            let next = min(count - 1, max(0, social.compareIndex + (command == .down ? 1 : -1)))
            guard count > 0, next != social.compareIndex else { return }
            social.compareIndex = next
            Sounds.shared.play(.move)
        case .select:
            guard social.compareGames.indices.contains(social.compareIndex) else { return }
            Sounds.shared.play(.select)
            openCompareGame(social.compareGames[social.compareIndex].titleId)
        case .back, .options:
            closeCompare()
        default:
            break
        }
    }

    /// Back to the profile it was opened from, as it was.
    func closeCompare() {
        social.compareTask?.cancel()
        social.compareGameTask?.cancel()
        withAnimation(Motion.overlay) { overlay = profilePage == nil ? nil : .profile }
        Sounds.shared.play(.back)
    }

    func previewCompare(with person: TogetherPerson, games: [TogetherCompareGame], index: Int = 0, view: TogetherCompareView? = nil, load: SocialState.CompareLoad = .shown, trophyIndex: Int = 0) {
        social.compareWith = person
        social.compareGames = games
        social.compareGamesLoad = load
        social.compareIndex = index
        social.compareTitle = view?.titleId
        social.compareView = view
        social.compareViewLoad = view == nil ? .loading : .shown
        social.compareTrophyIndex = trophyIndex
        overlay = .compare
    }
}
