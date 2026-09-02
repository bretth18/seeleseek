import SwiftUI
import AppKit
import SeeleseekCore

/// NSTableView we own (fixed row height, cell reuse, no SwiftUI delegate
/// measurement) whose cells host the real SwiftUI rows. The table only
/// scrolls and recycles; every row is still `SearchResultListItemView`.
struct SearchResultsHostedTableView: NSViewRepresentable {
    @Environment(\.appState) private var appState
    let items: [SearchListItem]
    let bottomInset: CGFloat

    static let rowHeight = SearchResultRowLayout.rowHeight + SeeleSpacing.dividerSpacing
    static let groupEndHeight: CGFloat = 9

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.style = .plain
        table.gridStyleMask = []
        let column = NSTableColumn(identifier: .init("row"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scrollView.documentView = table
        context.coordinator.table = table

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.appState = appState
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        context.coordinator.apply(items)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var appState: AppState
        weak var table: NSTableView?
        private(set) var items: [SearchListItem] = []
        private var ids: [String] = []

        init(appState: AppState) { self.appState = appState }

        func apply(_ newItems: [SearchListItem]) {
            guard let table else { items = newItems; return }
            let newIDs = newItems.map(\.id)
            if newIDs == ids { items = newItems; return }
            if newIDs.count > ids.count, Array(newIDs.prefix(ids.count)) == ids {
                items = newItems
                table.insertRows(at: IndexSet(ids.count..<newIDs.count), withAnimation: [])
                ids = newIDs
                return
            }
            items = newItems
            ids = newIDs
            table.reloadData()
        }

        @objc func boundsChanged() {
            appState.searchState.noteResultsScrollActivity()
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if case .groupEnd = items[row] { return SearchResultsHostedTableView.groupEndHeight }
            return SearchResultsHostedTableView.rowHeight
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("hosted")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? HostedRowCell) ?? {
                let c = HostedRowCell()
                c.identifier = id
                return c
            }()
            cell.configure(AnyView(
                SearchResultListItemView(item: items[row])
                    .environment(\.appState, appState)
            ))
            return cell
        }
    }
}

final class HostedRowCell: NSTableCellView {
    private var host: NSHostingView<AnyView>?

    func configure(_ view: AnyView) {
        if let host {
            host.rootView = view
            return
        }
        let h = NSHostingView(rootView: view)
        h.sizingOptions = []
        h.frame = bounds
        h.autoresizingMask = [.width, .height]
        addSubview(h)
        host = h
    }
}
