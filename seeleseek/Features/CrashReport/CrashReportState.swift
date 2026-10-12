import Foundation
import os
#if os(macOS)
import AppKit
#endif

@Observable
final class CrashReportState {
    private let logger = Logger(subsystem: "com.seeleseek", category: "CrashReport")

    private nonisolated static let offerKey = "crashReportOfferOnLaunch"
    private nonisolated static let lastSeenKey = "crashReportLastSeenDate"
    
    private nonisolated static let firstRunLookback: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let directory: URL
    private let processName: String

    var pendingReport: CrashReport?
    var showPrompt = false

    var offerOnLaunch: Bool {
        didSet { defaults.set(offerOnLaunch, forKey: Self.offerKey) }
    }

    init(
        defaults: UserDefaults = .standard,
        directory: URL = CrashReport.defaultDirectory,
        processName: String = ProcessInfo.processInfo.processName
    ) {
        self.defaults = defaults
        self.directory = directory
        self.processName = processName
        offerOnLaunch = defaults.object(forKey: Self.offerKey) as? Bool ?? true
    }

    func checkOnLaunch(now: Date = .now) async {
        let lastSeen = defaults.object(forKey: Self.lastSeenKey) as? Date
        
        defaults.set(now, forKey: Self.lastSeenKey)
        guard offerOnLaunch else { return }

        let since = lastSeen ?? now.addingTimeInterval(-Self.firstRunLookback)
        let directory = directory, processName = processName
        let report = await Task.detached(priority: .utility) {
            CrashReport.newest(in: directory, processName: processName, since: since)
        }.value
        guard let report else { return }

        logger.info("Found crash report \(report.fileURL.lastPathComponent, privacy: .public)")
        pendingReport = report
        showPrompt = true
    }

    #if os(macOS)
    func reportOnGitHub() {
        guard let report = pendingReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.fullText, forType: .string)
        NSWorkspace.shared.open(report.issueURL)
        pendingReport = nil
    }

    func revealInFinder() {
        guard let report = pendingReport else { return }
        NSWorkspace.shared.activateFileViewerSelecting([report.fileURL])
        pendingReport = nil
    }
    #endif

    func dismiss() {
        pendingReport = nil
    }
}
