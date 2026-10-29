import Foundation

/// Join codes, the Join button on Discord and deafening: their texts, from the language files (l10n).
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
}
