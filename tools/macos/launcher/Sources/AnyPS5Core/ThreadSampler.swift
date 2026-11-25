import Darwin
import Foundation

/// What the stall watchdog sees of the main thread a few seconds into a freeze, from its own
/// thread: how much CPU time the main thread used and its stack. The thread is held still
/// (thread_suspend) only while its registers and frame records are read, with nothing allocated or
/// locked in between, and let go before the frames are named (dladdr), so a main thread stuck
/// holding a lock cannot hold the watchdog too. The same lines as AnyPS5 Desktop's
/// launcher_health.dart writes.
public struct ThreadSampler: Sendable {
    public let thread: thread_act_t
    /// The thread's stack, from its lowest address to its top: frame records are read only there.
    let stackBottom: UInt
    let stackTop: UInt

    /// The frames a sample keeps: the innermost ones tell where it is stuck.
    public static let frameLimit = 24

    public init(pthread: pthread_t) {
        thread = pthread_mach_thread_np(pthread)
        stackTop = UInt(bitPattern: pthread_get_stackaddr_np(pthread))
        let size = UInt(pthread_get_stacksize_np(pthread))
        stackBottom = stackTop > size ? stackTop - size : 0
    }

    /// The launcher's main thread, where the interface runs (nil off it, without
    /// pthread_main_thread_np, which Swift's Darwin module does not bring).
    public static var main: ThreadSampler? {
        if Thread.isMainThread { return ThreadSampler(pthread: pthread_self()) }
        typealias MainThread = @convention(c) () -> pthread_t?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "pthread_main_thread_np"),
              let main = unsafeBitCast(symbol, to: MainThread.self)() else { return nil }
        return ThreadSampler(pthread: main)
    }

    /// The CPU time the thread has used, user and system, in ms.
    public func cpuMs() -> Int? {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let seconds = Int(info.user_time.seconds) + Int(info.system_time.seconds)
        let microseconds = Int(info.user_time.microseconds) + Int(info.system_time.microseconds)
        return seconds * 1000 + microseconds / 1000
    }

    /// The thread's return addresses, innermost first: its pc, its link register, then the frame
    /// records its frame pointers chain, read only inside its stack. nil when it could not be held.
    public func addresses() -> [UInt]? {
        #if arch(arm64)
        let limit = Self.frameLimit
        // Everything is made before the thread is held: nothing is allocated while it is.
        let frames = UnsafeMutablePointer<UInt>.allocate(capacity: limit)
        defer { frames.deallocate() }
        let stateSize = MemoryLayout<arm_thread_state64_t>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: stateSize, alignment: 16)
        defer { raw.deallocate() }
        let words = raw.bindMemory(to: natural_t.self, capacity: stateSize / MemoryLayout<natural_t>.size)
        guard let fpAt = MemoryLayout<arm_thread_state64_t>.offset(of: \.__fp), let lrAt = MemoryLayout<arm_thread_state64_t>.offset(of: \.__lr),
              let spAt = MemoryLayout<arm_thread_state64_t>.offset(of: \.__sp), let pcAt = MemoryLayout<arm_thread_state64_t>.offset(of: \.__pc) else { return nil }
        let flavor = thread_state_flavor_t(ARM_THREAD_STATE64)
        var stateCount = mach_msg_type_number_t(stateSize / MemoryLayout<natural_t>.size)
        // System libraries sign their return addresses (arm64e): the signature is cut off.
        let mask: UInt = 0x0000_000F_FFFF_FFFF
        let bottom = stackBottom, top = stackTop
        var count = 0

        // A thread that held itself would never be let go.
        guard thread != pthread_mach_thread_np(pthread_self()), thread_suspend(thread) == KERN_SUCCESS else { return nil }
        if thread_get_state(thread, flavor, words, &stateCount) == KERN_SUCCESS {
            let pc = raw.load(fromByteOffset: pcAt, as: UInt.self) & mask
            let lr = raw.load(fromByteOffset: lrAt, as: UInt.self) & mask
            let sp = raw.load(fromByteOffset: spAt, as: UInt.self)
            var fp = raw.load(fromByteOffset: fpAt, as: UInt.self)
            frames[0] = pc
            count = 1
            // A function stuck in a system call has no frame of its own: its caller is in lr.
            if lr != 0 {
                frames[1] = lr
                count = 2
            }
            while count < limit && fp >= sp && fp >= bottom && top >= 16 && fp <= top - 16 && fp & 7 == 0 {
                guard let record = UnsafeRawPointer(bitPattern: fp) else { break }
                let next = record.load(as: UInt.self)
                let back = record.load(fromByteOffset: 8, as: UInt.self) & mask
                if back == 0 { break }
                frames[count] = back
                count += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(thread)
        return Array(UnsafeBufferPointer(start: frames, count: count))
        #else
        return nil
        #endif
    }

    /// "0  libsystem_kernel.dylib +0x1234  mach_msg2_trap + 8": the image, the offset in it (what
    /// atos -l and a dSYM name in a stripped build) and the nearest symbol dladdr knows.
    public static func describe(_ addresses: [UInt]) -> [String] {
        addresses.enumerated().map { index, address in
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let base = info.dli_fbase else {
                return "\(index)  ? 0x\(String(address, radix: 16))"
            }
            let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
            var line = "\(index)  \(image) +0x\(String(address &- UInt(bitPattern: base), radix: 16))"
            if let name = info.dli_sname, let start = info.dli_saddr {
                line += "  \(demangled(name)) + \(address &- UInt(bitPattern: start))"
            }
            return line
        }
    }

    private typealias Demangle = @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32) -> UnsafeMutablePointer<CChar>?
    private static let demangler: Demangle? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle").map { unsafeBitCast($0, to: Demangle.self) }

    static func demangled(_ name: UnsafePointer<CChar>) -> String {
        guard let demangler, let readable = demangler(name, strlen(name), nil, nil, 0) else { return String(cString: name) }
        defer { free(readable) }
        return String(cString: readable)
    }

    /// The sample's first line: how far into the freeze it was taken and whether the thread was
    /// busy on the CPU or waiting in the `windowMs` before (from about a second into the freeze).
    public static func headline(sampledMs: Int, cpuMs: Int?, windowMs: Int?) -> String {
        let at = "Sampled \(sampledMs / 1000) s into the freeze"
        guard let cpuMs, let windowMs, windowMs > 0 else { return at + "." }
        let used = max(0, cpuMs)
        let doing = used * 2 >= windowMs ? "busy on the CPU" : "waiting, not on the CPU"
        // Tenths of a second rounded half up, as AnyPS5 Desktop's: the same words for the same times.
        let tenths = (windowMs + 50) / 100
        return at + ": \(doing) (\(used) ms of CPU time in the \(tenths / 10).\(tenths % 10) s before)."
    }

    /// The stack's heading, then its frames.
    public static let stackHeading = "Stack:"
    /// Until the frames are named (dladdr), or when that never finishes.
    public static let stackUnnamed = "Stack: naming its frames did not finish."
    /// The thread could not be held or read.
    public static let stackUnread = "Stack: could not be read."
}
