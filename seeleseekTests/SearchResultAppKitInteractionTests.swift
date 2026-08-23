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
        let header = makeHeader(group: group, isExpanded: true, onDownloadFolder: { folderResult = $0 })
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

    @Test("Header row activate expands and does not download the folder")
    func headerRowActivateExpandsOnly() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result(), result("alice", "music\\Album\\02.flac")]
        )
        var expanded = false
        var downloaded: SearchResult?
        let header = makeHeader(
            group: group,
            isExpanded: false,
            onRowActivate: { expanded = true },
            onDownloadFolder: { downloaded = $0 }
        )
        header.performRowActivateForTesting()

        #expect(expanded)
        #expect(downloaded == nil)
    }

    @Test("Table click on a header row is a no-op so cell+table cannot double-toggle")
    func tableClickIgnoresHeaders() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result()]
        )
        var expanded: SearchResultGroup?
        let coordinator = makeCoordinator(
            items: [.header(group)],
            onToggleExpansion: { expanded = $0 }
        )

        coordinator.handleRowClick(at: 0)

        #expect(expanded == nil)
    }

    @Test("Header double click does not start a folder download")
    func headerDoubleClickDoesNotDownload() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result()]
        )
        var downloaded: SearchResult?
        let coordinator = makeCoordinator(
            items: [.header(group)],
            onDownloadFolder: { downloaded = $0 }
        )

        coordinator.handleRowDoubleClick(at: 0)

        #expect(downloaded == nil)
    }

    @Test("File-row double click still downloads the file")
    func fileDoubleClickDownloads() {
        let file = result()
        var downloaded: SearchResult?
        let coordinator = makeCoordinator(
            items: [.loose(file)],
            onDownload: { downloaded = $0 }
        )

        coordinator.handleRowDoubleClick(at: 0)

        #expect(downloaded?.filename == file.filename)
    }

    @Test("Group header download hit target stays in the trailing cluster")
    func headerDownloadHitTargetIsTrailingOnly() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result()]
        )
        let header = makeHeader(group: group, isExpanded: false)
        header.layoutSubtreeIfNeeded()

        let trailing = SearchResultAppKitLayout.trailingClusterFrame(
            in: header.bounds,
            verticalCenter: header.bounds.height / 2
        )
        let centerHit = header.hitTest(NSPoint(x: 400, y: 28))
        let trailingHit = header.hitTest(NSPoint(x: trailing.midX, y: trailing.midY))

        #expect(!(centerHit is NSButton))
        #expect(trailingHit is NSButton)
    }

    @Test("Expanded header swaps to chevron.down instead of rotating")
    func expandedChevronUsesDownSymbol() {
        SearchResultSymbolCache.warmIfNeeded()
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result(), result("alice", "music\\Album\\02.flac")]
        )
        let header = makeHeader(group: group, isExpanded: false)
        header.layoutSubtreeIfNeeded()
        #expect(header.chevronImageForTesting === SearchResultSymbolCache.chevronSmall)

        header.configure(
            model: SearchResultAppKitGroupDisplayModel.make(from: group),
            group: group,
            isExpanded: true,
            isSelectionMode: false,
            groupSelection: .none,
            folderRequestState: nil,
            onRowActivate: {},
            onDownloadFolder: { _ in }
        )
        header.layoutSubtreeIfNeeded()
        #expect(header.chevronImageForTesting === SearchResultSymbolCache.chevronSmallDown)
    }

    @Test("Clicks on the folder title hit the header cell, not the label")
    func headerTitleClickReachesCell() {
        let group = SearchResultGroup(
            username: "alice",
            folderPath: "music\\Album",
            results: [result(), result("alice", "music\\Album\\02.flac")]
        )
        let header = makeHeader(group: group, isExpanded: false)
        header.layoutSubtreeIfNeeded()

        let titleHit = header.hitTest(NSPoint(x: 120, y: 18))
        let trailing = SearchResultAppKitLayout.trailingClusterFrame(
            in: header.bounds,
            verticalCenter: header.bounds.height / 2
        )
        let downloadHit = header.hitTest(NSPoint(x: trailing.midX, y: trailing.midY))

        #expect(titleHit === header)
        #expect(!(titleHit is NSTextField))
        #expect(downloadHit is NSButton)
    }

    @Test("Expanding the last folder is not treated as a stream append")
    func expandingLastFolderDoesNotAppendInPlace() {
        let collapsed = ["header-a", "header-b"]
        let expandedLast = ["header-a", "header-b", "child-1", "child-2", "end-b"]
        #expect(!SearchResultsTableView.canAppendRowsForTesting(from: collapsed, to: expandedLast))

        let streamedLoose = ["loose-1", "loose-2"]
        let moreLoose = ["loose-1", "loose-2", "loose-3"]
        #expect(SearchResultsTableView.canAppendRowsForTesting(from: streamedLoose, to: moreLoose))
    }

    private func makeHeader(
        group: SearchResultGroup,
        isExpanded: Bool,
        onRowActivate: @escaping () -> Void = {},
        onDownloadFolder: @escaping (SearchResult) -> Void = { _ in }
    ) -> SearchResultAppKitGroupHeaderView {
        let header = SearchResultAppKitGroupHeaderView(frame: NSRect(x: 0, y: 0, width: 800, height: 56))
        header.configure(
            model: SearchResultAppKitGroupDisplayModel.make(from: group),
            group: group,
            isExpanded: isExpanded,
            isSelectionMode: false,
            groupSelection: .none,
            folderRequestState: nil,
            onRowActivate: onRowActivate,
            onDownloadFolder: onDownloadFolder
        )
        return header
    }

    private func makeCoordinator(
        items: [SearchListItem],
        onToggleExpansion: @escaping (SearchResultGroup) -> Void = { _ in },
        onDownload: @escaping (SearchResult) -> Void = { _ in },
        onDownloadFolder: @escaping (SearchResult) -> Void = { _ in }
    ) -> SearchResultsTableView.Coordinator {
        SearchResultsTableView.Coordinator(
            items: items,
            isSelectionMode: false,
            selectedIDs: [],
            downloadStatusIndex: [:],
            folderRequestStates: [:],
            isExpanded: { _ in false },
            groupSelectionState: { _ in .none },
            onToggleExpansion: onToggleExpansion,
            onToggleSelection: { _ in },
            onToggleGroupSelection: { _ in },
            actions: SearchResultAppKitActions(
                onDownload: onDownload,
                onDownloadFolder: onDownloadFolder,
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
        )
    }
}
