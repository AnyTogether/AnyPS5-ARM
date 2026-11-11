@testable import AnyPS5
import AppKit
import SwiftUI
import XCTest

/// The launcher's screen in a real window, for what only a window shows: where the cursor is,
/// what a click does, how far a list scrolled. A window comes up, so these run on CI only.
@MainActor
final class LauncherWindow {
    let window: NSWindow
    let model: AppModel

    init(_ model: AppModel, width: CGFloat = 1600, height: CGFloat = 900) throws {
        guard ProcessInfo.processInfo.environment["CI"] == "true" else { throw XCTSkip("opens a window: CI only") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        self.model = model
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView().environmentObject(model))
        window.setContentSize(frame.size)
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        wait(0.6)
    }

    func close() { window.orderOut(nil) }

    /// Lets the screen settle: the events waiting are sent and the animations run on.
    func wait(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
        }
    }

    /// Whether the cursor is in a text field.
    var typing: Bool { (window.firstResponder as? NSTextView)?.isEditable == true }

    /// What the keyboard types goes where the cursor is.
    func type(_ text: String) {
        (window.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        wait(0.2)
    }

    func views<V: NSView>(_ kind: V.Type, in view: NSView? = nil) -> [V] {
        guard let view = view ?? window.contentView else { return [] }
        let own = (view as? V).map { [$0] } ?? []
        return own + view.subviews.flatMap { views(kind, in: $0) }
    }

    /// A view's frame in the window.
    func frame(_ view: NSView) -> NSRect { view.convert(view.bounds, to: nil) }

    /// A click of the left button at a point of the window.
    func click(_ point: NSPoint) {
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
        // A field follows the mouse until the button is let go: the release waits in the queue.
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
        wait(0.4)
    }
}
