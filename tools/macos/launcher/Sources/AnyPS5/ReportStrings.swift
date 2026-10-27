import Foundation

/// The texts of the crash report, the issue it opens and detailed logging, in both languages;
/// kept apart from `T` like `TE`. `TC.text(.key)` reads the launcher's current language.
enum TC {
    static func text(_ key: Key) -> String {
        let table = T.language == .turkish ? turkish : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case reportStopped, reportLastSession, reportReading, reportKicker, reportKickerShare
        case reportExport, reportExportDetail, reportOpenIssue, reportOpenIssueDetail, reportShowLog
        case reportPlayTraced, reportPlayTracedDetail
        case reportShareTitle, reportShareDetail, reportGitHub, reportGitHubDetail, reportEngine, reportEngineDetail, reportBack
        case reportLogTail, reportNoLog, reportFactMac, reportFactEngine, reportFactSession, reportFactLogging, reportFactCrash
        case reportCrashNone, reportOn, reportRan, reportNoWindow, reportNormal
        case reportSaved, reportSaveFailed, reportIssueOpened
        case traceTitle, traceDetail, traceOnNotice, traceOnNoticeDetail
        case lastSessionReport, lastSessionReportDetail
        case diagnosisAborted, diagnosisExited
    }

    static let english: [Key: String] = [
        .reportStopped: "%@ stopped",
        .reportLastSession: "%@ · Last Session",
        .reportReading: "Reading the log and macOS's crash report…",
        .reportKicker: "Crash report",
        .reportKickerShare: "Before it is shared",
        .reportExport: "Export Report",
        .reportExportDetail: "%@ · to attach to an issue",
        .reportOpenIssue: "Open Issue",
        .reportOpenIssueDetail: "On GitHub · you see what is shared first",
        .reportShowLog: "Show the Whole Log",
        .reportPlayTraced: "Play with Detailed Logging",
        .reportPlayTracedDetail: "Once, for a fuller report · the game may run slower",
        .reportShareTitle: "What will be shared",
        .reportShareDetail: "Your home folder, names, e-mail addresses and AnyTogether tokens are taken out. Nothing is sent until you submit the issue on GitHub yourself.",
        .reportGitHub: "Open on GitHub",
        .reportGitHubDetail: "AnyTogether/AnyPS5-ARM · then drag the exported report into it",
        .reportEngine: "Report to the AnyPS5 Engine",
        .reportEngineDetail: "boykopovar/AnyPS5 · for a bug in the engine itself, same text",
        .reportBack: "Back",
        .reportLogTail: "End of the log",
        .reportNoLog: "The game wrote nothing to its log.",
        .reportFactMac: "Mac",
        .reportFactEngine: "Engine",
        .reportFactSession: "Session",
        .reportFactLogging: "Detailed logging",
        .reportFactCrash: "macOS crash report",
        .reportCrashNone: "None",
        .reportOn: "On",
        .reportRan: "Ran %d min",
        .reportNoWindow: "The game closed before its window appeared.",
        .reportNormal: "No error found: the game closed normally.",
        .reportSaved: "Report saved: %@",
        .reportSaveFailed: "The report could not be saved",
        .reportIssueOpened: "Issue page opened: attach %@ there",
        .traceTitle: "Detailed Logging (Trace)",
        .traceDetail: "Slower · the log can grow to hundreds of MB",
        .traceOnNotice: "Detailed logging is on",
        .traceOnNoticeDetail: "The game may run slower; the log is kept under 512 MB.",
        .lastSessionReport: "Last Session's Report",
        .lastSessionReportDetail: "The log, the crash and this Mac, to export or report",
        .diagnosisAborted: "The engine stopped the game (abort).",
        .diagnosisExited: "The game exited with status %d.",
    ]

    static let turkish: [Key: String] = [
        .reportStopped: "%@ durdu",
        .reportLastSession: "%@ · Son Oturum",
        .reportReading: "Günlük ve macOS'un çökme raporu okunuyor…",
        .reportKicker: "Çökme raporu",
        .reportKickerShare: "Paylaşmadan önce",
        .reportExport: "Raporu Dışa Aktar",
        .reportExportDetail: "%@ · bir bildirime eklemek için",
        .reportOpenIssue: "Sorun Bildir",
        .reportOpenIssueDetail: "GitHub'da · önce neyin paylaşılacağını görürsün",
        .reportShowLog: "Günlüğün Tamamını Göster",
        .reportPlayTraced: "Ayrıntılı Günlükle Oyna",
        .reportPlayTracedDetail: "Bir kez, daha dolu bir rapor için · oyun yavaşlayabilir",
        .reportShareTitle: "Paylaşılacaklar",
        .reportShareDetail: "Ana klasörün, adların, e-posta adreslerin ve AnyTogether anahtarların çıkarıldı. Bildirimi GitHub'da sen göndermeden hiçbir şey gitmez.",
        .reportGitHub: "GitHub'da Aç",
        .reportGitHubDetail: "AnyTogether/AnyPS5-ARM · sonra dışa aktarılan raporu içine sürükle",
        .reportEngine: "AnyPS5 Motoruna Bildir",
        .reportEngineDetail: "boykopovar/AnyPS5 · motorun kendisindeki bir hata için, aynı metin",
        .reportBack: "Geri",
        .reportLogTail: "Günlüğün sonu",
        .reportNoLog: "Oyun günlüğüne hiçbir şey yazmadı.",
        .reportFactMac: "Mac",
        .reportFactEngine: "Motor",
        .reportFactSession: "Oturum",
        .reportFactLogging: "Ayrıntılı günlük",
        .reportFactCrash: "macOS çökme raporu",
        .reportCrashNone: "Yok",
        .reportOn: "Açık",
        .reportRan: "%d dk çalıştı",
        .reportNoWindow: "Oyun penceresi açılmadan kapandı.",
        .reportNormal: "Hata bulunmadı: oyun normal kapandı.",
        .reportSaved: "Rapor kaydedildi: %@",
        .reportSaveFailed: "Rapor kaydedilemedi",
        .reportIssueOpened: "Bildirim sayfası açıldı: %@ dosyasını oraya ekle",
        .traceTitle: "Ayrıntılı Günlük (İz)",
        .traceDetail: "Daha yavaş · günlük yüzlerce MB olabilir",
        .traceOnNotice: "Ayrıntılı günlük açık",
        .traceOnNoticeDetail: "Oyun yavaşlayabilir; günlük 512 MB'ın altında tutulur.",
        .lastSessionReport: "Son Oturumun Raporu",
        .lastSessionReportDetail: "Günlük, çökme ve bu Mac; dışa aktarmak ya da bildirmek için",
        .diagnosisAborted: "Motor oyunu durdurdu (abort).",
        .diagnosisExited: "Oyun %d durumuyla çıktı.",
    ]
}
