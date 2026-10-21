import Foundation

/// A game's trophies: the list and texts from the trophy packages in the dump's sce_sys/trophy2, and
/// what the engine recorded in the installed game's _trophy folder when the game unlocked them.
public struct TrophySet: Sendable {
    public enum Grade: String, Sendable, CaseIterable {
        case platinum = "P", gold = "G", silver = "S", bronze = "B"

        /// The console's weights: the percentage counts a gold trophy as six bronze ones.
        public var points: Int {
            switch self {
            case .platinum: return 300
            case .gold: return 90
            case .silver: return 30
            case .bronze: return 15
            }
        }
    }

    public struct Trophy: Identifiable, Sendable {
        public var id: String { "\(serviceLabel)/\(number)" }
        public let serviceLabel: Int
        public let number: Int
        public let grade: Grade
        public let hidden: Bool
        public let name: String
        public let detail: String
        public let icon: Data?
        public let unlocked: Date?
        /// The stat a progressive trophy counts, and its target.
        public let progress: (value: UInt64, target: UInt64)?
    }

    public let title: String
    public let icon: Data?
    public let trophies: [Trophy]

    public var unlockedCount: Int { trophies.filter { $0.unlocked != nil }.count }

    public func count(_ grade: Grade) -> (unlocked: Int, total: Int) {
        let graded = trophies.filter { $0.grade == grade }
        return (graded.filter { $0.unlocked != nil }.count, graded.count)
    }

    /// Unlocked points over all points, from 0 to 100.
    public var percent: Int {
        let total = trophies.reduce(0) { $0 + $1.grade.points }
        guard total > 0 else { return 0 }
        let unlocked = trophies.reduce(0) { $0 + ($1.unlocked != nil ? $1.grade.points : 0) }
        return unlocked * 100 / total
    }
}

public enum Trophies {
    static let recordSuffix = ".txt"
    static let statsSuffix = ".stats.txt"
    /// The engine's ticks are microseconds since 1 January of year 1.
    static let unixEpochTick: UInt64 = 62_135_596_800_000_000

    /// The game's trophies in the first of `languages` its packages have, nil when it has none.
    /// `bundle` is the installed game, which holds the unlocks; before the game is unlocked every
    /// trophy shows as locked.
    public static func load(_ game: Game, bundle: URL?, languages: [String]) -> TrophySet? {
        let folder = game.folder.appendingPathComponent("sce_sys/trophy2")
        let records = bundle?.appendingPathComponent("Contents/Resources/game/_trophy")
        var title = game.name
        var setIcon: Data?
        var trophies: [TrophySet.Trophy] = []
        for label in 0..<100 {
            let package = folder.appendingPathComponent(String(format: "trophy%02d.ucp", label))
            guard let data = try? Data(contentsOf: package, options: .mappedIfSafe) else {
                if label == 0 { continue }
                break
            }
            guard let files = readUcp(data), let loaded = parse(files, label: label, languages: languages, records: records) else { continue }
            if label == 0 || trophies.isEmpty {
                title = loaded.title
                setIcon = loaded.icon
            }
            trophies += loaded.trophies
        }
        return trophies.isEmpty ? nil : TrophySet(title: title, icon: setIcon, trophies: trophies)
    }

