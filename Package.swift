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
    targets: [
        .executableTarget(
            name: "Octowatch",
            path: "Sources/Octobar",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "OctowatchTests",
            dependencies: ["Octowatch"],
            path: "Tests/OctobarTests"
        )
    ]
)
