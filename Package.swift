// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LaunchpadPro",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "LaunchpadPro",
            path: "Sources/LaunchpadPro",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
