// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LaunchpadProCodex",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "LaunchpadProCodex",
            path: "Sources/LaunchpadProCodex",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("MultitouchSupport"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "LaunchpadProCodexTests",
            dependencies: ["LaunchpadProCodex"]
        )
    ]
)
