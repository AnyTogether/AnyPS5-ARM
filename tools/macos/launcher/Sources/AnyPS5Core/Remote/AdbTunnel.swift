import Darwin
import Foundation

/// Android phones on a cable reach the launcher without Wi-Fi, when adb is installed and the
/// phone allows USB debugging (macOS cannot use the USB tethering most Android phones offer):
/// adb forwards a port on the Mac to the phone app's port 47702, and the launcher joins each
/// connection there to its own phone server, as UsbTunnel does for iPhones.
public final class AdbTunnel: @unchecked Sendable {
    private let adb: URL
    private let phonePort: UInt16
    private let targetPort: UInt16
    private let interval: TimeInterval
    private let changed: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "org.anyps5.adb")
    private var running = false
    /// The phones adb lists, with the Mac's port forwarded to each.
    private var forwarded: [String: UInt16] = [:]
    private var joined: [String: (phone: Int32, server: Int32)] = [:]

    public init(adb: URL, phonePort: UInt16 = UsbTunnel.phonePort, targetPort: UInt16, interval: TimeInterval = 3, changed: @escaping @Sendable ([String]) -> Void = { _ in }) {
        self.adb = adb
        self.phonePort = phonePort
        self.targetPort = targetPort
        self.interval = interval
        self.changed = changed
    }

    /// adb where Android Studio, Homebrew or ANDROID_HOME put it.
    public static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment,
                              extra: [String] = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]) -> URL? {
        let candidates = [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]].compactMap { $0 }.map { "\($0)/platform-tools/adb" }
            + [home.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path] + extra
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// The serials of the phones ready in `adb devices` output; unauthorized ones are left out.
    static func devices(in listing: String) -> [String] {
        listing.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t")
            return fields.count == 2 && fields[1] == "device" ? String(fields[0]) : nil
        }
    }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            look()
        }
    }

    public func stop() {
        queue.sync {
            running = false
            for ends in joined.values {
                shutdown(ends.phone, SHUT_RDWR)
                shutdown(ends.server, SHUT_RDWR)
            }
            joined = [:]
            forwarded = [:]
        }
    }

    /// Asks adb for the phones every few seconds, off the queue.
    private func look() {
        guard running else { return }
        let adb = adb, phonePort = phonePort
        Thread.detachNewThread { [weak self] in
            let listed = AdbTunnel.devices(in: AdbTunnel.run(adb, ["devices"]) ?? "")
            guard let self else { return }
            let known = self.queue.sync { Set(self.forwarded.keys) }
            var ports: [String: UInt16] = [:]
            for serial in listed where !known.contains(serial) {
                let answer = AdbTunnel.run(adb, ["-s", serial, "forward", "tcp:0", "tcp:\(phonePort)"])
                if let port = answer.flatMap({ UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) { ports[serial] = port }
            }
            self.queue.async {
                guard self.running else { return }
                for serial in self.forwarded.keys where !listed.contains(serial) {
                    self.forwarded[serial] = nil
                    if let ends = self.joined[serial] {
                        shutdown(ends.phone, SHUT_RDWR)
                        shutdown(ends.server, SHUT_RDWR)
                    }
                }
                for (serial, port) in ports {
                    self.forwarded[serial] = port
                    self.attempt(serial)
                }
                self.queue.asyncAfter(deadline: .now() + self.interval) { self.look() }
            }
        }
    }

    /// adb takes the connection on the Mac even when the phone app is not listening, and closes
    /// it at once then: joined or not, a phone still listed is tried again two seconds after.
    private func attempt(_ serial: String) {
        guard running, let port = forwarded[serial], joined[serial] == nil else { return }
        guard let phone = UsbTunnel.loopback(port) else {
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.attempt(serial) }
            return
        }
        guard let server = UsbTunnel.loopback(targetPort) else {
            close(phone)
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.attempt(serial) }
            return
        }
        joined[serial] = (phone, server)
        let started = Date()
        UsbTunnel.join(phone, server) { [weak self] in
            guard let self else { return }
            self.queue.async {
                if self.joined[serial]?.phone == phone { self.joined[serial] = nil }
                // Only a connection that held counts as the phone being there.
                if Date().timeIntervalSince(started) > 1 { self.report() }
                self.queue.asyncAfter(deadline: .now() + 2) { self.attempt(serial) }
            }
        }
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.joined[serial]?.phone == phone else { return }
            self.report()
        }
    }

    private func report() {
        changed(joined.keys.sorted())
    }

    /// What adb printed, nil when it could not run or failed.
    static func run(_ adb: URL, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = adb
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
