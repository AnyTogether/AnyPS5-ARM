// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnyPS5Launcher",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Google's WebRTC, prebuilt (BSD-3-Clause), for voice in parties: arm64 and x86_64.
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "155.0.0"),
    ],
    targets: [
        // The ATRAC9 decoder for games' theme songs (vendored LibAtrac9, see its README).
        .target(name: "CAtrac9", path: "Sources/CAtrac9", exclude: ["LICENSE", "README.md"],
                cSettings: [.unsafeFlags(["-w"])]),
        // Game folders, SELF unwrapping, patches and the conversion into a Mac bundle: no UI.
        .target(name: "AnyPS5Core", dependencies: ["CAtrac9"], path: "Sources/AnyPS5Core"),
        // Share play over WebRTC: the host's stream to each viewer and a viewer's side of it.
        .target(name: "AnyPS5SharePlay", dependencies: ["AnyPS5Core", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5SharePlay"),
        // The PS5-style launcher.
        .executableTarget(name: "AnyPS5", dependencies: ["AnyPS5Core", "AnyPS5SharePlay", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5"),
        // The same pipeline from the command line, for scripted checks.
        .executableTarget(name: "anyps5-tool", dependencies: ["AnyPS5Core"], path: "Sources/anyps5-tool"),
        // Unit tests of the core, run with `swift test`.
        .testTarget(name: "AnyPS5CoreTests", dependencies: ["AnyPS5Core"], path: "Tests/AnyPS5CoreTests"),
        // Share play's WebRTC wiring end to end in one process, with a synthetic picture.
        .testTarget(name: "AnyPS5SharePlayTests", dependencies: ["AnyPS5SharePlay"], path: "Tests/AnyPS5SharePlayTests"),
    ]
)
