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
            name: "SeeleseekCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
