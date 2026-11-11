import Foundation

/// What a paired device is, for the sign before its name in Settings: read from the name it
/// introduced itself with, the only thing a hello carries about it.
public enum PhoneKind: Equatable, Sendable {
    /// An Android phone (its name says so, or its browser's User-Agent did).
    case android
    /// An iPhone or iPod touch.
    case iPhone
    case iPad
    /// A browser pad on a device whose system the User-Agent did not name.
    case browser
    /// A phone whose name says nothing about its system (the name its owner gave it).
    case phone
}

/// A paired device's name taken apart: its kind, and for a browser pad the device the browser runs
/// on. The name itself stays as it was stored and sent ("Android · Web"), so pairings made before
/// keep working; only what people read changes.
public struct PhoneLabel: Equatable, Sendable {
    /// What BrowserPadAccess.deviceName puts after the device: a pad in a browser, not the app.
    public static let browserSuffix = " · Web"

    public let name: String
    public let kind: PhoneKind
    /// A browser pad, as opposed to the phone app.
    public let isBrowser: Bool
    /// The device a browser pad runs on, as its User-Agent named it ("Android", "iPhone", "iPad");
    /// nil for the app and for a browser on a device it did not name ("Phone").
    public let browserDevice: String?

    public init(_ name: String) {
        self.name = name
        let browser = name.hasSuffix(PhoneLabel.browserSuffix)
        let device = browser ? String(name.dropLast(PhoneLabel.browserSuffix.count)) : name
        isBrowser = browser
        let folded = device.lowercased()
        let found: PhoneKind
        if folded.contains("ipad") {
            found = .iPad
        } else if folded.contains("iphone") || folded.contains("ipod") {
            found = .iPhone
        } else if folded.contains("android") {
            found = .android
        } else {
            found = browser ? .browser : .phone
        }
        kind = found
        browserDevice = browser && found != .browser ? device : nil
    }
}
