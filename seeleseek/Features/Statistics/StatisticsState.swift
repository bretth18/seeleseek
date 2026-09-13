import SwiftUI
import SeeleseekCore

@Observable
@MainActor
final class StatisticsState: StatisticsRecording {
    // MARK: - Network Statistics
    var totalDownloaded: UInt64 = 0
    var totalUploaded: UInt64 = 0
    var sessionDownloaded: UInt64 = 0
    var sessionUploaded: UInt64 = 0

    // MARK: - Transfer History
    var downloadHistory: [TransferHistoryEntry] = []
    var uploadHistory: [TransferHistoryEntry] = []

    // MARK: - File Statistics
    var filesDownloaded: Int = 0
    var filesUploaded: Int = 0
    var uniqueUsersDownloadedFrom: Set<String> = []
    var uniqueUsersUploadedTo: Set<String> = []

    // MARK: - Session Info
    var sessionStartTime: Date = Date()

    // MARK: - Types

    struct TransferHistoryEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let filename: String
        let username: String
        let size: UInt64
        let duration: TimeInterval
        let averageSpeed: Double
        let isDownload: Bool
    }

    // MARK: - Computed Properties

    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }

    var formattedSessionDuration: String {
        let hours = Int(sessionDuration) / 3600
        let minutes = (Int(sessionDuration) % 3600) / 60
        let seconds = Int(sessionDuration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Actions

    func recordTransfer(filename: String, username: String, size: UInt64, duration: TimeInterval, isDownload: Bool) {
        let entry = TransferHistoryEntry(
            timestamp: Date(),
            filename: filename,
            username: username,
            size: size,
            duration: duration,
            averageSpeed: duration > 0 ? Double(size) / duration : 0,
            isDownload: isDownload
        )

        if isDownload {
            downloadHistory.insert(entry, at: 0)
            filesDownloaded += 1
            sessionDownloaded += size
            totalDownloaded += size
            uniqueUsersDownloadedFrom.insert(username)

            // Keep last 100
            if downloadHistory.count > 100 {
                downloadHistory.removeLast()
            }
        } else {
            uploadHistory.insert(entry, at: 0)
            filesUploaded += 1
            sessionUploaded += size
            totalUploaded += size
            uniqueUsersUploadedTo.insert(username)

            if uploadHistory.count > 100 {
                uploadHistory.removeLast()
            }
        }
    }
}
