import Foundation

/// The texts of the free-space check before an unlock and of new games prepared in the
/// background, in both languages; kept apart from `T` like `TSteam`.
enum TPrep {
    static func text(_ key: Key) -> String {
        let table = T.language == .turkish ? turkish : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case prepareNewGames, prepareNewGamesDetail
        case newGamePreparing, newGamesPreparing, newGameWaiting, newGamesWaiting, newGameNotPreparedBattery, newGameNotPreparedSpace
        case preparing, preparingStep, preparingPaused, waitingToPrepare, playWhenReady, startsWhenReady, readyToPlay, readyToPlayDetail
        case notPreparedBattery, notPreparedSpace
        case noSpaceTitle, noSpaceSubtitle, noSpaceAmount, noSpaceNothingWritten, noSpaceWhy
        case noSpaceFolder, noSpaceFolderDetail, noSpaceStorage, noSpaceStorageDetail, noSpaceRetry, noSpaceRetryDetail
    }

    static let english: [Key: String] = [
        .prepareNewGames: "Prepare New Games Automatically",
        .prepareNewGamesDetail: "A game copied into the games folder unlocks in the background while you're not playing, so it's ready when you get to it. Never during a game or on a low battery",
        .newGamePreparing: "New game: %@ · Preparing…",
        .newGamesPreparing: "%d new games · Preparing…",
        .newGameWaiting: "New game: %@ · Prepares after your game",
        .newGamesWaiting: "%d new games · Prepare after your game",
        .newGameNotPreparedBattery: "New game: %@ · Plug in to prepare it",
        .newGameNotPreparedSpace: "New game: %@ · Not enough space to prepare it",
        .preparing: "Preparing…",
        .preparingStep: "Preparing · %@",
        .preparingPaused: "Paused while you play",
        .waitingToPrepare: "Prepares after your game",
        .playWhenReady: "Play When Ready",
        .startsWhenReady: "%@ starts as soon as it's ready",
        .readyToPlay: "%@ · Ready to play",
        .readyToPlayDetail: "Prepared in the background",
        .notPreparedBattery: "%@ wasn't prepared: the battery is low",
        .notPreparedSpace: "%@ wasn't prepared: it needs %@, %@ is free",
        .noSpaceTitle: "Not Enough Space",
        .noSpaceSubtitle: "The unlock didn't start",
        .noSpaceAmount: "Needs %@ · %@ free on %@",
        .noSpaceNothingWritten: "Nothing was written. Make room, or unlock into a games folder on a drive with more space.",
        .noSpaceWhy: "Unlocking writes the game's executable and modules converted for the Mac. The game's own files are cloned or linked, so they take no extra space.",
        .noSpaceFolder: "Add a Games Folder",
        .noSpaceFolderDetail: "Move the dump to a drive with more room and add that folder. The game unlocks on its own drive, where its files are cloned and cost nothing",
        .noSpaceStorage: "Open Storage Settings",
        .noSpaceStorageDetail: "See what takes the space on this Mac",
        .noSpaceRetry: "Try Again",
        .noSpaceRetryDetail: "After making room",
    ]

    static let turkish: [Key: String] = [
        .prepareNewGames: "Yeni Oyunları Otomatik Hazırla",
        .prepareNewGamesDetail: "Oyun klasörüne kopyalanan oyun, sen oynamıyorken arka planda açılır; sıra ona geldiğinde hazırdır. Oyun sırasında ya da pil azken asla",
        .newGamePreparing: "Yeni oyun: %@ · Hazırlanıyor…",
        .newGamesPreparing: "%d yeni oyun · Hazırlanıyor…",
        .newGameWaiting: "Yeni oyun: %@ · Oyunun bitince hazırlanacak",
        .newGamesWaiting: "%d yeni oyun · Oyunun bitince hazırlanacak",
        .newGameNotPreparedBattery: "Yeni oyun: %@ · Hazırlamak için şarja tak",
        .newGameNotPreparedSpace: "Yeni oyun: %@ · Hazırlamaya yer yok",
        .preparing: "Hazırlanıyor…",
        .preparingStep: "Hazırlanıyor · %@",
        .preparingPaused: "Sen oynarken duraklatıldı",
        .waitingToPrepare: "Oyunun bitince hazırlanacak",
        .playWhenReady: "Hazır Olunca Oyna",
        .startsWhenReady: "%@ hazır olur olmaz başlayacak",
        .readyToPlay: "%@ · Oynamaya hazır",
        .readyToPlayDetail: "Arka planda hazırlandı",
        .notPreparedBattery: "%@ hazırlanmadı: pil az",
        .notPreparedSpace: "%@ hazırlanmadı: %@ gerekiyor, %@ boş",
        .noSpaceTitle: "Yeterli Alan Yok",
        .noSpaceSubtitle: "Kilit açma başlamadı",
        .noSpaceAmount: "%1$@ gerekiyor · %3$@ diskinde %2$@ boş",
        .noSpaceNothingWritten: "Hiçbir şey yazılmadı. Yer aç ya da daha fazla alanı olan bir diskte oyun klasörü seç.",
        .noSpaceWhy: "Kilit açma, oyunun çalıştırılabilir dosyasını ve modüllerini Mac için dönüştürüp yazar. Oyunun kendi dosyaları klonlanır ya da bağlanır, ek yer kaplamaz.",
        .noSpaceFolder: "Oyun Klasörü Ekle",
        .noSpaceFolderDetail: "Dump'ı daha fazla yeri olan bir diske taşı ve o klasörü ekle. Oyun kendi diskinde açılır; dosyaları orada klonlanır, yer kaplamaz",
        .noSpaceStorage: "Depolama Ayarlarını Aç",
        .noSpaceStorageDetail: "Bu Mac'te yeri neyin kapladığını gör",
        .noSpaceRetry: "Yeniden Dene",
        .noSpaceRetryDetail: "Yer açtıktan sonra",
    ]
}
