// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "CommandShiftHero",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "GameCore"
        ),
        .target(
            name: "AudioAnalysis",
            dependencies: ["GameCore"],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFAudio"),
            ]
        ),
        .target(
            name: "GameScene",
            dependencies: ["GameCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("SpriteKit"),
            ]
        ),
        .target(
            name: "MusicBridge",
            linkerSettings: [
                .linkedFramework("iTunesLibrary"),
            ]
        ),
        .target(
            name: "TapCapture",
            dependencies: ["GameCore"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFAudio"),
            ]
        ),
        .executableTarget(
            name: "CommandShiftHero",
            dependencies: ["GameCore", "GameScene", "AudioAnalysis", "MusicBridge", "TapCapture"],
            resources: [.copy("Resources/demo.m4a")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "GameCoreTests",
            dependencies: ["GameCore"]
        ),
        .testTarget(
            name: "AudioAnalysisTests",
            dependencies: ["AudioAnalysis", "GameCore"]
        ),
    ]
)
