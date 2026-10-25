import Foundation

/// The console's system font sets a game opens (sceFontOpenFontSet) and the files the engine
/// looks for in ANYPS5_SYSTEM_FONTS for them, as core/libs/prx/libSceFont/src/SystemFont.cpp
/// maps them: the console's own file first, else an openly licensed Noto substitute.
public enum FontScript: String, CaseIterable, Codable, Sendable {
    case latin, latinItalic, typewriter, vietnamese, thai, japanese, chinese, korean, arabic

    /// The console's files, by weight (light, regular, medium, bold).
    public var consoleFiles: [String] {
        switch self {
        case .latin: return ["SST-Light.otf", "SST-Roman.otf", "SST-Medium.otf", "SST-Bold.otf"]
        case .latinItalic: return ["SST-LightItalic.otf", "SST-Italic.otf", "SST-MediumItalic.otf", "SST-BoldItalic.otf"]
        case .typewriter: return ["SSTTypewriter-Roman.otf", "SSTTypewriter-Roman.otf", "SSTTypewriter-Roman.otf", "SSTTypewriter-Bd.otf"]
        case .vietnamese: return ["SSTVietnamese-Light.otf", "SSTVietnamese-Roman.otf", "SSTVietnamese-Medium.otf", "SSTVietnamese-Bold.otf"]
        case .thai: return ["SSTThai-Light.otf", "SSTThai-Roman.otf", "SSTThai-Medium.otf", "SSTThai-Bold.otf"]
        case .japanese: return ["SSTJpPro-Regular.otf", "SSTJpPro-Regular.otf", "SSTJpPro-Regular.otf", "SSTJpPro-Bold.otf"]
        case .chinese: return Array(repeating: "DFHEI5-SONY.ttf", count: 4)
        case .korean: return ["SCEPS4Yoongd-Medium.otf", "SCEPS4Yoongd-Medium.otf", "SCEPS4Yoongd-Medium.otf", "SCEPS4Yoongd-Bold.otf"]
        case .arabic: return ["SSTArabic-Light.otf", "SSTArabic-Roman.otf", "SSTArabic-Medium.otf", "SSTArabic-Bold.otf"]
        }
    }

    /// The Noto files the engine takes in place of the console's, by weight.
    public var notoFiles: [String] {
        let weights = ["Light", "Regular", "Medium", "Bold"]
        switch self {
        case .latin, .vietnamese: return weights.map { "NotoSans-\($0).ttf" }
        case .latinItalic: return ["NotoSans-LightItalic.ttf", "NotoSans-Italic.ttf", "NotoSans-MediumItalic.ttf", "NotoSans-BoldItalic.ttf"]
        case .typewriter: return weights.map { "NotoSansMono-\($0).ttf" }
        case .thai: return weights.map { "NotoSansThai-\($0).ttf" }
        case .japanese, .chinese, .korean: return weights.map { "NotoSansCJK-\($0).ttc" }
        case .arabic: return weights.map { "NotoSansArabic-\($0).ttf" }
        }
    }

    /// Japanese, Chinese and Korean: the large fonts the launcher downloads when a game needs them.
    public var isCJK: Bool { self == .japanese || self == .chinese || self == .korean }
}

