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
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1")
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
                "GitHubWorkflowParsing"
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
