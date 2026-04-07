// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeNotch",
            dependencies: ["Sparkle"],
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
