import SwiftUI

/// Real-time activity feed showing network events as they happen
struct LiveActivityFeed: View {
    @Environment(\.appState) private var appState
    @State private var activityLog = ActivityLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            // Header
            HStack {
                Text("Activity Feed")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                // Live indicator
                HStack(spacing: SeeleSpacing.xs) {
                    Circle()
                        .fill(activityLog.hasRecentActivity ? SeeleColors.success : SeeleColors.textTertiary)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Button {
                    activityLog.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // Activity list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(activityLog.events) { event in
                            ActivityEventRow(event: event)
                                .id(event.id)
                        }
                    }
                }
                .onChange(of: activityLog.events.count) { _, _ in
                    if let lastEvent = activityLog.events.first {
                        withAnimation {
                            proxy.scrollTo(lastEvent.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

// MARK: - Activity Event Row

struct ActivityEventRow: View {
    let event: ActivityLog.ActivityEvent

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: SeeleSpacing.sm) {
            // Icon
            Image(systemName: event.type.icon)
                .font(.system(size: 12))
                .foregroundStyle(event.type.color)
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SeeleSpacing.xs) {
                    Text(event.title)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Spacer()

                    Text(formatTime(event.timestamp))
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                if let detail = event.detail {
                    Text(detail)
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .lineLimit(isExpanded ? nil : 1)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, SeeleSpacing.sm)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Activity Log

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

        // Trim old events
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }

        // Trigger activity indicator
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
}

#Preview {
    LiveActivityFeed()
        .environment(\.appState, AppState())
        .frame(width: 400, height: 300)
        .onAppear {
            let log = ActivityLog.shared
            log.logPeerConnected(username: "musicfan42", ip: "192.168.1.100")
            log.logSearchStarted(query: "pink floyd dark side")
            log.logSearchResults(query: "pink floyd dark side", count: 47, user: "vinylcollector")
            log.logDownloadStarted(filename: "01 - Speak to Me.flac", from: "vinylcollector")
            log.logDownloadCompleted(filename: "01 - Speak to Me.flac")
            log.logChatMessage(from: "djmixer", room: "Electronic")
            log.logError("Connection refused", detail: "Peer unavailable")
        }
}
