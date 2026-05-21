// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Foldwake",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "FoldwakeCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "Foldwake",
            dependencies: ["FoldwakeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "FoldwakeHelper",
            dependencies: ["FoldwakeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "FoldwakeCoreTests",
            dependencies: ["FoldwakeCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
