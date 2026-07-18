// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PasteIt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PasteIt", targets: ["PasteIt"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .executableTarget(
            name: "PasteIt",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/PasteIt",
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)
