---
title: Installation
description: Add SeeleseekCore to your Swift project with Swift Package Manager.
order: 11
section: package
---

## Requirements

- **Swift 6.0** or later
- **macOS 15+** or **iOS 18+**
- Xcode 16+

## Swift Package Manager

Add SeeleseekCore as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bretth18/seeleseek", from: "1.0.0")
]
```

Then add it to your target:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SeeleseekCore", package: "seeleseek")
        ]
    )
]
```

For a local package (the seeleseek app uses this method), give the path:

```swift
dependencies: [
    .package(path: "../Packages/SeeleseekCore")
]
```

## Xcode

1. Open your project in Xcode.
2. Select **File > Add Package Dependencies**.
3. Enter the repository URL.
4. Select the SeeleseekCore library product.

## Package Contents

The package has one library product, `SeeleseekCore`. It contains:

- The protocol implementation (message construction and parsing)
- Server and peer connection management
- The download and upload managers
- The shared folder index and its management
- NAT traversal and port mapping
- GeoIP resolution
- All model types

## App-Layer Dependencies

SeeleseekCore does **not** contain:

- UI components (it is a networking package)
- AppKit or UIKit imports
- Notification code
- Persistent storage (the app keeps the settings and the state)

Your app must implement some protocols. See the [Overview](/docs/package/overview) for `TransferTracking`, `StatisticsRecording`, `DownloadSettingsProviding`, and `MetadataReading`.
