import Foundation

/// Play Together: its texts, in both languages.
enum PT {
    enum Key {
        case start, startDetail, pickGame, pickGameDetail, starting, started, startFailed, alreadyRunning
        case title, titleDetail, joinRow, joinDetail, offer, offerDetail, leave, end, ended, endedYours, joined
        case you, host, inGame, notYet, connecting, direct, relay, unreachable, ms
        case signIn, missing, versionYou, versionHost, engineYou, engineHost, closeFirst, full, unlockAndPlay, updateAndPlay, unlockingFirst, updatingFirst
        case code, codeDetail, codeCopied, presence
    }

    static func text(_ key: Key) -> String { (T.language == .turkish ? turkish : english)[key] ?? english[key] ?? "" }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    static let english: [Key: String] = [
        .start: "Play Together: %@",
        .startDetail: "Everyone in the party gets a Join. Online play turns on for this game only",
        .pickGame: "Play Together",
        .pickGameDetail: "Pick a game on Home first, then start it here for the party",
        .starting: "Starting %@ for the party…",
        .started: "Playing %@ together. The party can join now",
        .startFailed: "Could not start Play Together",
        .alreadyRunning: "Your party is already playing together",
        .title: "Playing %@ together · %d/%d",
        .titleDetail: "Started by %@ · version %@",
        .joinRow: "Join %@'s %@",
        .joinDetail: "Starts it here with online play on, in the same game",
        .offer: "%@ started %@ — Join",
        .offerDetail: "Join from the party",
        .leave: "Leave the game",
        .end: "End Play Together",
        .ended: "%@'s game ended",
        .endedYours: "Play Together ended",
        .joined: "Joining %@ in %@…",
        .you: "You",
        .host: "Host",
        .inGame: "In the game",
        .notYet: "Not in yet",
        .connecting: "Connecting…",
        .direct: "Direct",
        .relay: "Relay",
        .unreachable: "Can't reach",
        .ms: "%d ms",
        .signIn: "Sign in to AnyTogether to join",
        .missing: "You need %@ in your library to join",
        .versionYou: "You need %@ version %@; you have %@. Add the update to your library",
        .versionHost: "%@ has version %@; you have %@. Ask them to update",
        .engineYou: "%@ plays on AnyPS5 %@; yours is %@. Update AnyPS5 to join",
        .engineHost: "%@ plays on AnyPS5 %@; yours is %@. Ask them to update",
        .closeFirst: "Close %@ first",
        .full: "The game is full",
        .unlockAndPlay: "Unlock and Play",
        .updateAndPlay: "Update and Play",
        .unlockingFirst: "Unlocking %@ first, then joining",
        .updatingFirst: "Updating %@ to the host's engine, then joining",
        .code: "Join code for this game",
        .codeDetail: "Lets someone outside the party in",
        .codeCopied: "Join code %@ copied",
        .presence: "Playing %@ together (%d/%d)",
    ]

    static let turkish: [Key: String] = [
        .start: "Birlikte Oyna: %@",
        .startDetail: "Partideki herkese Katıl gelir. Çevrim içi oyun yalnızca bu oyun için açılır",
        .pickGame: "Birlikte Oyna",
        .pickGameDetail: "Önce Ana ekranda bir oyun seç, sonra parti için buradan başlat",
        .starting: "%@ parti için başlatılıyor…",
        .started: "%@ birlikte oynanıyor. Parti artık katılabilir",
        .startFailed: "Birlikte Oyna başlatılamadı",
        .alreadyRunning: "Partin zaten birlikte oynuyor",
        .title: "%@ birlikte oynanıyor · %d/%d",
        .titleDetail: "Başlatan %@ · sürüm %@",
        .joinRow: "%@ ile %@ oyna",
        .joinDetail: "Çevrim içi oyunu açıp aynı oyunda burada başlatır",
        .offer: "%@, %@ başlattı — Katıl",
        .offerDetail: "Partiden katıl",
        .leave: "Oyundan ayrıl",
        .end: "Birlikte Oyna'yı bitir",
        .ended: "%@ oyunu bitirdi",
        .endedYours: "Birlikte Oyna bitti",
        .joined: "%@ ile %@ oyununa katılınıyor…",
        .you: "Sen",
        .host: "Kurucu",
        .inGame: "Oyunda",
        .notYet: "Henüz girmedi",
        .connecting: "Bağlanıyor…",
        .direct: "Doğrudan",
        .relay: "Aktarıcı",
        .unreachable: "Ulaşılamıyor",
        .ms: "%d ms",
        .signIn: "Katılmak için AnyTogether'a giriş yap",
        .missing: "Katılmak için kitaplığında %@ olmalı",
        .versionYou: "%@ için %@ sürümü gerekiyor; sende %@ var. Güncellemeyi kitaplığına ekle",
        .versionHost: "%@ kişisinde %@ sürümü var; sende %@. Güncellemesini iste",
        .engineYou: "%@ AnyPS5 %@ ile oynuyor; seninki %@. Katılmak için AnyPS5'i güncelle",
        .engineHost: "%@ AnyPS5 %@ ile oynuyor; seninki %@. Güncellemesini iste",
        .closeFirst: "Önce %@ oyununu kapat",
        .full: "Oyun dolu",
        .unlockAndPlay: "Kilidi Aç ve Oyna",
        .updateAndPlay: "Güncelle ve Oyna",
        .unlockingFirst: "Önce %@ kilidi açılıyor, sonra katılınacak",
        .updatingFirst: "%@ kurucunun motoruna güncelleniyor, sonra katılınacak",
        .code: "Bu oyun için katılma kodu",
        .codeDetail: "Parti dışından birini içeri alır",
        .codeCopied: "Katılma kodu %@ kopyalandı",
        .presence: "%@ birlikte oynanıyor (%d/%d)",
    ]
}
