// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SeeleseekCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "SeeleseekCore",
            targets: ["SeeleseekCore"]
        )
    ],
    targets: [
        .target(
            name: "SeeleseekCore"
        ),
        .testTarget(
            name: "SeeleseekCoreTests",
            dependencies: ["SeeleseekCore"],
            resources: [
                // MaxMind's public test fixture (Apache-2.0, safe to redistribute).
                // Source: https://github.com/maxmind/MaxMind-DB/tree/main/test-data
                .copy("Fixtures/GeoIP2-Country-Test.mmdb")
            ]
        )
    ]
)
