import AnyPS5Core
import Foundation

/// The texts of Settings → Game Presets, in both languages; kept apart from `T` like `TPrep`.
enum TPresets {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    enum Key: String, CaseIterable {
        case title = "presetsTitle", intro = "presetsIntro", gameDefault = "presetGameDefault", difficulty = "presetDifficulty", easiest = "presetEasiest", easy = "presetEasy", normal = "presetNormal", hard = "presetHard", hardest = "presetHardest"
        case priority = "presetPriority", priorityDetail = "presetPriorityDetail", performance = "presetPerformance", resolution = "presetResolution"
        case invertVerticalFirst = "presetInvertVerticalFirst", invertHorizontalFirst = "presetInvertHorizontalFirst", invertVerticalThird = "presetInvertVerticalThird", invertHorizontalThird = "presetInvertHorizontalThird"
        case subtitles = "presetSubtitles", show = "presetShow", hide = "presetHide", audioLanguage = "presetAudioLanguage", reset = "presetsReset"
    }

    static let english: [Key: String] = [
        .title: "Game Presets",
        .intro: "Games that support Game Presets start with these settings. A game that keeps its own settings uses those once you change them in it.",
        .gameDefault: "Game Default",
        .difficulty: "Difficulty",
        .easiest: "Easiest", .easy: "Easy", .normal: "Normal", .hard: "Hard", .hardest: "Hardest",
        .priority: "Performance Mode or Resolution Mode",
        .priorityDetail: "Favour a higher frame rate, or a sharper picture",
        .performance: "Performance Mode", .resolution: "Resolution Mode",
        .invertVerticalFirst: "Invert Vertical View · First-Person",
        .invertHorizontalFirst: "Invert Horizontal View · First-Person",
        .invertVerticalThird: "Invert Vertical View · Third-Person",
        .invertHorizontalThird: "Invert Horizontal View · Third-Person",
        .subtitles: "Subtitles", .show: "Show", .hide: "Hide",
        .audioLanguage: "Audio Language",
        .reset: "Reset Game Presets",
    ]

    static let turkish: [Key: String] = [
        .title: "Oyun Ön Ayarları",
        .intro: "Oyun Ön Ayarları'nı destekleyen oyunlar bu ayarlarla başlar. Kendi ayarlarını saklayan bir oyun, onları oyunda değiştirdiğinde kendininkileri kullanır.",
        .gameDefault: "Oyunun Varsayılanı",
        .difficulty: "Zorluk",
        .easiest: "En Kolay", .easy: "Kolay", .normal: "Normal", .hard: "Zor", .hardest: "En Zor",
        .priority: "Performans Modu ya da Çözünürlük Modu",
        .priorityDetail: "Daha yüksek kare hızı ya da daha keskin görüntü",
        .performance: "Performans Modu", .resolution: "Çözünürlük Modu",
        .invertVerticalFirst: "Dikey Bakışı Ters Çevir · Birinci Şahıs",
        .invertHorizontalFirst: "Yatay Bakışı Ters Çevir · Birinci Şahıs",
        .invertVerticalThird: "Dikey Bakışı Ters Çevir · Üçüncü Şahıs",
        .invertHorizontalThird: "Yatay Bakışı Ters Çevir · Üçüncü Şahıs",
        .subtitles: "Altyazılar", .show: "Göster", .hide: "Gizle",
        .audioLanguage: "Ses Dili",
        .reset: "Oyun Ön Ayarlarını Sıfırla",
    ]
}

extension AppModel {
    /// Settings → Game Presets: one set for every game (GamePresets).
    func gamePresetRows() -> [PanelRow] {
        let presets = gamePresets
        let difficulties = GamePresets.Difficulty.allCases
        let difficultyNames: [TPresets.Key] = [.gameDefault, .easiest, .easy, .normal, .hard, .hardest]
        let priorities = GamePresets.Priority.allCases
        let priorityNames: [TPresets.Key] = [.gameDefault, .performance, .resolution]
        let subtitles = GamePresets.Subtitles.allCases
        let subtitleNames: [TPresets.Key] = [.gameDefault, .show, .hide]
        let languages = ConsoleLanguage.all
        func toggle(_ id: String, _ title: TPresets.Key, _ symbol: String, _ path: WritableKeyPath<GamePresets, Bool>) -> PanelRow {
            PanelRow(id: id, title: TPresets.text(title), symbol: symbol, kind: .toggle(presets[keyPath: path]) { [weak self] value in self?.gamePresets[keyPath: path] = value })
        }
        var rows = [
            PanelRow(id: "presetsIntro", title: TPresets.text(.intro), kind: .info("")),
            PanelRow(id: "difficulty", title: TPresets.text(.difficulty), symbol: "flame",
                     kind: .choice(options: difficultyNames.map(TPresets.text), selected: difficulties.firstIndex(of: presets.difficulty) ?? 0) { [weak self] index in
                         self?.gamePresets.difficulty = difficulties[index]
                     }),
            PanelRow(id: "priority", title: TPresets.text(.priority), detail: TPresets.text(.priorityDetail), symbol: "speedometer",
                     kind: .choice(options: priorityNames.map(TPresets.text), selected: priorities.firstIndex(of: presets.priority) ?? 0) { [weak self] index in
                         self?.gamePresets.priority = priorities[index]
                     }),
            toggle("invertVerticalFirst", .invertVerticalFirst, "arrow.up.arrow.down", \.invertVerticalFirstPerson),
            toggle("invertHorizontalFirst", .invertHorizontalFirst, "arrow.left.arrow.right", \.invertHorizontalFirstPerson),
            toggle("invertVerticalThird", .invertVerticalThird, "arrow.up.arrow.down", \.invertVerticalThirdPerson),
            toggle("invertHorizontalThird", .invertHorizontalThird, "arrow.left.arrow.right", \.invertHorizontalThirdPerson),
            PanelRow(id: "subtitles", title: TPresets.text(.subtitles), symbol: "captions.bubble",
                     kind: .choice(options: subtitleNames.map(TPresets.text), selected: subtitles.firstIndex(of: presets.subtitles) ?? 0) { [weak self] index in
                         self?.gamePresets.subtitles = subtitles[index]
                     }),
            PanelRow(id: "audioLanguage", title: TPresets.text(.audioLanguage), symbol: "waveform",
                     kind: .choice(options: [TPresets.text(.gameDefault)] + languages.map(\.name),
                                   selected: presets.audioLanguage.flatMap { number in languages.firstIndex { $0.number == number }.map { $0 + 1 } } ?? 0) { [weak self] index in
                         self?.gamePresets.audioLanguage = index == 0 ? nil : languages[index - 1].number
                     }),
        ]
        if !presets.isEmpty {
            rows.append(PanelRow(id: "presetsReset", title: TPresets.text(.reset), symbol: "arrow.counterclockwise", kind: .action(destructive: false) { [weak self] in
                self?.gamePresets = GamePresets()
            }))
        }
        return rows
    }
}
