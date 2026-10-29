import AnyPS5Core
import AppKit
import SwiftUI

/// What the mouse's Forward button opens again: the screen Back closed, where Back left the user
/// and the game selected then.
struct ForwardStep: Equatable {
    let overlay: Overlay
    let landed: Overlay?
    let selected: Int
}

// Esc on the home screen ("Quit AnyPS5?") and the mouse's side buttons: Back is Circle wherever
// the user is, Forward opens again the screen Back just closed, as in a browser (as AnyPS5
// Desktop's launcher does).

extension AppModel {
    /// The screens Forward may open again: plain screens, never a question or a running step.
    static let forwardOverlays: [Overlay] = [.library, .settings, .gameSettings, .controls, .trophies, .gallery, .friends]

    /// Esc pressed (the key; Circle stays Back): on the home screen with the games in focus and
    /// nothing open, "Quit AnyPS5?" with Cancel first; on that question, Cancel. False everywhere
    /// else, where Esc is Back as before.
    func escape() -> Bool {
        if overlay == .confirmQuit { return gameMenuCommand(.back) }
        guard preferences.onboarded, overlay == nil, focus == .tiles, pairing == nil, ringing == nil, starting == nil, fontWait == nil, shareWatch == nil else { return false }
        forwardStep = nil
        menuIndex = 0
        open(.confirmQuit)
        return true
    }

    /// The mouse's Back button: Circle.
    func mouseBack() {
        forwardStep = nil
        let from = overlay, game = selected
        _ = handle(.back)
        if let from, overlay != from, Self.forwardOverlays.contains(from) {
            forwardStep = ForwardStep(overlay: from, landed: overlay, selected: game)
        }
    }

    /// The mouse's Forward button: the screen Back just closed opens again; nothing when the user
    /// went elsewhere or chose another game since.
    func mouseForward() {
        guard let step = forwardStep else { return }
        forwardStep = nil
        guard preferences.onboarded, pairing == nil, ringing == nil, starting == nil, fontWait == nil, shareWatch == nil,
              overlay == step.landed, selected == step.selected else { return }
        open(step.overlay)
    }
}
