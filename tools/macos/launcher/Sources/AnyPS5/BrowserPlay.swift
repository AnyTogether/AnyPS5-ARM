import AnyPS5Core
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Play from a browser (Settings → Advanced, under the phones): a phone with no app scans a QR
/// code and its browser becomes a pad, through the phone server like the phone app
/// (BrowserPadServer). The server runs only while the QR code is shown, while browsers it let in
/// are still connected (and a short while after, for a reload or a locked screen), or always
/// when Keep On is chosen; with the setting off it never runs.
@MainActor
final class BrowserPlay: ObservableObject {
    /// The QR code's link, its token good until `expires`.
    @Published private(set) var url: URL?
    @Published private(set) var expires: Date?
    /// The browsers with the page open, and whether each has been let in.
    @Published private(set) var pads: [Pad] = []
    /// No local network address, or the port would not open.
    @Published private(set) var unavailable = false
    @Published var showing = false

    struct Pad: Equatable, Identifiable {
        let id: String
        let name: String
        let allowed: Bool
    }

    private var server: BrowserPadServer?
    private var timer: Timer?
    private var quietSince: Date?
    private var hadPads = false
    /// After the last browser leaves, how long the server stays up for it to come back.
    static let grace: TimeInterval = 120

    /// The page every launcher build carries (build_launcher_app.sh), else the source tree's.
    static var page: Data? {
        if let bundled = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "browser-pad"), let data = try? Data(contentsOf: bundled) { return data }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../BrowserPad/index.html").standardized
        return try? Data(contentsOf: source)
    }

    /// Starts or stops the server for what is wanted now.
    func update(remote: RemoteServer?, devices: PairedDevices, enabled: Bool, keepOn: Bool) {
        let connected = !pads.isEmpty
        // The grace is for a browser that was here: with none ever, closing the code stops it.
        if connected {
            quietSince = nil
            hadPads = true
        } else if hadPads, quietSince == nil {
            quietSince = Date()
        }
        let recent = quietSince.map { Date().timeIntervalSince($0) < Self.grace } ?? false
        let wanted = enabled && remote?.controlPort != nil && (showing || keepOn || connected || (server != nil && recent))
        let host = wanted ? BrowserPadServer.lanAddress() : nil
        if let server, !wanted || host != server.host {
            server.stop()
            self.server = nil
            hadPads = false
            quietSince = nil
            refresh()
        }
        guard wanted, server == nil, let remote else {
            if wanted, host == nil { unavailable = true }
            return
        }
        guard let host, let page = Self.page, let control = remote.controlPort else { return unavailable = true }
        let changed: @Sendable () -> Void = { Task { @MainActor [weak self] in self?.refresh() } }
        for port in [BrowserPadServer.preferredPort, 0] {
            let attempt = BrowserPadServer(host: host, port: port, page: page, controlPort: control, devices: devices,
                                           players: { remote.phonePlayers }, changed: changed)
            do {
                try attempt.start()
                server = attempt
                unavailable = false
                break
            } catch {
                RemoteServer.log.error("browser pad: \(String(describing: error), privacy: .public)")
            }
        }
        if server == nil { unavailable = true }
        refresh()
    }

    /// Keeps the QR code's token fresh and the list of browsers current, once a second while
    /// anything is up.
    func watch(_ tick: @escaping @MainActor () -> Void) {
        guard timer == nil, server != nil || showing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                tick()
                // Nothing up any more: no more ticks until it is wanted again.
                if let self, self.server == nil, !self.showing {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }

    func refresh() {
        guard let server else {
            url = nil
            expires = nil
            pads = []
            return
        }
        let link = server.pairingURL
        if link != url { url = link }
        let good = server.access.currentToken().expires
        if good != expires { expires = good }
        let now = server.connected.map { Pad(id: $0.deviceID, name: $0.name, allowed: $0.allowed) }
        if now != pads { pads = now }
    }

    var running: Bool { server != nil }

    /// A fresh code at once (the old one stops working).
    func renew() {
        server?.access.renewToken()
        refresh()
    }

    /// What the screen shows, for `--render-preview`.
    func preview(url: URL?, pads: [Pad], unavailable: Bool = false) {
        self.url = url
        expires = Date().addingTimeInterval(97)
        self.pads = pads
        self.unavailable = unavailable
    }

    func stop() {
        server?.stop()
        server = nil
        refresh()
    }
}

