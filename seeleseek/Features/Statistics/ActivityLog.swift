import SwiftUI
import SeeleseekCore

@Observable
@MainActor
final class ActivityLog: ActivityLogging {
    static let shared = ActivityLog()

    private(set) var events: [ActivityEvent] = []
    private(set) var hasRecentActivity = false
    private var activityTimer: Timer?

    // Non-observable staging buffer. Log events land here synchronously and
    // are drained into `events` in batches, coalescing observable
    // invalidation so the sidebar console can't drive app-wide frame drops
    // when activity is bursty. See `scheduleFlush` / `flush`.
    private var pendingEvents: [ActivityEvent] = []
    private var flushTask: Task<Void, Never>?
    private static let flushInterval: Duration = .milliseconds(250)

    private let maxEvents = 500

    struct ActivityEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: EventType
        let title: String
        let detail: String?
        let username: String?
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

        /// Spoken name for VoiceOver row labels. The icon and its
        /// color are the only visual cues for the event type.
        var spokenName: String {
            switch self {
            case .peerConnected: "Peer connected"
            case .peerDisconnected: "Peer disconnected"
            case .searchStarted: "Search started"
            case .searchResult: "Search result"
            case .downloadStarted: "Download started"
            case .downloadCompleted: "Download completed"
            case .uploadStarted: "Upload started"
            case .uploadCompleted: "Upload completed"
            case .chatMessage: "Chat message"
            case .error: "Error"
            case .info: "Info"
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

    func log(_ type: EventType, title: String, detail: String? = nil, username: String? = nil) {
        let event = ActivityEvent(
            timestamp: Date(),
            type: type,
            title: title,
            detail: detail,
            username: username
        )

        // Stage into the non-observable buffer — no view invalidation yet.
        pendingEvents.append(event)
        scheduleFlush()

        // User-facing notifications are intentionally NOT batched; they
        // have their own dedupe/throttle inside NotificationService.
        NotificationService.shared.handleActivityEvent(type: type, title: title, detail: detail)
    }

    func clear() {
        pendingEvents.removeAll(keepingCapacity: true)
        events.removeAll()
        flushTask?.cancel()
        flushTask = nil
    }

    /// Start a deferred flush of `pendingEvents` into `events`. Subsequent
    /// log calls during the flush window are absorbed into the same batch.
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    /// Prepend the pending batch onto `events` in one observable write,
    /// preserving newest-first ordering.
    private func flush() {
        flushTask = nil
        guard !pendingEvents.isEmpty else { return }
        // pendingEvents is append-ordered (oldest first). Reverse so the
        // newest event lands at index 0, matching the pre-batching insert-at-0
        // semantics.
        events.insert(contentsOf: pendingEvents.reversed(), at: 0)
        pendingEvents.removeAll(keepingCapacity: true)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
        triggerActivity()
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
        log(.peerConnected, title: "Connected to \(username)", detail: ip, username: username)
    }

    func logPeerDisconnected(username: String) {
        log(.peerDisconnected, title: "Disconnected from \(username)", username: username)
    }

    func logSearchStarted(query: String) {
        log(.searchStarted, title: "Searching for \"\(query)\"")
    }

    func logSearchResults(query: String, count: Int, user: String) {
        log(.searchResult, title: "\(count) results from \(user)", detail: query, username: user)
    }

    func logDownloadStarted(filename: String, from user: String) {
        log(.downloadStarted, title: "Download started from \(user)", detail: filename, username: user)
    }

    func logDownloadCompleted(filename: String) {
        log(.downloadCompleted, title: "Download completed", detail: filename)
        let displayName = (filename as NSString).lastPathComponent
        VoiceOverAnnouncer.shared.announce("Download complete: \(displayName)")
    }

    func logUploadStarted(filename: String, to user: String) {
        log(.uploadStarted, title: "Upload started to \(user)", detail: filename, username: user)
    }

    func logUploadCompleted(filename: String) {
        log(.uploadCompleted, title: "Upload completed", detail: filename)
    }

    func logChatMessage(from user: String, room: String?) {
        if let room = room {
            log(.chatMessage, title: "Message from \(user)", detail: "in \(room)", username: user)
        } else {
            log(.chatMessage, title: "Private message from \(user)", username: user)
            VoiceOverAnnouncer.shared.announce("Private message from \(user)")
        }
    }

    func logFolderRequestStarted(username: String, folder: String) {
        log(.info, title: "Getting folder contents from \(username)", detail: folder, username: username)
        VoiceOverAnnouncer.shared.announce("Getting folder contents from \(username)")
    }

    func logFolderQueued(count: Int, username: String, folder: String) {
        log(.downloadStarted, title: "Queued \(count) files from \(username)", detail: folder, username: username)
        VoiceOverAnnouncer.shared.announce("Queued \(count) files from \(username)")
    }

    func logFolderRequestFailed(username: String, folder: String, reason: String) {
        log(.error, title: "Folder download from \(username) failed: \(reason)", detail: folder, username: username)
        VoiceOverAnnouncer.shared.announce(reason)
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
        VoiceOverAnnouncer.shared.announce("Connected to Soulseek as \(username)")
    }

    func logConnectionFailed(reason: String) {
        log(.error, title: "Login failed", detail: reason)
        VoiceOverAnnouncer.shared.announce("Login failed: \(reason)")
    }

    func logDisconnected(reason: String? = nil) {
        log(.info, title: "Disconnected", detail: reason)
        VoiceOverAnnouncer.shared.announce("Disconnected from the Soulseek server")
    }

    func logRelogged() {
        log(.error, title: "Kicked: another client logged in")
        VoiceOverAnnouncer.shared.announce("Disconnected: another client logged in with your account")
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