public enum SystemFontSet {
    /// Every font set type the console has (SystemFont.cpp's SYSTEM_FONT_SET_TYPES).
    public static let types: Set<UInt32> = [
        0x18070043, 0x18070044, 0x18070045, 0x18070047, 0x18070053, 0x18070054,
        0x18070055, 0x18070057, 0x180700C3, 0x180700C4, 0x180700C5, 0x180700C7,
        0x18070444, 0x18070447, 0x18070454, 0x18070457, 0x180704C4, 0x180704C7,
        0x18071053, 0x18071054, 0x18071055, 0x18071057, 0x18071454, 0x18071457,
        0x18072444, 0x18072447, 0x180724C4, 0x180724C7, 0x18073454, 0x18073457,
        0x180734D4, 0x180734D7, 0x18078044, 0x180780C4, 0x18079054, 0x1807A044,
        0x1807A0C4, 0x1807A444, 0x1807A4C4, 0x1807AC44, 0x1807ACC4, 0x1807B054,
        0x1807B0D4, 0x1807B454, 0x1807B4D4, 0x1807BC54, 0x1807BCD4, 0x18080444,
        0x18080447, 0x18080454, 0x18080457, 0x180804C4, 0x180804C7, 0x18081454,
        0x18081457, 0x18082444, 0x18082447, 0x180824C4, 0x180824C7, 0x18083454,
        0x18083457, 0x180834D4, 0x180834D7, 0x1808A444, 0x1808A4C4, 0x1808B454,
        0x1808B4D4, 0x180C8044, 0x180C80C4, 0x180C9054, 0x180CA044, 0x180CA0C4,
        0x180CAC44, 0x180CACC4, 0x180CB054, 0x180CB0D4, 0x180CBC54, 0x180CBCD4,
        0x18170043, 0x18170044, 0x18170045, 0x18170047, 0x18170444, 0x18170447,
        0x18370044, 0x18370047, 0x18370444, 0x18370447, 0x1A070543, 0x1A070547,
        0x1A070553, 0x1A070557, 0x1A0705C3, 0x1A0705C7, 0x1A071553, 0x1A071557,
        0x1A072543, 0x1A072547, 0x1A0725C3, 0x1A0725C7, 0x1A073553, 0x1A073557,
        0x1A0735D3, 0x1A0735D7, 0x1A080543, 0x1A080547, 0x1A080553, 0x1A080557,
        0x1A0805C3, 0x1A0805C7, 0x1A081553, 0x1A081557, 0x1A082543, 0x1A082547,
        0x1A0825C3, 0x1A0825C7, 0x1A083553, 0x1A083557, 0x1A0835D3, 0x1A0835D7,
    ]

    /// The script whose file a set opens first (SystemFont.cpp's FamilyOf).
    public static func primary(_ type: UInt32) -> FontScript {
        let region = (type >> 16) & 0xFF
        let scripts = (type >> 8) & 0xFE
        let vietnamese = type & 0x10 != 0
        switch region {
        case 0x17: return .latinItalic
        case 0x37: return .typewriter
        case 0x08: return scripts == 0x04 && vietnamese ? .vietnamese : .japanese
        case 0x0C: return .chinese
        default:
            if scripts == 0x10 { return .thai }
            if scripts == 0 && vietnamese { return .vietnamese }
            return .latin
        }
    }

    /// Every script a set opens: its own first, then those it falls back on for the characters
    /// its own file lacks (FallbackFamilies). Empty for a type the console does not have.
    public static func scripts(_ type: UInt32) -> [FontScript] {
        guard types.contains(type) else { return [] }
        let scripts = (type >> 8) & 0xFF
        var found = [primary(type)]
        func add(_ wanted: Bool, _ script: FontScript) {
            if wanted && !found.contains(script) { found.append(script) }
        }
        add(type & 0x10 != 0, .vietnamese)
        add(scripts & 0x10 != 0, .thai)
        add(scripts & 0x88 == 0x88, .chinese)
        add(scripts & 0x04 != 0, .japanese)
        add(scripts & 0x80 != 0, .chinese)
        add(scripts & 0x20 != 0, .korean)
        add(type & 0x80 != 0, .arabic)
        return found
    }

    /// The font sets a game opened, from its log: the engine writes `fontSetType=0x…` for each
    /// sceFontOpenFontSet, whether a file was found for it or not.
    public static func opened(inLog log: String) -> Set<UInt32> {
        var found: Set<UInt32> = []
        var rest = log[...]
        while let range = rest.range(of: "fontSetType=0x") {
            let digits = rest[range.upperBound...].prefix(8)
            if digits.count == 8, let type = UInt32(digits, radix: 16) { found.insert(type) }
            rest = rest[range.upperBound...]
        }
        return found
    }

