// swift-tools-version: 6.2

import PackageDescription

// SE-0461 caller-actor semantics: nonisolated async functions run on the
// caller's actor unless marked @concurrent. Matches the app target's
// SWIFT_APPROACHABLE_CONCURRENCY = YES so async semantics are uniform
// across the module boundary.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

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
            name: "SeeleseekCore",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SeeleseekCoreTests",
            dependencies: ["SeeleseekCore"],
            resources: [
                // MaxMind's public test fixture (Apache-2.0, safe to redistribute).
                // Source: https://github.com/maxmind/MaxMind-DB/tree/main/test-data
                .copy("Fixtures/GeoIP2-Country-Test.mmdb")
            ],
            swiftSettings: swiftSettings
        )
    ]
)
