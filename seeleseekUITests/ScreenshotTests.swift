import XCTest

/// Captures marketing screenshots of the main app surfaces.
///
/// Run with:
///   xcodebuild test -project seeleseek.xcodeproj \
///     -scheme seeleseek \
///     -only-testing:seeleseekUITests/ScreenshotTests \
///     -destination 'platform=macOS'
///
/// PNGs are written to `$SCREENSHOTS_DIR` (env var) if set,
/// otherwise to `<repo>/screenshots/`. They are also attached to
/// the test result for inspection in Xcode's Report Navigator.
nonisolated final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        outputDirectory = Self.resolveOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        print("📸 Screenshots will be written to: \(outputDirectory.path)")

        app = XCUIApplication()
        app.launchArguments += ["--screenshots"]
        app.launch()

        // Give SwiftUI a beat to render the seeded data on first appearance.
        sleep(1)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Tests

    func test_captureAllScreenshots() throws {
        // Each tuple: (file name, Cmd+N shortcut from app's Navigate menu)
        let screens: [(String, String)] = [
            ("01-search",     "1"),
            ("02-wishlists",  "2"),
            ("03-transfers",  "3"),
            ("04-chat",       "6"),
            ("05-browse",     "4"),
            ("06-friends",    "5"),
            ("07-statistics", "7"),
            ("08-settings",   "9")
        ]
        for (name, key) in screens {
            try captureScreen(named: name, shortcut: key)
        }
    }

    // MARK: - Helpers

    private func captureScreen(named name: String, shortcut key: String) throws {
        navigate(shortcut: key)
        // Allow transitions / list rendering to settle.
        usleep(750_000)

        let window = app.windows.firstMatch
        let screenshot = window.exists ? window.screenshot() : app.screenshot()

        // Attach to the test report for Xcode UI inspection.
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Also write to disk so marketing can consume the PNGs directly.
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
    }

    private func navigate(shortcut key: String) {
        // Use the app's Navigate menu Cmd+N shortcuts (defined in seeleseekApp.swift).
        app.typeKey(key, modifierFlags: .command)
    }

    // MARK: - Output directory resolution

    /// Resolution order:
    /// 1. `SCREENSHOTS_DIR` env var (set via xcodebuild `-testPlan` env or scheme).
    /// 2. `<repo>/screenshots/` derived from the test source file's compile-time path.
    ///    (Works only when the user has granted the UI test runner Files-and-Folders
    ///    access to the repo — macOS 14+ otherwise blocks writes here with EPERM.)
    /// 3. Fallback: a writable subdirectory inside `NSTemporaryDirectory()`.
    private static func resolveOutputDirectory(file: StaticString = #filePath) -> URL {
        let env = ProcessInfo.processInfo.environment

        if let override = env["SCREENSHOTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        let thisFile = URL(fileURLWithPath: "\(file)")
        let repoRoot = thisFile
            .deletingLastPathComponent()  // seeleseekUITests/
            .deletingLastPathComponent()  // <repo>/
        let inRepo = repoRoot.appendingPathComponent("screenshots")

        // Probe whether the runner can write to the repo path.
        let fm = FileManager.default
        if (try? fm.createDirectory(at: inRepo, withIntermediateDirectories: true)) != nil {
            return inRepo
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seeleseek-screenshots")
    }
}
