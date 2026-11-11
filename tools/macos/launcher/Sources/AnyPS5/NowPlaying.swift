import AnyPS5Core
import AppKit
import SwiftUI

/// Now playing: what Spotify or Music plays, as a card in the quick menu with previous, play or
/// pause and next, and (when the user chose so) as "Listening to …" for friends on AnyTogether.
///
/// The players are read with AppleScript, the public way. macOS has no public way to ask what any
/// app plays (MediaRemote is private), so only these two can be read here, while Windows and Linux
/// read the system's media session and work with any player. A player is asked only while it
/// runs (it is never started), and only when the card is about to show or the user shares what
/// they listen to: macOS then asks the user once for each of the two.

/// The players through AppleScript, on one thread of their own: a script waits while macOS asks
/// the user, and the interface must not.
final class ScriptedPlayers: NowPlayingSource, @unchecked Sendable {
    /// errAEEventNotPermitted: the user (or a profile) does not let the launcher script the app.
    static let notPermitted = -1743
    /// A cover larger than this is not shown.
    static let coverLimit = 4 * 1024 * 1024

    private let worker = ScriptThread()
    /// All below are the worker's.
    private var denied: Set<NowPlayingPlayer> = []
    private var covers: [NowPlayingPlayer: (key: String, data: Data?)] = [:]

    /// What a player plays, as a list: state, title, artist, cover address (Spotify's only). The
    /// script names the app by its identifier and asks nothing of one that does not run.
    static func stateScript(_ player: NowPlayingPlayer) -> String {
        let cover = player == .spotify ? """
                try
                    set theCover to (artwork url of theTrack) as text
                end try
        """ : ""
        return """
        if application id "\(player.rawValue)" is running then
            tell application id "\(player.rawValue)"
                if player state is playing then
                    set theState to "playing"
                else if player state is paused then
                    set theState to "paused"
                else
                    return {"stopped", "", "", ""}
                end if
                set theTrack to current track
                set theTitle to ""
                set theArtist to ""
                set theCover to ""
                try
                    set theTitle to (name of theTrack) as text
                end try
                try
                    set theArtist to (artist of theTrack) as text
                end try
        \(cover)
                return {theState, theTitle, theArtist, theCover}
            end tell
        end if
        return {"stopped", "", "", ""}
        """
    }

