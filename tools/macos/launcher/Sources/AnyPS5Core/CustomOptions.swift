import Foundation

/// What is wrong with a typed options text (Advanced → Custom Relinker Options, Launch Options).
/// The first problem from the left is the one said. The same checks as AnyPS5 Desktop's.
public enum OptionsProblem: Error, Equatable, Sendable {
    /// A quote is opened and never closed.
    case openQuote
    /// An option the launcher chooses itself: the platform, the target, the files, the patches.
    case launcherOption(String)
    /// An option after which the rebuild makes no game that starts (or none at all).
    case breaksGame(String)
    /// An option that has its own switch on the page (--trace-imports).
    case hasSwitch(String)
    /// Not an option of the relinker.
    case unknown(String)
    /// An option that takes a value, without one after it.
    case needsValue(String)
    /// A word that is no option: the relinker would read it as one of its files.
    case positional(String)
}

/// Splits an options text into words as a POSIX shell would, without ever running one: unquoted
/// whitespace separates them, '…' keeps everything as it is, "…" keeps everything but \" and \\,
/// and outside quotes a backslash takes the next character as it is. Quoted parts join the word
/// they touch.
public enum OptionWords {
    public static func split(_ text: String) -> Result<[String], OptionsProblem> {
        var words: [String] = []
        var word: String?
        var characters = Array(text)[...]
        while let character = characters.popFirst() {
            switch character {
            case " ", "\t", "\n", "\r", "\r\n":
                if let finished = word { words.append(finished) }
                word = nil
            case "'":
                guard let end = characters.firstIndex(of: "'") else { return .failure(.openQuote) }
                word = (word ?? "") + String(characters[..<end])
                characters = characters[(end + 1)...]
            case "\"":
                var quoted = ""
                var closed = false
                while let inside = characters.popFirst() {
                    if inside == "\"" { closed = true; break }
                    if inside == "\\", let next = characters.first, next == "\"" || next == "\\" {
                        quoted.append(next)
                        characters = characters.dropFirst()
                    } else {
                        quoted.append(inside)
                    }
                }
                guard closed else { return .failure(.openQuote) }
                word = (word ?? "") + quoted
            case "\\":
                word = (word ?? "") + String(characters.popFirst() ?? "\\")
            default:
                word = (word ?? "") + String(character)
            }
        }
        if let finished = word { words.append(finished) }
        return .success(words)
    }
}

/// The relinker options a player may add for one game (Advanced → Custom Relinker Options), after
/// the launcher's own. The relinker's options are those of core/relinker/cli/src/CliArgs.cpp: the
/// ones that choose the platform, the target or the files are the launcher's, and the ones that
/// make no working game are refused, so only what is left here reaches the relinker.
public enum CustomRelinkerOptions {
    /// The launcher's to choose: the system and CPU the game is made for, where its modules and
    /// libraries are, and the title's patches.
    public static let launcherOwned: Set<String> = [
        "--windows", "--windows-gui", "--macos", "--to-intel", "--to-rosetta",
        "--sce-module-path", "--module-dir", "--executable", "--rpath", "--patches", "--no-patches",
    ]
    /// After these the rebuild writes no game, or one without its modules.
    public static let breaking: Set<String> = [
        "--skip-sce-module", "--dry-run", "--autorun", "--verify-patches", "--verify-output", "--help", "--version",
    ]
    /// The options with a switch of their own on the page (RelinkerFlag).
    public static let switched: Set<String> = Set(RelinkerFlag.allCases.map(\.rawValue))
    /// Options that take the next word as their value.
    public static let withValue: Set<String> = ["--exclude-sce-module", "--windows-fixed-base", "--linux-fixed-base", "--macos-fixed-base"]
    /// Options that stand alone.
    public static let plain: Set<String> = [
        "--windows-diagnostics", "--frame-red-zone", "--omit-unavailable-dependencies", "--registry",
        "--skip-syscall-check", "--trap-sdk-syscall-stubs", "--lazy-binding",
    ]
    /// The relinker's one option without dashes, with the values it takes.
    public static let unusedFilters: Set<String> = ["unused-filter=0", "unused-filter=1", "unused-filter=2"]

