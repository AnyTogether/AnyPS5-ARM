// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnyPS5Launcher",
    platforms: [.macOS(.v14)],
    targets: [
        // The ATRAC9 decoder for games' theme songs (vendored LibAtrac9, see its README).
        .target(name: "CAtrac9", path: "Sources/CAtrac9", exclude: ["LICENSE", "README.md"],
                cSettings: [.unsafeFlags(["-w"])]),
        // Game folders, SELF unwrapping, patches and the conversion into a Mac bundle: no UI.
        .target(name: "AnyPS5Core", dependencies: ["CAtrac9"], path: "Sources/AnyPS5Core"),
        // The PS5-style launcher.
        .executableTarget(name: "AnyPS5", dependencies: ["AnyPS5Core"], path: "Sources/AnyPS5"),
        // The same pipeline from the command line, for scripted checks.
        .executableTarget(name: "anyps5-tool", dependencies: ["AnyPS5Core"], path: "Sources/anyps5-tool"),
        // Unit tests of the core, run with `swift test`.
        .testTarget(name: "AnyPS5CoreTests", dependencies: ["AnyPS5Core"], path: "Tests/AnyPS5CoreTests"),
    ]
)
