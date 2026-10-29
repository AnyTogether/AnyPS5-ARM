import Foundation

/// Profiles (the picker, adding one, online and offline, Settings → Profiles) and the
/// friends-only name and picture: their texts, in both languages.
enum TPro {
    enum Key: String, CaseIterable {
        case profilesCategory, pickerKicker = "profileKicker", whoIsPlaying = "profileWhoIsPlaying", pickerSubtitle = "profilePickerSubtitle", pickerSubtitleLaunch = "profilePickerSubtitleLaunch", hintPlay = "profileHintPlay", playingNow = "profilePlayingNow", online = "profileOnline", offline = "profileOffline"
        case howToPlay = "profileHowToPlay", howToPlaySubtitle = "profileHowToPlaySubtitle", profileNamePlaceholder = "profileNameHint", playerNumber = "profilePlayerNumber", continueStep = "profileContinueStep"
        case offlineTitle = "profileOfflineTitle", offlineLead = "profileOfflineLead", offlineFact1 = "profileOfflineFact1", offlineFact2 = "profileOfflineFact2", offlineFact3 = "profileOfflineFact3", offlineTag = "profileOfflineTag"
        case onlineTitle = "profileOnlineTitle", onlineLead = "profileOnlineLead", onlineFact1 = "profileOnlineFact1", onlineFact2 = "profileOnlineFact2", onlineFact3 = "profileOnlineFact3", onlineTag = "profileOnlineTag"
        case signInTitleNew = "profileSignInNew", signInTitleOnline = "profileSignInOnline", signInTitleAgain = "profileSignInAgain", signInSubtitle = "profileSignInSubtitle"
        case menuKicker = "profileMenuTitle", otherProfiles = "profileOtherProfiles", otherProfile = "profileOtherProfile", addSomeone = "profileAddSomeone", goOffline = "profileGoOffline", goOnline = "profileGoOnline", goOfflineDetail = "profileGoOfflineDetail", goOnlineDetail = "profileGoOnlineDetail", manageProfiles = "profileManage"
        case closeGameFirst = "profileCloseGameFirst", waitForSync = "profileWaitForSync", welcomeBack = "profileWelcomeBack", nowOffline = "profileNowOffline", savesNotSwapped = "profileSavesNotSwapped"
        case onlineAs = "profileOnlineAs", onlineSignedOut = "profileOnlineSignedOut", offlineDetail = "profileOfflineDetail", tileColour = "profileColour", tileColourDetail = "profileTileColourDetail", askEveryTime = "profileAskEveryTime", askEveryTimeDetail = "profileAskEveryTimeDetail"
        case otherProfilesTitle = "profileOtherTitle", switchTo = "profileSwitchTo", deleteProfile = "profileDelete", deleteQuestion = "profileDeleteQuestion", addProfile = "profileAdd", addProfileDetail = "profileAddProfileDetail", backupFolder = "profileBackupFolder", cannotDelete = "profileCannotDelete", deleted = "profileDeleted"
        case offlineTogether = "profileOfflineTogether", offlineTogetherDetail = "profileOfflineTogetherDetail"
        case friendsOnlyTitle = "privateTitle", friendsOnlyDetail = "privateDetail", friendsOnlyName = "privateName", friendsOnlyNameDetail = "profileFriendsOnlyNameDetail", friendsOnlyNameSave = "privateNameSave", friendsOnlyNameClear = "privateNameClear"
        case friendsOnlyNameSaved = "privateNameSaved", friendsOnlyNameCleared = "privateNameCleared", friendsOnlyPicture = "profileFriendsOnlyPicture", friendsOnlyPictureDetail = "profileFriendsOnlyPictureDetail", friendsOnlyPictureRemove = "privatePictureRemove"
        case friendsOnlyPictureSaved = "privatePictureSaved", friendsOnlyPictureRemoved = "privatePictureRemoved", friendsOnlyBadge = "privateBadge"
        case colourIndigo, colourTeal, colourCoral, colourAmber, colourViolet, colourGreen, colourPink, colourSky
    }

