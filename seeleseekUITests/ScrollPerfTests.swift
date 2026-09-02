import XCTest

/// Full-fidelity scroll-performance harness for the search results list.
///
/// Launches the app with `--synth-search` (the debug driver that streams
/// synthetic results), parks the REAL cursor over the results list, and
/// scrolls with REAL wheel events — so hover tracking, cursor rects, and
/// the responsive-scrolling path are all exercised, unlike the in-process
/// `--synth-scroll` clip-view driver. Frame pacing is measured inside the
/// app (`PACE` lines, mirrored to `$SEELE_SYNTH_LOG`); this test only
/// generates load and never asserts on timing, so it stays CI-safe.
///
/// Run with (`TEST_RUNNER_` prefix required — xcodebuild forwards only
/// those env vars to the test runner, minus the prefix):
///   TEST_RUNNER_SEELE_SYNTH_LOG=/tmp/scrollperf.log xcodebuild test \
///     -scheme seeleseek \
///     -only-testing:seeleseekUITests/ScrollPerfTests
nonisolated final class ScrollPerfTests: XCTestCase {
    func testScrollWhileSearchStreams() throws {
        let app = XCUIApplication()
        // The app injects its own wheel events; XCUI's scroll(byDeltaX:) is
        // one XPC round trip per call and cannot scroll fast. This test only
        // supplies what the app cannot fake: the real cursor over the rows.
        app.launchArguments += ["--synth-search", "--synth-scroll"]
        // XCUIApplication does not inherit the runner's environment; the
        // log-path override must be forwarded explicitly or the app
        // silently falls back to its temp-directory log.
        if let logPath = ProcessInfo.processInfo.environment["SEELE_SYNTH_LOG"] {
            app.launchEnvironment["SEELE_SYNTH_LOG"] = logPath
        }
        app.launch()

        // Let the first results land so the list exists.
        sleep(4)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // Middle of the results area, clear of the header and filter bar.
        let listPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.6))

        // ~2 minutes spanning several stream/hold cycles; re-hover
        // periodically so the cursor stays parked over the moving rows.
        for _ in 0..<60 {
            listPoint.hover()
            sleep(2)
        }
    }
}
