import AnyPS5Core
import SwiftUI

/// A tile of Home's row: a game, or a console's folder standing for its games (the first of
/// them is `gameIndex`).
struct HomeTile: Equatable, Identifiable {
    let gameIndex: Int
    let folder: RetroPlatform?
    /// The game's identifier, or the folder's.
    let id: String

    init(gameIndex: Int, folder: RetroPlatform? = nil, game: Game) {
        self.gameIndex = gameIndex
        self.folder = folder
        self.id = folder.map { "folder-\($0.rawValue)" } ?? game.id
    }
}

/// Settings › Emulators › Show as folders, as on Windows and Linux: the games of a console whose
/// emulator is chosen gather in one tile after the other games. Selected, the folder shows its
/// games in a row under it; Down or Select goes into that row, Up or Back comes out of it. With
/// the setting off, or no disc in the library, Home's row is the games as ever.
extension AppModel {
    private func groupsHomePlatform(_ platform: RetroPlatform) -> Bool {
        showsRetroFolders && standaloneEmulator(platform) != nil
    }

    /// The folder whose row of games has the selection.
    var activeHomeRetroFolder: RetroPlatform? {
        guard let folder = homeRetroFolder, selectedGame?.retro?.platform == folder, groupsHomePlatform(folder) else { return nil }
        return folder
    }

    /// The folder the selection is on, closed.
    var selectedHomeFolder: RetroPlatform? {
        guard let platform = selectedGame?.retro?.platform, activeHomeRetroFolder == nil, groupsHomePlatform(platform) else { return nil }
        return platform
    }

    /// The game Home shows the name, art and song of: none while a folder is selected.
    var homePreviewGame: Game? { selectedHomeFolder == nil ? selectedGame : nil }

    /// The folder whose games show in the row under the games', open or not.
    var homeFolderPlatform: RetroPlatform? { activeHomeRetroFolder ?? selectedHomeFolder }

    /// Home's row: the games that are in no folder, then a tile for each console that has one.
    var homeTiles: [HomeTile] {
        var titles: [HomeTile] = []
        var folders: [RetroPlatform: Int] = [:]
        var grouped: [RetroPlatform: Bool] = [:]
        for (index, game) in games.enumerated() {
            if let platform = game.retro?.platform {
                let groups = grouped[platform] ?? groupsHomePlatform(platform)
                grouped[platform] = groups
                if groups {
                    if folders[platform] == nil { folders[platform] = index }
                    continue
                }
            }
            titles.append(HomeTile(gameIndex: index, game: game))
        }
        return titles + RetroPlatform.allCases.compactMap { platform in folders[platform].map { HomeTile(gameIndex: $0, folder: platform, game: games[$0]) } }
    }

    /// The games of the folder shown under Home's row.
    var homeFolderTiles: [HomeTile] {
        guard let folder = homeFolderPlatform else { return [] }
        return games.enumerated().compactMap { index, game in game.retro?.platform == folder ? HomeTile(gameIndex: index, game: game) : nil }
    }

    /// Where the selection is in `tiles`: the selected game, or in Home's row the folder it is in.
    func homeTileIndex(_ tiles: [HomeTile], folderContents: Bool = false) -> Int {
        let folder = folderContents ? nil : homeFolderPlatform
        return tiles.firstIndex { tile in folder == nil ? tile.gameIndex == selected : tile.folder == folder } ?? 0
    }

    func setShowRetroFolders(_ enabled: Bool) {
        guard showsRetroFolders != enabled else { return }
        preferences.showRetroFolders = enabled ? true : nil
        if homeRetroFolder != nil { homeRetroFolder = nil }
        if selectedHomeFolder != nil { focus = .tiles }
    }

    /// A click on a tile of either row.
    func selectHomeTile(_ index: Int, folderContents: Bool = false) {
        let tiles = folderContents ? homeFolderTiles : homeTiles
        guard tiles.indices.contains(index) else { return }
        if homeTileIndex(tiles, folderContents: folderContents) != index { Sounds.shared.play(.move) }
        setHomeAnchor(tiles[index], folderContents: folderContents, keepFocus: false)
    }