extension AppModel {
    var browserPlayEnabled: Bool { preferences.browserPlay ?? true }

    /// Settings → Advanced: the rows under the phones.
    func browserPlayRows() -> [PanelRow] {
        var rows = [PanelRow(id: "browserPlay", title: TW.text(.title), detail: TW.text(browserPlayEnabled ? .rowDetail : .offDetail), symbol: "qrcode",
                             kind: .toggle(browserPlayEnabled) { [weak self] value in
                                 self?.preferences.browserPlay = value ? nil : false
                                 self?.updateBrowserPlay()
                             })]
        guard browserPlayEnabled else { return rows }
        rows.append(PanelRow(id: "browserPlayShow", title: TW.text(.showCode), detail: TW.text(.showCodeDetail), symbol: "qrcode.viewfinder",
                             kind: .action(destructive: false) { [weak self] in self?.openBrowserPlay() }))
        rows.append(PanelRow(id: "browserPlayKeep", title: TW.text(.keepOn), detail: TW.text(.keepOnDetail), symbol: "antenna.radiowaves.left.and.right",
                             kind: .toggle(preferences.browserPlayAlways == true) { [weak self] value in
                                 self?.preferences.browserPlayAlways = value ? true : nil
                                 self?.updateBrowserPlay()
                             }))
        return rows
    }

    func openBrowserPlay() {
        browserPlay.showing = true
        updateBrowserPlay()
        browserPlay.renew()
        withAnimation(Motion.overlay) { overlay = .browserPlay }
        Sounds.shared.play(.select)
    }

    func closeBrowserPlay() {
        browserPlay.showing = false
        updateBrowserPlay()
        withAnimation(Motion.overlay) { overlay = .settings }
        Sounds.shared.play(.back)
    }

    func browserPlayCommand(_ command: Command) -> Bool {
        switch command {
        case .back, .select: closeBrowserPlay()
        case .options: browserPlay.renew()
        default: break
        }
        return true
    }

    /// Starts or stops the browser pad server for what the settings and the screen want now.
    func updateBrowserPlay() {
        browserPlay.update(remote: remote, devices: pairedDevices, enabled: browserPlayEnabled, keepOn: preferences.browserPlayAlways == true)
        browserPlay.watch { [weak self] in
            guard let self else { return }
            self.browserPlay.refresh()
            self.browserPlay.update(remote: self.remote, devices: self.pairedDevices, enabled: self.browserPlayEnabled, keepOn: self.preferences.browserPlayAlways == true)
        }
    }
}

