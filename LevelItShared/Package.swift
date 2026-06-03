// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LevelItShared",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LevelItShared",
            targets: ["LevelItShared"]
        ),
    ],
    targets: [
        .target(
            name: "LevelItShared",
            path: "Sources"
        ),
        .testTarget(
            name: "LevelItSharedTests",
            dependencies: ["LevelItShared"],
            path: "Tests"
        ),
    ]
)
