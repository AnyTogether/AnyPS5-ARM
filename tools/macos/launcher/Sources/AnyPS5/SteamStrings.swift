import Foundation

/// The texts of Settings → Steam (AnyPS5 as a non-Steam game, and its games), in both languages;
/// kept apart from `T` like `TF`.
enum TSteam {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case title = "steam", looking = "steamLooking", notFound = "steamNotFound", notFoundDetail = "steamNotFoundDetail", account = "steamAccount", add = "steamAdd", addDetail = "steamAddDetail", update = "steamUpdate", inSteam = "steamInSteam", inSteamLauncher = "steamInSteamLauncher", inSteamGames = "steamInSteamGames"
        case notInSteam = "steamNotInSteam", games = "steamGames", gamesDetail = "steamGamesDetail", fullscreen = "steamFullscreen", remove = "steamRemove", removeDetail = "steamRemoveDetail", running = "steamRunning", runningDetail = "steamRunningDetail", closeAndAdd = "steamCloseAndAdd", closeAndRemove = "steamCloseAndRemove"
        case closing = "steamClosing", working = "steamWorking", added = "steamAdded", removed = "steamRemoved", nothing = "steamNothing", failed = "steamFailed", wouldNotClose = "steamWouldNotClose", fromSteam = "steamFromSteam", open = "steamOpen", playMissing = "steamPlayMissing"
    }

    static let english: [Key: String] = [
        .title: "Steam",
        .looking: "Looking for Steam…",
        .notFound: "Not found on this Mac",
        .notFoundDetail: "Install Steam and sign in once, then come back here.",
        .account: "Steam Account",
        .add: "Add to Steam",
        .addDetail: "AnyPS5 in your Steam library with its artwork: start it from Big Picture",
        .update: "Update in Steam",
        .inSteam: "In Steam",
        .inSteamLauncher: "AnyPS5",
        .inSteamGames: "AnyPS5 and %d games",
        .notInSteam: "Not added yet",
        .games: "Add My Games Too",
        .gamesDetail: "Every unlocked game as its own Steam entry with its art, starting straight into the game",
        .fullscreen: "Open Full Screen from Steam",
        .remove: "Remove from Steam",
        .removeDetail: "Takes out only AnyPS5's entries and their pictures",
        .running: "Steam is open",
        .runningDetail: "Steam writes over its shortcuts when it quits: quit it first, or let AnyPS5 quit it.",
        .closeAndAdd: "Quit Steam and Add",
        .closeAndRemove: "Quit Steam and Remove",
        .closing: "Quitting Steam…",
        .working: "Making the artwork…",
        .added: "Added to Steam: %@. Open Steam to find it in the AnyPS5 collection.",
        .removed: "AnyPS5 is no longer in Steam",
        .nothing: "AnyPS5 was not in Steam",
        .failed: "Steam was not changed: %@",
        .wouldNotClose: "Steam did not quit. Quit it from its menu, then try again.",
        .fromSteam: "AnyPS5 was started from Steam. To change Steam's shortcuts, open AnyPS5 on its own.",
        .open: "Open Steam",
        .playMissing: "Steam asked for %@, which is not in your games folder",
    ]

    static let turkish: [Key: String] = [
        .title: "Steam",
        .looking: "Steam aranıyor…",
        .notFound: "Bu Mac'te bulunamadı",
        .notFoundDetail: "Steam'i kur ve bir kez giriş yap, sonra buraya dön.",
        .account: "Steam Hesabı",
        .add: "Steam'e Ekle",
        .addDetail: "AnyPS5 görselleriyle Steam kütüphanende: Big Picture'dan başlat",
        .update: "Steam'de Güncelle",
        .inSteam: "Steam'de",
        .inSteamLauncher: "AnyPS5",
        .inSteamGames: "AnyPS5 ve %d oyun",
        .notInSteam: "Henüz eklenmedi",
        .games: "Oyunlarımı da Ekle",
        .gamesDetail: "Kilidi açılmış her oyun görseliyle ayrı bir Steam girdisi olur, doğrudan oyunu başlatır",
        .fullscreen: "Steam'den Tam Ekran Aç",
        .remove: "Steam'den Kaldır",
        .removeDetail: "Yalnızca AnyPS5 girdilerini ve görsellerini kaldırır",
        .running: "Steam açık",
        .runningDetail: "Steam kapanırken kısayollarının üzerine yazar: önce ondan çık ya da AnyPS5 çıksın.",
        .closeAndAdd: "Steam'den Çık ve Ekle",
        .closeAndRemove: "Steam'den Çık ve Kaldır",
        .closing: "Steam kapatılıyor…",
        .working: "Görseller hazırlanıyor…",
        .added: "Steam'e eklendi: %@. Steam'i açınca AnyPS5 koleksiyonunda bulursun.",
        .removed: "AnyPS5 artık Steam'de değil",
        .nothing: "AnyPS5 Steam'de değildi",
        .failed: "Steam değiştirilmedi: %@",
        .wouldNotClose: "Steam kapanmadı. Menüsünden çık, sonra yeniden dene.",
        .fromSteam: "AnyPS5 Steam'den başlatıldı. Steam kısayollarını değiştirmek için AnyPS5'i tek başına aç.",
        .open: "Steam'i Aç",
        .playMissing: "Steam %@ oyununu istedi ama oyun klasöründe yok",
    ]
}
