// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PasteIt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PasteIt", targets: ["PasteIt"]),
        .library(name: "PasteItCore", targets: ["PasteItCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.59.3")
    ],
    targets: [
        .target(
            name: "PasteItCore",
            path: "Sources/PasteItCore",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "PasteIt",
            dependencies: [
                "PasteItCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "PostHog", package: "posthog-ios")
            ],
            path: "Sources/PasteIt",
            resources: [
                .process("../../Resources")
            ],
            linkerSettings: [
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "PasteItTests",
            dependencies: ["PasteItCore"],
            path: "Tests/PasteItTests"
        )
    ]
)
