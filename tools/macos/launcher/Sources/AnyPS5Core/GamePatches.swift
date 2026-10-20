import Foundation

/// Per-title byte patches for an executable relinked with `relinker --macos`: the Swift form of
/// tools/macos/game_patches.py, reading the same tools/macos/patches/<title id>.json files.
public struct GamePatches: Decodable {
    public struct Edit: Decodable {
        let address: String
        let original: String
        let replacement: String
    }

    public struct Patch: Decodable {
        public let name: String
        let edits: [Edit]
    }

    public struct Field: Decodable {
        let value: String
        let address: String
        let instruction: String
        let offset: Int
    }

    public struct Resolution: Decodable {
        public let `default`: String
        public let choices: [String]
        let fields: [Field]
    }

    public let patches: [Patch]
    public let resolution: Resolution?

    enum CodingKeys: String, CodingKey {
        case patches
        case resolution
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        patches = try container.decodeIfPresent([Patch].self, forKey: .patches) ?? []
        resolution = try container.decodeIfPresent(Resolution.self, forKey: .resolution)
    }

    public static func load(titleID: String, from directory: URL) -> GamePatches? {
        let file = directory.appendingPathComponent(titleID + ".json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(GamePatches.self, from: data)
    }

    struct Segment {
        let vmaddr: UInt64
        let fileoff: UInt64
        let filesize: UInt64
    }

    static func segments(_ data: [UInt8]) throws -> [Segment] {
        guard data.count >= 32, SelfUnwrap.u32(data, 0) == 0xFEED_FACF else { throw SelfUnwrap.Refused(reason: "not a 64-bit Mach-O executable") }
        let count = Int(SelfUnwrap.u32(data, 16))
        var cursor = 32
        var result: [Segment] = []
        for _ in 0..<count {
            guard cursor + 8 <= data.count else { break }
            let command = SelfUnwrap.u32(data, cursor)
            let size = Int(SelfUnwrap.u32(data, cursor + 4))
            if command == 0x19 {
                let vmaddr = SelfUnwrap.u64(data, cursor + 24)
                let fileoff = SelfUnwrap.u64(data, cursor + 40)
                let filesize = SelfUnwrap.u64(data, cursor + 48)
                if filesize != 0 { result.append(Segment(vmaddr: vmaddr, fileoff: fileoff, filesize: filesize)) }
            }
            guard size > 0 else { break }
            cursor += size
        }
        return result
    }

    static func fileOffset(_ segments: [Segment], _ address: UInt64, _ length: Int) throws -> Int {
        for segment in segments where segment.vmaddr <= address && address + UInt64(length) <= segment.vmaddr + segment.filesize {
            return Int(segment.fileoff + address - segment.vmaddr)
        }
        throw SelfUnwrap.Refused(reason: "0x\(String(address, radix: 16)) is not in a file-backed segment")
    }

    static func bytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            if let byte = UInt8(hex[index..<next], radix: 16) { result.append(byte) }
            index = next
        }
        return result
    }

    static func address(_ text: String) -> UInt64 {
        UInt64(text.hasPrefix("0x") ? String(text.dropFirst(2)) : text, radix: 16) ?? 0
    }

    /// Applies the patches to the executable; returns (name, state) pairs as game_patches.py does.
    public func apply(to eboot: URL) throws -> [(String, String)] {
        guard !patches.isEmpty else { return [] }
        var data = [UInt8](try Data(contentsOf: eboot))
        let list = try GamePatches.segments(data)
        var results: [(String, String)] = []
        for patch in patches {
            var planned: [(Int, [UInt8])] = []
            var state: String?
            for edit in patch.edits {
                let original = GamePatches.bytes(edit.original)
                let replacement = GamePatches.bytes(edit.replacement)
                guard original.count == replacement.count else { throw SelfUnwrap.Refused(reason: "\(patch.name): original and replacement at \(edit.address) differ in length") }
                let offset = try GamePatches.fileOffset(list, GamePatches.address(edit.address), original.count)
                let current = Array(data[offset..<(offset + original.count)])
                if current == original {
                    planned.append((offset, replacement))
                } else if current != replacement {
                    state = "skipped: \(edit.address) holds \(current.map { String(format: "%02x", $0) }.joined()), expected \(edit.original)"
                    break
                }
            }
            if state == nil {
                state = planned.isEmpty ? "already applied" : "applied"
                for (offset, replacement) in planned { data.replaceSubrange(offset..<(offset + replacement.count), with: replacement) }
            }
            results.append((patch.name, state!))
        }
        try Data(data).write(to: eboot)
        return results
    }

    /// The file offsets of the width and height values, or nil when this build does not match.
    public func resolutionOffsets(in eboot: URL) -> (width: Int, height: Int)? {
        guard let resolution, let data = try? [UInt8](Data(contentsOf: eboot)), let list = try? GamePatches.segments(data) else { return nil }
        var width: Int?
        var height: Int?
        for field in resolution.fields {
            let instruction = GamePatches.bytes(field.instruction)
            guard let offset = try? GamePatches.fileOffset(list, GamePatches.address(field.address), instruction.count) else { return nil }
            let prefix = Array(instruction.prefix(field.offset))
            guard Array(data[offset..<(offset + prefix.count)]) == prefix else { return nil }
            if field.value == "width" { width = offset + field.offset }
            if field.value == "height" { height = offset + field.offset }
        }
        guard let width, let height else { return nil }
        return (width, height)
    }

    public static func parse(resolution text: String) -> (UInt32, UInt32)? {
        let parts = text.lowercased().split(separator: "x")
        guard parts.count == 2, let width = UInt32(parts[0]), let height = UInt32(parts[1]), width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// Writes an output resolution into the executable's width and height values.
    public static func write(resolution text: String, offsets: (width: Int, height: Int), to eboot: URL) throws {
        guard let (width, height) = parse(resolution: text) else { throw SelfUnwrap.Refused(reason: "not a WIDTHxHEIGHT resolution: \(text)") }
        let handle = try FileHandle(forUpdating: eboot)
        defer { try? handle.close() }
        for (offset, value) in [(offsets.width, width), (offsets.height, height)] {
            try handle.seek(toOffset: UInt64(offset))
            var little = value.littleEndian
            handle.write(Data(bytes: &little, count: 4))
        }
    }
}
