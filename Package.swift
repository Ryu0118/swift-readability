// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-readability",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Readability",
            targets: ["Readability"]
        ),
        .library(
            name: "ReadabilityUI",
            targets: ["ReadabilityUI"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Readability",
            dependencies: [
                "ReadabilityCore"
            ],
            resources: [
                .copy("../../node_modules/@mozilla/readability/Readability.js"),
                .copy("../../node_modules/@mozilla/readability/Readability-readerable.js"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ReadabilityUI",
            dependencies: [
                "ReadabilityCore"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "ReadabilityCore"
        ),
        .testTarget(
            name: "ReadabilityTests",
            dependencies: ["Readability"]
        ),
    ]
)
