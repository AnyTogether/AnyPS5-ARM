import Foundation

/// The oldest macOS a toolkit's code loads on, from the Mach-O files themselves: each names it in
/// LC_BUILD_VERSION (minos) or, in older files, LC_VERSION_MIN_MACOSX. A library built for a newer
/// macOS than the running one links against what this system lacks, and dyld stops the game while
/// it loads ("Symbol not found"); the launcher says so before it unlocks or starts anything with it.
/// tools/macos/minimum_macos.py reads the files the same way for the build.
public enum SystemMinimum {
    /// A macOS version as the files and ProcessInfo give it, compared part by part.
    public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
        public var major: Int
        public var minor: Int
        public var patch: Int

        public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public init(_ system: OperatingSystemVersion) {
            self.init(system.majorVersion, system.minorVersion, system.patchVersion)
        }

        /// xxxx.yy.zz in 16, 8 and 8 bits, as LC_BUILD_VERSION packs it.
        init(packed: UInt32) {
            self.init(Int(packed >> 16), Int((packed >> 8) & 0xFF), Int(packed & 0xFF))
        }

        public static func < (left: Version, right: Version) -> Bool {
            (left.major, left.minor, left.patch) < (right.major, right.minor, right.patch)
        }

        /// 14.0, 15.4, 14.6.1: as macOS names its versions.
        public var description: String { "\(major).\(minor)" + (patch == 0 ? "" : ".\(patch)") }
    }

    /// The macOS this launcher runs on.
    public static var running: Version { Version(ProcessInfo.processInfo.operatingSystemVersion) }

    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    static let magic64: UInt32 = 0xFEED_FACF
    static let magic32: UInt32 = 0xFEED_FACE
    static let buildVersion: UInt32 = 0x32
    static let versionMinMacOS: UInt32 = 0x24
    static let platformMacOS: UInt32 = 1

    /// The oldest macOS the Mach-O file at `url` names, the newest of its slices'; nil for a file
    /// that is not Mach-O or names none.
    public static func minimum(of url: URL) -> Version? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4096), head.count >= 8 else { return nil }
        let magic = head.uint32(at: 0, bigEndian: true)
        if magic == fatMagic || magic == fatMagic64 {
            let count = Int(head.uint32(at: 4, bigEndian: true))
            guard count > 0, count < 32 else { return nil }
            let stride = magic == fatMagic ? 20 : 32
            var offsets: [UInt64] = []
            for index in 0..<count {
                let entry = 8 + index * stride
                guard entry + stride <= head.count else { return nil }
                offsets.append(magic == fatMagic ? UInt64(head.uint32(at: entry + 8, bigEndian: true)) : head.uint64(at: entry + 8, bigEndian: true))
            }
            return offsets.compactMap { thinMinimum(handle, at: $0) }.max()
        }
        return thinMinimum(handle, at: 0, head: head)
    }

    private static func thinMinimum(_ handle: FileHandle, at offset: UInt64, head: Data? = nil) -> Version? {
        var header = head ?? Data()
        if head == nil {
            guard (try? handle.seek(toOffset: offset)) != nil, let read = try? handle.read(upToCount: 4096) else { return nil }
            header = read
        }
        guard header.count >= 28 else { return nil }
        let magic = header.uint32(at: 0)
        guard magic == magic64 || magic == magic32 else { return nil }
        let headerSize = magic == magic64 ? 32 : 28
        let count = Int(header.uint32(at: 16))
        let size = Int(header.uint32(at: 20))
        if headerSize + size > header.count {
            guard (try? handle.seek(toOffset: offset)) != nil, let read = try? handle.read(upToCount: headerSize + size) else { return nil }
            header = read
        }
        return commandsMinimum(header, start: headerSize, count: count, end: min(headerSize + size, header.count))
    }

    static func commandsMinimum(_ data: Data, start: Int, count: Int, end: Int) -> Version? {
        var position = start
        for _ in 0..<count {
            guard position + 8 <= end else { return nil }
            let command = data.uint32(at: position)
            let length = Int(data.uint32(at: position + 4))
            if command == buildVersion, position + 16 <= end {
                if data.uint32(at: position + 8) == platformMacOS { return Version(packed: data.uint32(at: position + 12)) }
            } else if command == versionMinMacOS, position + 12 <= end {
                return Version(packed: data.uint32(at: position + 8))
            }
            guard length >= 8 else { return nil }
            position += length
        }
        return nil
    }

    /// The newest minimum among the files of `folders` (not their subfolders) and `files`.
    public static func newest(files: [URL] = [], folders: [URL] = []) -> Version? {
        let fileManager = FileManager.default
        let listed = folders.flatMap { folder in
            ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
        }
        return (files + listed).compactMap(minimum(of:)).max()
    }

    /// What a toolkit's code needs at least: its relinker, libraries, Vulkan loader and MoltenVK.
    public static func required(by toolkit: Toolkit) -> Version? {
        newest(files: [toolkit.relinker], folders: [toolkit.libraries, toolkit.vulkan])
    }

    /// What an unlocked game's libraries need at least (Contents/MacOS/libs of its bundle).
    public static func required(byBundle bundle: URL) -> Version? {
        newest(folders: [bundle.appendingPathComponent("Contents/MacOS/libs")])
    }

    /// The version `required` names when it is newer than `system`, else nil.
    public static func unmet(_ required: Version?, on system: Version = running) -> Version? {
        guard let required, required > system else { return nil }
        return required
    }
}

private extension Data {
    func uint32(at offset: Int, bigEndian: Bool = false) -> UInt32 {
        let bytes = self[index(startIndex, offsetBy: offset)..<index(startIndex, offsetBy: offset + 4)]
        let value = bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }

    func uint64(at offset: Int, bigEndian: Bool = false) -> UInt64 {
        let high = UInt64(uint32(at: offset, bigEndian: true))
        let low = UInt64(uint32(at: offset + 4, bigEndian: true))
        let value = high << 32 | low
        return bigEndian ? value : value.byteSwapped
    }
}
