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
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
