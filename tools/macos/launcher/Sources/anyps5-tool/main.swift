import AnyPS5Core
import Foundation

// anyps5-tool unwrap <self> <elf>
// anyps5-tool scan <games folder>
// anyps5-tool install <game folder> <games folder>    (ANYPS5_TOOLKIT names the toolkit)
// anyps5-tool remote [--allow-all] [--devices <file>] [--port <control port>]   (the phone server, until killed)
func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

let usage = "usage: anyps5-tool unwrap <self> <elf> | scan <games folder> | install <game folder> <games folder> | remote [--allow-all] [--devices <file>] [--port <port>]"

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
case "remote":
    var allowAll = false
    var file = PairedDevices.defaultFile
    var port: UInt16 = 0
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
        default: fail(usage)
        }
    }
    let server = Locked<RemoteServer?>(nil)
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
        connected: { name in say("connected \(name)") },
        disconnected: { say("disconnected") },
        latency: { milliseconds in say(String(format: "latency %.1f", milliseconds)) })
    let running = RemoteServer(name: Host.current().localizedName ?? "Mac", devices: PairedDevices(file: file), events: events, controlPort: port)
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