/// The QR code to scan, how to, and the browsers connected so far.
struct BrowserPlayCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var play: BrowserPlay
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            FrostFill(opacity: 0.55).ignoresSafeArea()
            HStack(alignment: .center, spacing: 40 * scale) {
                code
                VStack(alignment: .leading, spacing: 18 * scale) {
                    VStack(alignment: .leading, spacing: 6 * scale) {
                        Text(TW.text(.title)).font(.display(34 * scale, .semibold)).foregroundStyle(.white)
                        Text(TW.text(.subtitle)).font(.display(16 * scale)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 12 * scale) {
                        step(1, TW.text(.step1))
                        step(2, TW.text(.step2))
                        step(3, TW.text(.step3))
                    }
                    if !play.pads.isEmpty {
                        VStack(alignment: .leading, spacing: 8 * scale) {
                            ForEach(Array(play.pads.enumerated()), id: \.element.id) { _, pad in
                                HStack(spacing: 10 * scale) {
                                    Circle().fill(pad.allowed ? PhoneIndicator.green : PhoneIndicator.orange).frame(width: 9 * scale, height: 9 * scale)
                                        .shadow(color: pad.allowed ? PhoneIndicator.green : PhoneIndicator.orange, radius: 4 * scale)
                                    Text(pad.name).font(.display(16 * scale, .semibold)).foregroundStyle(.white)
                                    Text(TW.text(pad.allowed ? .playing : .asking)).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .padding(.top, 2 * scale)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    HStack(spacing: 14 * scale) {
                        ConsoleButton(title: TW.text(.newCode), symbol: "arrow.clockwise", focused: false, minWidth: 150) { play.renew() }
                        ConsoleButton(title: TW.text(.done), symbol: "checkmark", focused: true, prominent: true, minWidth: 150) { model.closeBrowserPlay() }
                    }
                    .padding(.top, 4 * scale)
                }
                .frame(maxWidth: 470 * scale, alignment: .leading)
            }
            .padding(44 * scale)
            .glass(30 * scale, opacity: 0.45)
            .animation(.spring(duration: 0.4, bounce: 0.25), value: play.pads)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
            Text("\(number)")
                .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 22 * scale, height: 22 * scale)
                .background(Circle().fill(model.accent))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 * scale }
            Text(text).font(.display(16 * scale)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var code: some View {
        VStack(spacing: 14 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 26 * scale, style: .continuous).fill(.white)
                if let url = play.url, let image = QRCode.image(url.absoluteString) {
                    Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(20 * scale)
                        .id(url).transition(.opacity)
                } else {
                    VStack(spacing: 10 * scale) {
                        Image(systemName: play.unavailable ? "wifi.exclamationmark" : "qrcode").font(.system(size: 40 * scale, weight: .light))
                        Text(TW.text(play.unavailable ? .noNetwork : .starting)).font(.display(14 * scale, .medium)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.black.opacity(0.55))
                    .padding(24 * scale)
                }
                // The four corner ticks of a viewfinder, in the launcher's accent.
                Viewfinder().stroke(model.accent, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round)).padding(-10 * scale)
            }
            .frame(width: 290 * scale, height: 290 * scale)
            .animation(.easeOut(duration: 0.25), value: play.url)
            if let url = play.url {
                Text(verbatim: "\(url.host ?? ""):\(url.port ?? 80)")
                    .font(.system(size: 15 * scale, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                if let expires = play.expires {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(expires.timeIntervalSince(context.date)))
                        Text(TW.format(.renews, left / 60, left % 60)).font(.display(13 * scale)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }
}

/// Corner ticks around a square.
struct Viewfinder: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.12
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

enum QRCode {
    /// The text as a QR code, twelve pixels a module.
    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        // Drawn large here, so no scaling on screen smooths its edges.
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

/// Play from a browser's texts, in both languages.
enum TW {
    enum Key: String, CaseIterable {
        case title = "browserPlay", subtitle = "browserPlaySubtitle", rowDetail = "browserPlayDetail", offDetail = "browserPlayOff", showCode = "browserPlayShow", showCodeDetail = "browserPlayShowDetail", keepOn = "browserPlayKeep", keepOnDetail = "browserPlayKeepDetail"
        case step1 = "browserPlayStep1", step2 = "browserPlayStep2", step3 = "browserPlayStep3", playing = "browserPlayPlaying", asking = "browserPlayAsking", newCode = "browserPlayNewCode", done = "browserPlayDone", renews = "browserPlayRenewsIn", noNetwork = "browserPlayNoNetwork", starting = "browserPlayStarting"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    static let english: [Key: String] = [
        .title: "Play from a browser",
        .subtitle: "Any phone becomes a controller, no app needed. Up to four players with the phone app's seats.",
        .rowDetail: "A phone scans a QR code and its browser is the pad",
        .offDetail: "Off: nothing is served on the network",
        .showCode: "Show QR code",
        .showCodeDetail: "Scan it with the phone's camera",
        .keepOn: "Keep browser play on",
        .keepOnDetail: "Phones let in before can come back without a new code while AnyPS5 is open",
        .step1: "Join the same Wi-Fi as this Mac.",
        .step2: "Scan the code with the phone's camera and open the link.",
        .step3: "Allow the phone here when it asks. The same code shows on both screens.",
        .playing: "playing",
        .asking: "waiting to be allowed",
        .newCode: "New Code",
        .done: "Done",
        .renews: "A new code in %d:%02d · each one works once",
        .noNetwork: "No local network.\nJoin Wi-Fi or Ethernet.",
        .starting: "Starting…",
    ]

    static let turkish: [Key: String] = [
        .title: "Tarayıcıdan oyna",
        .subtitle: "Her telefon kumandaya dönüşür, uygulama gerekmez. Telefon uygulamasının yer kurallarıyla dört oyuncuya kadar.",
        .rowDetail: "Telefon QR kodu tarar, tarayıcısı kumanda olur",
        .offDetail: "Kapalı: ağda hiçbir şey sunulmaz",
        .showCode: "QR kodu göster",
        .showCodeDetail: "Telefonun kamerasıyla tara",
        .keepOn: "Tarayıcıdan oynamayı açık tut",
        .keepOnDetail: "Daha önce izin verilen telefonlar AnyPS5 açıkken yeni kod olmadan dönebilir",
        .step1: "Bu Mac ile aynı Wi-Fi'a bağlan.",
        .step2: "Kodu telefonun kamerasıyla tara ve bağlantıyı aç.",
        .step3: "Telefon sorunca buradan izin ver. İki ekranda da aynı kod görünür.",
        .playing: "oynuyor",
        .asking: "izin bekliyor",
        .newCode: "Yeni Kod",
        .done: "Tamam",
        .renews: "%d:%02d sonra yeni kod · her biri bir kez çalışır",
        .noNetwork: "Yerel ağ yok.\nWi-Fi'a ya da Ethernet'e bağlan.",
        .starting: "Başlatılıyor…",
    ]
}

/// Play from a browser drawn offscreen for `--render-preview`: the code with one browser playing
/// and one waiting, the settings rows, and no network.
@MainActor
enum BrowserPlayPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let link = URL(string: "http://192.168.1.24:47710/?t=Qm9vbS1ub3QtYS1yZWFsLXRva2Vu")
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("browser-play.png")) { model in
            model.browserPlay.preview(url: link, pads: [.init(id: "a", name: "iPhone · Web", allowed: true), .init(id: "b", name: "Android · Web", allowed: false)])
            model.overlay = .browserPlay
        }
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("browser-play-empty.png")) { model in
            model.browserPlay.preview(url: link, pads: [])
            model.overlay = .browserPlay
        }
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("browser-play-offline.png")) { model in
            model.browserPlay.preview(url: nil, pads: [], unavailable: true)
            model.overlay = .browserPlay
        }
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("browser-play-settings.png")) { model in
            model.overlay = .settings
            let categories = model.panelCategories()
            model.panelCategory = categories.firstIndex { $0.id == "advanced" } ?? 0
            model.panelInRows = true
            model.panelRow = categories.first { $0.id == "advanced" }?.rows.firstIndex { $0.id == "browserPlayShow" } ?? 0
        }
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("browser-play-pairing.png")) { model in
            model.browserPlay.preview(url: link, pads: [.init(id: "b", name: "iPhone · Web", allowed: false)])
            model.overlay = .browserPlay
            model.previewPairing(PairingRequest(id: UUID(), deviceName: "iPhone · Web", code: "4821"))
        }
    }
}
