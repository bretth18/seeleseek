import SwiftUI

/// Index math for tab traversal: menu commands wrap, arrow keys clamp.
enum TabCycler {
    static func wrappedNext(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    static func wrappedPrevious(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index - 1) % count + count) % count
    }

    static func clampedNext(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(index + 1, count - 1)
    }

    static func clampedPrevious(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(min(index, count - 1) - 1, 0)
    }
}

/// Tab actions published through the focused scene value by whichever
/// view currently owns a tab bar; the menu commands act on them.
struct TabCommands {
    var selectNext: () -> Void
    var selectPrevious: () -> Void
    /// nil when the surface's tabs cannot be closed.
    var closeCurrent: (() -> Void)?
}

extension TabCommands {
    /// Wrap-around cycling over a fixed `CaseIterable` tab enum.
    @MainActor
    static func cycling<Tab: CaseIterable & Equatable>(_ selection: Binding<Tab>) -> TabCommands {
        func move(_ step: (Int, Int) -> Int) {
            let all = Array(Tab.allCases)
            guard let index = all.firstIndex(of: selection.wrappedValue) else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selection.wrappedValue = all[step(index, all.count)]
            }
        }
        return TabCommands(
            selectNext: { move(TabCycler.wrappedNext) },
            selectPrevious: { move(TabCycler.wrappedPrevious) },
            closeCurrent: nil
        )
    }
}

extension FocusedValues {
    @Entry var tabCommands: TabCommands?
}

#if os(macOS)
/// While a closable tab exists, ⌘W closes the tab and Close Window moves
/// to ⇧⌘W (Safari convention).
struct TabNavigationCommands: Commands {
    @FocusedValue(\.tabCommands) private var tabCommands

    var body: some Commands {
        CommandGroup(before: .windowArrangement) {
            Button("Show Next Tab") {
                tabCommands?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(tabCommands == nil)

            Button("Show Previous Tab") {
                tabCommands?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(tabCommands == nil)

            Divider()
        }

        CommandGroup(replacing: .saveItem) {
            if let closeTab = tabCommands?.closeCurrent {
                Button("Close Tab") {
                    closeTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            } else {
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
#endif
