import AppKit
import Testing
@testable import seeleseek
@testable import SeeleseekCore

@Suite("AppKit search result interactions")
@MainActor
struct SearchResultAppKitInteractionTests {

    private func result(_ user: String = "alice", _ path: String = "music\\Album\\01.flac") -> SearchResult {
        SearchResult(
            username: user,
            filename: path,
            size: 1_000,
            freeSlots: true,
            uploadSpeed: 100_000
        )
    }

    @Test("Result context menu includes download and download-entire-folder")
    func resultMenuHasDownloadActions() {
        let items = SearchResultAppKitMenuBuilder.items(
            for: result(),
            isIgnored: false,
            isQueued: false
        )
        let titles = items.map(\.title)
        #expect(titles.contains("Download"))
        #expect(titles.contains("Download entire folder"))
        #expect(titles.contains("Browse folder"))
        #expect(titles.contains("Copy filename"))
    }

    @Test("Queued download menu item is disabled and labeled Downloading…")
    func queuedDownloadDisabled() {
        let items = SearchResultAppKitMenuBuilder.items(
            for: result(),
            isIgnored: false,
            isQueued: true
        )
        guard case .download(let isQueued) = items.first else {
            Issue.record("Expected download as first menu item")
            return
        }
        #expect(isQueued)
        #expect(items[0].title == "Downloading…")
        #expect(!items[0].isEnabled(isIgnored: false))
    }

    @Test("Ignored user disables download actions without renaming them")
    func ignoredDisablesDownloads() {
        let items = SearchResultAppKitMenuBuilder.items(
            for: result(),
            isIgnored: true,
            isQueued: false
        )
        #expect(items[0].title == "Download")
        #expect(!items[0].isEnabled(isIgnored: true))
        #expect(!items[1].isEnabled(isIgnored: true))
        #expect(items.contains(.unignoreUser))
    }

    @Test("Group header menu offers download entire folder")
    func groupMenuHasFolderDownload() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result()]
        )
        let titles = SearchResultAppKitMenuBuilder.items(for: group, isIgnored: false).map(\.title)
        #expect(titles.contains("Download entire folder"))
        #expect(titles.contains("Browse alice"))
    }

    @Test("Download button action invokes onDownload for a result row")
    func downloadButtonFiresCallback() {
        var downloaded: SearchResult?
        let row = SearchResultAppKitRowView(frame: NSRect(x: 0, y: 0, width: 800, height: 56))
        let model = SearchResultAppKitDisplayModel.make(from: result())
        row.configure(
            model: model,
            result: result(),
            isSelectionMode: false,
            isSelected: false,
            isNested: false,
            downloadStatus: nil,
            isIgnored: false,
            onDownload: { downloaded = $0 }
        )
        row.performDownloadForTesting()

        #expect(downloaded?.filename == "music\\Album\\01.flac")
    }

    @Test("Queued download appearance disables the button and uses the filled glyph")
    func queuedAppearance() {
        let appearance = SearchResultAppKitDownloadAppearance.make(status: .queued, isIgnored: false)
        #expect(!appearance.isEnabled)
        #expect(appearance.toolTip == "In queue")
        #expect(appearance.image === SearchResultSymbolCache.downloadFilled)
    }

    @Test("Completed download appearance shows checkmark and stays disabled")
    func completedAppearance() {
        let appearance = SearchResultAppKitDownloadAppearance.make(status: .completed, isIgnored: false)
        #expect(!appearance.isEnabled)
        #expect(appearance.toolTip == "Already downloaded")
        #expect(appearance.image === SearchResultSymbolCache.downloadComplete)
    }

    @Test("Failed download appearance offers retry")
    func failedAppearance() {
        let appearance = SearchResultAppKitDownloadAppearance.make(status: .failed, isIgnored: false)
        #expect(appearance.isEnabled)
        #expect(appearance.toolTip == "Retry download")
        #expect(appearance.image === SearchResultSymbolCache.downloadRetry)
    }

    @Test("Group header download button invokes onDownloadFolder")
    func groupDownloadButtonFiresCallback() {
        var folderResult: SearchResult?
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result()]
        )
        let header = SearchResultAppKitGroupHeaderView(frame: NSRect(x: 0, y: 0, width: 800, height: 56))
        let model = SearchResultAppKitGroupDisplayModel.make(from: group)
        header.configure(
            model: model,
            group: group,
            isExpanded: true,
            isSelectionMode: false,
            groupSelection: .none,
            folderRequestState: nil,
            onDownloadFolder: { folderResult = $0 }
        )
        header.performDownloadForTesting()

        #expect(folderResult?.username == "alice")
        #expect(folderResult?.filename == "music\\Album\\01.flac")
    }

    @Test("Actions.perform routes download-entire-folder for a result row")
    func performRoutesFolderDownload() {
        var folder: SearchResult?
        let actions = SearchResultAppKitActions(
            onDownload: { _ in },
            onDownloadFolder: { folder = $0 },
            onBrowseFolder: { _ in },
            onBrowseUser: { _ in },
            onViewProfile: { _ in },
            onToggleIgnore: { _ in },
            onCopyFilename: { _ in },
            onCopyPath: { _ in },
            isIgnored: { _ in false },
            downloadStatus: { _ in nil },
            folderRequestState: { _ in nil }
        )
        let item = SearchListItem.loose(result())
        actions.perform(.downloadFolder, for: item)
        #expect(folder?.filename == "music\\Album\\01.flac")
    }
}
