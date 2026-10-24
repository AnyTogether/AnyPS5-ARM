import AnyPS5Core
import Combine
import SwiftUI

/// What the social screens (activity, leaderboards, notifications) hold. It lives apart from
/// `AppModel`'s own properties and passes its changes on to the model, so the views that watch the
/// model redraw with it.
@MainActor
final class SocialState: ObservableObject {
    // Activity
    @Published var feed = TogetherFeed()
    @Published var feedFailed = false
    @Published var feedIndex = 0
    /// The reaction the focused item's reactions are on, 0-3.
    @Published var feedReaction = 0
    var feedTask: Task<Void, Never>?
    var feedOlderTask: Task<Void, Never>?
    /// The panel the feed was opened from, to go back to.
    var feedReturn: AppModel.ProfileReturn?

    /// The recent activity of the profile on screen; nil while it is read.
    @Published var profileActivity: [TogetherActivity]?
    @Published var profileActivityFailed = false
    var profileActivityTask: Task<Void, Never>?

    // Leaderboards
    /// The game whose board is open; nil for overall trophy points.
    @Published var boardGame: TogetherActivity.Game?
    @Published var boardKind = TogetherGameBoard.points
    @Published var boardScope = TogetherBoardScope.friends
    @Published var leaderboard: TogetherLeaderboard?
    @Published var boardFailed = false
    /// The game is not on AnyTogether (no one played it there).
    @Published var boardMissing = false
    @Published var boardIndex = 0
    var boardTask: Task<Void, Never>?
    var boardReturn: AppModel.ProfileReturn?

    // Notifications
    @Published var notifications = TogetherNotifications()
    @Published var notificationsFailed = false
    var notificationsTask: Task<Void, Never>?

    /// Whose feed and boards these are: another account signed in starts them again.
    private var viewer: String?

    private var forward: AnyCancellable?

    init(owner: AppModel) {
        forward = objectWillChange.sink { [weak owner] _ in owner?.objectWillChange.send() }
    }

    /// Forgets what another account read.
    func follow(_ user: String?) {
        guard user != viewer else { return }
        viewer = user
        feedTask?.cancel()
        feedOlderTask?.cancel()
        boardTask?.cancel()
        feed = TogetherFeed()
        feedFailed = false
        leaderboard = nil
        boardGame = nil
        notificationsTask?.cancel()
        notifications = TogetherNotifications()
        notificationsFailed = false
    }
}

extension AppModel {
    /// The Friends panel's ways into the social screens.
    func socialRows() -> [PanelRow] {
        [
            PanelRow(id: "friends-feed", title: TS.text(.feedRow), detail: TS.text(.feedRowDetail), symbol: "sparkles", kind: .action(destructive: false) { [weak self] in
                self?.openFeed()
            }),
            PanelRow(id: "friends-board", title: TS.text(.boardTitle), detail: TS.text(.boardRowDetail), symbol: "list.number", kind: .action(destructive: false) { [weak self] in
                self?.openLeaderboard(nil)
            }),
        ]
    }

    /// The game panel's social rows, signed in: the game's leaderboard.
    func gameSocialRows(_ game: Game) -> [PanelRow] {
        guard togetherUser != nil else { return [] }
        return [
            PanelRow(id: "leaderboard", title: TS.text(.boardTitle), detail: TS.text(.boardGameRowDetail), symbol: "list.number", kind: .action(destructive: false) { [weak self] in
                self?.openLeaderboard(game)
            }),
        ]
    }
}
