import Foundation
import XCTest
@testable import AnyPS5Core

/// Mach-O files as the build makes them, cut down to their header and load commands.
enum FakeMachO {
    static func little(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    static func big(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        return data
    }

    static func packed(_ major: UInt32, _ minor: UInt32, _ patch: UInt32 = 0) -> UInt32 { major << 16 | minor << 8 | patch }

    static func buildVersion(_ major: UInt32, _ minor: UInt32, _ patch: UInt32 = 0, platform: UInt32 = 1) -> Data {
        little([0x32, 24, platform, packed(major, minor, patch), packed(26, 0), 0])
    }

    static func versionMin(_ major: UInt32, _ minor: UInt32) -> Data { little([0x24, 16, packed(major, minor), packed(26, 0)]) }

    static let uuid = little([0x1B, 24, 0, 0, 0, 0])

    static func thin(_ commands: Data...) -> Data { thin(commands) }

    static func thin(_ commands: [Data]) -> Data {
        let body = commands.reduce(Data(), +)
        return little([0xFEED_FACF, 0x0100_0007, 3, 6, UInt32(commands.count), UInt32(body.count), 0, 0]) + body + Data(count: 64)
    }

    /// A universal file with each image at its own 4 KiB page.
    static func universal(_ images: [(cpu: UInt32, image: Data)]) -> Data {
        var header = big([0xCAFE_BABE, UInt32(images.count)])
        var placed = Data()
        for (cpu, image) in images {
            header += big([cpu, 3, UInt32(0x1000 + placed.count), UInt32(image.count), 12])
            placed += image + Data(count: (0x1000 - image.count % 0x1000) % 0x1000)
        }
        return header + Data(count: 0x1000 - header.count) + placed
    }
}

final class SystemMinimumTests: XCTestCase {
    var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("minimum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func write(_ name: String, _ data: Data) throws -> URL {
        let file = scratch.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    func testReadsTheBuildVersionAfterOtherCommands() throws {
        let file = try write("libSceVideoOut.prx", FakeMachO.thin(FakeMachO.uuid, FakeMachO.buildVersion(26, 0)))
        XCTAssertEqual(SystemMinimum.minimum(of: file), SystemMinimum.Version(26, 0))
    }

    func testReadsTheOlderVersionMinCommand() throws {
        XCTAssertEqual(SystemMinimum.minimum(of: try write("libvulkan.1.dylib", FakeMachO.thin(FakeMachO.versionMin(10, 15)))), SystemMinimum.Version(10, 15))
    }

    func testOtherPlatformsAndOtherFilesNameNoMacOS() throws {
        XCTAssertNil(SystemMinimum.minimum(of: try write("ios.dylib", FakeMachO.thin(FakeMachO.buildVersion(17, 0, platform: 2)))))
        XCTAssertNil(SystemMinimum.minimum(of: try write("PPSA02100.json", Data(#"{"titleId":"PPSA02100"}"#.utf8))))
        XCTAssertNil(SystemMinimum.minimum(of: scratch.appendingPathComponent("missing.prx")))
    }

    func testAUniversalFileNamesItsNewestSlice() throws {
        let data = FakeMachO.universal([(0x0100_0007, FakeMachO.thin(FakeMachO.buildVersion(11, 0))), (0x0100_000C, FakeMachO.thin(FakeMachO.buildVersion(14, 2)))])
        XCTAssertEqual(SystemMinimum.minimum(of: try write("libMoltenVK.dylib", data)), SystemMinimum.Version(14, 2))
    }

    func testLoadCommandsPastTheFirstPageAreRead() throws {
        let commands = Array(repeating: FakeMachO.uuid, count: 300) + [FakeMachO.buildVersion(15, 4)]
        let file = try write("libkernel.prx", FakeMachO.thin(commands))
        XCTAssertEqual(SystemMinimum.minimum(of: file), SystemMinimum.Version(15, 4))
    }

    func testAToolkitNeedsTheNewestOfItsCode() throws {
        let root = try FakeToolkit.make(in: scratch)
        XCTAssertNil(SystemMinimum.required(by: Toolkit(root: root)), "the made-up files are no Mach-O")
        try FakeMachO.thin(FakeMachO.buildVersion(14, 0)).write(to: root.appendingPathComponent("relinker"))
        try FakeMachO.thin(FakeMachO.buildVersion(14, 0)).write(to: root.appendingPathComponent("libs/libSceAgc.prx"))
        try FakeMachO.thin(FakeMachO.buildVersion(12, 0)).write(to: root.appendingPathComponent("vulkan/libMoltenVK.dylib"))
        XCTAssertEqual(SystemMinimum.required(by: Toolkit(root: root)), SystemMinimum.Version(14, 0))
        XCTAssertNil(SystemMinimum.unmet(SystemMinimum.required(by: Toolkit(root: root)), on: SystemMinimum.Version(14, 0)))
        try FakeMachO.thin(FakeMachO.buildVersion(26, 0)).write(to: root.appendingPathComponent("libs/libSceAudioOut.prx"))
        XCTAssertEqual(SystemMinimum.unmet(SystemMinimum.required(by: Toolkit(root: root)), on: SystemMinimum.Version(15, 7, 1)), SystemMinimum.Version(26, 0))
        XCTAssertNil(SystemMinimum.unmet(SystemMinimum.required(by: Toolkit(root: root)), on: SystemMinimum.Version(26, 1)))
    }

    func testAnUnlockedGameNeedsWhatItsLibrariesNeed() throws {
        let bundle = scratch.appendingPathComponent("Astro.app")
        _ = try write("Astro.app/Contents/MacOS/eboot", FakeMachO.thin(FakeMachO.buildVersion(11, 0)))
        _ = try write("Astro.app/Contents/MacOS/libs/libc.prx", FakeMachO.thin(FakeMachO.buildVersion(26, 0)))
        _ = try write("Astro.app/Contents/MacOS/libs/MoltenVK_icd.json", Data("{}".utf8))
        XCTAssertEqual(SystemMinimum.required(byBundle: bundle), SystemMinimum.Version(26, 0))
    }

    func testVersionsReadAsMacOSNamesThem() {
        XCTAssertEqual(SystemMinimum.Version(14, 0).description, "14.0")
        XCTAssertEqual(SystemMinimum.Version(14, 6, 1).description, "14.6.1")
        XCTAssertLessThan(SystemMinimum.Version(14, 6, 1), SystemMinimum.Version(15, 0))
        XCTAssertLessThan(SystemMinimum.Version(9, 9), SystemMinimum.Version(10, 0))
        XCTAssertEqual(SystemMinimum.running, SystemMinimum.Version(ProcessInfo.processInfo.operatingSystemVersion))
    }
}
