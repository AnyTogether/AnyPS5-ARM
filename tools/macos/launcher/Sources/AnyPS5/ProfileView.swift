import AnyPS5Core
import AppKit
import SwiftUI

/// A profile on AnyTogether, the user's own or a friend's, opened from the Friends panel or from
/// Settings → AnyTogether: the card (avatar, name, handle, bio), four numbers, the games with
/// their play time and trophy progress, and the trophies earned last with how rare they are.
extension AppModel {
    /// Where the profile was opened from, to go back to as it was.
    struct ProfileReturn {
        let overlay: Overlay
        let category: Int
        let row: Int
        let inRows: Bool
    }

    /// The trophies the profile lists, newest first.
    static let recentTrophyCount = 30

    func openMyProfile() {
        guard let user = togetherUser else { return }
        openProfile(user.handle, card: TogetherPerson(userId: user.id, handle: user.handle, displayName: user.displayName, avatar: user.avatar))
        // The name or handle may have changed on the website: read again, and a new handle's page.
        guard togetherConnected, !ownProfileReading else { return }
        if let read = ownProfileReadAt, Date().timeIntervalSince(read) < AppModel.ownProfileAgeShown { return }
        ownProfileReading = true
        Task {
            defer { ownProfileReading = false }
            guard let profile = try? await together.myProfile(), togetherUser?.id == user.id else { return }
            ownProfileReadAt = Date()
            togetherUser = together.user
            followHandle(profile.handle)
            guard profile.handle != user.handle, overlay == .profile, let now = togetherUser else { return }
            openProfile(now.handle, card: TogetherPerson(userId: now.id, handle: now.handle, displayName: now.displayName, avatar: now.avatar))
        }
    }

    func openProfile(_ handle: String, card: TogetherPerson) {
        guard togetherUser != nil else { return }
        if let overlay, overlay != .profile { profileReturn = ProfileReturn(overlay: overlay, category: panelCategory, row: panelRow, inRows: panelInRows) }
        profileCard = card
        profilePage = nil
        profileFailed = false
        profileColumn = 0
        profileIndex = 0
        withAnimation(Motion.overlay) { overlay = .profile }
        Sounds.shared.play(.select)
        profileTask?.cancel()
        loadProfileActivity(handle)
        loadProfileGallery(handle)
        loadProfileShowcase(handle)
        profileTask = Task {
            do {
                let page = try await together.profilePage(handle, card: card)
                guard !Task.isCancelled, overlay == .profile else { return }
                withAnimation(Motion.overlay) {
                    profilePage = page
                    profileColumn = (page.library.value?.isEmpty ?? true) && !(page.trophies.value?.isEmpty ?? true) ? 1 : 0
                }
            } catch is CancellationError {
            } catch let problem as TogetherProblem where problem.status == 404 {
                show(T.format(.friendsNoOne, "@\(card.handle)"), symbol: "person.crop.circle.badge.questionmark")
                closeProfile()
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { profileFailed = true }
            }
        }
    }

    /// Back to the panel the profile was opened from, on the same row.
    func closeProfile() {
        profileTask?.cancel()
        profileTask = nil
        guard overlay == .profile else { return }
        guard let back = profileReturn else { return closeOverlay() }
        profileReturn = nil
        withAnimation(Motion.overlay) {
            overlay = back.overlay
            panelCategory = back.category
            panelRow = back.row
            panelInRows = back.inRows
        }
        if back.overlay == .friends { refreshFriends() }
        Sounds.shared.play(.back)
    }

    var profileGames: [TogetherPlayedGame] { profilePage?.library.value ?? [] }
    var profileTrophies: [TogetherEarnedTrophy] { Array((profilePage?.trophies.value ?? []).prefix(Self.recentTrophyCount)) }

