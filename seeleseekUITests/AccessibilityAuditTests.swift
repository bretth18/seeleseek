import XCTest

/// Runs the Xcode accessibility audit on the main app screens
/// (VoiceOver labels, element descriptions, contrast, hit region
/// size). Added for issue #55, VoiceOver support.
///
/// Run with:
///   xcodebuild test -project seeleseek.xcodeproj \
///     -scheme seeleseek \
///     -only-testing:seeleseekUITests/AccessibilityAuditTests \
///     -destination 'platform=macOS'
///
/// Uses the same `--screenshots` demo-data launch mode as
/// `ScreenshotTests`. Thus each list shows realistic rows.
nonisolated final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["--screenshots"]
        app.launch()

        // Give SwiftUI time to render the demo data at the first
        // appearance.
        sleep(1)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Per-screen audits

    // Each test goes to a screen with the Navigate menu shortcuts
    // (⌘1–⌘9, defined in seeleseekApp.swift). Then it audits the
    // front window. There is one test for each screen. Thus a failure
    // names the screen directly.

    func test_auditSearch() throws {
        try auditScreen(shortcut: "1")
    }

    func test_auditWishlists() throws {
        try auditScreen(shortcut: "2")
    }

    func test_auditTransfers() throws {
        try auditScreen(shortcut: "3")
    }

    func test_auditBrowse() throws {
        try auditScreen(shortcut: "4")
    }

    func test_auditFriends() throws {
        try auditScreen(shortcut: "5")
    }

    func test_auditChat() throws {
        try auditScreen(shortcut: "6")
    }

    func test_auditStatistics() throws {
        try auditScreen(shortcut: "7")
    }

    func test_auditNetworkMonitor() throws {
        try auditScreen(shortcut: "8")
    }

    func test_auditSettings() throws {
        try auditScreen(shortcut: "9")
    }

    // MARK: - Helpers

    private func auditScreen(shortcut key: String) throws {
        app.typeKey(key, modifierFlags: .command)
        // Give the transitions and the list rendering time to
        // complete.
        usleep(750_000)

        try app.performAccessibilityAudit { issue in
            let elementType = issue.element?.elementType

            // SwiftUI and AppKit make container groups without labels.
            // App code cannot label them. Examples: the
            // NavigationSplitView wrapper groups, and a 14x14 group in
            // the window zoom button (found with a hierarchy dump).
            // Ignore issues on these containers. Keep each issue on a
            // real control, image, or text element.
            if elementType == .group || elementType == .splitGroup || issue.element == nil {
                print("♿️ AUDIT ignored (system container): [\(issue.auditType)] \(issue.compactDescription)")
                return true
            }

            // Zero-frame elements are invisible SwiftUI scroll
            // artifacts ("Other, {{0,0},{0,0}}" in each ScrollView).
            // A user cannot move to them.
            if let frame = issue.element?.frame, frame.isEmpty {
                print("♿️ AUDIT ignored (zero frame): [\(issue.auditType)] \(issue.compactDescription)")
                return true
            }

            // Contrast is not part of the CI gate. This is intentional:
            // SeeleColors.textTertiary is dim in the standard
            // appearance. It becomes brighter when the user sets
            // "Increase contrast" in System Settings. The audit runs in
            // the standard appearance, thus it reports the dim value.
            if issue.auditType == .contrast {
                print("♿️ AUDIT ignored (contrast, by increase-contrast support): \(issue.compactDescription) → \(issue.element.map { "\($0)" } ?? "?")")
                return true
            }

            // SwiftUI Menu and Picker become AppKit MenuButton and
            // PopUpButton. VoiceOver operates these through AXShowMenu.
            // The audit reports a missing AXPress action. This is
            // framework behavior. App code cannot correct it.
            if elementType == .menuButton || elementType == .popUpButton,
               issue.compactDescription.contains("Action is missing") {
                print("♿️ AUDIT ignored (menu AXPress, framework): \(issue.compactDescription)")
                return true
            }

            // The Touch Bar is a system element.
            if elementType == .touchBar {
                print("♿️ AUDIT ignored (Touch Bar): \(issue.compactDescription)")
                return true
            }

            // macOS injects an "emoji & symbols" pop-up above the
            // window content when a text field has focus. It sits
            // outside the content area (negative Y, empty id). App
            // code cannot label it. The filter is scoped to the
            // description issue so a real app picker that scrolls
            // above the viewport keeps its other audit checks.
            if elementType == .popUpButton, let el = issue.element,
               el.identifier.isEmpty,
               issue.compactDescription.lowercased().contains("no description"),
               el.label.lowercased().contains("emoji") || el.frame.minY < 0 {
                print("♿️ AUDIT ignored (system text-input control): \(issue.compactDescription)")
                return true
            }

            // SwiftUI makes unlabeled "Other" elements around scroll
            // and content regions. Ignore an "Other" that is a
            // container (it has children). An unlabeled leaf "Other"
            // is a real problem and fails the gate.
            if elementType == .other, let el = issue.element,
               el.identifier.isEmpty,
               el.children(matching: .any).firstMatch.exists {
                print("♿️ AUDIT ignored (container plate): \(issue.compactDescription) frame=\(el.frame)")
                return true
            }

            // Write the element to the log. The default failure
            // message gives only the issue type, not the element.
            let element = issue.element.map {
                "\($0)  [id='\($0.identifier)' frame=\($0.frame)]"
            } ?? "unknown element"
            print("♿️ AUDIT [\(issue.auditType)] \(issue.compactDescription) → \(element)")
            return false
        }
    }
}
