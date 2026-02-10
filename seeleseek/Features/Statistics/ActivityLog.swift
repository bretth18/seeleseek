import SwiftUI

@Observable
@MainActor
final class ActivityLog {
    static let shared = ActivityLog()

    private(set) var events: [ActivityEvent] = []
    private(set) var hasRecentActivity = false
    private var activityTimer: Timer?

    private let maxEvents = 500

    struct ActivityEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: EventType
        let title: String
        let detail: String?
    }

    enum EventType {
        case peerConnected
        case peerDisconnected
        case searchStarted
        case searchResult
        case downloadStarted
        case downloadCompleted
        case uploadStarted
        case uploadCompleted
        case chatMessage
        case error
        case info

        var icon: String {
            switch self {
            case .peerConnected: "person.fill.checkmark"
            case .peerDisconnected: "person.fill.xmark"
            case .searchStarted: "magnifyingglass"
            case .searchResult: "doc.text.magnifyingglass"
            case .downloadStarted: "arrow.down.circle"
            case .downloadCompleted: "arrow.down.circle.fill"
            case .uploadStarted: "arrow.up.circle"
            case .uploadCompleted: "arrow.up.circle.fill"
            case .chatMessage: "bubble.left.fill"
            case .error: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .peerConnected, .downloadCompleted, .uploadCompleted:
                return SeeleColors.success
            case .peerDisconnected:
                return SeeleColors.textTertiary
            case .searchStarted, .searchResult:
                return SeeleColors.info
            case .downloadStarted, .uploadStarted:
                return SeeleColors.accent
            case .chatMessage:
                return SeeleColors.warning
            case .error:
                return SeeleColors.error
            case .info:
                return SeeleColors.textSecondary
            }
        }
    }

    private init() {}

    func log(_ type: EventType, title: String, detail: String? = nil) {
        let event = ActivityEvent(
            timestamp: Date(),
            type: type,
            title: title,
            detail: detail
        )

        events.insert(event, at: 0)

        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }

        triggerActivity()
    }

    func clear() {
        events.removeAll()
    }

    private func triggerActivity() {
        hasRecentActivity = true
        activityTimer?.invalidate()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.hasRecentActivity = false
            }
        }
    }

    // MARK: - Convenience Methods

    func logPeerConnected(username: String, ip: String) {
        log(.peerConnected, title: "Connected to \(username)", detail: ip)
    }

    func logPeerDisconnected(username: String) {
        log(.peerDisconnected, title: "Disconnected from \(username)")
    }

    func logSearchStarted(query: String) {
        log(.searchStarted, title: "Searching for \"\(query)\"")
    }

    func logSearchResults(query: String, count: Int, user: String) {
        log(.searchResult, title: "\(count) results from \(user)", detail: query)
    }

    func logDownloadStarted(filename: String, from user: String) {
        log(.downloadStarted, title: "Download started from \(user)", detail: filename)
    }

    func logDownloadCompleted(filename: String) {
        log(.downloadCompleted, title: "Download completed", detail: filename)
    }

    func logUploadStarted(filename: String, to user: String) {
        log(.uploadStarted, title: "Upload started to \(user)", detail: filename)
    }

    func logUploadCompleted(filename: String) {
        log(.uploadCompleted, title: "Upload completed", detail: filename)
    }

    func logChatMessage(from user: String, room: String?) {
        if let room = room {
            log(.chatMessage, title: "Message from \(user)", detail: "in \(room)")
        } else {
            log(.chatMessage, title: "Private message from \(user)")
        }
    }

    func logError(_ message: String, detail: String? = nil) {
        log(.error, title: message, detail: detail)
    }

    func logInfo(_ message: String, detail: String? = nil) {
        log(.info, title: message, detail: detail)
    }

    // MARK: - Connection & Server Events

    func logConnectionSuccess(username: String, server: String) {
        log(.info, title: "Connected as \(username)", detail: server)
    }

    func logConnectionFailed(reason: String) {
        log(.error, title: "Login failed", detail: reason)
    }

    func logDisconnected(reason: String? = nil) {
        log(.info, title: "Disconnected", detail: reason)
    }

    func logRelogged() {
        log(.error, title: "Kicked: another client logged in")
    }

    func logRoomJoined(room: String, userCount: Int) {
        log(.chatMessage, title: "Joined \(room)", detail: "\(userCount) users")
    }

    func logRoomLeft(room: String) {
        log(.chatMessage, title: "Left \(room)")
    }

    func logNATMapping(port: UInt16, success: Bool) {
        if success {
            log(.info, title: "NAT mapped port \(port)")
        } else {
            log(.error, title: "NAT mapping failed", detail: "Port \(port)")
        }
    }

    func logDistributedSearch(query: String, matchCount: Int) {
        log(.searchResult, title: "\(matchCount) shared for \"\(query)\"")
    }
}
