import AnyPS5Core
import Foundation

// anyps5-tool unwrap <self> <elf>
// anyps5-tool scan <games folder>
// anyps5-tool install <game folder> <games folder>    (ANYPS5_TOOLKIT names the toolkit)
// anyps5-tool theme <snd0.at9> <out.wav>   (a game's theme song, decoded)
// anyps5-tool toolkit-check <AnyPS5-toolkit-macos-….zip> [<store folder>]   (unpacks and verifies it as the
//   launcher's engine picker does, into a temporary store unless one is named; prints its version)
// anyps5-tool engines   (the toolkits on GitHub's releases, as the engine picker lists them)
// anyps5-tool remote [--allow-all] [--devices <file>] [--port <control port>] [--games <folder> [--language en|tr]] [--hidden]
//   (the phone server, until killed; with --games it shows that library and plays games only pretend;
//   --hidden leaves it out of Bonjour, so only a phone given its address finds it)
func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

let usage = "usage: anyps5-tool unwrap <self> <elf> | scan <games folder> | theme <snd0.at9> <out.wav> | update-check <version> [--download] | toolkit-check <zip> [<store folder>] | engines | install <game folder> <games folder> | remote [--allow-all] [--devices <file>] [--port <port>] [--games <folder> [--language en|tr]] [--hidden]"

