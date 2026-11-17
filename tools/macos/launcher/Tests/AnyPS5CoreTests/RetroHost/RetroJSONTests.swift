import XCTest
@testable import AnyPS5Core

/// The emulator host's JSON rules (anyps5-retro-host docs/protocol.md "Values"), as on Windows and
/// Linux (AnyPS5 Desktop's test/core/retro_host/strict_json_test.dart).
final class RetroJSONTests: XCTestCase {
    private func parse(_ text: String) throws -> RetroJSON { try RetroJSON.parse(Array(text.utf8)) }

    private func assertRejects(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parse(text), "accepted \(text)", file: file, line: line)
    }

    private func assertRejects(bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try RetroJSON.parse(bytes), "accepted \(bytes)", file: file, line: line)
    }

    func testAnObjectReadsWithEveryKindOfValue() throws {
        let value = try parse(#" {"a":null,"b":true,"c":false,"d":-12.5e1,"e":"x\"\\\/\b\f\n\r\t\u00e9","f":[1,[]],"g":{}} "#)
        XCTAssertEqual(value, .object([
            "a": .null, "b": .bool(true), "c": .bool(false), "d": .number(-125), "e": .string("x\"\\/\u{8}\u{c}\n\r\té"),
            "f": .array([.number(1), .array([])]), "g": .object([:]),
        ]))
    }

    func testAKeyTwiceInOneObjectIsAnErrorAtAnyDepth() {
        assertRejects(#"{"type":"a","type":"b"}"#)
        assertRejects(#"{"type":"reply","result":{"x":1,"x":1}}"#)
        assertRejects(#"{"a":[{"k":1,"k":2}]}"#)
        assertRejects(#"{"t":1,"\u0074":2}"#)
        XCTAssertNoThrow(try parse(#"{"a":{"k":1},"b":{"k":1}}"#))
    }

    func testALoneSurrogateEscapeIsAnError() throws {
        assertRejects(#"{"s":"\ud800"}"#)
        assertRejects(#"{"s":"\ud800x"}"#)
        assertRejects(#"{"s":"\ud800\u0041"}"#)
        assertRejects(#"{"s":"\udc00"}"#)
        assertRejects(#"{"s":"a\uDFFFb"}"#)
        XCTAssertEqual(try parse(#""\ud83d\ude00""#), .string("😀"))
        XCTAssertEqual(try parse(#""\uD83D\uDE00""#), .string("😀"))
    }

    func testTheBodyMustBeStrictUTF8() {
        assertRejects(bytes: [0x22, 0xC0, 0x80, 0x22])
        assertRejects(bytes: [0x22, 0xED, 0xA0, 0x80, 0x22])
        assertRejects(bytes: [0x22, 0xF5, 0x80, 0x80, 0x80, 0x22])
        assertRejects(bytes: [0x22, 0xF4, 0x90, 0x80, 0x80, 0x22])
        assertRejects(bytes: [0x22, 0xE2, 0x82, 0x22])
        assertRejects(bytes: [0x22, 0xFF, 0x22])
        XCTAssertEqual(try RetroJSON.parse([0x22, 0xE2, 0x82, 0xAC, 0x22]), .string("€"))
    }

    func testIntegersAreJudgedByValue() throws {
        XCTAssertEqual(try parse("1").intValue, 1)
        XCTAssertEqual(try parse("1.0").intValue, 1)
        XCTAssertEqual(try parse("1e0").intValue, 1)
        XCTAssertEqual(try parse("10E-1").intValue, 1)
        XCTAssertEqual(try parse("-0").intValue, 0)
        XCTAssertEqual(try parse("4294967295").intValue, 4_294_967_295)
        XCTAssertEqual(try parse("-2147483648").intValue, -2_147_483_648)
        XCTAssertNil(try parse("1.5").intValue)
        XCTAssertNil(try parse("\"1\"").intValue)
        XCTAssertNil(try parse("true").intValue)
    }

    func testANumberMustBeFiniteAsADouble() {
        assertRejects("1e400")
        assertRejects("-1e400")
        assertRejects("[1,2e999]")
        XCTAssertNoThrow(try parse("1e308"))
    }

    func testOnlyJSONGrammarIsRead() {
        for text in ["", " ", "01", "1.", ".5", "+1", "-", "1e", "1e+", "tru", "nul", "NaN", "Infinity", "'a'", "[1,]",
                     "{\"a\":1,}", "{\"a\"}", "{a:1}", "[1 2]", "\"a", "\"\\x\"", "\"\\u12\"", "\"\\u12G4\"", "1 2", "{} x"] {
            assertRejects(text)
        }
        assertRejects(bytes: [0x22, 0x0A, 0x22])
        assertRejects(bytes: [0x22, 0x00, 0x22])
        XCTAssertEqual(try parse("\"\\u0000\""), .string("\u{0}"))
    }

    func testNestingPastTheLimitIsAnErrorNotACrash() throws {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        assertRejects(deep)
        let fine = String(repeating: "[", count: RetroJSON.maxDepth) + String(repeating: "]", count: RetroJSON.maxDepth)
        XCTAssertNoThrow(try parse(fine))
        let over = String(repeating: "[", count: RetroJSON.maxDepth + 1) + String(repeating: "]", count: RetroJSON.maxDepth + 1)
        assertRejects(over)
    }

    func testWritingGivesCompactJSONThatReadsBack() throws {
        let value: RetroJSON = .object([
            "type": .string("call"), "id": .int(7), "args": .object(["level": .number(0.25), "muted": .bool(false)]),
            "text": .string("quote \" backslash \\ newline \n tab \t bell \u{7} é 😀"), "none": .null,
            "list": .array([.int(-32768), .number(1e300), .number(4294967295)]),
        ])
        let bytes = try value.encoded()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"id\":7"), text)
        XCTAssertTrue(text.contains("-32768"), text)
        XCTAssertTrue(text.contains("4294967295"), text)
        XCTAssertTrue(text.contains("\\u0007"), text)
        XCTAssertFalse(text.contains(" :"), text)
        XCTAssertEqual(try RetroJSON.parse(bytes), value)
    }

    func testANumberThatIsNotFiniteCannotBeWritten() {
        XCTAssertThrowsError(try RetroJSON.number(.infinity).encoded())
        XCTAssertThrowsError(try RetroJSON.array([.number(.nan)]).encoded())
    }

    func testEveryFixtureFileReads() throws {
        guard let checkout = RetroHostFixtures.checkout else { throw XCTSkip("ANYPS5_RETRO_HOST_CHECKOUT is not set") }
        let root = checkout.appendingPathComponent("fixtures/v1")
        var read = 0
        for folder in ["messages", "sessions"] {
            let directory = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasSuffix(".json") {
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                XCTAssertNotNil(try RetroJSON.parse(data).objectValue, name)
                read += 1
            }
        }
        XCTAssertGreaterThan(read, 40)
    }
}
