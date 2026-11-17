import CRetroHost
import Darwin
import Foundation

/// The clock every time limit of the emulator host's protocol is measured on: monotonic
/// (`mach_absolute_time`, through `DispatchTime`), so a step of the wall clock, such as a correction
/// after waking from sleep, cannot set a limit off. It does not count time asleep, when the host
/// sleeps too.
enum RetroClock {
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func seconds(_ value: Double) -> UInt64 { UInt64(value * 1_000_000_000) }
}

/// How the host process ended.
public enum RetroHostExit: Equatable, Sendable {
    /// It exited with this code.
    case code(Int32)
    /// A signal ended it.
    case signal(Int32)
    /// Something else reaped it first, so how it ended is not known.
    case unknown

    /// The exit code, when it exited by itself.
    public var code: Int32? {
        if case .code(let value) = self { return value }
        return nil
    }
}

/// What the connection's threads report. The reader's messages come in stream order, and the exit
/// comes after the reader has passed on everything the host wrote (or 2 seconds after the exit,
/// when something else still holds the host's end and the stream does not end).
enum RetroHostConnectionEvent {
    /// A whole message: one JSON object with a string `type`, and the one descriptor that came with
    /// it (only ever on a `ring`), or -1.
    case message(RetroJSON, descriptor: Int32)
    /// The stream broke a framing rule; every descriptor that came with the message is closed.
    case protocolError(String)
    /// The stream ended (or failed).
    case endOfStream
    /// A write failed: the host closed its end.
    case writeFailed
    /// The host process has ended.
    case exited(RetroHostExit)
}

/// Why the host could not be started.
public struct RetroHostStartError: Error, CustomStringConvertible {
    public let description: String
}

/// Reads whole messages from the control stream (protocol.md "Framing") on a thread of its own: a
/// read never asks past the current message, each read is a `recvmsg` with room for 4 descriptors,
/// and descriptors count only on the read that holds the first byte of a length. Each received
/// descriptor gets `FD_CLOEXEC` at once (macOS has no `MSG_CMSG_CLOEXEC`).
final class RetroHostReader {
    private enum Received {
        case data(Int, [Int32])
        case end([Int32])
        case failed([Int32], String)
    }

    private let socket: Int32
    private let events: (RetroHostConnectionEvent) -> Void
    private let control: UnsafeMutableRawPointer
    private let controlSize: Int
    private let vector = UnsafeMutablePointer<iovec>.allocate(capacity: 1)

    init(socket: Int32, events: @escaping (RetroHostConnectionEvent) -> Void) {
        self.socket = socket
        self.events = events
        controlSize = anyps5_retro_cmsg_space(4 * MemoryLayout<Int32>.size)
        control = UnsafeMutableRawPointer.allocate(byteCount: controlSize, alignment: 16)
    }

    deinit {
        control.deallocate()
        vector.deallocate()
    }

    static func closeAll(_ descriptors: [Int32]) {
        for descriptor in descriptors { Darwin.close(descriptor) }
    }

    /// Reads until the stream ends or breaks a rule, reporting each message.
    func run() {
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        while true {
            var held: [Int32] = []
            var got = 0
            while got < 4 {
                let read = lengthBytes.withUnsafeMutableBytes { receive(into: $0.baseAddress! + got, count: 4 - got) }
                switch read {
                case .failed(let descriptors, let problem):
                    Self.closeAll(held + descriptors)
                    events(.protocolError(problem))
                    return
                case .end(let descriptors):
                    Self.closeAll(held + descriptors)
                    events(.endOfStream)
                    return
                case .data(let count, let descriptors):
                    if got == 0 {
                        held = descriptors
                    } else if !descriptors.isEmpty {
                        Self.closeAll(held + descriptors)
                        events(.protocolError("A descriptor came on a read that did not hold the first byte of a length."))
                        return
                    }
                    got += count
                }
            }
            let length = Int(lengthBytes[0]) | Int(lengthBytes[1]) << 8 | Int(lengthBytes[2]) << 16 | Int(lengthBytes[3]) << 24
            guard (RetroProtocol.minBody...RetroProtocol.maxBody).contains(length) else {
                Self.closeAll(held)
                events(.protocolError("A message length of \(length) is outside 2 to 1 MiB."))
                return
            }
            var body = [UInt8](repeating: 0, count: length)
            got = 0
            while got < length {
                let read = body.withUnsafeMutableBytes { receive(into: $0.baseAddress! + got, count: length - got) }
                switch read {
                case .failed(let descriptors, let problem):
                    Self.closeAll(held + descriptors)
                    events(.protocolError(problem))
                    return
                case .end(let descriptors):
                    Self.closeAll(held + descriptors)
                    events(.endOfStream)
                    return
                case .data(let count, let descriptors):
                    guard descriptors.isEmpty else {
                        Self.closeAll(held + descriptors)
                        events(.protocolError("A descriptor came on a read that did not hold the first byte of a length."))
                        return
                    }
                    got += count
                }
            }
            do {
                let value = try Self.decode(body: body, descriptors: held)
                events(.message(value, descriptor: held.first ?? -1))
            } catch {
                Self.closeAll(held)
                events(.protocolError((error as? RetroProtocolError)?.message ?? "\(error)"))
                return
            }
        }
    }

