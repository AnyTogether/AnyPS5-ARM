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
        // Share play's audio device for WebRTC: the game's sound in, the received sound out.
        .target(name: "CShareAudio", dependencies: [.product(name: "WebRTC", package: "WebRTC")], path: "Sources/CShareAudio"),
        // Share play over WebRTC: the host's stream to each viewer and a viewer's side of it.
        .target(name: "AnyPS5SharePlay", dependencies: ["AnyPS5Core", "CShareAudio", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5SharePlay"),
        // Online play's game packets between players over WebRTC data channels.
        .target(name: "AnyPS5Online", dependencies: ["AnyPS5Core", "CShareAudio", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5Online"),
        // The PS5-style launcher.
        .executableTarget(name: "AnyPS5", dependencies: ["AnyPS5Core", "AnyPS5SharePlay", "AnyPS5Online", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5"),
        // The same pipeline from the command line, for scripted checks.
        .executableTarget(name: "anyps5-tool", dependencies: ["AnyPS5Core"], path: "Sources/anyps5-tool"),
        // Unit tests of the core, run with `swift test`.
        .testTarget(name: "AnyPS5CoreTests", dependencies: ["AnyPS5Core"], path: "Tests/AnyPS5CoreTests", exclude: ["Fixtures"]),
        // Share play's WebRTC wiring end to end in one process, with a synthetic picture.
        .testTarget(name: "AnyPS5SharePlayTests", dependencies: ["AnyPS5SharePlay"], path: "Tests/AnyPS5SharePlayTests"),
        // Online play end to end in one process: two launchers, two fake engines, real data channels.
        .testTarget(name: "AnyPS5OnlineTests", dependencies: ["AnyPS5Online"], path: "Tests/AnyPS5OnlineTests"),
        // The launcher's texts against its language files in l10n (TRANSLATING.md there).
        .testTarget(name: "AnyPS5Tests", dependencies: ["AnyPS5"], path: "Tests/AnyPS5Tests"),
    ]
)
