import Foundation

/// Join codes, the Join button on Discord and deafening: their texts, in both languages.
enum JS {
    enum Key: String, CaseIterable {
        case codeTitle = "joinCodeTitle", codeDetail = "joinCodeDetail", copyCode = "partyCodeCopy", copyLink = "partyCodeCopyLink", codeCopied = "partyCodeCopied", linkCopied = "partyLinkCopied", newCode = "partyCodeNew", newCodeDetail = "joinNewCodeDetail", stopCode = "joinStopCode", codeStopped = "joinCodeStopped", makeCode = "partyCodeMake", makeCodeDetail = "joinMakeCodeDetail", codeMade = "joinCodeMade"
        case withCode = "partyRequestWithCode", joinWithCode = "partyCodeEnter", joinWithCodeDetail, lookingUp = "joinLookingUp", codeParty = "partyCodeOf", codeShare = "joinCodeShare", askToJoin = "partyCodeAsk", askedParty = "joinAskedParty", askedShare = "joinAskedShare", invitedParty = "joinInvitedParty", invitedShare = "joinInvitedShare", alreadyIn = "joinAlreadyIn"
        case noSuchCode = "joinNoSuchCode", familyBlocks = "joinFamilyBlocks", familyBlocksOther = "joinFamilyBlocksOther", accountMuted = "joinAccountMuted", tooMany = "joinTooMany", notACode = "joinNotACode"
        case deafen = "joinDeafen", deafenDetail = "joinDeafenDetail", deafened = "joinDeafened", deafenedYou = "joinDeafenedYou"
        case discordJoin = "joinDiscordJoin", discordJoinDetail = "joinDiscordJoinDetail", discordJoinLabel = "joinDiscordJoinLabel", inParty = "joinInParty", discordLink = "partyDiscord", discordLinkDetail = "joinDiscordLinkDetail", discordLinkSaved = "partyDiscordSaved", discordLinkRemoved = "partyDiscordRemoved", discordLinkBad = "joinDiscordLinkBad", openDiscord = "partyDiscordOpen"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// "14:05", or "26 Eki 14:05" when it is not today, in the launcher's language.
    static func until(_ date: Date) -> String {
        let locale = T.locale
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        guard !Calendar.current.isDateInToday(date) else { return date.formatted(time) }
        return date.formatted(Date.FormatStyle().month(.abbreviated).day().locale(locale)) + " " + date.formatted(time)
    }

    static let turkish: [Key: String] = [
        .codeTitle: "Katılma kodu",
        .codeDetail: "Kodu olan katılmak isteyebilir · bitiş %@",
        .copyCode: "Kodu kopyala",
        .copyLink: "Bağlantıyı kopyala",
        .codeCopied: "Kod kopyalandı",
        .linkCopied: "Bağlantı kopyalandı",
        .newCode: "Yeni kod",
        .newCodeDetail: "Eskisi artık çalışmaz",
        .stopCode: "Kodu durdur",
        .codeStopped: "Kod artık çalışmıyor",
        .makeCode: "Katılma kodu oluştur",
        .makeCodeDetail: "Kodu ya da bağlantısını paylaş; her isteğe yine sen karar verirsin",
        .codeMade: "Yeni kod: %@",
        .withCode: "kodla istedi",
        .joinWithCode: "Kodla katıl",
        .joinWithCodeDetail: "Bir kod ya da bağlantısını yaz veya yapıştır",
        .lookingUp: "Bakılıyor…",
        .codeParty: "%@ partisi",
        .codeShare: "%@ paylaşıyor",
        .askToJoin: "Katılmak iste",
        .askedParty: "İstendi. Lider yanıt verince haber gelir",
        .askedShare: "İstendi. Paylaşan yanıt verince haber gelir",
        .invitedParty: "Davet edildin: Parti'deki davetten katıl",
        .invitedShare: "Davet edildin: Arkadaşlar'daki davetten izle",
        .alreadyIn: "Zaten içindesin",
        .noSuchCode: "Böyle bir kod yok ya da artık çalışmıyor",
        .familyBlocks: "Aile ayarların buna izin vermiyor",
        .familyBlocksOther: "Onun aile ayarları buna izin vermiyor",
        .accountMuted: "Hesabın şimdilik susturuldu",
        .tooMany: "Çok fazla istek. Biraz sonra yeniden dene",
        .notACode: "Kod 8 harf ve rakamdan oluşur",
        .deafen: "Sağırlaştır",
        .deafenDetail: "Kimseyi duymazsın, mikrofonun da kapanır",
        .deafened: "duymuyor",
        .deafenedYou: "Sağırlaştırıldın",
        .discordJoin: "Discord'da Katıl düğmesi göster",
        .discordJoinDetail: "Partide ya da paylaşırken; düğme katılma sayfasını açar, onayı yine sen verirsin",
        .discordJoinLabel: "AnyTogether'da katıl",
        .inParty: "Partide",
        .discordLink: "Discord bağlantısı",
        .discordLinkDetail: "discord.gg daveti ya da kanal bağlantısı",
        .discordLinkSaved: "Discord bağlantısı kaydedildi",
        .discordLinkRemoved: "Discord bağlantısı kaldırıldı",
        .discordLinkBad: "Bu bir Discord daveti ya da kanal bağlantısı değil",
        .openDiscord: "Discord'da aç",
    ]

    static let english: [Key: String] = [
        .codeTitle: "Join code",
        .codeDetail: "Anyone with it can ask to join · ends %@",
        .copyCode: "Copy code",
        .copyLink: "Copy link",
        .codeCopied: "Code copied",
        .linkCopied: "Link copied",
        .newCode: "New code",
        .newCodeDetail: "The old one stops working",
        .stopCode: "Stop code",
        .codeStopped: "The code no longer works",
        .makeCode: "Make a join code",
        .makeCodeDetail: "Share it or its link; you still say yes to each one",
        .codeMade: "New code: %@",
        .withCode: "asked with the code",
        .joinWithCode: "Join with a code",
        .joinWithCodeDetail: "Type or paste a code or its link",
        .lookingUp: "Looking it up…",
        .codeParty: "%@'s party",
        .codeShare: "%@ is sharing",
        .askToJoin: "Ask to join",
        .askedParty: "Asked. You'll hear when the leader answers",
        .askedShare: "Asked. You'll hear when the host answers",
        .invitedParty: "You're invited: join from the invite in Party",
        .invitedShare: "You're invited: watch from the invite in Friends",
        .alreadyIn: "You're already in",
        .noSuchCode: "No such code, or it no longer works",
        .familyBlocks: "Your family settings don't allow this",
        .familyBlocksOther: "Their family settings don't allow this",
        .accountMuted: "Your account is muted for now",
        .tooMany: "Too many requests. Try again in a while",
        .notACode: "A code is 8 letters and numbers",
        .deafen: "Deafen",
        .deafenDetail: "Hear nobody, and your microphone is off",
        .deafened: "deafened",
        .deafenedYou: "Deafened",
        .discordJoin: "Show a Join button on Discord",
        .discordJoinDetail: "In a party or sharing; it opens the join page, and you still say yes",
        .discordJoinLabel: "Join on AnyTogether",
        .inParty: "In a party",
        .discordLink: "Discord link",
        .discordLinkDetail: "A discord.gg invite or a channel link",
        .discordLinkSaved: "Discord link saved",
        .discordLinkRemoved: "Discord link removed",
        .discordLinkBad: "That's not a Discord invite or channel link",
        .openDiscord: "Open in Discord",
    ]
}
