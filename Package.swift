// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Octowatch",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Octowatch", targets: ["Octowatch"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.1")
    ],
    targets: [
        .target(
            name: "GitHubWorkflowParsing",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/GitHubWorkflowParsing"
        ),
        .executableTarget(
            name: "Octowatch",
            dependencies: [
                "GitHubWorkflowParsing",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Octobar",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "OctowatchTests",
            dependencies: [
                "Octowatch",
                "GitHubWorkflowParsing"
            ],
            path: "Tests/OctobarTests"
        )
    ]
)
