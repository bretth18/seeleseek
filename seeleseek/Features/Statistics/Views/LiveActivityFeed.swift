import SwiftUI

/// Real-time activity feed showing network events as they happen
struct LiveActivityFeed: View {
    @Environment(\.appState) private var appState
    @State private var activityLog = ActivityLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("Activity Feed")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

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
                        .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
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
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

// MARK: - Activity Event Row

struct ActivityEventRow: View {
    let event: ActivityLog.ActivityEvent

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: SeeleSpacing.sm) {
            Image(systemName: event.type.icon)
                .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                .foregroundStyle(event.type.color)
                .frame(width: SeeleSpacing.iconSizeMedium)

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
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
        DateTimeFormatters.formatTime(date)
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