    /// A whole message's body, or `RetroProtocolError` for a body that is not one JSON object with a
    /// string `type`, more than one descriptor, or a descriptor on anything but a `ring`.
    static func decode(body: [UInt8], descriptors: [Int32]) throws -> RetroJSON {
        let value: RetroJSON
        do {
            value = try RetroJSON.parse(body)
        } catch {
            throw RetroProtocolError("A message body is not valid: \(error)")
        }
        guard let object = value.objectValue else { throw RetroProtocolError("A message body is not one JSON object.") }
        guard let type = object["type"]?.stringValue else { throw RetroProtocolError("A message has no string type.") }
        if descriptors.count > 1 { throw RetroProtocolError("A \(type) message came with \(descriptors.count) descriptors.") }
        if descriptors.count == 1, type != "ring" { throw RetroProtocolError("A descriptor came with a \(type) message.") }
        return value
    }

    private func receive(into buffer: UnsafeMutableRawPointer, count: Int) -> Received {
        while true {
            vector.pointee = iovec(iov_base: buffer, iov_len: count)
            var message = msghdr()
            message.msg_iov = vector
            message.msg_iovlen = 1
            message.msg_control = control
            message.msg_controllen = socklen_t(controlSize)
            let read = recvmsg(socket, &message, 0)
            if read < 0 {
                if errno == EINTR { continue }
                return .end([])
            }
            var descriptors: [Int32] = []
            var problem: String?
            if message.msg_controllen > 0 {
                var header = anyps5_retro_cmsg_first(&message)
                while let current = header {
                    if current.pointee.cmsg_level == SOL_SOCKET, current.pointee.cmsg_type == SCM_RIGHTS {
                        let data = UnsafeRawPointer(anyps5_retro_cmsg_data(current)!)
                        let count = anyps5_retro_cmsg_data_bytes(current) / MemoryLayout<Int32>.size
                        for index in 0..<count {
                            let descriptor = data.loadUnaligned(fromByteOffset: index * MemoryLayout<Int32>.size, as: Int32.self)
                            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
                            descriptors.append(descriptor)
                        }
                    } else {
                        problem = "A control message other than SCM_RIGHTS came."
                    }
                    header = anyps5_retro_cmsg_next(&message, current)
                }
            }
            if message.msg_flags & MSG_CTRUNC != 0 { problem = "The ancillary data was cut short (MSG_CTRUNC)." }
            if let problem { return .failed(descriptors, problem) }
            if read == 0 { return .end(descriptors) }
            return .data(read, descriptors)
        }
    }
}

/// One emulator host process and its control stream (protocol.md "Processes"): started with
/// `posix_spawn`, its end of a `socketpair` at descriptor 3 and nothing else
/// (`POSIX_SPAWN_CLOEXEC_DEFAULT`), an empty signal mask and `SIGTERM` at its default. A reader, a
/// writer and an exit watcher run on threads of their own, so nothing here ever blocks the caller
/// once the host is started; `close()` waits for them and is never called on the main thread.
final class RetroHostConnection: @unchecked Sendable {
    let pid: pid_t
    private let socket: Int32
    private let events: (RetroHostConnectionEvent) -> Void
    private let lock = NSCondition()
    private var outbox: [[UInt8]] = []
    private var closing = false
    private var closed = false
    private var writeStartedAt: UInt64?
    private var writeFailed = false
    private var processGone = false
    private var readerFinished = false
    private let threads = DispatchGroup()

    /// Starts `command` (its first entry the executable's absolute path) with the protocol's own
    /// arguments after it, `--ipc-fd 3 --parent-pid <the launcher's pid>`, and `environment` as its
    /// whole environment.
    init(command: [String], environment: [String: String], events: @escaping (RetroHostConnectionEvent) -> Void) throws {
        guard let executable = command.first, executable.hasPrefix("/") else {
            throw RetroHostStartError(description: "The host's command does not start with an absolute path.")
        }
        self.events = events
        var ends: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &ends) == 0 else {
            throw RetroHostStartError(description: "socketpair failed (errno \(errno)).")
        }
        for end in ends { _ = fcntl(end, F_SETFD, FD_CLOEXEC) }
        var on: Int32 = 1
        _ = setsockopt(ends[0], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var hostEnd = ends[1]
        if hostEnd == 3 {
            let moved = fcntl(hostEnd, F_DUPFD_CLOEXEC, 4)
            Darwin.close(hostEnd)
            hostEnd = moved
        }
        let arguments = command + ["--ipc-fd", "3", "--parent-pid", String(getpid())]
        var spawned: pid_t = 0
        let result = Self.spawn(executable: executable, arguments: arguments, environment: environment,
                                hostEnd: hostEnd, pid: &spawned)
        if hostEnd >= 0 { Darwin.close(hostEnd) }
        guard result == 0 else {
            Darwin.close(ends[0])
            throw RetroHostStartError(description: "posix_spawn of \(executable) failed: \(String(cString: strerror(result))).")
        }
        pid = spawned
        socket = ends[0]
        startThreads()
    }

