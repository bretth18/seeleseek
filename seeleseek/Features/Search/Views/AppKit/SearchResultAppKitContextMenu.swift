import AppKit
import SeeleseekCore

/// Menu entries for AppKit search rows — mirrors `SearchResultRow`'s SwiftUI
/// context menu so right-click stays feature-complete after the table port.
enum SearchResultAppKitMenuItem: Equatable {
    case download(isQueued: Bool)
    case downloadFolder
    case browseFolder
    case browseUser(String)
    case viewProfile
    case ignoreUser
    case unignoreUser
    case copyFilename
    case copyPath
    case separator

    var title: String {
        switch self {
        case .download(let isQueued):
            isQueued ? "Downloading…" : "Download"
        case .downloadFolder:
            "Download entire folder"
        case .browseFolder:
            "Browse folder"
        case .browseUser(let username):
            "Browse \(username)"
        case .viewProfile:
            "View profile"
        case .ignoreUser:
            "Ignore user"
        case .unignoreUser:
            "Unignore user"
        case .copyFilename:
            "Copy filename"
        case .copyPath:
            "Copy full path"
        case .separator:
            ""
        }
    }

    var systemImage: String? {
        switch self {
        case .download: "arrow.down.circle"
        case .downloadFolder: "arrow.down.square.fill"
        case .browseFolder: "folder.badge.questionmark"
        case .browseUser: "folder"
        case .viewProfile: "person.crop.circle"
        case .ignoreUser: "eye.slash"
        case .unignoreUser: "eye"
        case .copyFilename: "doc.on.doc"
        case .copyPath: "link"
        case .separator: nil
        }
    }

    func isEnabled(isIgnored: Bool) -> Bool {
        switch self {
        case .download(let isQueued):
            !isQueued && !isIgnored
        case .downloadFolder:
            !isIgnored
        case .separator:
            true
        default:
            true
        }
    }
}

enum SearchResultAppKitMenuBuilder {
    /// Spec for a result row — matches the pre-AppKit `SearchResultRow` menu.
    static func items(
        for result: SearchResult,
        isIgnored: Bool,
        isQueued: Bool
    ) -> [SearchResultAppKitMenuItem] {
        [
            .download(isQueued: isQueued),
            .downloadFolder,
            .browseFolder,
            .browseUser(result.username),
            .viewProfile,
            .separator,
            isIgnored ? .unignoreUser : .ignoreUser,
            .separator,
            .copyFilename,
            .copyPath,
        ]
    }

    /// Group headers only had a download-folder button in SwiftUI; right-click
    /// still needs the folder/user actions that used to live on child rows.
    static func items(
        for group: SearchResultGroup,
        isIgnored: Bool
    ) -> [SearchResultAppKitMenuItem] {
        [
            .downloadFolder,
            .browseFolder,
            .browseUser(group.username),
            .viewProfile,
            .separator,
            isIgnored ? .unignoreUser : .ignoreUser,
        ]
    }
}

/// Callbacks the AppKit table needs from SwiftUI / `AppState`.
struct SearchResultAppKitActions {
    var onDownload: (SearchResult) -> Void
    var onDownloadFolder: (SearchResult) -> Void
    var onBrowseFolder: (SearchResult) -> Void
    var onBrowseUser: (SearchResult) -> Void
    var onViewProfile: (SearchResult) -> Void
    var onToggleIgnore: (SearchResult) -> Void
    var onCopyFilename: (SearchResult) -> Void
    var onCopyPath: (SearchResult) -> Void
    var isIgnored: (String) -> Bool
    var downloadStatus: (SearchResult) -> Transfer.TransferStatus?
    var folderRequestState: (SearchResult) -> AppState.FolderRequestState?

    /// In-flight (not completed / cancelled / failed) — matches `SearchResultRow.isQueued`.
    func isQueued(_ result: SearchResult) -> Bool {
        guard let status = downloadStatus(result) else { return false }
        return status != .completed && status != .cancelled && status != .failed
    }

    func menuItems(for listItem: SearchListItem) -> [SearchResultAppKitMenuItem] {
        switch listItem {
        case .loose(let result), .child(let result):
            return SearchResultAppKitMenuBuilder.items(
                for: result,
                isIgnored: isIgnored(result.username),
                isQueued: isQueued(result)
            )
        case .header(let group):
            return SearchResultAppKitMenuBuilder.items(
                for: group,
                isIgnored: isIgnored(group.username)
            )
        case .groupEnd:
            return []
        }
    }

    func makeMenu(for listItem: SearchListItem, target: AnyObject, action: Selector) -> NSMenu? {
        let items = menuItems(for: listItem)
        guard !items.isEmpty else { return nil }

        let ignored: Bool = {
            switch listItem {
            case .loose(let result), .child(let result):
                return isIgnored(result.username)
            case .header(let group):
                return isIgnored(group.username)
            case .groupEnd:
                return false
            }
        }()

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, item) in items.enumerated() {
            if case .separator = item {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(
                title: item.title,
                action: action,
                keyEquivalent: ""
            )
            menuItem.target = target
            menuItem.tag = index
            menuItem.isEnabled = item.isEnabled(isIgnored: ignored)
            if let systemImage = item.systemImage,
               let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
                menuItem.image = image
            }
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }
        return menu
    }

    func perform(_ item: SearchResultAppKitMenuItem, for listItem: SearchListItem) {
        switch listItem {
        case .loose(let result), .child(let result):
            perform(item, result: result)
        case .header(let group):
            guard let representative = group.results.first else { return }
            perform(item, result: representative)
        case .groupEnd:
            break
        }
    }

    private func perform(_ item: SearchResultAppKitMenuItem, result: SearchResult) {
        switch item {
        case .download:
            onDownload(result)
        case .downloadFolder:
            onDownloadFolder(result)
        case .browseFolder:
            onBrowseFolder(result)
        case .browseUser:
            onBrowseUser(result)
        case .viewProfile:
            onViewProfile(result)
        case .ignoreUser, .unignoreUser:
            onToggleIgnore(result)
        case .copyFilename:
            onCopyFilename(result)
        case .copyPath:
            onCopyPath(result)
        case .separator:
            break
        }
    }
}
