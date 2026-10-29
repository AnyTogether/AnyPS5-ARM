import Foundation

/// The texts of Settings → Battery & Heat, the quick menu's power line and the heat note over a
/// game, in both languages; kept apart from `T` like `TF`.
enum TPow {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case title = "powerTitle", intro = "powerIntro", pluggedIn = "powerPluggedIn", onBattery = "powerOnBattery", onBatteryPercent = "powerOnBatteryPercent", noBattery = "powerNoBattery", timeLeft = "powerTimeLeft", estimating = "powerEstimating", hoursMinutes = "powerHoursMinutes", minutes = "powerMinutes"
        case thermalNominal = "powerThermalNominal", thermalFair = "powerThermalFair", thermalSerious = "powerThermalSerious", thermalCritical = "powerThermalCritical", lowPowerMode = "powerLowPowerMode"
        case profileNone = "powerProfileNone", profileBattery = "powerProfileBattery", profileHot = "powerProfileHot", profileUndone = "powerProfileUndone", capSummary = "powerCapSummary", inForce = "powerInForce", inForceNothing = "powerInForceNothing"
        case sectionBattery = "powerSectionBattery", sectionHot = "powerSectionHot", batteryProfile = "powerBatteryProfile", batteryProfileDetail = "powerBatteryProfileDetail", hotProfile = "powerHotProfile", hotProfileDetail = "powerHotProfileDetail"
        case frameCap = "powerFrameCap", frameCapDetail = "powerFrameCapDetail", fps = "powerFps", lowerResolution = "powerLowerResolution", lowerResolutionDetail = "powerLowerResolutionDetail", pauseFrameGeneration = "powerPauseFrameGeneration", pauseFrameGenerationDetail = "powerPauseFrameGenerationDetail"
        case dimEffects = "powerDimEffects", dimEffectsDetail = "powerDimEffectsDetail", undo = "powerUndo", undoDetail = "powerUndoDetail", undone = "powerUndone"
        case hotTitle = "powerHotTitle", hotLowered = "powerHotLowered", hotEased = "powerHotEased", hotDetail = "powerHotDetail", quickUndoHot = "powerQuickUndoHot", quickUndoBattery = "powerQuickUndoBattery", quickUndoDetail = "powerQuickUndoDetail"
    }

    static let english: [Key: String] = [
        .title: "Battery & Heat",
        .intro: "What a MacBook on battery, or a Mac running hot, does to the game you play. Plugged in and cool, nothing changes.",
        .pluggedIn: "Plugged in",
        .onBattery: "On battery",
        .onBatteryPercent: "On battery · %d%%",
        .noBattery: "No battery: only the heat profile applies",
        .timeLeft: "about %@ left",
        .estimating: "working out the time left",
        .hoursMinutes: "%d h %d min",
        .minutes: "%d min",
        .thermalNominal: "Temperature: normal",
        .thermalFair: "Temperature: warm",
        .thermalSerious: "Temperature: hot",
        .thermalCritical: "Temperature: very hot",
        .lowPowerMode: "Low Power Mode is on, so the battery profile holds",
        .profileNone: "No change",
        .profileBattery: "Battery profile",
        .profileHot: "Heat profile",
        .profileUndone: "%@ undone",
        .capSummary: "%d FPS cap",
        .inForce: "In force now: %@",
        .inForceNothing: "Games run as you set them",
        .sectionBattery: "On battery",
        .sectionHot: "When hot",
        .batteryProfile: "Battery Profile",
        .batteryProfileDetail: "On battery or in Low Power Mode, for more play time and a quieter Mac",
        .hotProfile: "Heat Profile",
        .hotProfileDetail: "When macOS says the Mac is hot. A note shows over the game, with Undo in the quick menu",
        .frameCap: "Frame Rate Cap",
        .frameCapDetail: "Changes at once, during a game too",
        .fps: "%d FPS",
        .lowerResolution: "Lower Resolution",
        .lowerResolutionDetail: "Games with a resolution option start one step lower. Applies next launch",
        .pauseFrameGeneration: "Pause Frame Generation",
        .pauseFrameGenerationDetail: "Changes at once, for games started with frame generation on",
        .dimEffects: "Lighter Launcher",
        .dimEffectsDetail: "Turns down the Glass blur and the animations",
        .undo: "Undo for Now",
        .undoDetail: "Back to your settings until the Mac cools down or the power source changes",
        .undone: "Back to your settings",
        .hotTitle: "Your Mac is hot",
        .hotLowered: "AnyPS5 lowered the frame rate",
        .hotEased: "AnyPS5 eased the load",
        .hotDetail: "%@. To undo: PS › Quick Menu",
        .quickUndoHot: "Undo Heat Profile",
        .quickUndoBattery: "Undo Battery Profile",
        .quickUndoDetail: "Back to your settings for now",
    ]

    static let turkish: [Key: String] = [
        .title: "Pil ve Isı",
        .intro: "Pildeki bir MacBook'un ya da ısınan bir Mac'in oynadığın oyuna yaptığı. Prizde ve serinken hiçbir şey değişmez.",
        .pluggedIn: "Prize takılı",
        .onBattery: "Pilde",
        .onBatteryPercent: "Pilde · %%%d",
        .noBattery: "Pil yok: yalnızca ısı profili geçerli",
        .timeLeft: "yaklaşık %@ kaldı",
        .estimating: "kalan süre hesaplanıyor",
        .hoursMinutes: "%d sa %d dk",
        .minutes: "%d dk",
        .thermalNominal: "Sıcaklık: normal",
        .thermalFair: "Sıcaklık: ılık",
        .thermalSerious: "Sıcaklık: sıcak",
        .thermalCritical: "Sıcaklık: çok sıcak",
        .lowPowerMode: "Düşük Güç Modu açık, bu yüzden pil profili geçerli",
        .profileNone: "Değişiklik yok",
        .profileBattery: "Pil profili",
        .profileHot: "Isı profili",
        .profileUndone: "%@ geri alındı",
        .capSummary: "%d FPS sınırı",
        .inForce: "Şu an geçerli: %@",
        .inForceNothing: "Oyunlar senin ayarladığın gibi çalışır",
        .sectionBattery: "Pildeyken",
        .sectionHot: "Isınınca",
        .batteryProfile: "Pil Profili",
        .batteryProfileDetail: "Pilde ya da Düşük Güç Modu'nda: daha uzun oyun, daha sessiz bir Mac",
        .hotProfile: "Isı Profili",
        .hotProfileDetail: "macOS Mac'in ısındığını söyleyince. Oyunun üstünde bir not çıkar, Hızlı Menü'den geri alınır",
        .frameCap: "Kare Hızı Sınırı",
        .frameCapDetail: "Hemen değişir, oyun sırasında da",
        .fps: "%d FPS",
        .lowerResolution: "Daha Düşük Çözünürlük",
        .lowerResolutionDetail: "Çözünürlük seçeneği olan oyunlar bir adım düşük başlar. Bir sonraki açılışta geçerli",
        .pauseFrameGeneration: "Ara Kareyi Duraklat",
        .pauseFrameGenerationDetail: "Hemen değişir; ara kare açık başlatılan oyunlarda",
        .dimEffects: "Hafif Başlatıcı",
        .dimEffectsDetail: "Cam bulanıklığını ve animasyonları azaltır",
        .undo: "Şimdilik Geri Al",
        .undoDetail: "Mac soğuyana ya da güç kaynağı değişene kadar senin ayarların",
        .undone: "Ayarlarına dönüldü",
        .hotTitle: "Mac'in ısındı",
        .hotLowered: "AnyPS5 kare hızını düşürdü",
        .hotEased: "AnyPS5 yükü hafifletti",
        .hotDetail: "%@. Geri almak için: PS › Hızlı Menü",
        .quickUndoHot: "Isı Profilini Geri Al",
        .quickUndoBattery: "Pil Profilini Geri Al",
        .quickUndoDetail: "Şimdilik senin ayarların",
    ]
}
