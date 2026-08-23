import AppKit
import SeeleseekCore
import SwiftUI

/// AppKit search results list for flat and grouped paths via `displayItems`.
struct SearchResultsTableView: NSViewRepresentable {
    let items: [SearchListItem]
    var isSelectionMode: Bool
    var selectedIDs: Set<UUID>
    var bottomInset: CGFloat
    /// Observed so status-driven download chrome refreshes after queueing.
    var downloadStatusIndex: [String: Transfer.TransferStatus]
    var folderRequestStates: [AppState.FolderRequest: AppState.FolderRequestState]
    var isExpanded: (SearchResultGroup) -> Bool
    var groupSelectionState: (SearchResultGroup) -> SearchState.GroupSelection
    var onToggleExpansion: (SearchResultGroup) -> Void
    var onToggleSelection: (UUID) -> Void
    var onToggleGroupSelection: (SearchResultGroup) -> Void
    var actions: SearchResultAppKitActions

    private static let rowHeight = SearchResultAppKitLayout.rowHeight
    private static let groupEndHeight = SearchResultAppKitLayout.groupEndHeight

    func makeCoordinator() -> Coordinator {
        Coordinator(
            items: items,
            isSelectionMode: isSelectionMode,
            selectedIDs: selectedIDs,
            downloadStatusIndex: downloadStatusIndex,
            folderRequestStates: folderRequestStates,
            isExpanded: isExpanded,
            groupSelectionState: groupSelectionState,
            onToggleExpansion: onToggleExpansion,
            onToggleSelection: onToggleSelection,
            onToggleGroupSelection: onToggleGroupSelection,
            actions: actions
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        SearchResultSymbolCache.warmIfNeeded()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        let table = SearchResultsNSTableView()
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.style = .plain
        table.gridStyleMask = []
        table.target = context.coordinator
        table.action = #selector(Coordinator.tableClick(_:))
        table.doubleAction = #selector(Coordinator.tableDoubleClick(_:))
        table.menuProvider = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("searchResult"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        column.minWidth = 200
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scrollView.documentView = table
        context.coordinator.tableView = table

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isSelectionMode = isSelectionMode
        coordinator.selectedIDs = selectedIDs
        coordinator.isExpanded = isExpanded
        coordinator.groupSelectionState = groupSelectionState
        coordinator.onToggleExpansion = onToggleExpansion
        coordinator.onToggleSelection = onToggleSelection
        coordinator.onToggleGroupSelection = onToggleGroupSelection
        coordinator.actions = actions

        let statusChromeChanged =
            coordinator.downloadStatusIndex != downloadStatusIndex
            || coordinator.folderRequestStates != folderRequestStates
        coordinator.downloadStatusIndex = downloadStatusIndex
        coordinator.folderRequestStates = folderRequestStates

        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        guard let table = coordinator.tableView else { return }
        coordinator.syncColumnWidth()

        let oldIDs = coordinator.itemIDs
        let newIDs = items.map(\.id)
        let newItems = items

        if Self.canAppendRows(from: oldIDs, to: newIDs) {
            coordinator.items = newItems
            let start = oldIDs.count
            table.beginUpdates()
            table.insertRows(at: IndexSet(start..<newIDs.count), withAnimation: [])
            table.endUpdates()
            if statusChromeChanged {
                coordinator.reloadActionChrome(in: table)
            }
            return
        }

        if oldIDs != newIDs {
            coordinator.items = newItems
            coordinator.rowDisplayCache.removeAll(keepingCapacity: true)
            table.reloadData()
            coordinator.lastSelectionMode = isSelectionMode
            coordinator.lastSelectedIDs = selectedIDs
            return
        }

        coordinator.items = newItems

        if coordinator.lastSelectionMode != isSelectionMode {
            coordinator.lastSelectionMode = isSelectionMode
            table.reloadData()
            return
        }

        let selectionDelta = coordinator.lastSelectedIDs.symmetricDifference(selectedIDs)
        if !selectionDelta.isEmpty {
            coordinator.lastSelectedIDs = selectedIDs
            let rows = rowsAffectedBySelectionChange(in: newItems, changedIDs: selectionDelta)
            if !rows.isEmpty {
                table.reloadData(forRowIndexes: IndexSet(rows), columnIndexes: IndexSet(integer: 0))
            }
            if statusChromeChanged {
                coordinator.reloadActionChrome(in: table)
            }
            return
        }

        if statusChromeChanged {
            coordinator.reloadActionChrome(in: table)
            return
        }

        // Same ids — refresh headers whose aggregate metadata may have changed.
        let headerRows = newItems.enumerated().compactMap { index, item -> Int? in
            guard case .header = item else { return nil }
            return index
        }
        if !headerRows.isEmpty {
            table.reloadData(forRowIndexes: IndexSet(headerRows), columnIndexes: IndexSet(integer: 0))
        }
    }

    private func rowsAffectedBySelectionChange(in items: [SearchListItem], changedIDs: Set<UUID>) -> [Int] {
        var rows: [Int] = []
        for (index, item) in items.enumerated() {
            switch item {
            case .loose(let result), .child(let result):
                if changedIDs.contains(result.id) { rows.append(index) }
            case .header(let group):
                if group.results.contains(where: { changedIDs.contains($0.id) }) {
                    rows.append(index)
                }
            case .groupEnd:
                break
            }
        }
        return rows
    }

    private static func canAppendRows(from old: [String], to new: [String]) -> Bool {
        guard new.count > old.count, !old.isEmpty else { return false }
        guard zip(old, new.prefix(old.count)).allSatisfy({ $0 == $1 }) else { return false }
        // Expanding the last folder appends `child-` / `end-` ids. Treating that
        // as a stream-append would skip reloading the header, leaving the
        // chevron stuck. Only true loose-result streaming may append in place.
        let appended = new[old.count...]
        return appended.allSatisfy { $0.hasPrefix("loose-") }
    }

    /// Test seam for the append heuristic.
    static func canAppendRowsForTesting(from old: [String], to new: [String]) -> Bool {
        canAppendRows(from: old, to: new)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, SearchResultsTableMenuProviding {
        var items: [SearchListItem]
        var isSelectionMode: Bool
        var selectedIDs: Set<UUID>
        var lastSelectedIDs: Set<UUID>
        var lastSelectionMode: Bool
        var downloadStatusIndex: [String: Transfer.TransferStatus]
        var folderRequestStates: [AppState.FolderRequest: AppState.FolderRequestState]
        var isExpanded: (SearchResultGroup) -> Bool
        var groupSelectionState: (SearchResultGroup) -> SearchState.GroupSelection
        var onToggleExpansion: (SearchResultGroup) -> Void
        var onToggleSelection: (UUID) -> Void
        var onToggleGroupSelection: (SearchResultGroup) -> Void
        var actions: SearchResultAppKitActions
        weak var tableView: NSTableView?
        var rowDisplayCache: [UUID: SearchResultAppKitDisplayModel] = [:]
        /// Set when a cell download button fires so the table click does not
        /// also toggle selection / expansion for the same mouse-up.
        private var suppressNextTableClick = false
        private var menuListItem: SearchListItem?

        var itemIDs: [String] { items.map(\.id) }

        func syncColumnWidth() {
            guard let tableView, let column = tableView.tableColumns.first else { return }
            let width = tableView.bounds.width
            guard width > 0, abs(column.width - width) > 0.5 else { return }
            column.width = width
        }

        func reloadActionChrome(in tableView: NSTableView) {
            let rows = IndexSet(
                items.enumerated().compactMap { index, item -> Int? in
                    switch item {
                    case .loose, .child, .header: return index
                    case .groupEnd: return nil
                    }
                }
            )
            guard !rows.isEmpty else { return }
            tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        }

        init(
            items: [SearchListItem],
            isSelectionMode: Bool,
            selectedIDs: Set<UUID>,
            downloadStatusIndex: [String: Transfer.TransferStatus],
            folderRequestStates: [AppState.FolderRequest: AppState.FolderRequestState],
            isExpanded: @escaping (SearchResultGroup) -> Bool,
            groupSelectionState: @escaping (SearchResultGroup) -> SearchState.GroupSelection,
            onToggleExpansion: @escaping (SearchResultGroup) -> Void,
            onToggleSelection: @escaping (UUID) -> Void,
            onToggleGroupSelection: @escaping (SearchResultGroup) -> Void,
            actions: SearchResultAppKitActions
        ) {
            self.items = items
            self.isSelectionMode = isSelectionMode
            self.selectedIDs = selectedIDs
            self.lastSelectedIDs = selectedIDs
            self.lastSelectionMode = isSelectionMode
            self.downloadStatusIndex = downloadStatusIndex
            self.folderRequestStates = folderRequestStates
            self.isExpanded = isExpanded
            self.groupSelectionState = groupSelectionState
            self.onToggleExpansion = onToggleExpansion
            self.onToggleSelection = onToggleSelection
            self.onToggleGroupSelection = onToggleGroupSelection
            self.actions = actions
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            switch items[row] {
            case .groupEnd:
                return SearchResultsTableView.groupEndHeight
            default:
                return SearchResultsTableView.rowHeight
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch items[row] {
            case .loose(let result):
                return resultRow(for: result, nested: false, in: tableView)
            case .child(let result):
                return resultRow(for: result, nested: true, in: tableView)
            case .header(let group):
                return groupHeader(for: group, in: tableView)
            case .groupEnd:
                return groupEnd(in: tableView)
            }
        }

        private func resultRow(for result: SearchResult, nested: Bool, in tableView: NSTableView) -> NSView {
            let id = SearchResultAppKitRowView.cellIdentifier
            let cell: SearchResultAppKitRowView
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? SearchResultAppKitRowView {
                cell = reused
            } else {
                cell = SearchResultAppKitRowView(frame: .zero)
                cell.identifier = id
            }
            let model = rowDisplayModel(for: result)
            cell.configure(
                model: model,
                result: result,
                isSelectionMode: isSelectionMode,
                isSelected: selectedIDs.contains(result.id),
                isNested: nested,
                downloadStatus: actions.downloadStatus(result),
                isIgnored: actions.isIgnored(result.username),
                onDownload: { [weak self] result in
                    self?.suppressNextTableClick = true
                    self?.actions.onDownload(result)
                }
            )
            return cell
        }

        private func groupHeader(for group: SearchResultGroup, in tableView: NSTableView) -> NSView {
            let id = SearchResultAppKitGroupHeaderView.cellIdentifier
            let cell: SearchResultAppKitGroupHeaderView
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? SearchResultAppKitGroupHeaderView {
                cell = reused
            } else {
                cell = SearchResultAppKitGroupHeaderView(frame: .zero)
                cell.identifier = id
            }
            let model = groupDisplayModel(for: group)
            let representative = group.results.first
            cell.configure(
                model: model,
                group: group,
                isExpanded: isExpanded(group),
                isSelectionMode: isSelectionMode,
                groupSelection: groupSelectionState(group),
                folderRequestState: representative.flatMap { actions.folderRequestState($0) },
                onRowActivate: { [weak self] in
                    // Cell owns the click so labels cannot swallow it. Suppress
                    // the table `action` or we expand then immediately collapse.
                    self?.suppressNextTableClick = true
                    guard let self else { return }
                    if self.isSelectionMode {
                        self.onToggleGroupSelection(group)
                    } else {
                        self.onToggleExpansion(group)
                    }
                },
                onDownloadFolder: { [weak self] result in
                    self?.suppressNextTableClick = true
                    self?.actions.onDownloadFolder(result)
                }
            )
            return cell
        }

        private func groupEnd(in tableView: NSTableView) -> NSView {
            let id = SearchResultAppKitGroupEndView.cellIdentifier
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? SearchResultAppKitGroupEndView {
                return reused
            }
            let cell = SearchResultAppKitGroupEndView(frame: .zero)
            cell.identifier = id
            return cell
        }

        private func rowDisplayModel(for result: SearchResult) -> SearchResultAppKitDisplayModel {
            if let cached = rowDisplayCache[result.id] {
                return cached
            }
            let model = SearchResultAppKitDisplayModel.make(from: result)
            rowDisplayCache[result.id] = model
            return model
        }

        private func groupDisplayModel(for group: SearchResultGroup) -> SearchResultAppKitGroupDisplayModel {
            // Headers are few and their aggregates change as results stream in.
            SearchResultAppKitGroupDisplayModel.make(from: group)
        }

        func menu(forRow row: Int) -> NSMenu? {
            guard items.indices.contains(row) else { return nil }
            let listItem = items[row]
            menuListItem = listItem
            return actions.makeMenu(
                for: listItem,
                target: self,
                action: #selector(contextMenuItemClicked(_:))
            )
        }

        @objc func contextMenuItemClicked(_ sender: NSMenuItem) {
            guard let listItem = menuListItem,
                  let item = sender.representedObject as? SearchResultAppKitMenuItem else {
                return
            }
            actions.perform(item, for: listItem)
        }

        @objc func tableClick(_ sender: NSTableView) {
            if suppressNextTableClick {
                suppressNextTableClick = false
                return
            }
            handleRowClick(at: sender.clickedRow)
        }

        @objc func tableDoubleClick(_ sender: NSTableView) {
            handleRowDoubleClick(at: sender.clickedRow)
        }

        /// Single-click routing for file rows. Headers activate via the cell's
        /// own `mouseDown` so we never double-toggle against the table action.
        func handleRowClick(at row: Int) {
            guard items.indices.contains(row) else { return }

            switch items[row] {
            case .loose(let result), .child(let result):
                if isSelectionMode {
                    onToggleSelection(result.id)
                }
            case .header, .groupEnd:
                break
            }
        }

        /// Double-click downloads a file row. Headers deliberately do nothing —
        /// a Finder-style double-click would otherwise expand then queue a
        /// whole-folder download on the second click.
        func handleRowDoubleClick(at row: Int) {
            guard items.indices.contains(row), !isSelectionMode else { return }

            switch items[row] {
            case .loose(let result), .child(let result):
                actions.onDownload(result)
            case .header, .groupEnd:
                break
            }
        }
    }
}

/// Supplies a per-row context menu; `NSTableView.menu` alone cannot vary by row.
protocol SearchResultsTableMenuProviding: AnyObject {
    func menu(forRow row: Int) -> NSMenu?
}

private final class SearchResultsNSTableView: NSTableView {
    weak var menuProvider: SearchResultsTableMenuProviding?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        // Highlight the right-clicked row so the menu target is visible.
        if selectedRowIndexes != IndexSet(integer: row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuProvider?.menu(forRow: row)
    }
}
