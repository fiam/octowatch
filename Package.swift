// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Octobar",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Octobar", targets: ["Octobar"])
    ],
    targets: [
        .executableTarget(
            name: "Octobar",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "OctobarTests",
            dependencies: ["Octobar"]
        )
    ]
)