    /// Up and down in a column, left and right between the games and the trophies.
    func profileCommand(_ command: Command) {
        if cloud.viewing != nil {
            if command == .back || command == .select || command == .options { closeViewer() }
            return
        }
        let counts = [profileGames.count, profileTrophies.count, social.profileActivity?.count ?? 0]
        switch command {
        case .up, .down:
            let count = counts[profileColumn]
            let next = min(count - 1, max(0, profileIndex + (command == .down ? 1 : -1)))
            guard count > 0, next != profileIndex else { return }
            profileIndex = next
            Sounds.shared.play(.move)
        case .left, .right:
            // The next column that has something, that way.
            let way = command == .right ? 1 : -1
            guard let column = stride(from: profileColumn + way, to: way > 0 ? counts.count : -1, by: way).first(where: { counts[$0] > 0 }) else { return }
            withAnimation(Motion.focus) {
                profileColumn = column
                profileIndex = min(profileIndex, counts[column] - 1)
            }
            Sounds.shared.play(.move)
        case .options:
            // A friend's profile: their trophies beside the user's.
            if let profile = profilePage?.profile, !profile.isMe { openCompare() } else { closeProfile() }
        case .select:
            // A game of someone else's: that game's trophies side by side.
            guard let profile = profilePage?.profile, !profile.isMe, profileColumn == 0, profileGames.indices.contains(profileIndex) else { return }
            openCompare(profileGames[profileIndex].titleId)
        case .back:
            closeProfile()
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    /// The level the profile on screen shows: the user's own as last heard (a level up moves it).
    var profileLevel: TogetherTrophyLevel? {
        guard let profile = profilePage?.profile else { return nil }
        return profile.isMe ? togetherProfile?.trophyLevel ?? profile.trophyLevel : profile.trophyLevel
    }

    /// The icon of a game in someone's library: this Mac's own copy when it has the game.
    func localIcon(_ titleID: String) -> URL? { games.first { $0.titleID == titleID }?.icon }

    func previewProfile(_ page: TogetherProfilePage?, column: Int = 0, index: Int = 0, showcase: TogetherShowcase? = nil) {
        social.profileShowcase = showcase
        profileCard = page.map { TogetherPerson(userId: $0.profile.userId, handle: $0.profile.handle, displayName: $0.profile.displayName, avatar: $0.profile.avatar,
                                                privateName: $0.profile.privateName, privateAvatar: $0.profile.privateAvatar) }
        profilePage = page
        profileColumn = column
        profileIndex = index
        overlay = .profile
    }
}

struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let page = model.profilePage
        VStack(alignment: .leading, spacing: 30 * scale) {
            header(page)
            if let page, let showcase = model.social.profileShowcase, !showcase.isEmpty || (showcase.isPrivate && !page.profile.isMe && (page.library != .private || page.trophies != .private)) {
                ProfileShowcaseStrip(showcase: showcase, owner: page.profile.displayName).transition(.opacity)
            }
            if page != nil, let gallery = model.cloud.profileGallery {
                ProfileGalleryStrip(gallery: gallery, mine: page?.profile.isMe == true).transition(.opacity)
            }
            if let page {
                HStack(alignment: .top, spacing: 28 * scale) {
                    gamesColumn(page)
                        .frame(maxWidth: .infinity)
                    trophiesColumn(page)
                        .frame(width: 440 * scale)
                    ProfileActivityColumn()
                        .frame(width: 420 * scale)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 18 * scale) {
                    if model.profileFailed {
                        ProfileNotice(symbol: "wifi.exclamationmark", text: T.text(.profileFailed))
                    } else {
                        IndeterminateLine(color: model.accent).frame(width: 260 * scale)
                        Text(T.text(.profileLoading)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 80 * scale)
        .padding(.vertical, 56 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .screenFrost(0.74)
        .overlay {
            if let media = model.cloud.viewing { MediaViewer(media: media).transition(.opacity) }
        }
        // Capitals in the launcher's language: "PROFİLİM", not "PROFILIM".
        .environment(\.locale, T.locale)
    }

    // MARK: Card

    private func header(_ page: TogetherProfilePage?) -> some View {
        let card = model.profileCard
        let profile = page?.profile
        // A friend's friends-only name and picture (the user's own too), the handle under it.
        let identity = (profile.map { model.shown($0) } ?? card.map { model.shown($0) })
        let name = identity?.name ?? ""
        let handle = profile?.handle ?? card?.handle ?? ""
        return HStack(alignment: .center, spacing: 30 * scale) {
            ProfileAvatar(url: identity?.avatar, name: name, size: 128 * scale)
                .overlay(alignment: .bottomTrailing) {
                    if profile?.isMe == true, model.appearingOffline { AppearingOfflineDot(size: 34 * scale).offset(x: -4 * scale, y: -4 * scale) }
                }
            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(profile?.isMe == true ? T.text(.profileMine) : T.text(.profileTitle))
                    .font(.display(13 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(name)
                    .font(.display(40 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 12 * scale) {
                    Text("@\(handle)").font(.display(17 * scale, .medium)).foregroundStyle(.white.opacity(0.75))
                    if let identity, identity.isPrivate {
                        // Whose real name it is stays clear: the public name and who sees this.
                        Label(identity.publicName == identity.name ? TPro.text(.friendsOnlyBadge) : "\(identity.publicName) · \(TPro.text(.friendsOnlyBadge))", systemImage: "lock.fill")
                            .font(.display(12 * scale, .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let country = profile?.country, let flag = Self.flag(country) { Text(flag).font(.system(size: 17 * scale)) }
                    if let tag = profile.flatMap(Self.relation) {
                        Text(tag)
                            .font(.display(12 * scale, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10 * scale)
                            .padding(.vertical, 4 * scale)
                            .background(Capsule().fill(model.accent.opacity(0.35)))
                            .overlay(Capsule().strokeBorder(model.accent.opacity(0.6), lineWidth: 1))
                    }
                    if profile?.isMe == true, model.appearingOffline { AppearingOfflineTag() }
                }
                if let level = model.profileLevel {
                    LevelCard(level: level).padding(.vertical, 2 * scale)
                }
                if page?.detailsPrivate == true {
                    Label(T.text(.profileDetailsPrivate), systemImage: "lock.fill")
                        .font(.display(15 * scale))
                        .foregroundStyle(.white.opacity(0.5))
                } else if let bio = profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.display(16 * scale))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .frame(maxWidth: 560 * scale, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 26 * scale) {
                HStack(spacing: 22 * scale) {
                    Hint(keys: "← → ↑ ↓", label: T.text(.hintMove))
                    if let profile, !profile.isMe { Hint(keys: "O / △", label: TL.text(.compareTrophies)) }
                    Hint(keys: "esc / ○", label: T.text(.hintBack))
                }
                if let page { totals(page.totals) }
            }
        }
    }

    private func totals(_ totals: TogetherProfilePage.Totals?) -> some View {
        HStack(spacing: 12 * scale) {
            stat(totals.map { "\($0.games)" }, T.text(.profileGames), symbol: "gamecontroller.fill")
            stat(totals.map { Self.hours($0.seconds) }, T.text(.profileHours), symbol: "clock.fill")
            stat(totals.map { "\($0.trophies)" }, T.text(.profileTrophies), symbol: "trophy.fill")
            stat(totals.map { "\($0.points)" }, T.text(.profilePoints), symbol: "star.fill")
        }
    }

    private func stat(_ value: String?, _ label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(value ?? "—")
                .font(.display(28 * scale, .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Label(label, systemImage: symbol)
                .font(.display(12 * scale, .semibold))
                .foregroundStyle(model.accent)
                .labelStyle(ProfileStatLabel())
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .frame(minWidth: 118 * scale, alignment: .leading)
        .glass(16 * scale, opacity: 0.3)
    }

    // MARK: Columns

    private func gamesColumn(_ page: TogetherProfilePage) -> some View {
        ProfileColumn(title: T.text(.profileGamesTitle), count: page.library.value?.count, focusedIndex: model.profileColumn == 0 ? model.profileIndex : nil,
                      ids: model.profileGames.map(\.id)) {
            switch page.library {
            case .shown(let games) where games.isEmpty:
                ProfileNotice(symbol: "gamecontroller", text: T.text(.profileNoGames))
            case .shown(let games):
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    ProfileGameRow(game: game, icon: model.localIcon(game.titleId), focused: model.profileColumn == 0 && model.profileIndex == index)
                        .id(game.id)
                        .onTapGesture { model.profileColumn = 0; model.profileIndex = index }
                }
            case .private:
                ProfileNotice(symbol: "lock.fill", text: privateText(page.profile))
            case .failed:
                ProfileNotice(symbol: "wifi.exclamationmark", text: T.text(.profileFailed))
            }
        }
    }

    private func trophiesColumn(_ page: TogetherProfilePage) -> some View {
        let trophies = model.profileTrophies
        return ProfileColumn(title: T.text(.profileRecentTrophies), count: nil, focusedIndex: model.profileColumn == 1 ? model.profileIndex : nil, ids: trophies.map(\.id)) {
            switch page.trophies {
            case .shown where trophies.isEmpty:
                ProfileNotice(symbol: "trophy", text: T.text(.profileNoTrophies))
            case .shown:
                ForEach(Array(trophies.enumerated()), id: \.element.id) { index, trophy in
                    ProfileTrophyRow(trophy: trophy, focused: model.profileColumn == 1 && model.profileIndex == index)
                        .id(trophy.id)
                        .onTapGesture { model.profileColumn = 1; model.profileIndex = index }
                }
            case .private:
                ProfileNotice(symbol: "lock.fill", text: privateText(page.profile))
            case .failed:
                ProfileNotice(symbol: "wifi.exclamationmark", text: T.text(.profileFailed))
            }
        }
    }

    /// Not friends: only friends may look. Friends (or oneself): the owner keeps it private.
    private func privateText(_ profile: TogetherProfile) -> String {
        profile.friendship == "friends" || profile.isMe ? T.format(.profilePrivate, profile.displayName) : T.format(.profileFriendsOnly, profile.displayName)
    }

    // MARK: Formats

    static func relation(_ profile: TogetherProfile) -> String? {
        switch profile.friendship {
        case "me": return T.text(.profileYou)
        case "friends": return T.text(.profileFriend)
        case "pending_out": return T.text(.friendsWaiting)
        case "pending_in": return T.text(.friendsWantsToBe)
        default: return nil
        }
    }

    /// Whole hours; under one hour, "<1".
    static func hours(_ seconds: Int) -> String {
        seconds > 0 && seconds < 3600 ? "<1" : "\(seconds / 3600)"
    }

    /// "12 h 30 min", "42 h", "45 min".
    static func playTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return T.format(.profileMinutes, max(minutes, seconds > 0 ? 1 : 0)) }
        return minutes % 60 == 0 ? T.format(.profileHoursOnly, minutes / 60) : T.format(.profileHoursMinutes, minutes / 60, minutes % 60)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = T.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = T.locale
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// "TR" → 🇹🇷.
    static func flag(_ country: String) -> String? {
        let letters = country.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
        return String(String.UnicodeScalarView(letters.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }
}

/// A column of the profile: a title, then its rows, scrolled to the focused one.
struct ProfileColumn<Content: View>: View {
    let title: String
    let count: Int?
    let focusedIndex: Int?
    let ids: [String]
    @ViewBuilder let content: Content
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            if !title.isEmpty {
                HStack(spacing: 10 * scale) {
                    Text(title).font(.display(20 * scale, .semibold)).foregroundStyle(.white)
                    if let count, count > 0 {
                        Text("\(count)").font(.display(15 * scale, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 8 * scale)
            }
            if previewRender {
                Color.clear.overlay(alignment: .top) { rows }.clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) { rows }
                        .onChange(of: focusedIndex) { _, index in
                            guard let index, ids.indices.contains(index) else { return }
                            withAnimation(Motion.focus) { proxy.scrollTo(ids[index], anchor: .center) }
                        }
                }
            }
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 10 * scale) { content }.padding(8 * scale)
    }
}

struct ProfileGameRow: View {
    let game: TogetherPlayedGame
    let icon: URL?
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 18 * scale) {
            let size = 64 * scale
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).fill(Color.white.opacity(0.07))
                if let icon {
                    ArtworkImage(url: icon, maxPixels: 400)
                } else if let remote = game.iconUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: remote) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { placeholder(size) }
                } else {
                    placeholder(size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(game.name(in: T.language.rawValue))
                    .font(.display(18 * scale, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text([ProfileView.playTime(game.secondsPlayed), game.lastPlayedAt.map { T.format(.profileLastPlayed, ProfileView.relative($0)) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.display(14 * scale))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 12 * scale)
            VStack(alignment: .trailing, spacing: 8 * scale) {
                HStack(spacing: 8 * scale) {
                    Image(systemName: "trophy.fill").foregroundStyle(TrophySet.Grade.gold.color.opacity(game.trophiesEarned > 0 ? 1 : 0.45))
                    Text(game.trophiesTotal.map { "\(game.trophiesEarned)/\($0)" } ?? "\(game.trophiesEarned)").monospacedDigit()
                    if let progress = game.progress {
                        Text("\(progress)%").monospacedDigit().foregroundStyle(.white.opacity(0.55))
                    }
                }
                .font(.display(14 * scale, .semibold))
                .foregroundStyle(.white.opacity(0.85))
                if let progress = game.progress {
                    ProgressLine(fraction: Double(progress) / 100, color: model.accent, height: 4 * scale)
                        .frame(width: 150 * scale)
                }
            }
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 12 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 16 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    private func placeholder(_ size: CGFloat) -> some View {
        Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.34)).foregroundStyle(.white.opacity(0.4))
    }
}

struct ProfileTrophyRow: View {
    let trophy: TogetherEarnedTrophy
    let focused: Bool
    @Environment(\.scale) private var scale

    /// Read so the view is drawn again in another language (its texts come from T).
    @Environment(\.languageCode) private var languageCode

    var body: some View {
        let _ = languageCode
        let grade = TrophySet.Grade(name: trophy.grade)
        HStack(spacing: 16 * scale) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 22 * scale, weight: .semibold))
                .foregroundStyle(grade.color)
                .frame(width: 52 * scale, height: 52 * scale)
                .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(grade.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text(trophy.name(in: T.language.rawValue) ?? T.text(.trophyHidden))
                    .font(.display(16 * scale, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(trophy.gameName(in: T.language.rawValue)) · \(ProfileView.day(trophy.earnedAt))")
                    .font(.display(13 * scale))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8 * scale)
            if let label = trophy.rarityLabel {
                VStack(alignment: .trailing, spacing: 4 * scale) {
                    Text(Self.rarityName(label))
                        .font(.display(13 * scale, .semibold))
                        .foregroundStyle(Self.rarityColor(label))
                    if let rarity = trophy.rarity {
                        Text(Self.percent(rarity))
                            .font(.display(12 * scale, .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 11 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.13 : 0.05)))
        .focusRing(focused, radius: 14 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    static func rarityName(_ label: String) -> String {
        switch label {
        case "ultra_rare": return T.text(.rarityUltraRare)
        case "very_rare": return T.text(.rarityVeryRare)
        case "rare": return T.text(.rarityRare)
        case "uncommon": return T.text(.rarityUncommon)
        default: return T.text(.rarityCommon)
        }
    }

    static func rarityColor(_ label: String) -> Color {
        switch label {
        case "ultra_rare": return Color(red: 1, green: 0.62, blue: 0.9)
        case "very_rare": return Color(red: 0.68, green: 0.6, blue: 1)
        case "rare": return Color(red: 0.48, green: 0.78, blue: 1)
        default: return .white.opacity(0.7)
        }
    }

    /// "3.1%", or "%3,1" in Turkish.
    static func percent(_ share: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.locale = T.locale
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: share)) ?? "\(Int(share * 100))%"
    }
}

/// An empty, private or failed section.
struct ProfileNotice: View {
    let symbol: String
    let text: String
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 14 * scale) {
            Image(systemName: symbol).font(.system(size: 18 * scale, weight: .semibold))
            Text(text).font(.display(16 * scale, .medium)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 20 * scale)
        .padding(.vertical, 22 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [5 * scale, 4 * scale])))
    }
}

/// The picture someone chose, or their initial on the accent.
struct ProfileAvatar: View {
    let url: String?
    let name: String
    let size: CGFloat
    var glow = true
    /// A picture on this Mac, before the avatar's address and the initial.
    var picture: NSImage? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var look

    var body: some View {
        ZStack {
            // The Glass theme's light Ice accent takes dark ink, on a fill that stays light enough for it.
            Circle().fill(LinearGradient(colors: [model.accent, model.accent.opacity(look.glass ? 0.8 : 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.prefix(1)).uppercased()).font(.display(size * 0.42, .semibold)).foregroundStyle(look.glass ? model.accent.onFill : .white)
            if let picture {
                Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else if let remote = url.flatMap(URL.init(string:)) {
                AsyncImage(url: remote) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: glow ? 2 : 1))
        .shadow(color: model.accent.opacity(glow ? 0.35 : 0), radius: size * 0.18)
    }
}

/// A stat's label: a small icon, then the word.
struct ProfileStatLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title.textCase(.uppercase).tracking(0.6)
        }
    }
}

extension TrophySet.Grade {
    /// From AnyTogether's grade names.
    init(name: String) {
        switch name {
        case "platinum": self = .platinum
        case "gold": self = .gold
        case "silver": self = .silver
        default: self = .bronze
        }
    }
}
