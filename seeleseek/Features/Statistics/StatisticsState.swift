import SwiftUI

@Observable
@MainActor
final class StatisticsState {
    // MARK: - Network Statistics
    var totalDownloaded: UInt64 = 0
    var totalUploaded: UInt64 = 0
    var sessionDownloaded: UInt64 = 0
    var sessionUploaded: UInt64 = 0

    // MARK: - Transfer History
    var downloadHistory: [TransferHistoryEntry] = []
    var uploadHistory: [TransferHistoryEntry] = []

    // MARK: - Speed Samples (for charts)
    var speedSamples: [SpeedSample] = []
    var maxRecordedSpeed: Double = 0

    // MARK: - Connection Statistics
    var peersConnected: Int = 0
    var peersEverConnected: Int = 0
    var connectionAttempts: Int = 0
    var connectionFailures: Int = 0

    // MARK: - Search Statistics
    var searchesPerformed: Int = 0
    var totalResultsReceived: Int = 0
    var averageResponseTime: TimeInterval = 0

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

    struct SpeedSample: Identifiable {
        let id: UUID
        let timestamp: Date
        let downloadSpeed: Double
        let uploadSpeed: Double

        init(id: UUID = UUID(), timestamp: Date, downloadSpeed: Double, uploadSpeed: Double) {
            self.id = id
            self.timestamp = timestamp
            self.downloadSpeed = downloadSpeed
            self.uploadSpeed = uploadSpeed
        }
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

    var averageDownloadSpeed: Double {
        guard sessionDuration > 0 else { return 0 }
        return Double(sessionDownloaded) / sessionDuration
    }

    var averageUploadSpeed: Double {
        guard sessionDuration > 0 else { return 0 }
        return Double(sessionUploaded) / sessionDuration
    }

    var connectionSuccessRate: Double {
        guard connectionAttempts > 0 else { return 0 }
        return Double(connectionAttempts - connectionFailures) / Double(connectionAttempts)
    }

    var currentDownloadSpeed: Double {
        speedSamples.last?.downloadSpeed ?? 0
    }

    var currentUploadSpeed: Double {
        speedSamples.last?.uploadSpeed ?? 0
    }

    // MARK: - Actions

    func addSpeedSample(download: Double, upload: Double) {
        let sample = SpeedSample(
            timestamp: Date(),
            downloadSpeed: download,
            uploadSpeed: upload
        )
        speedSamples.append(sample)

        // Keep last 120 samples (2 minutes at 1/second)
        if speedSamples.count > 120 {
            speedSamples.removeFirst()
        }

        maxRecordedSpeed = max(maxRecordedSpeed, download, upload)
    }

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

    func recordSearch(resultsCount: Int, responseTime: TimeInterval) {
        searchesPerformed += 1
        totalResultsReceived += resultsCount

        // Update rolling average
        averageResponseTime = (averageResponseTime * Double(searchesPerformed - 1) + responseTime) / Double(searchesPerformed)
    }

    func recordConnectionAttempt(success: Bool) {
        connectionAttempts += 1
        if !success {
            connectionFailures += 1
        } else {
            peersEverConnected += 1
        }
    }

    func resetSession() {
        sessionStartTime = Date()
        sessionDownloaded = 0
        sessionUploaded = 0
        speedSamples.removeAll()
        peersConnected = 0
        connectionAttempts = 0
        connectionFailures = 0
        searchesPerformed = 0
        totalResultsReceived = 0
        averageResponseTime = 0
    }
}
