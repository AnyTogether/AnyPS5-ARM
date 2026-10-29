import Foundation

/// The launcher's language files (tools/macos/launcher/l10n, TRANSLATING.md there): one JSON object
/// per language named by its code (de.json is German), its texts by key and its name and console
/// language in "@meta". The same format and keys as AnyPS5-Desktop's assets/l10n.
public struct LanguageFile: Equatable, Sendable {
    public let code: String
    /// The language's name in itself, as Settings lists it.
    public let name: String
    /// The console language a game starts in when its own setting follows the launcher.
    public let consoleLanguage: Int
    public let texts: [String: String]

    public init(code: String, name: String, consoleLanguage: Int, texts: [String: String]) {
        self.code = code
        self.name = name
        self.consoleLanguage = consoleLanguage
        self.texts = texts
    }
}

public enum LanguageFiles {
    /// The reserved key of a file's name and console language; never a text.
    public static let meta = "@meta"
    /// The console languages the engine knows (ConsoleLanguage in GameSettings.swift).
    public static let consoleLanguages = 22
    /// English, the language every other one falls back to.
    public static let english = "en"

    public enum Failure: Error, Equatable {
        case notJSON(String)
        case notAnObject
    }

    /// Reads one file of language [code]. Values that are not texts are left out; a missing or
    /// broken "@meta" gives the code as the name and English's console language.
    public static func parse(_ data: Data, code: String) throws -> LanguageFile {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Failure.notJSON(String(describing: error))
        }
        guard let object = json as? [String: Any] else { throw Failure.notAnObject }
        let about = object[meta] as? [String: Any]
        let name = (about?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let console = about?["consoleLanguage"] as? Int
        var texts: [String: String] = [:]
        for (key, value) in object where key != meta {
            if let text = value as? String { texts[key] = text }
        }
        return LanguageFile(code: code, name: name?.isEmpty == false ? name! : code,
                            consoleLanguage: console.map { (0..<consoleLanguages).contains($0) ? $0 : 1 } ?? 1, texts: texts)
    }

    /// The language files in [folders], the first folder first: a file there comes before one of
    /// the same code further on (the user's Languages folder before the built-in files), and one
    /// that cannot be read is left out for the next of its code. English comes first, then the
    /// others by name.
    public static func load(_ folders: [URL], log: (String) -> Void = { _ in }) -> [LanguageFile] {
        var candidates: [String: [URL]] = [:]
        var order: [String] = []
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
                let code = file.deletingPathExtension().lastPathComponent
                guard !code.isEmpty, !code.hasPrefix(".") else { continue }
                if candidates[code] == nil { order.append(code) }
                candidates[code, default: []].append(file)
            }
        }
        var found: [LanguageFile] = []
        for code in order {
            for file in candidates[code] ?? [] {
                do {
                    found.append(try parse(Data(contentsOf: file), code: code))
                    break
                } catch {
                    log("the language file \(file.path) is left out: \(error)")
                }
            }
        }
        return found.sorted { a, b in
            if a.code == english || b.code == english { return a.code == english }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    /// A text's placeholders as String(format:) fills them: (argument number, kind) for each,
    /// numbered in order, and each %1$@ by its own number; %% is a percent sign, not one. The kind
    /// is the conversion (@, d, f, …) with its length modifier (ld), not its width or precision; a
    /// percent sign before a space ("0 % is solid") is no placeholder.
    public static func placeholders(_ text: String) -> Set<Placeholder> {
        var found = Set<Placeholder>()
        var next = 0
        let characters = Array(text.unicodeScalars)
        var index = 0
        while index < characters.count {
            guard characters[index] == "%", index + 1 < characters.count else { index += 1; continue }
            var cursor = index + 1
            if characters[cursor] == "%" { index = cursor + 1; continue }
            var position: Int?
            var digits = ""
            var probe = cursor
            while probe < characters.count, ("0"..."9").contains(characters[probe]) { digits.unicodeScalars.append(characters[probe]); probe += 1 }
            if !digits.isEmpty, probe < characters.count, characters[probe] == "$" {
                position = Int(digits)
                cursor = probe + 1
            }
            while cursor < characters.count, "-+#0123456789.".unicodeScalars.contains(characters[cursor]) { cursor += 1 }
            var kind = ""
            while cursor < characters.count, "hlqLzjt".unicodeScalars.contains(characters[cursor]) { kind.unicodeScalars.append(characters[cursor]); cursor += 1 }
            guard cursor < characters.count, "@dDiuUxXoOfFeEgGcCsSpaA".unicodeScalars.contains(characters[cursor]) else { index = cursor; continue }
            kind.unicodeScalars.append(characters[cursor])
            if let position {
                found.insert(Placeholder(number: position, kind: kind))
            } else {
                next += 1
                found.insert(Placeholder(number: next, kind: kind))
            }
            index = cursor + 1
        }
        return found
    }

    public struct Placeholder: Hashable, Comparable, CustomStringConvertible, Sendable {
        public let number: Int
        public let kind: String

        public init(number: Int, kind: String) {
            self.number = number
            self.kind = kind
        }

        public static func < (a: Placeholder, b: Placeholder) -> Bool { (a.number, a.kind) < (b.number, b.kind) }
        public var description: String { "#\(number) %\(kind)" }
    }

    /// What is wrong with [file] next to the English texts, as check_translations.dart in
    /// AnyPS5-Desktop says it: a key English lacks, or other placeholders than English's.
    public static func problems(_ file: LanguageFile, english: [String: String]) -> [String] {
        var problems: [String] = []
        for key in file.texts.keys.sorted() {
            guard let englishText = english[key] else {
                problems.append("\(file.code).json: \"\(key)\" is not a key of en.json (a typo, or a key English no longer has)")
                continue
            }
            let want = placeholders(englishText), have = placeholders(file.texts[key]!)
            if want != have {
                let shown = { (found: Set<Placeholder>) in found.isEmpty ? "none" : found.sorted().map(\.description).joined(separator: ", ") }
                problems.append("\(file.code).json: \"\(key)\" has the placeholders \(shown(have)), English has \(shown(want))")
            }
        }
        return problems
    }
}

/// The texts of every language file, looked up with English as the fallback. A translated text
/// whose placeholders are not English's is left out (English shows instead): String(format:)
/// would read the wrong argument, or crash.
public struct LanguageTexts: Sendable {
    public let languages: [LanguageFile]
    private let texts: [String: [String: String]]

    public init(_ languages: [LanguageFile]) {
        let english = languages.first { $0.code == LanguageFiles.english }?.texts ?? [:]
        var texts: [String: [String: String]] = [:]
        for language in languages {
            texts[language.code] = language.code == LanguageFiles.english ? language.texts : language.texts.filter { key, text in
                english[key].map { LanguageFiles.placeholders($0) == LanguageFiles.placeholders(text) } ?? true
            }
        }
        self.languages = languages
        self.texts = texts
    }

    /// The text for [key] in [code], English when the language has none, the key itself when
    /// English has none either.
    public func text(_ key: String, in code: String) -> String {
        texts[code]?[key] ?? texts[LanguageFiles.english]?[key] ?? key
    }

    public func language(_ code: String) -> LanguageFile? {
        languages.first { $0.code == code }
    }
}
