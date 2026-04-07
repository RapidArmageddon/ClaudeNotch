// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeNotch",
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
