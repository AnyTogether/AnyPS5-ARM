import Darwin
import Foundation

/// The programs the launcher starts that would outlive it, as on Windows and Linux
/// (AnyPS5-Desktop's ChildProcesses): an engine build's git, CMake and Ninja. Foundation's
/// processes go on after the app that started them quits, so each one is remembered while it
/// runs and `endAll` ends what is left as the launcher quits, with the programs it started
/// (Ninja's compilers). Programs meant to go on (Homebrew installing the build tools) are never
/// remembered. The relinker is cancelled by its installer as the launcher quits.
public enum ChildProcesses {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var live: [Int32: Process] = [:]

    /// How many remembered programs have not been forgotten yet.
    public static var count: Int { lock.withLock { live.count } }

    /// Remembers `process`, once it runs, until `forget`.
    public static func remember(_ process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        lock.withLock { live[pid] = process }
    }

    /// The program ended (or was handed over): it is no longer ended with the launcher.
    public static func forget(_ process: Process) {
        let pid = process.processIdentifier
        lock.withLock {
            if live[pid] === process { live[pid] = nil }
        }
    }

    /// Ends every remembered program still running and every program each one started: all are
    /// asked with SIGTERM (and SIGCONT, so a stopped one gets it), and what is still there after
    /// `grace` gets SIGKILL. Synchronous: it runs as the app terminates.
    public static func endAll(grace: TimeInterval = 0.5) {
        let processes = lock.withLock { () -> [Process] in
            let all = Array(live.values)
            live.removeAll()
            return all
        }
        // An ended one's number may already belong to another program.
        let roots = processes.filter(\.isRunning).map(\.processIdentifier).filter { $0 > 0 }
        guard !roots.isEmpty else { return }
        let table = parents()
        var pids: [pid_t] = []
        for root in roots {
            for pid in descendants(of: root, parents: table) + [root] where !pids.contains(pid) {
                pids.append(pid)
            }
        }
        for pid in pids {
            kill(pid, SIGTERM)
            kill(pid, SIGCONT)
        }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, pids.contains(where: running) { usleep(20_000) }
        for pid in pids where running(pid) { kill(pid, SIGKILL) }
    }

    /// Every process `root` started, and the ones they started, from a table of each process's
    /// parent: the deepest last.
    public static func descendants(of root: pid_t, parents: [pid_t: pid_t]) -> [pid_t] {
        guard root > 0 else { return [] }
        var children: [pid_t: [pid_t]] = [:]
        for (pid, parent) in parents where pid != parent { children[parent, default: []].append(pid) }
        var found: [pid_t] = []
        var next = [root]
        while !next.isEmpty {
            let pid = next.removeFirst()
            for child in (children[pid] ?? []).sorted() where child != root && !found.contains(child) {
                found.append(child)
                next.append(child)
            }
        }
        return found
    }

    /// Each running process's parent, from the kernel's process table.
    static func parents() -> [pid_t: pid_t] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
        // Room for the processes started since.
        size += size / 4
        let stride = MemoryLayout<kinfo_proc>.stride
        var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        let result = table.withUnsafeMutableBytes { sysctl(&name, 4, $0.baseAddress, &size, nil, 0) }
        guard result == 0 else { return [:] }
        var parents: [pid_t: pid_t] = [:]
        for info in table.prefix(size / stride) {
            parents[info.kp_proc.p_pid] = info.kp_eproc.e_ppid
        }
        return parents
    }

    private static func running(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }
}
