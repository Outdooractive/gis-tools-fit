// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "gis-tools-fit",
    platforms: [
        .iOS(.v15),
        .macOS(.v15),
        .tvOS(.v15),
        .watchOS(.v7),
    ],
    products: [
        .library(
            name: "GISToolsFIT",
            targets: ["GISToolsFIT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools", exact: "3.0.0-beta.5"),
    ],
    targets: [
        .target(
            name: "GISToolsFIT",
            dependencies: [
                .product(name: "GISTools", package: "gis-tools"),
            ]),
        .testTarget(
            name: "GISToolsFITTests",
            dependencies: ["GISToolsFIT"],
            resources: [
                .copy("TestData"),
            ]),
    ]
)
