# seeleseek

seeleseek is a native macOS client for the soulseek protocol.

## Overview

seeleseek is a modern, native macOS client for the soulseek protocol. It provides a clean and intuitive interface for searching, downloading, and sharing files on the soulseek network.

[Docs](https://seeleseek.net)


<img width="554" height="383" alt="Screenshot" src="./site/static/screenshots/01-search.png" />

## Installation

### Prerequisites
- macOS 15+

### From GitHub Releases

1. Download the latest release from the [Releases](https://github.com/bretth18/seeleseek/releases) page. Unsigned builds are available in from the `.zip` assets. It's recommended to use the `.pkg` signed installer for ease of use.
2. Open the app. You may need to approve it in System Preferences > Security & Privacy > General.


## Uninstallation
1. Quit the app.
2. Delete the app from the Applications folder.


## Dependencies
- [GRDB](https://github.com/groue/GRDB.swift)

## Contributing
Contributions are welcome, Please open an issue or submit a pull request.

### Reporting Issues
If you encounter any bugs or have feature requests, please open an issue on the [GitHub Issues](https://github.com/bretth18/seeleseek/issues) page.


## Development

### Prerequisites
- Xcode 16+ (Swift 6)

### Architecture
The core networking and protocol implementation lives in a local Swift Package at `Packages/SeeleseekCore/`. The app target imports this package and adds UI-specific extensions.

- **SeeleseekCore** — Protocol encoding/decoding, server/peer connections, download/upload management, models
- **seeleseek** — SwiftUI app, feature states, design system, database layer

### Documentation Site
A SvelteKit based marketing + documentation site lives in this repo under `/site`

### Setup
1. Clone the repository.
2. Open `seeleseek.xcodeproj` (the local package resolves automatically).

### Build
Run `xcodebuild` or use Xcode.

### CI/CD
GitHub Actions is configured to build and release the app on push to `main`.

## License

[MIT](./LICENSE)

## Acknowledgments

- [SoulSeek](https://www.slsknet.org)
- [Nicotine+](https://nicotine-plus.org) (protocol reference)
- [MusicBrainz](https://musicbrainz.org/) (metadata services)
- [GRDB](https://github.com/groue/GRDB.swift)