    /// The trophy package's files: a big-endian table of names, offsets and sizes.
    static func readUcp(_ data: Data) -> [String: Data]? {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ size: Int) -> UInt64? {
            guard offset >= 0, offset + size <= bytes.count else { return nil }
            return bytes[offset..<offset + size].reduce(0) { $0 << 8 | UInt64($1) }
        }
        guard number(0, 4) == 0xB228_C60A, number(4, 4) == 1, let count = number(0x10, 4), let toc = number(0x14, 4), count <= 4096 else { return nil }
        var files: [String: Data] = [:]
        for index in 0..<Int(count) {
            let entry = Int(toc) + 0x20 + index * 0x40
            guard let offset = number(entry + 0x20, 8), let length = number(entry + 0x28, 8),
                  offset + length <= UInt64(bytes.count) else { return nil }
            let field = bytes[entry..<entry + 0x20]
            let name = String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
            files[name] = data.subdata(in: Int(offset)..<Int(offset + length))
        }
        return files
    }

    static func parse(_ files: [String: Data], label: Int, languages: [String], records: URL?) -> TrophySet? {
        guard let conf = json(files["tropconf.json"]), let definitions = conf["trophies"] as? [[String: Any]] else { return nil }
        let fallback = conf["defaultLanguage"] as? String ?? "en-US"
        let candidates = languages + ["en-US", "en-GB", fallback]
        let available = Set(files.keys.filter { $0.hasPrefix("tropmeta_") }.map { String($0.dropFirst(9).dropLast(5)) })
        guard let language = candidates.first(where: available.contains) ?? available.sorted().first,
              let metadata = json(files["tropmeta_\(language).json"])?["metadata"] as? [String: Any] else { return nil }
        var texts: [Int: (name: String, detail: String)] = [:]
        for entry in metadata["trophyMetadata"] as? [[String: Any]] ?? [] {
            guard let id = identifier(entry["id"]) else { continue }
            texts[id] = (entry["name"] as? String ?? "", entry["detail"] as? String ?? "")
        }
        let unlocks = records.map { unlocked(in: $0, label: label) } ?? [:]
        let stats = records.map { statValues(in: $0, label: label) } ?? [:]
        let trophies: [TrophySet.Trophy] = definitions.compactMap { definition in
            guard let id = identifier(definition["id"]), let letter = definition["grade"] as? String, let grade = TrophySet.Grade(rawValue: letter) else { return nil }
            var progress: (UInt64, UInt64)?
            if let condition = definition["unlockCondition"] as? [String: Any], (condition["progressive"] as? Bool) == true,
               let stat = unsigned(condition["udsStatId"]), let target = unsigned(condition["targetValue"]), target > 1 {
                progress = (min(stats[stat] ?? 0, target), target)
            }
            let text = texts[id] ?? ("", "")
            return TrophySet.Trophy(serviceLabel: label, number: id, grade: grade, hidden: (definition["hidden"] as? Bool) == true,
                                    name: text.name, detail: text.detail, icon: files[String(format: "trop%04d.png", id)],
                                    unlocked: unlocks[id], progress: progress)
        }
        let title = (metadata["titleMetadata"] as? [String: Any])?["name"] as? String ?? ""
        let icon = files["icon0_\(language).png"] ?? files["icon0.png"] ?? files.keys.sorted().first { $0.hasPrefix("icon0") }.flatMap { files[$0] }
        return TrophySet(title: title, icon: icon, trophies: trophies)
    }

    /// Every user's unlocks of the package: `<user>_<label>.txt` lines of `<trophy id> <tick>`.
    static func unlocked(in records: URL, label: Int) -> [Int: Date] {
        var result: [Int: Date] = [:]
        for (key, tick) in pairs(in: records, label: label, suffix: recordSuffix) {
            guard let id = Int(exactly: key), tick >= unixEpochTick else { continue }
            let date = Date(timeIntervalSince1970: Double(tick - unixEpochTick) / 1_000_000)
            result[id] = min(result[id] ?? date, date)
        }
        return result
    }

    /// The stats the engine counted for the package: `<user>_<label>.stats.txt` lines of `<stat id> <value>`.
    static func statValues(in records: URL, label: Int) -> [UInt64: UInt64] {
        var result: [UInt64: UInt64] = [:]
        for (key, value) in pairs(in: records, label: label, suffix: statsSuffix) { result[key] = max(result[key] ?? 0, value) }
        return result
    }

    static func pairs(in records: URL, label: Int, suffix: String) -> [(UInt64, UInt64)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: records.path) else { return [] }
        let ending = "_\(label)" + suffix
        var result: [(UInt64, UInt64)] = []
        for name in names where name.hasSuffix(ending) && UInt64(name.dropLast(ending.count)) != nil {
            guard let text = try? String(contentsOf: records.appendingPathComponent(name), encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: " ")
                if parts.count == 2, let key = UInt64(parts[0]), let value = UInt64(parts[1]) { result.append((key, value)) }
            }
        }
        return result
    }

    static func json(_ data: Data?) -> [String: Any]? {
        guard var data else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Ids and stat numbers come as "0007" strings or as plain numbers.
    static func unsigned(_ value: Any?) -> UInt64? {
        if let text = value as? String { return UInt64(text) }
        if let number = value as? NSNumber, number.int64Value >= 0 { return number.uint64Value }
        return nil
    }

    static func identifier(_ value: Any?) -> Int? {
        unsigned(value).flatMap { $0 <= UInt64(Int32.max) ? Int($0) : nil }
    }
}
