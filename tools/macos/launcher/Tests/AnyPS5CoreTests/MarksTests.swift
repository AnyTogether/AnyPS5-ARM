import Darwin
import XCTest
@testable import AnyPS5Core

final class MarksTests: XCTestCase {
    func mark(_ url: URL, _ name: String) {
        let value: [UInt8] = [1, 2, 0, 0xB1]
        XCTAssertEqual(setxattr(url.path, name, value, value.count, 0, XATTR_NOFOLLOW), 0, "cannot set \(name)")
    }

    func names(_ url: URL) -> [String] {
        let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        listxattr(url.path, &buffer, size, XATTR_NOFOLLOW)
        return buffer.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    }

    func testClearMarksRemovesProvenanceAndQuarantineEverywhere() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("marks-\(UUID().uuidString).app")
        let deep = bundle.appendingPathComponent("Contents/Resources/game/app0")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let file = deep.appendingPathComponent("eboot.bin")
        try Data([1]).write(to: file)
        for url in [bundle, deep, file] {
            mark(url, "com.apple.provenance")
            mark(url, "com.apple.quarantine")
            mark(url, "org.anyps5.keep")
        }
        Installer.clearMarks(bundle)
        for url in [bundle, deep, file] {
            XCTAssertEqual(names(url), ["org.anyps5.keep"], url.lastPathComponent)
        }
    }
}