    /// "1 other profile", "3 other profiles", or the way to add one when there is none.
    static func others(_ count: Int) -> String {
        count > 1 ? format(.otherProfiles, count) : count == 1 ? text(.otherProfile) : text(.addSomeone)
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// The tile colours, in AppModel.profilePalette's order.
    static var colourNames: [String] {
        [.colourIndigo, .colourTeal, .colourCoral, .colourAmber, .colourViolet, .colourGreen, .colourPink, .colourSky].map(text)
    }

    static let english: [Key: String] = [
        .profilesCategory: "Profiles",
        .pickerKicker: "AnyPS5",
        .whoIsPlaying: "Who's playing?",
        .pickerSubtitle: "Each profile has its own saves, trophies and settings.",
        .pickerSubtitleLaunch: "Pick your profile to carry on where you left off.",
        .hintPlay: "Play",
        .playingNow: "Playing now",
        .online: "Online",
        .offline: "Offline",
        .howToPlay: "How do you want to play?",
        .howToPlaySubtitle: "You can switch between offline and online later from Options.",
        .profileNamePlaceholder: "Name",
        .playerNumber: "Player %d",
        .continueStep: "Continue",
        .offlineTitle: "Play Offline",
        .offlineLead: "No account needed.",
        .offlineFact1: "Trophies and progress stay on this Mac",
        .offlineFact2: "Nothing is synced or shared",
        .offlineFact3: "Go online any time from Options",
        .offlineTag: "Local",
        .onlineTitle: "Play Online",
        .onlineLead: "Create an AnyTogether account or sign in to yours.",
        .onlineFact1: "Friends, parties and Play Together",
        .onlineFact2: "Trophies and cloud saves follow you",
        .onlineFact3: "Sign in with an email code, the website or your phone",
        .onlineTag: "AnyTogether",
        .signInTitleNew: "Create an account or sign in",
        .signInTitleOnline: "Go online with AnyTogether",
        .signInTitleAgain: "Sign in again",
        .signInSubtitle: "New to AnyTogether? The email code makes your account as it signs you in.",
        .menuKicker: "Options",
        .otherProfiles: "%d other profiles on this Mac",
        .otherProfile: "1 other profile on this Mac",
        .addSomeone: "Add someone who plays here",
        .goOffline: "Go Offline",
        .goOnline: "Go Online",
        .goOfflineDetail: "Trophies and progress stay on this Mac until you go online again",
        .goOnlineDetail: "Friends, parties and syncing with AnyTogether",
        .manageProfiles: "Profiles",
        .closeGameFirst: "Close %@ first",
        .waitForSync: "Wait until the saves are synced",
        .welcomeBack: "Hi, %@",
        .nowOffline: "Offline: trophies and progress stay on this Mac",
        .savesNotSwapped: "%@'s saves could not be put in place for this profile",
        .onlineAs: "Online as @%@",
        .onlineSignedOut: "Online, signed out: sign in under AnyTogether",
        .offlineDetail: "Offline: trophies and progress stay on this Mac and are not synced",
        .tileColour: "Colour",
        .tileColourDetail: "The tile's colour when there is no picture",
        .askEveryTime: "Ask Who's Playing at Every Start",
        .askEveryTimeDetail: "With more than one profile the launcher always asks",
        .otherProfilesTitle: "Other Profiles",
        .switchTo: "Switch to %@",
        .deleteProfile: "Delete %@",
        .deleteQuestion: "Delete %@? Their saves and trophies on this Mac are backed up to Documents → AnyPS5 → Backups, then removed.",
        .addProfile: "Add Profile",
        .addProfileDetail: "Someone else who plays on this Mac",
        .backupFolder: "Profile %@",
        .cannotDelete: "This profile cannot be deleted now",
        .deleted: "%@ was deleted",
        .offlineTogether: "This profile plays offline",
        .offlineTogetherDetail: "Trophies and progress stay on this Mac. Go online to sign in or create an account.",
        .friendsOnlyTitle: "Friends-Only Name and Picture",
        .friendsOnlyDetail: "Only your accepted friends see them, always next to your @handle. Everyone else sees your public name and picture.",
        .friendsOnlyName: "Friends-Only Name",
        .friendsOnlyNameDetail: "Your real name, say; up to 40 characters",
        .friendsOnlyNameSave: "Save Friends-Only Name",
        .friendsOnlyNameClear: "Clear Friends-Only Name",
        .friendsOnlyNameSaved: "Friends now see your private name",
        .friendsOnlyNameCleared: "Your private name is cleared",
        .friendsOnlyPicture: "Use Profile Picture for Friends",
        .friendsOnlyPictureDetail: "Friends see it in place of your public picture",
        .friendsOnlyPictureRemove: "Remove Friends-Only Picture",
        .friendsOnlyPictureSaved: "Friends now see your private picture",
        .friendsOnlyPictureRemoved: "Your private picture is removed",
        .friendsOnlyBadge: "Friends only",
        .colourIndigo: "Indigo", .colourTeal: "Teal", .colourCoral: "Coral", .colourAmber: "Amber",
        .colourViolet: "Violet", .colourGreen: "Green", .colourPink: "Pink", .colourSky: "Sky",
    ]

    static let turkish: [Key: String] = [
        .profilesCategory: "Profiller",
        .pickerKicker: "AnyPS5",
        .whoIsPlaying: "Kim oynuyor?",
        .pickerSubtitle: "Her profilin kendi kayıtları, kupaları ve ayarları var.",
        .pickerSubtitleLaunch: "Kaldığın yerden devam etmek için profilini seç.",
        .hintPlay: "Oyna",
        .playingNow: "Şu an oynuyor",
        .online: "Çevrimiçi",
        .offline: "Çevrimdışı",
        .howToPlay: "Nasıl oynamak istersin?",
        .howToPlaySubtitle: "Çevrimdışı ve çevrimiçi arasında sonra Seçenekler'den geçebilirsin.",
        .profileNamePlaceholder: "Ad",
        .playerNumber: "Oyuncu %d",
        .continueStep: "Devam",
        .offlineTitle: "Çevrimdışı Oyna",
        .offlineLead: "Hesap gerekmez.",
        .offlineFact1: "Kupalar ve ilerleme bu Mac'te kalır",
        .offlineFact2: "Hiçbir şey eşitlenmez ya da paylaşılmaz",
        .offlineFact3: "İstediğin zaman Seçenekler'den çevrimiçi ol",
        .offlineTag: "Yerel",
        .onlineTitle: "Çevrimiçi Oyna",
        .onlineLead: "AnyTogether hesabı oluştur ya da hesabına giriş yap.",
        .onlineFact1: "Arkadaşlar, partiler ve Birlikte Oyna",
        .onlineFact2: "Kupalar ve bulut kayıtları seninle gelir",
        .onlineFact3: "E-posta koduyla, web sitesinden ya da telefonunla giriş yap",
        .onlineTag: "AnyTogether",
        .signInTitleNew: "Hesap oluştur ya da giriş yap",
        .signInTitleOnline: "AnyTogether ile çevrimiçi ol",
        .signInTitleAgain: "Yeniden giriş yap",
        .signInSubtitle: "AnyTogether'da yeni misin? E-posta kodu seni giriş yaptırırken hesabını da oluşturur.",
        .menuKicker: "Seçenekler",
        .otherProfiles: "Bu Mac'te %d profil daha",
        .otherProfile: "Bu Mac'te 1 profil daha",
        .addSomeone: "Burada oynayan birini ekle",
        .goOffline: "Çevrimdışı Ol",
        .goOnline: "Çevrimiçi Ol",
        .goOfflineDetail: "Yeniden çevrimiçi olana kadar kupalar ve ilerleme bu Mac'te kalır",
        .goOnlineDetail: "Arkadaşlar, partiler ve AnyTogether ile eşitleme",
        .manageProfiles: "Profiller",
        .closeGameFirst: "Önce %@ oyununu kapat",
        .waitForSync: "Kayıtlar eşitlenene kadar bekle",
        .welcomeBack: "Merhaba, %@",
        .nowOffline: "Çevrimdışı: kupalar ve ilerleme bu Mac'te kalır",
        .savesNotSwapped: "%@ kayıtları bu profil için yerine konamadı",
        .onlineAs: "@%@ olarak çevrimiçi",
        .onlineSignedOut: "Çevrimiçi, oturum kapalı: AnyTogether bölümünden giriş yap",
        .offlineDetail: "Çevrimdışı: kupalar ve ilerleme bu Mac'te kalır, eşitlenmez",
        .tileColour: "Renk",
        .tileColourDetail: "Fotoğraf yokken kutucuğun rengi",
        .askEveryTime: "Her Açılışta Kimin Oynadığını Sor",
        .askEveryTimeDetail: "Birden fazla profil varken başlatıcı her zaman sorar",
        .otherProfilesTitle: "Diğer Profiller",
        .switchTo: "%@ profiline geç",
        .deleteProfile: "%@ profilini sil",
        .deleteQuestion: "%@ silinsin mi? Bu Mac'teki kayıtları ve kupaları Belgeler → AnyPS5 → Backups klasörüne yedeklenir, sonra kaldırılır.",
        .addProfile: "Profil Ekle",
        .addProfileDetail: "Bu Mac'te oynayan başka biri",
        .backupFolder: "Profil %@",
        .cannotDelete: "Bu profil şu an silinemez",
        .deleted: "%@ silindi",
        .offlineTogether: "Bu profil çevrimdışı oynuyor",
        .offlineTogetherDetail: "Kupalar ve ilerleme bu Mac'te kalır. Giriş yapmak ya da hesap oluşturmak için çevrimiçi ol.",
        .friendsOnlyTitle: "Yalnızca Arkadaşlara Ad ve Fotoğraf",
        .friendsOnlyDetail: "Yalnızca kabul ettiğin arkadaşların görür, her zaman @kullanıcı adının yanında. Diğer herkes herkese açık adını ve fotoğrafını görür.",
        .friendsOnlyName: "Arkadaşlara Görünen Ad",
        .friendsOnlyNameDetail: "Örneğin gerçek adın; en fazla 40 karakter",
        .friendsOnlyNameSave: "Arkadaşlara Görünen Adı Kaydet",
        .friendsOnlyNameClear: "Arkadaşlara Görünen Adı Temizle",
        .friendsOnlyNameSaved: "Arkadaşların artık özel adını görüyor",
        .friendsOnlyNameCleared: "Özel adın temizlendi",
        .friendsOnlyPicture: "Profil Fotoğrafını Arkadaşlara Göster",
        .friendsOnlyPictureDetail: "Arkadaşların herkese açık fotoğrafının yerine bunu görür",
        .friendsOnlyPictureRemove: "Arkadaşlara Özel Fotoğrafı Kaldır",
        .friendsOnlyPictureSaved: "Arkadaşların artık özel fotoğrafını görüyor",
        .friendsOnlyPictureRemoved: "Özel fotoğrafın kaldırıldı",
        .friendsOnlyBadge: "Yalnızca arkadaşlar",
        .colourIndigo: "Çivit", .colourTeal: "Camgöbeği", .colourCoral: "Mercan", .colourAmber: "Kehribar",
        .colourViolet: "Mor", .colourGreen: "Yeşil", .colourPink: "Pembe", .colourSky: "Gök",
    ]
}
