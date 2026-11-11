import AnyPS5Core
import Foundation

/// What the Delete game card (Overlay.confirmDeleteGame) asks about: Game Settings › Delete game
/// takes the game itself off the disk, not only what the launcher built from it (Uninstall). The
/// game's own folder, its update, its add-ons and the archive it was unpacked from go to the
/// Trash; the installation goes as Uninstall takes it; the saves and trophies in it are kept in
/// the store for the day the game is added again. The flow is in AppModel (askDeleteGame,
/// confirmDeleteGame), what may go in AnyPS5Core's GameDeletion, the card in HomeMenus.swift.
struct DeleteAsk: Equatable {
    let plan: DeletionPlan
    /// Asked a second time: the files cannot go to the Trash where they are, so this deletes them
    /// for good.
    var permanent = false
    /// What the plan's items take on the disk, nil while it is measured.
    var size: Int64?
}
