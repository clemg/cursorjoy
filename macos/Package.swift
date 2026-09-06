// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "CursorJoy",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CursorJoy",
            path: "Sources/CursorJoy",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
