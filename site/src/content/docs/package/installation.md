---
title: Installation
description: Add SeeleseekCore to your Swift project via Swift Package Manager.
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

Or if you're using it as a local package (like the seeleseek app does), reference the path:

```swift
dependencies: [
    .package(path: "../Packages/SeeleseekCore")
]
```

## Xcode

1. Open your project in Xcode
2. Go to **File > Add Package Dependencies**
3. Enter the repository URL
4. Select the SeeleseekCore library product

## What's Included

The package provides a single library product, `SeeleseekCore`, which includes:

- Protocol implementation (message building and parsing)
- Server and peer connection management
- Download and upload managers
- Share indexing and management
- NAT traversal and port mapping
- GeoIP resolution
- All model types

## App-Layer Dependencies

SeeleseekCore intentionally does **not** include:

- UI components (it's a networking package)
- AppKit/UIKit imports
- Notification handling
- Persistent storage (the app handles settings/state persistence)

Your app needs to provide implementations of several protocols — see the [Overview](/docs/package/overview) for details on `TransferTracking`, `StatisticsRecording`, `DownloadSettingsProviding`, and `MetadataReading`.