    /// The scripts the sets in a log need.
    public static func scripts(inLog log: String) -> Set<FontScript> {
        Set(opened(inLog: log).flatMap(scripts))
    }
}

/// Where the fonts a game gets come from, and the folder that puts them together for the engine,
/// which reads one folder (ANYPS5_SYSTEM_FONTS).
///
/// The user's own folder comes first: its files win over the launcher's of the same name, and the
/// engine takes the console's files (SST-Roman.otf, …) over any Noto substitute anyway. The
/// downloaded Japanese, Chinese and Korean fonts come next, then the fonts inside the app.
public struct SystemFonts: Sendable {
    public enum Source: String, Sendable { case user, downloaded, builtIn }

    /// One script as games get it now: the file, and where it comes from.
    public struct Pick: Equatable, Sendable {
        public let file: String
        public let source: Source
        /// The console's own font rather than a Noto substitute.
        public var isConsole: Bool { !file.hasPrefix("Noto") }
    }

    public static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    public var user: URL?
    public var downloaded: URL?
    public var builtIn: URL?

    public init(user: URL?, downloaded: URL?, builtIn: URL?) {
        self.user = user
        self.downloaded = downloaded
        self.builtIn = builtIn
    }

    /// The fonts inside the app (Contents/Resources/fonts), or ANYPS5_LAUNCHER_FONTS for a
    /// launcher run from its build folder.
    public static func locateBuiltIn(environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main) -> URL? {
        var candidates: [URL] = []
        if let path = environment["ANYPS5_LAUNCHER_FONTS"], !path.isEmpty { candidates.append(URL(fileURLWithPath: path)) }
        if let resources = bundle.resourceURL { candidates.append(resources.appendingPathComponent("fonts")) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("NotoSans-Regular.ttf").path) }
    }

    var layers: [(Source, URL)] {
        [(Source.user, user), (.downloaded, downloaded), (.builtIn, builtIn)].compactMap { source, folder in folder.map { (source, $0) } }
    }

    /// The font files in a folder, by name.
    static func fonts(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { name in
            guard extensions.contains((name as NSString).pathExtension.lowercased()), !name.hasPrefix(".") else { return false }
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path, isDirectory: &directory) && !directory.boolValue
        }.sorted()
    }

    /// Each font file games get, by name: the first folder that has it.
    public func files() -> [String: (source: Source, url: URL)] {
        var chosen: [String: (source: Source, url: URL)] = [:]
        for (source, folder) in layers {
            for name in SystemFonts.fonts(in: folder) where chosen[name] == nil {
                chosen[name] = (source, folder.appendingPathComponent(name))
            }
        }
        return chosen
    }

    /// The file the engine opens for a script at regular weight, as it searches: the console's
    /// file, then the Noto one. nil when games get nothing for it.
    public func pick(_ script: FontScript, weight: Int = 1) -> Pick? {
        let files = files()
        for name in [script.consoleFiles[weight], script.notoFiles[weight]] {
            if let found = files[name] { return Pick(file: name, source: found.source) }
        }
        return nil
    }

    /// Puts every font together in `folder` as links to the files they stand for. Links that
    /// already point right stay, so a game running from the folder can be given fonts that came
    /// in after it started (the engine opens a font set only when the game asks for it). Returns
    /// nil, and leaves no folder, when there are no fonts at all: the engine then looks beside
    /// the game as it always did.
    @discardableResult
    public func assemble(in folder: URL) throws -> URL? {
        let fileManager = FileManager.default
        let files = files()
        guard !files.isEmpty else {
            if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
            return nil
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let link = folder.appendingPathComponent(name)
            let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path)
            if target == nil || target != files[name]?.url.path { try fileManager.removeItem(at: link) }
        }
        for (name, found) in files where (try? fileManager.destinationOfSymbolicLink(atPath: folder.appendingPathComponent(name).path)) == nil {
            try fileManager.createSymbolicLink(atPath: folder.appendingPathComponent(name).path, withDestinationPath: found.url.path)
        }
        return folder
    }
}
