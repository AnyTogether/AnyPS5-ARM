// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnyPS5Launcher",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Google's WebRTC, prebuilt (BSD-3-Clause), for voice in parties: arm64 and x86_64.
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "155.0.0"),
        // LiveKit's client (Apache-2.0), for the optional media server: share plays with more
        // viewers than the mesh holds and big party calls. It brings its own renamed WebRTC
        // (LiveKitWebRTC), which links beside stasel's.
        .package(url: "https://github.com/livekit/client-sdk-swift.git", exact: "2.18.0"),
    ],
    targets: [
        // The ATRAC9 decoder for games' theme songs (vendored LibAtrac9, see its README).
        .target(name: "CAtrac9", path: "Sources/CAtrac9", exclude: ["LICENSE", "README.md"],
                cSettings: [.unsafeFlags(["-w"])]),
        // macOS's own libarchive (/usr/lib), for games dumped as a zip (GameArchives.swift).
        .systemLibrary(name: "CArchive", path: "Sources/CArchive"),
        // Game folders, SELF unwrapping, patches and the conversion into a Mac bundle: no UI.
        .target(name: "AnyPS5Core", dependencies: ["CAtrac9", "CArchive"], path: "Sources/AnyPS5Core"),
        // Share play's audio device for WebRTC: the game's sound in, the received sound out.
        .target(name: "CShareAudio", dependencies: [.product(name: "WebRTC", package: "WebRTC")], path: "Sources/CShareAudio"),
        // Share play over WebRTC: the host's stream to each viewer and a viewer's side of it.
        .target(name: "AnyPS5SharePlay", dependencies: ["AnyPS5Core", "CShareAudio", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5SharePlay"),
        // The optional media server (LiveKit): a big share play's picture and sound published once,
        // watched from it, and a big party's voice.
        .target(name: "AnyPS5MediaServer", dependencies: ["AnyPS5Core", .product(name: "LiveKit", package: "client-sdk-swift")], path: "Sources/AnyPS5MediaServer"),
        // Online play's game packets between players over WebRTC data channels.
        .target(name: "AnyPS5Online", dependencies: ["AnyPS5Core", "CShareAudio", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5Online"),
        // The PS5-style launcher.
        .executableTarget(name: "AnyPS5", dependencies: ["AnyPS5Core", "AnyPS5SharePlay", "AnyPS5Online", "AnyPS5MediaServer", .product(name: "WebRTC", package: "WebRTC")], path: "Sources/AnyPS5"),
        // The same pipeline from the command line, for scripted checks.
        .executableTarget(name: "anyps5-tool", dependencies: ["AnyPS5Core"], path: "Sources/anyps5-tool"),
        // Unit tests of the core, run with `swift test`.
        .testTarget(name: "AnyPS5CoreTests", dependencies: ["AnyPS5Core"], path: "Tests/AnyPS5CoreTests", exclude: ["Fixtures"]),
        // Share play's WebRTC wiring end to end in one process, with a synthetic picture.
        .testTarget(name: "AnyPS5SharePlayTests", dependencies: ["AnyPS5SharePlay"], path: "Tests/AnyPS5SharePlayTests"),
        // The media server end to end against a LiveKit dev server, when ANYPS5_LIVEKIT_URL names one.
        .testTarget(name: "AnyPS5MediaServerTests", dependencies: ["AnyPS5MediaServer"], path: "Tests/AnyPS5MediaServerTests"),
        // Online play end to end in one process: two launchers, two fake engines, real data channels.
        .testTarget(name: "AnyPS5OnlineTests", dependencies: ["AnyPS5Online"], path: "Tests/AnyPS5OnlineTests"),
        // The launcher's texts against its language files in l10n (TRANSLATING.md there).
        .testTarget(name: "AnyPS5Tests", dependencies: ["AnyPS5"], path: "Tests/AnyPS5Tests"),
    ]
)