    /// Music's cover of the track playing, as the picture's own bytes; "" when it has none.
    static let musicCoverScript = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            end try
        end tell
    end if
    return ""
    """

    static func commandScript(_ command: NowPlayingCommand, _ player: NowPlayingPlayer) -> String {
        let verb: String
        switch command {
        case .previous: verb = "previous track"
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        }
        return """
        if application id "\(player.rawValue)" is running then
            tell application id "\(player.rawValue)" to \(verb)
        end if
        """
    }

    /// The players that run now, by the system's list of running apps, with the names it has
    /// for them.
    static func running() -> [NowPlayingPlayer: String?] {
        var found: [NowPlayingPlayer: String?] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let player = app.bundleIdentifier.flatMap(NowPlayingPlayer.init(rawValue:)), found[player] == nil else { continue }
            found[player] = .some(app.localizedName)
        }
        return found
    }

    func read(_ done: @escaping @Sendable ([NowPlayingReading], Set<NowPlayingPlayer>) -> Void) {
        let names = Self.running()
        let running = NowPlayingPlayer.allCases.filter { names[$0] != nil }
        worker.run { [self] in
            var readings: [NowPlayingReading] = []
            var fetch: (player: NowPlayingPlayer, key: String, url: URL)?
            for player in running where !denied.contains(player) {
                guard let result = execute(Self.stateScript(player), player), result.numberOfItems == 4,
                      let state = NowPlayingReading.State(rawValue: result.atIndex(1)?.stringValue ?? "") else { continue }
                var reading = NowPlayingReading(player: player, state: state, title: result.atIndex(2)?.stringValue ?? "", artist: result.atIndex(3)?.stringValue ?? "",
                                                name: names[player] ?? nil)
                if reading.track != nil {
                    let key = reading.title + "\n" + reading.artist
                    if let kept = covers[player], kept.key == key {
                        reading.artwork = kept.data
                    } else if player == .music {
                        let cover = musicCover()
                        covers[player] = (key, cover)
                        reading.artwork = cover
                    } else if let url = URL(string: result.atIndex(4)?.stringValue ?? ""), url.scheme == "https" {
                        fetch = (player, key, url)
                    } else {
                        covers[player] = (key, nil)
                    }
                }
                readings.append(reading)
            }
            // A player that quit has no cover to keep.
            for player in NowPlayingPlayer.allCases where !running.contains(player) { covers[player] = nil }
            done(readings, denied.intersection(running))
            // Spotify's cover is on the web: the words first, then again with the picture.
            guard let fetch else { return }
            let data = Self.download(fetch.url)
            covers[fetch.player] = (fetch.key, data)
            guard data != nil, let index = readings.firstIndex(where: { $0.player == fetch.player }) else { return }
            readings[index].artwork = data
            done(readings, denied.intersection(running))
        }
    }

    func send(_ command: NowPlayingCommand, to player: NowPlayingPlayer) {
        guard Self.running()[player] != nil else { return }
        worker.run { [self] in
            guard !denied.contains(player) else { return }
            _ = execute(Self.commandScript(command, player), player)
        }
    }

    func forgetDenials() {
        worker.run { [self] in denied = [] }
    }

    /// Runs a script for a player; nil when it failed. A refusal by macOS is remembered.
    private func execute(_ source: String, _ player: NowPlayingPlayer) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == Self.notPermitted { denied.insert(player) }
            return nil
        }
        return result
    }

    private func musicCover() -> Data? {
        guard let result = execute(Self.musicCoverScript, .music), result.descriptorType != typeUnicodeText, result.descriptorType != typeUTF8Text else { return nil }
        return Self.picture(result.data)
    }

    /// The bytes when they are a picture of a size worth showing.
    static func picture(_ data: Data) -> Data? {
        guard data.count > 64, data.count <= coverLimit, NSBitmapImageRep(data: data) != nil else { return nil }
        return data
    }

    /// The cover at an https address the player named, waited for at most a few seconds.
    private static func download(_ url: URL) -> Data? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        let done = DispatchSemaphore(value: 0)
        let found = Found()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 { found.set(ScriptedPlayers.picture(data)) }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + 6) == .timedOut { task.cancel() }
        return found.data
    }

    /// The download's answer, handed from its thread to the worker's.
    private final class Found: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: Data?
        var data: Data? { lock.withLock { kept } }
        func set(_ data: Data?) { lock.withLock { kept = data } }
    }
}

/// One thread that runs the scripts in turn; started with the first of them.
private final class ScriptThread: Thread {
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var started = false

    func run(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        if !started {
            started = true
            name = "org.anyps5.now-playing"
            qualityOfService = .utility
            start()
        }
        condition.signal()
        condition.unlock()
    }

    override func main() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            autoreleasepool { job() }
        }
    }
}

/// What the launcher keeps for Now playing: the players' source, the track, and the watch over
/// the players while someone needs it.
@MainActor
final class NowPlayingCenter {
    /// AppleScript in the app; the tests give a fake, the previews none.
    var source: NowPlayingSource?
    var state = NowPlayingState()
    /// The players macOS did not let the launcher ask.
    var denied: Set<NowPlayingPlayer> = []
    /// How often the players are asked while watched; nil while nobody needs them.
    private(set) var every: TimeInterval?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    var reading = false
    var readAgain = false
    var ends: Task<Void, Never>?

    /// Watches the players: their own change notifications (public, no permission needed) and a
    /// timer for what they do not announce. nil stops both.
    func watch(every interval: TimeInterval?, tick: @escaping @MainActor () -> Void) {
        guard interval != every else { return }
        every = interval
        timer?.invalidate()
        timer = nil
        guard let interval else {
            for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
            observers = []
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in Task { @MainActor in tick() } }
        timer?.tolerance = interval / 4
        guard observers.isEmpty else { return }
        observers = NowPlayingPlayer.allCases.map { player in
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(player.changeNotification), object: nil, queue: .main) { _ in
                Task { @MainActor in tick() }
            }
        }
    }
}

extension AppModel {
    /// With the quick menu open the players are asked this often, between their notifications.
    static let nowPlayingMenuEvery: TimeInterval = 3
    /// And this often while only friends are told.
    static let nowPlayingShareEvery: TimeInterval = 20

    var nowPlayingCardOn: Bool { preferences.nowPlayingCard ?? true }

    /// Whether the user may show friends what they listen to: signed in to AnyTogether and not
    /// under family limits (a child's profile).
    var nowPlayingMayShare: Bool { togetherUser != nil && familyRules == nil }
    var nowPlayingSharing: Bool { nowPlayingMayShare && preferences.nowPlayingShare == true }

    /// The track the quick menu's card shows.
    var nowPlayingTrack: NowPlayingTrack? { nowPlayingCardOn ? nowPlaying.state.track : nil }

    /// What friends are told now: nothing unless the user chose it, something plays (or paused
    /// within the last minute) and they may share.
    var nowPlayingListening: TogetherListening? { nowPlayingSharing ? nowPlaying.state.listening() : nil }

    private var nowPlayingSource: NowPlayingSource? {
        if nowPlaying.source == nil, persists { nowPlaying.source = ScriptedPlayers() }
        return nowPlaying.source
    }

    /// The quick menu opened or closed, a switch changed, the account signed in: the players are
    /// watched only while the card shows or friends are told.
    func followNowPlaying() {
        let menu = nowPlayingCardOn && overlay == .quickMenu
        let wanted = menu || nowPlayingSharing
        nowPlaying.watch(every: wanted ? (menu ? Self.nowPlayingMenuEvery : Self.nowPlayingShareEvery) : nil) { [weak self] in self?.nowPlayingTick() }
        if wanted { readNowPlaying() }
        shareListening()
    }

    /// The timer or a player's notification: the account or the family may have changed since.
    private func nowPlayingTick() {
        let menu = nowPlayingCardOn && overlay == .quickMenu
        guard menu || nowPlayingSharing else { return followNowPlaying() }
        readNowPlaying()
    }

    /// Asks the players; one question at a time, and once more when something changed meanwhile.
    func readNowPlaying() {
        guard let source = nowPlayingSource else { return }
        guard !nowPlaying.reading else {
            nowPlaying.readAgain = true
            return
        }
        nowPlaying.reading = true
        source.read { readings, denied in
            Task { @MainActor [weak self] in self?.nowPlayingRead(readings, denied: denied) }
        }
    }

    func nowPlayingRead(_ readings: [NowPlayingReading], denied: Set<NowPlayingPlayer>, now: Date = Date()) {
        nowPlaying.reading = false
        let had = nowPlayingTrack != nil
        let changed = nowPlaying.state.update(readings, now: now)
        if changed || denied != nowPlaying.denied {
            nowPlaying.denied = denied
            objectWillChange.send()
            // The card came or went, just before Close Game: the focus stays on the row it was on,
            // and one that was on the card moves up, never onto Close Game.
            let has = nowPlayingTrack != nil
            if overlay == .quickMenu, had != has {
                let count = quickMenuRows().count
                if has, menuIndex >= count - 2 { menuIndex += 1 }
                if !has, menuIndex >= count - 1 { menuIndex = max(0, menuIndex - 1) }
            }
        }
        shareListening(now: now)
        if nowPlaying.readAgain {
            nowPlaying.readAgain = false
            readNowPlaying()
        }
    }

    /// Tells the gateway what friends may see, and again when a pause's minute is over.
    func shareListening(now: Date = Date()) {
        togetherSocket?.setListening(nowPlayingListening)
        nowPlaying.ends?.cancel()
        nowPlaying.ends = nil
        guard nowPlayingSharing, let end = nowPlaying.state.listeningEnds(now: now) else { return }
        nowPlaying.ends = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.5))
            guard let self, !Task.isCancelled else { return }
            self.nowPlaying.ends = nil
            self.shareListening()
        }
    }

    /// Previous, play or pause, next: sent to the player the card shows, which is asked again a
    /// moment later (its own notification usually comes first).
    func nowPlayingCommand(_ command: NowPlayingCommand) {
        guard let track = nowPlayingTrack, let player = NowPlayingPlayer(rawValue: track.playerID) else { return }
        Sounds.shared.play(.move)
        nowPlayingSource?.send(command, to: player)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.readNowPlaying()
        }
    }

    /// Settings › Behaviour, after Discord's rows: the card's switch (on unless turned off) and,
    /// for someone signed in to AnyTogether and not under family limits, the friends' switch (off
    /// unless turned on).
    func nowPlayingSettingsRows() -> [PanelRow] {
        var rows = [
            PanelRow(id: "nowPlayingCard", title: TH.text(.nowPlayingCard), detail: TH.text(nowPlaying.denied.isEmpty ? .nowPlayingCardDetail : .nowPlayingDenied), symbol: "music.note",
                     kind: .toggle(nowPlayingCardOn) { [weak self] value in
                         guard let self else { return }
                         self.preferences.nowPlayingCard = value ? nil : false
                         if value {
                             // Turned on: macOS may be asked again, and asks the user here.
                             self.nowPlaying.source?.forgetDenials()
                             self.nowPlaying.denied = []
                             self.readNowPlaying()
                         }
                         self.followNowPlaying()
                     }),
        ]
        if nowPlayingMayShare {
            rows.append(PanelRow(id: "nowPlayingShare", title: TH.text(.nowPlayingShare), detail: TH.text(.nowPlayingShareDetail), symbol: "headphones",
                                 kind: .toggle(preferences.nowPlayingShare == true) { [weak self] value in
                                     self?.preferences.nowPlayingShare = value ? true : nil
                                     self?.followNowPlaying()
                                 }))
        }
        return rows
    }

    /// "Listening to Around the World, Daft Punk", as a friend's line says it.
    static func listeningText(_ listening: TogetherListening) -> String {
        listening.artist.map { TH.format(.friendsListeningBy, listening.title, $0) } ?? TH.format(.friendsListening, listening.title)
    }

    /// The card's small line: "Now playing in Spotify", "Paused in Music".
    static func nowPlayingLabel(_ track: NowPlayingTrack) -> String {
        TH.format(track.playing ? .nowPlayingIn : .nowPlayingPausedIn, track.player)
    }
}

/// The quick menu's Now playing card: the cover, where it plays, the title and artist, and
/// previous, play or pause and next. Focused, ← and → skip and ↩ / ✕ plays or pauses; the three
/// buttons take the mouse.
struct NowPlayingCard: View {
    let track: NowPlayingTrack
    let focused: Bool
    let accent: Color
    let focus: () -> Void
    let command: (NowPlayingCommand) -> Void
    @Environment(\.scale) private var scale

    var body: some View {
        let ink: Color = focused ? .black : .white
        HStack(spacing: 14 * scale) {
            cover
            VStack(alignment: .leading, spacing: 3 * scale) {
                HStack(spacing: 7 * scale) {
                    EqualiserBars(playing: track.playing, color: focused ? .black : accent)
                        .frame(width: 13 * scale, height: 11 * scale)
                    Text(AppModel.nowPlayingLabel(track).uppercased())
                        .font(.display(10.5 * scale, .semibold)).tracking(1.1 * scale)
                        .opacity(0.62).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(track.title)
                    .font(.display(18 * scale, .semibold)).tracking(-0.2 * scale)
                    .lineLimit(1).truncationMode(.tail)
                if let artist = track.artist {
                    Text(artist).font(.display(12.5 * scale)).opacity(0.62).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6 * scale) {
                button(.previous, symbol: "backward.fill", label: TH.text(.nowPlayingPrevious), ink: ink)
                button(.playPause, symbol: track.playing ? "pause.fill" : "play.fill", label: TH.text(.nowPlayingPlayPause), ink: ink, main: true)
                button(.next, symbol: "forward.fill", label: TH.text(.nowPlayingNext), ink: ink)
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, 12 * scale)
        .padding(.trailing, 14 * scale)
        .padding(.vertical, 11 * scale)
        .frame(maxWidth: .infinity, minHeight: 78 * scale)
        .background {
            FocusFill(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(0.07))
        }
        .shadow(color: Color.white.opacity(focused ? 0.25 : 0), radius: 12 * scale)
        .scaleEffect(focused ? 1.02 : 1)
        .animation(Motion.focus, value: focused)
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
        .accessibilityElement(children: .contain)
        .accessibilityLabel([AppModel.nowPlayingLabel(track), track.title, track.artist].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 11 * scale, style: .continuous)
        ZStack {
            shape.fill((focused ? Color.black : Color.white).opacity(0.1))
            if let data = track.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 22 * scale, weight: .semibold)).opacity(0.55)
            }
        }
        .frame(width: 56 * scale, height: 56 * scale)
        .clipShape(shape)
        .overlay(shape.strokeBorder((focused ? Color.black : Color.white).opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8 * scale, y: 3 * scale)
        .accessibilityHidden(true)
    }

    private func button(_ which: NowPlayingCommand, symbol: String, label: String, ink: Color, main: Bool = false) -> some View {
        let size = (main ? 40 : 32) * scale
        return Button {
            focus()
            command(which)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: (main ? 15 : 12) * scale, weight: .bold))
                .foregroundStyle(main ? (focused ? Color.white : Color.black) : ink)
                .frame(width: size, height: size)
                .background(Circle().fill(main ? ink : ink.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Three small bars that move while something plays and rest while it is paused, or when motion
/// is reduced.
struct EqualiserBars: View {
    let playing: Bool
    let color: Color

    /// A bar's height from 0 to 1 at a time: each bar at its own pace, so they never line up.
    static func level(_ bar: Int, at time: TimeInterval) -> Double {
        let pace = [5.1, 7.3, 6.2][bar % 3], phase = [0.0, 1.7, 0.6][bar % 3]
        return 0.35 + 0.65 * abs(sin(time * pace / 2 + phase))
    }

    static let resting: [Double] = [0.45, 0.8, 0.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing || Motion.reduced)) { context in
            GeometryReader { area in
                let width = area.size.width / 5
                HStack(alignment: .bottom, spacing: width) {
                    ForEach(0..<3, id: \.self) { bar in
                        let level = playing && !Motion.reduced ? Self.level(bar, at: context.date.timeIntervalSinceReferenceDate) : Self.resting[bar] * (playing ? 1 : 0.5)
                        Capsule().fill(color).frame(width: width, height: max(width, area.size.height * level))
                    }
                }
                .frame(width: area.size.width, height: area.size.height, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}
