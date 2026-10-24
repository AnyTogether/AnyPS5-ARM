import Compression
import XCTest
@testable import AnyPS5Core

/// Writes .pak files the way Unreal does, for the tests: the old index (version 8) or the
/// encoded entries and full directory index of 4.26 and later (version 11).
struct PakWriter {
    var version = 11
    var mount = "../../../"
    var files: [(path: String, data: Data, zlib: Bool)] = []
    var encryptedIndex = false

    static func string(_ text: String) -> Data {
        var data = le(Int32(text.utf8.count + 1))
        data += Data(text.utf8) + [0]
        return data
    }

    static func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    static func zlib(_ data: Data) -> Data {
        var output = Data(count: data.count + 64)
        let count = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_encode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, data.count + 64, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return Data([0x78, 0x9C]) + output.prefix(count) + Data([0, 0, 0, 0])
    }

    /// The header before a file's bytes, and the old index's entry: the same fields.
    func entry(offset: Int64, size: Int64, uncompressed: Int64, method: UInt32, blocks: [(Int64, Int64)]) -> Data {
        var data = Self.le(offset) + Self.le(size) + Self.le(uncompressed)
        data += version < 8 ? Self.le(Int32(method)) : Self.le(method)
        data += Data(repeating: 0, count: 20)
        if method != 0 {
            data += Self.le(Int32(blocks.count))
            for block in blocks { data += Self.le(block.0) + Self.le(block.1) }
        }
        data += Data([0]) + Self.le(UInt32(method != 0 ? 65536 : 0))
        return data
    }

    func write(to url: URL) throws {
        var pak = Data()
        var located: [(path: String, offset: Int64, size: Int64, uncompressed: Int64, method: UInt32, blocks: [(Int64, Int64)])] = []
        for file in files {
            let offset = Int64(pak.count)
            let stored = file.zlib ? Self.zlib(file.data) : file.data
            let method: UInt32 = file.zlib ? 1 : 0
            let headerLength = Int64(entry(offset: 0, size: 0, uncompressed: 0, method: method, blocks: file.zlib ? [(0, 0)] : []).count)
            let blocks: [(Int64, Int64)] = file.zlib ? [(headerLength, headerLength + Int64(stored.count))] : []
            pak += entry(offset: offset, size: Int64(stored.count), uncompressed: Int64(file.data.count), method: method, blocks: blocks)
            pak += stored
            located.append((file.path, offset, Int64(stored.count), Int64(file.data.count), method, blocks))
        }
        var index = Self.string(mount)
        if version < 10 {
            index += Self.le(Int32(located.count))
            for file in located {
                index += Self.string(file.path) + entry(offset: file.offset, size: file.size, uncompressed: file.uncompressed, method: file.method, blocks: file.blocks)
            }
        } else {
            var encoded = Data()
            var locations: [String: Int32] = [:]
            for file in located {
                locations[file.path] = Int32(encoded.count)
                var bits: UInt32 = (1 << 31) | (1 << 30) | (1 << 29) | (file.method << 23)
                if file.method != 0 { bits |= UInt32(file.blocks.count) << 6 | 32 }
                encoded += Self.le(bits) + Self.le(UInt32(file.offset)) + Self.le(UInt32(file.uncompressed))
                if file.method != 0 { encoded += Self.le(UInt32(file.size)) }
            }
            var directory = Data()
            let folders = Dictionary(grouping: located.map(\.path)) { path in path.contains("/") ? String(path[...path.lastIndex(of: "/")!]) : "/" }
            directory += Self.le(Int32(folders.count))
            for (folder, paths) in folders {
                directory += Self.string(folder) + Self.le(Int32(paths.count))
                for path in paths { directory += Self.string(String(path.dropFirst(folder == "/" ? 0 : folder.count))) + Self.le(locations[path]!) }
            }
            let directoryOffset = Int64(pak.count)
            pak += directory
            index += Self.le(Int32(located.count)) + Self.le(UInt64(0)) + Self.le(UInt32(0))
            index += Self.le(UInt32(1)) + Self.le(directoryOffset) + Self.le(Int64(directory.count)) + Data(repeating: 0, count: 20)
            index += Self.le(Int32(encoded.count)) + encoded + Self.le(Int32(0))
        }
        let indexOffset = Int64(pak.count)
        pak += index
        if version >= 7 { pak += Data(repeating: 0, count: 16) }
        pak += Data([encryptedIndex ? 1 : 0])
        pak += Self.le(UnrealPak.magic) + Self.le(UInt32(version)) + Self.le(indexOffset) + Self.le(Int64(index.count)) + Data(repeating: 0, count: 20)
        if version >= 8 {
            for name in ["Zlib", "", "", "", ""] { pak += Data(name.utf8) + Data(repeating: 0, count: 32 - name.utf8.count) }
        }
        try pak.write(to: url)
    }
}

final class UnrealPakTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pak-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func files() -> [(path: String, data: Data, zlib: Bool)] {
        [("Stray/Config/DefaultInput.ini", Data("[/Script/Engine.InputSettings]\n+ActionMappings=(ActionName=\"Jump\",Key=Gamepad_FaceButton_Bottom)\n".utf8), false),
         ("Stray/Config/DefaultGame.ini", Data(String(repeating: "[/Script/EngineSettings.GeneralProjectSettings]\nProjectName=Stray\n", count: 40).utf8), true),
         ("Engine/Config/BaseInput.ini", Data("engine".utf8), false)]
    }

    func testFilesComeOutOfAPakWithTheDirectoryIndex() throws {
        let url = folder.appendingPathComponent("pakchunk0-ps5.pak")
        try PakWriter(version: 11, files: files()).write(to: url)
        let pak = try UnrealPak(url: url)
        XCTAssertEqual(pak.version, 11)
        XCTAssertEqual(Set(pak.paths), ["Stray/Config/DefaultInput.ini", "Stray/Config/DefaultGame.ini", "Engine/Config/BaseInput.ini"])
        XCTAssertEqual(pak.file(endingWith: "config/defaultinput.ini"), files()[0].data)
        XCTAssertEqual(pak.file(endingWith: "DefaultGame.ini"), files()[1].data, "a zlib file")
        XCTAssertEqual(try pak.file("Engine/Config/BaseInput.ini"), Data("engine".utf8))
    }

    func testFilesComeOutOfAPakWithTheOldIndex() throws {
        let url = folder.appendingPathComponent("old.pak")
        try PakWriter(version: 8, files: files()).write(to: url)
        let pak = try UnrealPak(url: url)
        XCTAssertEqual(pak.version, 8)
        XCTAssertEqual(pak.file(endingWith: "DefaultInput.ini"), files()[0].data)
        XCTAssertEqual(pak.file(endingWith: "DefaultGame.ini"), files()[1].data)
    }

    func testAnEncryptedIndexIsSaidSo() throws {
        let url = folder.appendingPathComponent("locked.pak")
        try PakWriter(version: 11, files: files(), encryptedIndex: true).write(to: url)
        XCTAssertThrowsError(try UnrealPak(url: url)) { XCTAssertTrue("\($0)".contains("encrypted")) }
    }

    func testSomethingElseIsNotAPak() throws {
        let url = folder.appendingPathComponent("other.pak")
        try Data(repeating: 7, count: 300).write(to: url)
        XCTAssertThrowsError(try UnrealPak(url: url))
    }
}
