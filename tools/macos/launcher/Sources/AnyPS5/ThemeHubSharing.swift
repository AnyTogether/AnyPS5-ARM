import AnyPS5Core
import AppKit
import SwiftUI

/// The Theme Hub on AnyTogether: the Hub lists the server's themes (the GitHub folder while it
/// has none), "Share on the Hub" uploads the theme with a still of it when signed in, and an
/// anyps5://theme/<ID> link downloads and installs one.
extension AppModel {
    /// Where the Hub is read from, in order.
    var hubBases: [URL] { [ThemeHub.base(onServer: together.base), ThemeHub.defaultBase] }

    /// Uploads the theme; the toast says when it is on the Hub, or why not.
    func shareOnHub(_ design: ThemeDesign) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hub-\(UUID().uuidString.prefix(8))")
            .appendingPathComponent("\(design.name).\(ThemeDesign.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try themes.export(design, to: file)
        } catch {
            return show(T.text(.themeSaveFailed), symbol: "exclamationmark.triangle.fill")
        }
        // The server needs a picture of the theme: its own background, or the animated one drawn now.
        let preview = design.background == nil || design.backgroundIsVideo ? Self.themeStill(design) : nil
        show(TS.format(.hubSharing, design.name), symbol: "arrow.up.circle")
        Task {
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            do {
                let shared = try await together.shareTheme(file, preview: preview)
                show(TS.format(shared.version > 1 ? .hubSharedVersion : .hubShared, shared.name, shared.version), symbol: "checkmark.circle.fill")
                loadHub(again: true)
            } catch {
                show(hubShareMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func hubShareMessage(_ error: Error) -> String {
        guard let problem = error as? TogetherProblem else { return T.text(.togetherUnreachable) }
        switch problem.code {
        case "payload_too_large": return TS.text(.hubTooLarge)
        case "bad_theme", "unsupported_media_type": return TS.text(.hubBadTheme)
        case "preview_required", "bad_image": return TS.text(.hubNoPreview)
        default: return togetherMessage(error)
        }
    }

    /// A 1280x720 PNG of the theme's animated background in its colors.
    static func themeStill(_ design: ThemeDesign) -> Data? {
        guard let image = BackgroundView.still(theme: Theme(rawValue: design.style) ?? .cosmic, palette: design.palette, width: 1280, height: 720, time: 260),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// anyps5://theme/<ID>: the theme is read, downloaded and used.
    func installHubTheme(_ id: String) {
        Task {
            do {
                let found = try await together.hubTheme(id)
                guard let theme = found.hubTheme else { throw URLError(.badURL) }
                installFromHub(theme)
            } catch let problem as TogetherProblem where problem.status == 404 {
                show(TS.text(.hubNoTheme), symbol: "questionmark.circle")
            } catch {
                show(T.text(.themeInstallFailed), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}
