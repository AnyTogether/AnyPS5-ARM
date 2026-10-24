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

    private var forward: AnyCancellable?

    init(owner: AppModel) {
        forward = objectWillChange.sink { [weak owner] _ in owner?.objectWillChange.send() }
    }
}

extension AppModel {
    /// The Friends panel's ways into the social screens.
    func socialRows() -> [PanelRow] {
        [
            PanelRow(id: "friends-feed", title: TS.text(.feedRow), detail: TS.text(.feedRowDetail), symbol: "sparkles", kind: .action(destructive: false) { [weak self] in
                self?.openFeed()
            }),
        ]
    }
}
