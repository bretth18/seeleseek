import Foundation
import os
import AppKit

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

    var showPrompt: Bool {
        get { pendingReport != nil }
        set { if !newValue { pendingReport = nil } }
    }

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
    }

    func reportOnGitHub(_ report: CrashReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.fullText, forType: .string)
        NSWorkspace.shared.open(report.issueURL)
    }

    func revealInFinder(_ report: CrashReport) {
        NSWorkspace.shared.activateFileViewerSelecting([report.fileURL])
    }
}
