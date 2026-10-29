import Foundation

/// The texts of the crash report, the issue it opens and detailed logging, from the language files (l10n);
/// kept apart from `T` like `TE`. `TC.text(.key)` reads the launcher's current language.
enum TC {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case reportStopped, reportLastSession, reportReading, reportKicker, reportKickerShare
        case reportExport, reportExportDetail, reportOpenIssue, reportOpenIssueDetail, reportShowLog
        case reportPlayTraced, reportPlayTracedDetail
        case reportShareTitle, reportShareDetail, reportGitHub, reportGitHubDetail = "reportGitHubRepoDetail", reportEngine, reportEngineDetail, reportBack
        case reportLogTail, reportNoLog, reportFactMac, reportFactEngine, reportFactSession, reportFactLogging, reportFactCrash
        case reportCrashNone, reportOn, reportRan, reportNoWindow, reportNormal
        case reportSaved = "reportSavedTo", reportSaveFailed, reportIssueOpened
        case traceTitle, traceDetail, traceOnNotice, traceOnNoticeDetail
        case lastSessionReport, lastSessionReportDetail
        case diagnosisAborted, diagnosisExited
    }
}
