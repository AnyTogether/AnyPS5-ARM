import AnyPS5Core
import AppKit
import SwiftUI

/// Profiles and the friends-only names, drawn offscreen for `--render-preview`: the first
/// start's last step, the picker, Add Profile, the sign-in, the Options menu and the settings.
@MainActor
enum ProfilePreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, mode: InputMode, configure: (AppModel) -> Void) in
            InputModeState.shared.preview(mode)
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in configure(model) }
            InputModeState.shared.preview(.keyboard)
        }
        /// Robin (online, signed in) plays; Mira and Deniz share the Mac.
        func family(_ model: AppModel) {
            PreviewRenderer.signedIn(model)
            if let robin = model.currentProfile {
                model.profiles.setMode(robin.id, .online)
                model.profiles.setAccount(robin.id, .init(userId: "u1", handle: "robin"))
            }
            _ = model.profiles.add(name: "Mira", mode: .online, account: .init(userId: "u7", handle: "mira.k"))
            _ = model.profiles.add(name: "Deniz", mode: .offline)
            model.profilesChanged()
        }
        func settings(_ model: AppModel, _ category: String, row: String?) {
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == category } ?? 0
            model.panelInRows = row != nil
            let rows = model.panelCategories().first { $0.id == category }?.rows ?? []
            model.panelRow = rows.firstIndex { $0.id == row } ?? 0
        }

        var fresh = preferences
        fresh.onboarded = false
        fresh.libraryFolders = [root.path]
        PreviewRenderer.render(fresh, found, root, still, output.appendingPathComponent("onboarding3.png")) { model in
            model.onboardingStep = 3
            model.profileFlow.modeChoice = 1
        }
        InputModeState.shared.preview(.pad)
        PreviewRenderer.render(fresh, found, root, still, output.appendingPathComponent("onboarding3-pad.png")) { model in
            model.onboardingStep = 3
            model.profileFlow.modeChoice = 0
        }
        InputModeState.shared.preview(.keyboard)
        PreviewRenderer.render(fresh, found, root, still, output.appendingPathComponent("onboarding3-signin.png")) { model in
            model.onboardingStep = 3
            model.profileFlow.origin = .firstStart
            model.profileFlow.pendingID = LauncherProfile.legacyID
            model.overlay = .signIn
            model.panelInRows = true
            model.panelRow = 1
        }

        render("profile-picker", .pad) { model in
            family(model)
            model.openProfilePicker(atLaunch: true)
            model.profileFlow.pickerIndex = 1
        }
        render("profile-picker-add", .keyboard) { model in
            family(model)
            model.openProfilePicker()
            model.profileFlow.pickerIndex = 3
        }
        render("profile-add", .pad) { model in
            family(model)
            model.openAddProfile()
            model.profileFlow.modeChoice = 0
        }
        render("profile-signin", .keyboard) { model in
            family(model)
            model.togetherUser = nil
            model.profileFlow.origin = .goingOnline
            model.overlay = .signIn
            model.panelInRows = true
            model.panelRow = 2
        }
        render("profile-menu", .pad) { model in
            family(model)
            model.openProfileMenu()
            model.menuIndex = 1
        }
        render("profile-menu-offline", .keyboard) { model in
            family(model)
            if let robin = model.currentProfile { model.profiles.setMode(robin.id, .offline) }
            model.profilesChanged()
            model.togetherUser = nil
            model.openProfileMenu()
            model.menuIndex = 2
        }
        render("menu-home-profiles", .pad) { model in
            family(model)
            model.overlay = .homeMenu
            model.menuIndex = 0
        }
        render("settings-profiles", .keyboard) { model in
            family(model)
            settings(model, "profiles", row: "profile-mode")
        }
        render("settings-profiles-delete", .pad) { model in
            family(model)
            let deniz = model.profileBook.profiles.first { $0.name == "Deniz" }?.id ?? ""
            settings(model, "profiles", row: nil)
            model.panelInRows = true
            model.ask("profile-delete-\(deniz)")
            let rows = model.panelCategories()[model.panelCategory].rows
            model.focusRow(rows.firstIndex { $0.id == "profile-delete-\(deniz)-cancel" } ?? 0, in: rows)
        }
        render("settings-together-offline", .keyboard) { model in
            if let robin = model.currentProfile {
                model.profiles.setMode(robin.id, .offline)
                model.profiles.setAccount(robin.id, .init(userId: "u1", handle: "robin"))
            }
            model.profilesChanged()
            settings(model, "together", row: "together-go-online")
        }

        // The friends-only names and pictures.
        func privateFriends(_ model: AppModel) {
            PreviewRenderer.signedIn(model)
            let title = model.games.first?.titleID ?? "PPSA01234"
            model.togetherFriends = [
                TogetherFriend(userId: "f1", handle: "mira", displayName: "NightOwl", avatar: nil, presence: .init(state: "in_game", titleId: title, since: nil),
                               privateName: "Mira Kaya"),
                TogetherFriend(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil), privateName: nil),
                TogetherFriend(userId: "f3", handle: "kenji", displayName: "K3NJ1", avatar: nil, presence: nil, privateName: "Kenji Sato"),
            ]
        }
        render("friends-private", .keyboard) { model in
            privateFriends(model)
            model.open(.friends)
            model.panelRow = 3
        }
        render("party-private", .keyboard) { model in
            privateFriends(model)
            let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
            // A party event's card carries no private name: the friends list's is kept by user ID.
            let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "NightOwl", avatar: nil)
            model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [robin, mira], invited: [], call: nil))
            model.open(.party)
        }
        render("profile-friend-private", .keyboard) { model in
            privateFriends(model)
            model.previewProfile(TogetherProfilePage(profile: TogetherProfile(userId: "f1", handle: "mira", displayName: "NightOwl", avatar: nil, bio: "Speedruns and cosy games.",
                                                                              country: "TR", friendship: "friends", privateName: "Mira Kaya"),
                                                     library: .shown([]), trophies: .shown([])))
        }
        render("settings-together-private", .keyboard) { model in
            family(model)
            model.previewOwnProfile(TogetherOwnProfile(handle: "robin", displayName: "Robin", bio: nil, avatar: nil, country: nil, handleChangeAt: nil, privacy: .standard,
                                                       privateName: "Robin Yılmaz"))
            settings(model, "together", row: nil)
            let rows = model.panelCategories()[model.panelCategory].rows
            model.panelInRows = true
            model.focusRow(rows.firstIndex { $0.id.hasPrefix("private-name-save") } ?? 0, in: rows)
        }
    }
}
