import Foundation

/// What an Unreal Engine game does with each pad button, from its own input settings
/// (DefaultInput.ini and the platform's file after it, in the game's pak): the action and axis
/// mappings that name a gamepad key. Games that keep their controls only in Enhanced Input
/// assets, or whose pak is encrypted, say nothing.
public enum UnrealControls {
    static let section = "[/Script/Engine.InputSettings]"

    /// The game's actions by pad button, nil when its files say nothing readable.
    public static func read(game folder: URL) -> [PadAction: [String]]? {
        for url in paks(in: folder) {
            guard let pak = try? UnrealPak(url: url) else { continue }
            let projectFiles = pak.paths.filter { !$0.lowercased().hasPrefix("engine/") }
            // The project's file, then its platform files, which change it.
            let defaults = projectFiles.filter { $0.lowercased().hasSuffix("/config/defaultinput.ini") }.sorted { $0.count < $1.count }
            guard let main = defaults.first else { continue }
            let platform = projectFiles.filter { path in
                let lower = path.lowercased()
                return lower.hasSuffix("input.ini") && lower.contains("/config/") && !defaults.contains(path) && (lower.contains("/ps5/") || lower.contains("ps5input"))
            }.sorted()
            let texts = ([main] + platform).compactMap { try? pak.file($0) }.map { String(decoding: $0, as: UTF8.self) }
            let controls = parse(texts)
            return controls.isEmpty ? nil : controls
        }
        return nil
    }

    /// The game's .pak files, the first chunk first (it holds the config).
    static func paks(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if walker.level > 6 { walker.skipDescendants() }
            if url.pathExtension.lowercased() == "pak" { found.append(url) }
        }
        func rank(_ url: URL) -> Int {
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix("pakchunk0-") || name.hasPrefix("pakchunk0_") ? 0 : name.contains("pakchunk0") ? 1 : 2
        }
        return found.sorted { (rank($0), $0.lastPathComponent) < (rank($1), $1.lastPathComponent) }
    }

    /// The mappings in `files`, later files changing earlier ones.
    static func parse(_ files: [String]) -> [PadAction: [String]] {
        var actions: [(name: String, key: String)] = []
        var axes: [(name: String, key: String)] = []
        for text in files {
            var inSection = false
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") {
                    inSection = line == section
                    continue
                }
                guard inSection, let first = line.first, "+-!".contains(first) || line.hasPrefix("ActionMappings") || line.hasPrefix("AxisMappings") else { continue }
                let body = "+-!".contains(first) ? String(line.dropFirst()) : line
                let isAction = body.hasPrefix("ActionMappings=")
                guard isAction || body.hasPrefix("AxisMappings=") else { continue }
                if first == "!" {
                    if isAction { actions = [] } else { axes = [] }
                    continue
                }
                guard let name = field(isAction ? "ActionName" : "AxisName", in: body), let key = field("Key", in: body) else { continue }
                let mapping = (name: name, key: key)
                if first == "-" {
                    if isAction { actions.removeAll { $0 == mapping } } else { axes.removeAll { $0 == mapping } }
                } else if isAction {
                    if !actions.contains(where: { $0 == mapping }) { actions.append(mapping) }
                } else if !axes.contains(where: { $0 == mapping }) {
                    axes.append(mapping)
                }
            }
        }
        var controls: [PadAction: [String]] = [:]
        for mapping in actions + axes {
            let shown = title(mapping.name)
            for action in buttons(for: mapping.key) where !(controls[action]?.contains(shown) ?? false) {
                controls[action, default: []].append(shown)
            }
        }
        return controls
    }

    /// A value in `(Name="Value",Key=Gamepad_X)`, quoted or not.
    static func field(_ name: String, in body: String) -> String? {
        guard let range = body.range(of: "\(name)=") else { return nil }
        var rest = body[range.upperBound...]
        if rest.first == "\"" {
            rest = rest.dropFirst()
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
        let end = rest.firstIndex { $0 == "," || $0 == ")" } ?? rest.endIndex
        return String(rest[..<end])
    }

    /// The pad buttons an Unreal gamepad key is; a stick axis is both its directions.
    static func buttons(for key: String) -> [PadAction] {
        switch key.lowercased() {
        case "gamepad_facebutton_bottom": return [.cross]
        case "gamepad_facebutton_right": return [.circle]
        case "gamepad_facebutton_left": return [.square]
        case "gamepad_facebutton_top": return [.triangle]
        case "gamepad_leftshoulder": return [.l1]
        case "gamepad_rightshoulder": return [.r1]
        case "gamepad_lefttrigger", "gamepad_lefttriggeraxis": return [.l2]
        case "gamepad_righttrigger", "gamepad_righttriggeraxis": return [.r2]
        case "gamepad_leftthumbstick": return [.l3]
        case "gamepad_rightthumbstick": return [.r3]
        case "gamepad_special_right": return [.options]
        case "gamepad_special_left": return [.touchLeft]
        case "gamepad_dpad_up": return [.up]
        case "gamepad_dpad_down": return [.down]
        case "gamepad_dpad_left": return [.left]
        case "gamepad_dpad_right": return [.right]
        case "gamepad_leftstick_up": return [.leftStickUp]
        case "gamepad_leftstick_down": return [.leftStickDown]
        case "gamepad_leftstick_left": return [.leftStickLeft]
        case "gamepad_leftstick_right": return [.leftStickRight]
        case "gamepad_rightstick_up": return [.rightStickUp]
        case "gamepad_rightstick_down": return [.rightStickDown]
        case "gamepad_rightstick_left": return [.rightStickLeft]
        case "gamepad_rightstick_right": return [.rightStickRight]
        case "gamepad_lefty": return [.leftStickUp, .leftStickDown]
        case "gamepad_leftx": return [.leftStickLeft, .leftStickRight]
        case "gamepad_righty": return [.rightStickUp, .rightStickDown]
        case "gamepad_rightx": return [.rightStickLeft, .rightStickRight]
        default: return []
        }
    }

    /// "Interact_Primary" and "IA_OpenMenu" read as "Interact primary" and "Open menu".
    static func title(_ name: String) -> String {
        var name = name
        for prefix in ["IA_", "Action_", "Axis_", "Input_"] where name.hasPrefix(prefix) && name.count > prefix.count { name.removeFirst(prefix.count) }
        var words: [String] = []
        var word = ""
        var previous: Character?
        for character in name {
            if character == "_" || character == " " {
                if !word.isEmpty { words.append(word) }
                word = ""
            } else if character.isUppercase, let previous, previous.isLowercase || previous.isNumber {
                words.append(word)
                word = String(character)
            } else {
                word.append(character)
            }
            previous = character
        }
        if !word.isEmpty { words.append(word) }
        return words.enumerated().map { index, word in
            // Short all-capital words (UI, HUD) stay as they are.
            if word.count > 1, word == word.uppercased() { return word }
            return index == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word.lowercased()
        }.joined(separator: " ")
    }
}