    /// The words of `text` to pass to the relinker, or the first problem with them.
    public static func check(_ text: String) -> Result<[String], OptionsProblem> {
        let words: [String]
        switch OptionWords.split(text) {
        case .failure(let problem): return .failure(problem)
        case .success(let split): words = split
        }
        var index = 0
        while index < words.count {
            let word = words[index]
            if word.hasPrefix("--") && word != "--" {
                if launcherOwned.contains(word) { return .failure(.launcherOption(word)) }
                if breaking.contains(word) { return .failure(.breaksGame(word)) }
                if switched.contains(word) { return .failure(.hasSwitch(word)) }
                if withValue.contains(word) {
                    guard index + 1 < words.count, !words[index + 1].isEmpty, !words[index + 1].hasPrefix("--") else { return .failure(.needsValue(word)) }
                    index += 2
                    continue
                }
                guard plain.contains(word) else { return .failure(.unknown(word)) }
            } else if word.hasPrefix("unused-filter") {
                guard unusedFilters.contains(word) else { return .failure(.unknown(word)) }
            } else {
                return .failure(.positional(word.isEmpty ? "\"\"" : word))
            }
            index += 1
        }
        return .success(words)
    }
}

/// A game's launch options (Advanced → Launch Options): environment variables as NAME=value first,
/// then the arguments the game is started with. A variable the launcher sets for the start keeps
/// the launcher's value.
public struct LaunchOptions: Equatable, Sendable {
    /// The variables in the order typed; a name typed twice keeps its last value.
    public var variables: [(name: String, value: String)]
    public var arguments: [String]

    public init(variables: [(name: String, value: String)] = [], arguments: [String] = []) {
        self.variables = variables
        self.arguments = arguments
    }

    public static func == (lhs: LaunchOptions, rhs: LaunchOptions) -> Bool {
        lhs.variables.map { "\($0.name)=\($0.value)" } == rhs.variables.map { "\($0.name)=\($0.value)" } && lhs.arguments == rhs.arguments
    }

    public var isEmpty: Bool { variables.isEmpty && arguments.isEmpty }

    /// The leading NAME=value words of `text`, then everything from the first other word on.
    public static func parse(_ text: String) -> Result<LaunchOptions, OptionsProblem> {
        let words: [String]
        switch OptionWords.split(text) {
        case .failure(let problem): return .failure(problem)
        case .success(let split): words = split
        }
        var options = LaunchOptions()
        var rest = words[...]
        while let word = rest.first, let equals = word.firstIndex(of: "="), isName(word[..<equals]) {
            options.variables.append((name: String(word[..<equals]), value: String(word[word.index(after: equals)...])))
            rest = rest.dropFirst()
        }
        options.arguments = Array(rest)
        return .success(options)
    }

    static func isName(_ name: Substring) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && CharacterSet.letters.contains(first)) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) }
    }

    /// The typed variables with `launcher`'s over them: the launcher's value wins. Those named in
    /// `reserved` (what the game's launch script sets itself) are left out too.
    public func environment(under launcher: [String: String], reserved: Set<String> = []) -> [String: String] {
        var environment: [String: String] = [:]
        for variable in variables where !reserved.contains(variable.name) { environment[variable.name] = variable.value }
        return environment.merging(launcher) { _, own in own }
    }

    /// The typed variables the launcher sets too, so theirs is not used; sorted.
    public func overridden(by launcher: [String: String], reserved: Set<String> = []) -> [String] {
        Set(variables.map(\.name)).filter { launcher[$0] != nil || reserved.contains($0) }.sorted()
    }
}

extension GameSettings {
    /// The custom relinker options to pass on this game's next rebuild; none while the saved text
    /// does not pass the check (it cannot be saved so, see init(from:)).
    public var chosenRelinkerOptions: [String] {
        guard let customRelinkerOptions, case .success(let words) = CustomRelinkerOptions.check(customRelinkerOptions) else { return [] }
        return words
    }

    /// The launch options to start this game with; none while the saved text does not parse.
    public var chosenLaunchOptions: LaunchOptions {
        guard let launchOptions, case .success(let options) = LaunchOptions.parse(launchOptions) else { return LaunchOptions() }
        return options
    }

    /// Saves `text` as the custom relinker options when it passes the check (blank clears them);
    /// returns the problem, leaving them as they were, when it does not.
    @discardableResult
    public mutating func setCustomRelinkerOptions(_ text: String) -> OptionsProblem? {
        if case .failure(let problem) = CustomRelinkerOptions.check(text) { return problem }
        customRelinkerOptions = GameSettings.saved(text)
        return nil
    }

    /// Saves `text` as the launch options when it parses (blank clears them); returns the problem,
    /// leaving them as they were, when it does not.
    @discardableResult
    public mutating func setLaunchOptions(_ text: String) -> OptionsProblem? {
        if case .failure(let problem) = LaunchOptions.parse(text) { return problem }
        launchOptions = GameSettings.saved(text)
        return nil
    }

    static func saved(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