/// Prints a line at once, so a script reading the output sees it while the server runs.
func say(_ line: String) {
    print(line)
    fflush(stdout)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
switch command {
case "unwrap":
    guard arguments.count == 3 else { fail(usage) }
    do {
        let size = try SelfUnwrap.unwrap(URL(fileURLWithPath: arguments[1]), to: URL(fileURLWithPath: arguments[2]))
        print("wrote \(arguments[2]), \(size) bytes")
    } catch {
        fail("FAIL: \(arguments[1]): \(error.localizedDescription)")
    }
case "scan":
    guard arguments.count == 2 else { fail(usage) }
    let root = URL(fileURLWithPath: arguments[1])
    for game in GameLibrary.scan(root) {
        let installed = Installer.record(of: Installer.bundle(for: game, root: root)) != nil
        print("\(game.titleID)\t\(game.name)\t\(game.executable)\t\(installed ? "installed" : "locked")\t\(game.folder.path)")
    }
case "install":
    guard arguments.count == 3 else { fail(usage) }
    guard let toolkit = Toolkit.locate() else { fail("no toolkit: set ANYPS5_TOOLKIT") }
    guard let game = GameLibrary.inspect(URL(fileURLWithPath: arguments[1])) else { fail("not a game folder: \(arguments[1])") }
    let installer = Installer(game: game, toolkit: toolkit, progress: { step, fraction in
        print(String(format: "[%@ %3.0f%%]", "\(step)", fraction * 100))
    }, log: { line in print(line) })
    do {
        let started = Date()
        let bundle = try installer.run(root: URL(fileURLWithPath: arguments[2]))
        print("installed \(bundle.path) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
    } catch {
        fail("FAIL: \(error.localizedDescription)")
    }
case "toolkit-check":
    guard arguments.count == 2 || arguments.count == 3 else { fail(usage) }
    let zip = URL(fileURLWithPath: arguments[1])
    let name = zip.deletingPathExtension().lastPathComponent
    let release = name.hasPrefix(EngineCatalogue.assetPrefix) ? String(name.dropFirst(EngineCatalogue.assetPrefix.count)) : nil
    let temporary = arguments.count == 2
    let store = ToolkitStore(folder: temporary ? FileManager.default.temporaryDirectory.appendingPathComponent("anyps5-toolkit-check-\(UUID().uuidString)") : URL(fileURLWithPath: arguments[2]))
    defer { if temporary { try? FileManager.default.removeItem(at: store.folder) } }
    do {
        let installed = try store.install(zip: zip, digest: nil, release: release, launcherVersion: "dev")
        _ = try store.verifiedToolkit(version: installed.version)
        print("OK \(installed.version): \(installed.manifest.files.count) files verified, engine \(installed.manifest.engineCommit ?? "?"), built \(installed.manifest.buildDate ?? "?"), needs launcher \(installed.manifest.minimumLauncher ?? "any")")
    } catch {
        fail("FAIL: \(error.localizedDescription)")
    }
case "engines":
    let done = DispatchSemaphore(value: 0)
    Task {
        if let entries = await EngineCatalogue.fetch() {
            if entries.isEmpty { print("no toolkits on the releases yet") }
            for entry in entries {
                print("\(entry.release)\t\(entry.date.map { ISO8601DateFormatter().string(from: $0) } ?? "?")\t\(entry.size ?? 0) bytes\t\(entry.digest == nil ? "no digest" : "sha256 known")\t\(entry.summary)")
            }
        } else {
            print("GitHub did not answer")
        }
        done.signal()
    }
    done.wait()
case "update-check":
    guard arguments.count >= 2 else { fail(usage) }
    let current = arguments[1]
    let download = arguments.contains("--download")
    let done = DispatchSemaphore(value: 0)
    Task {
        defer { done.signal() }
        guard let release = await Updates.check(current: current) else { return say("no newer release than \(current)") }
        say("newer: \(release.tag) (\(release.version)) \(release.download?.absoluteString ?? "no zip") \(release.size ?? 0) bytes")
        guard download else { return }
        do {
            let app = try await Updates.prepare(release, bundleIdentifier: "org.anyps5.launcher", current: current)
            say("ready: \(app.path)")
        } catch {
            say("FAIL: \(error)")
        }
    }
    done.wait()
case "theme":
    guard arguments.count == 3 else { fail(usage) }
    do {
        let song = try ThemeSong.decode(URL(fileURLWithPath: arguments[1]))
        var wav = Data("RIFF".utf8)
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        let pcm = song.samples.map { Int16(max(-1, min(1, $0)) * 32767) }
        put(UInt32(36 + pcm.count * 2)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(song.channels)); put(UInt32(song.sampleRate))
        put(UInt32(song.sampleRate * song.channels * 2)); put(UInt16(song.channels * 2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count * 2))
        pcm.withUnsafeBytes { wav.append(contentsOf: $0) }
        try wav.write(to: URL(fileURLWithPath: arguments[2]))
        say(String(format: "%.1f s, %d Hz, %d channels, loop %@", Double(song.frames) / Double(song.sampleRate), song.sampleRate, song.channels, song.loop.map { "\($0)" } ?? "whole"))
    } catch {
        fail("FAIL: \(error)")
    }
case "remote":
    var allowAll = false
    var file = PairedDevices.defaultFile
    var port: UInt16 = 0
    var library: [Game] = []
    var language = "en"
    var hidden = false
    var rest = arguments.dropFirst()
    while let option = rest.popFirst() {
        switch option {
        case "--allow-all": allowAll = true
        case "--devices":
            guard let path = rest.popFirst() else { fail(usage) }
            file = URL(fileURLWithPath: path)
        case "--port":
            guard let value = rest.popFirst().flatMap({ UInt16($0) }) else { fail(usage) }
            port = value
        case "--games":
            guard let path = rest.popFirst() else { fail(usage) }
            library = GameLibrary.scan(URL(fileURLWithPath: path))
        case "--hidden": hidden = true
        case "--language":
            guard let value = rest.popFirst() else { fail(usage) }
            language = value
        default: fail(usage)
        }
    }
    let server = Locked<RemoteServer?>(nil)
    let games = library
    let shownLanguage = language
    let selected = Locked<String?>(games.first?.id)
    let playing = Locked<String?>(nil)
    let layouts = Locked<[String: String]>([:])
    @Sendable func tell() {
        let list = games.map { game in
            RemoteGame(id: game.id, name: game.name, state: playing.value == game.id ? .running : .installed, trophies: nil,
                       art: RemoteArt.tag(icon: game.icon, background: game.background), layout: layouts.value[game.id])
        }
        server.value?.publish(.library(games: list, selected: selected.value, running: playing.value, language: shownLanguage))
    }
    let events = RemoteServer.Events(
        pairing: { request in
            say("pairing \(request.deviceName) \(request.code)")
            if allowAll {
                server.value?.respond(to: request.id, allow: true)
                return
            }
            DispatchQueue.global().async {
                let answer = readLine()?.lowercased()
                server.value?.respond(to: request.id, allow: answer == "y" || answer == "yes")
            }
        },
        connected: { name in
            say("connected \(name)")
            if !games.isEmpty { tell() }
        },
        disconnected: { say("disconnected") },
        latency: { milliseconds in say(String(format: "latency %.1f", milliseconds)) },
        request: { message in
            say("request \(message.text)")
            switch message {
            case .wantArt(let id):
                guard let game = games.first(where: { $0.id == id }) else { return }
                server.value?.publish(.art(id: id, icon: RemoteArt.jpeg(game.icon, longestSide: RemoteArt.iconSide),
                                           background: RemoteArt.jpeg(game.background, longestSide: RemoteArt.backgroundSide)))
            case .select(let id): selected.value = id
            case .launch(let id):
                selected.value = id
                // A pretend update and start, then a pretend trophy, to see the phone's cards.
                guard let game = games.first(where: { $0.id == id }) else { return }
                DispatchQueue.global().async {
                    let began = Date()
                    let steps: [(RemoteActivity.Phase, Double)] = [(.unwrap, 0.4), (.relink, 2.0), (.copy, 0.4), (.bundle, 0.3), (.finish, 0.2)]
                    for (index, (phase, seconds)) in steps.enumerated() {
                        for tick in 0...10 {
                            let done = (Double(index) + Double(tick) / 10) / Double(steps.count)
                            server.value?.publish(.activity(RemoteActivity(id: id, phase: phase, updating: true, fraction: done,
                                                                           elapsed: Date().timeIntervalSince(began))))
                            Thread.sleep(forTimeInterval: seconds / 10)
                        }
                    }
                    server.value?.publish(.activity(RemoteActivity(id: id, phase: .starting, updating: true, fraction: nil, elapsed: Date().timeIntervalSince(began))))
                    Thread.sleep(forTimeInterval: 1.5)
                    playing.value = id
                    server.value?.publish(.activity(nil))
                    tell()
                    Thread.sleep(forTimeInterval: 1.5)
                    server.value?.publish(.trophy(name: "First Steps", detail: "Start \(game.name)", grade: "gold",
                                                  icon: RemoteArt.jpeg(game.icon, longestSide: 160)))
                }
            case .close: playing.value = nil
            case .saveLayout(let id, let layout): layouts.value[id] = layout
            default: return
            }
            tell()
        })
    let running = RemoteServer(name: Host.current().localizedName ?? "Mac", devices: PairedDevices(file: file), events: events, advertise: !hidden, controlPort: port)
    server.value = running
    do {
        try running.start()
    } catch {
        fail("FAIL: \(error.localizedDescription)")
    }
    say("control \(running.controlPort ?? 0) udp \(running.udpPort ?? 0) bridge 127.0.0.1:\(running.bridgePort ?? 0)")
    dispatchMain()
default:
    fail(usage)
}
