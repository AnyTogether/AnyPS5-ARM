import Darwin
import Foundation

/// iPhones on a cable reach the launcher without Wi-Fi: for each one plugged in, it keeps
/// trying to open the phone app's port over the cable (through usbmuxd) and, once it is open,
/// joins it to the launcher's own phone server, so the phone talks to the server as it would
/// over Wi-Fi. Everything but the copying runs on one private queue.
public final class UsbTunnel: @unchecked Sendable {
    /// The port the phone app listens on for the Mac, on the phone.
    public static let phonePort: UInt16 = 47702

    private let phonePort: UInt16
    private let targetPort: UInt16
    private let usbmux: String
    private let changed: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "org.anyps5.usb")
    private var running = false
    private var watching: Int32 = -1
    private var plugged: [Int: Usbmux.Device] = [:]
    /// The joined connections, by phone: the phone's end and the server's end.
    private var joined: [Int: (phone: Int32, server: Int32)] = [:]

    /// `changed` is told the serials of the phones joined, whenever that changes.
    public init(phonePort: UInt16 = UsbTunnel.phonePort, targetPort: UInt16, usbmux: String = Usbmux.socketPath, changed: @escaping @Sendable ([String]) -> Void = { _ in }) {
        self.phonePort = phonePort
        self.targetPort = targetPort
        self.usbmux = usbmux
        self.changed = changed
    }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            listen()
        }
    }

    public func stop() {
        queue.sync {
            running = false
            if watching >= 0 { close(watching) }
            watching = -1
            plugged = [:]
            for ends in joined.values {
                shutdown(ends.phone, SHUT_RDWR)
                shutdown(ends.server, SHUT_RDWR)
            }
            joined = [:]
        }
    }

    /// Follows phones plugged in and out; usbmuxd going away (or not being there) is tried
    /// again a few seconds later.
    private func listen() {
        guard running else { return }
        do {
            watching = try Usbmux.watch(path: usbmux, queue: queue, { [weak self] event in self?.handle(event) }, ended: { [weak self] in
                guard let self, self.running else { return }
                self.watching = -1
                self.queue.asyncAfter(deadline: .now() + 5) { self.listen() }
            })
        } catch {
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.listen() }
        }
    }

    private func handle(_ event: Usbmux.Event) {
        switch event {
        case .attached(let device):
            plugged[device.id] = device
            attempt(device.id)
        case .detached(let id):
            plugged[id] = nil
            if let ends = joined[id] {
                shutdown(ends.phone, SHUT_RDWR)
                shutdown(ends.server, SHUT_RDWR)
            }
        }
    }

    /// Opens the phone app's port and joins it to the server; tried again every two seconds
    /// while the phone is plugged in and its app is not listening.
    private func attempt(_ id: Int) {
        guard running, plugged[id] != nil, joined[id] == nil else { return }
        let phonePort = phonePort, targetPort = targetPort, usbmux = usbmux
        Thread.detachNewThread { [weak self] in
            let phone = try? Usbmux.connect(device: id, port: phonePort, path: usbmux)
            let server = phone.flatMap { _ in UsbTunnel.loopback(targetPort) }
            guard let self else { return }
            self.queue.async {
                guard let phone, let server, self.running, self.plugged[id] != nil, self.joined[id] == nil else {
                    if let phone { close(phone) }
                    if let server { close(server) }
                    self.queue.asyncAfter(deadline: .now() + 2) { self.attempt(id) }
                    return
                }
                self.joined[id] = (phone, server)
                self.report()
                UsbTunnel.join(phone, server) {
                    self.queue.async {
                        if self.joined[id]?.phone == phone { self.joined[id] = nil }
                        self.report()
                        self.queue.asyncAfter(deadline: .now() + 1) { self.attempt(id) }
                    }
                }
            }
        }
    }

    private func report() {
        changed(joined.keys.sorted().compactMap { plugged[$0]?.serial })
    }

    /// A TCP connection to the launcher's own port.
    private static func loopback(_ port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        Usbmux.noSignal(fd)
        var noDelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Copies each way until either end closes, then closes both and calls `ended`.
    private static func join(_ left: Int32, _ right: Int32, ended: @escaping @Sendable () -> Void) {
        let remaining = Locked(2)
        for (from, to) in [(left, right), (right, left)] {
            Thread.detachNewThread {
                var chunk = [UInt8](repeating: 0, count: 16384)
                copying: while true {
                    let count = read(from, &chunk, chunk.count)
                    guard count > 0 else { break }
                    var sent = 0
                    while sent < count {
                        let wrote = chunk.withUnsafeBytes { write(to, $0.baseAddress! + sent, count - sent) }
                        guard wrote > 0 else { break copying }
                        sent += wrote
                    }
                }
                shutdown(left, SHUT_RDWR)
                shutdown(right, SHUT_RDWR)
                let last = remaining.withLock { count -> Bool in
                    count -= 1
                    return count == 0
                }
                if last {
                    close(left)
                    close(right)
                    ended()
                }
            }
        }
    }
}