    /// Left and right on Home: through the row that has the selection (`folderContents` names
    /// one, for a scroll over it).
    func moveHomeSelection(_ delta: Int, folderContents: Bool? = nil) {
        guard showsRetroFolders else { return moveSelection(delta) }
        let contents = folderContents ?? (activeHomeRetroFolder != nil)
        let tiles = contents ? homeFolderTiles : homeTiles
        guard !tiles.isEmpty else { return }
        let current = homeTileIndex(tiles, folderContents: contents)
        let next = min(tiles.count - 1, max(0, current + delta))
        guard next != current else { return }
        Sounds.shared.play(.move)
        setHomeAnchor(tiles[next], folderContents: contents, keepFocus: true)
    }

    private func setHomeAnchor(_ tile: HomeTile, folderContents: Bool, keepFocus: Bool) {
        let folder = homeFolderPlatform
        anchoringHome = true
        defer { anchoringHome = false }
        let open = folderContents ? folder : nil
        if homeRetroFolder != open { homeRetroFolder = open }
        if folderContents || tile.folder == nil || tile.folder != folder, selected != tile.gameIndex { selected = tile.gameIndex }
        if !keepFocus || tile.folder != nil, focus != .tiles { focus = .tiles }
        if case .actions(let index) = focus, index >= actionCount { focus = .actions(actionCount - 1) }
        if tile.folder == nil { measureSelected() }
    }

    /// Down or Select on a folder: into its row of games. False when the selection is on no folder.
    @discardableResult
    func openSelectedHomeFolder() -> Bool {
        guard let folder = selectedHomeFolder else { return false }
        homeRetroFolder = folder
        focus = .tiles
        Sounds.shared.play(.select)
        measureSelected()
        return true
    }

    /// Up or Back in a folder's row: back to the folder's tile. False when no folder is open.
    @discardableResult
    func closeHomeFolder() -> Bool {
        guard activeHomeRetroFolder != nil else { return false }
        homeRetroFolder = nil
        focus = .tiles
        Sounds.shared.play(.back)
        return true
    }
}

/// A console's folder on Home: the console's name over a disc's rings, on the surface the game
/// tiles without art have, and a mark that its games are under it.
struct RetroFolderTile: View {
    let console: RetroPlatform
    let size: CGFloat
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.look) private var look

    var body: some View {
        let radius = size * 0.12
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.08))
            // A disc behind the name: rings in the theme's accent, fading toward the rim.
            ForEach(0..<4, id: \.self) { ring in
                Circle()
                    .strokeBorder(model.accent.opacity(0.34 - Double(ring) * 0.07), lineWidth: max(1, size * 0.012))
                    .frame(width: size * (0.36 + CGFloat(ring) * 0.26), height: size * (0.36 + CGFloat(ring) * 0.26))
                    .offset(x: size * 0.26, y: size * 0.22)
            }
            Text(console.label)
                .font(.display(size * 0.24, .semibold))
                .tracking(size * 0.008)
                .foregroundStyle(model.accent)
                .offset(y: -size * 0.06)
            Image(systemName: "chevron.down")
                .font(.system(size: size * 0.11, weight: .semibold))
                .foregroundStyle(model.accent)
                .offset(y: size * 0.33)
            if look.glass {
                LinearGradient(stops: [.init(color: .white.opacity(focused ? 0.2 : 0.12), location: 0), .init(color: .white.opacity(0), location: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
                IceRim(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), strength: focused ? 0.9 : 0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: look.glass ? Ice.scrim.opacity(0.7) : .black.opacity(0.45), radius: focused ? 22 * scale : 10 * scale, y: 8 * scale)
        .focusRing(focused, radius: radius)
        .animation(Motion.focus, value: focused)
        .animation(Motion.layout, value: size)
        .accessibilityLabel(TRetro.format(.retroGames, console.label))
    }
}