    private static func spawn(executable: String, arguments: [String], environment: [String: String],
                              hostEnd: Int32, pid: inout pid_t) -> Int32 {
        guard hostEnd >= 0 else { return EBADF }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_adddup2(&actions, hostEnd, 3)
        var empty = sigset_t()
        var terminate = sigset_t(1) << sigset_t(SIGTERM - 1)
        posix_spawnattr_setsigmask(&attributes, &empty)
        posix_spawnattr_setsigdefault(&attributes, &terminate)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for item in argv { free(item) }
            for item in envp { free(item) }
        }
        return posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
    }

    private func startThreads() {
        let reader = RetroHostReader(socket: socket, events: events)
        let readThread = Thread { [self] in
            reader.run()
            lock.lock()
            readerFinished = true
            lock.broadcast()
            lock.unlock()
            threads.leave()
        }
        readThread.name = "org.anyps5.retro-host.reader"
        readThread.stackSize = 4 << 20
        let writeThread = Thread { [self] in
            writeLoop()
            threads.leave()
        }
        writeThread.name = "org.anyps5.retro-host.writer"
        let exitThread = Thread { [self] in
            watchExit()
            threads.leave()
        }
        exitThread.name = "org.anyps5.retro-host.exit"
        for thread in [readThread, writeThread, exitThread] {
            threads.enter()
            thread.start()
        }
    }

    /// Queues one framed message for the writer; false once the stream can take no more.
    @discardableResult
    func send(_ framed: [UInt8]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closing, !writeFailed else { return false }
        outbox.append(framed)
        lock.broadcast()
        return true
    }

    /// When the write in progress started, if one is, and whether a write failed.
    func writeState() -> (startedAt: UInt64?, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (writeStartedAt, writeFailed)
    }

    private func writeLoop() {
        while true {
            lock.lock()
            while outbox.isEmpty, !closing { lock.wait() }
            if closing {
                lock.unlock()
                return
            }
            let data = outbox.removeFirst()
            writeStartedAt = RetroClock.now()
            lock.unlock()
            let written = data.withUnsafeBytes { raw -> Bool in
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.send(socket, raw.baseAddress! + offset, raw.count - offset, 0)
                    if count < 0 {
                        if errno == EINTR { continue }
                        return false
                    }
                    offset += count
                }
                return true
            }
            lock.lock()
            writeStartedAt = nil
            if !written { writeFailed = true }
            lock.unlock()
            if !written {
                events(.writeFailed)
                return
            }
        }
    }

    /// Waits for the host to end without reaping it (`WNOWAIT`), so `kill()` can never reach a later
    /// process given the same id, then reaps it and reports the exit once the reader is done.
    private func watchExit() {
        var info = siginfo_t()
        var waited: Int32
        repeat {
            waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)
        } while waited != 0 && errno == EINTR
        lock.lock()
        processGone = true
        lock.unlock()
        var status: Int32 = 0
        var reaped: pid_t
        repeat {
            reaped = waitpid(pid, &status, 0)
        } while reaped < 0 && errno == EINTR
        let exit: RetroHostExit
        if reaped == pid {
            exit = status & 0x7F == 0 ? .code((status >> 8) & 0xFF) : .signal(status & 0x7F)
        } else if waited == 0 {
            exit = info.si_code == CLD_EXITED ? .code(info.si_status) : .signal(info.si_status)
        } else {
            exit = .unknown
        }
        let deadline = RetroClock.now() + RetroClock.seconds(2)
        lock.lock()
        while !readerFinished, RetroClock.now() < deadline {
            _ = lock.wait(until: Date(timeIntervalSinceNow: 0.05))
        }
        lock.unlock()
        events(.exited(exit))
    }

    /// Kills the host if it has not ended yet.
    func kill() {
        lock.lock()
        defer { lock.unlock() }
        if !processGone { _ = Darwin.kill(pid, SIGKILL) }
    }

    /// Kills the host if it still runs, ends the stream and waits for every thread. Blocks: never
    /// on the main thread.
    func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        closing = true
        outbox.removeAll()
        lock.broadcast()
        lock.unlock()
        kill()
        _ = Darwin.shutdown(socket, SHUT_RDWR)
        threads.wait()
        Darwin.close(socket)
    }
}
