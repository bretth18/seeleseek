import SwiftUI
import SeeleseekCore

struct SidebarConsoleView: View {
    @State private var activityLog = ActivityLog.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(SeeleColors.divider)

            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .background(SeeleColors.surfaceSecondary)
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        VStack(spacing: 0) {
            header
            if let latest = activityLog.events.first {
                peekLine(latest)
            }
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(activityLog.events.reversed()) { event in
                            consoleRow(event)
                                .id(event.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: activityLog.events.count) { _, _ in
                    if let latest = activityLog.events.first {
                        withAnimation {
                            proxy.scrollTo(latest.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SeeleColors.textTertiary)

                Text("Console")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)

                if !activityLog.events.isEmpty {
                    Text("\(activityLog.events.count)")
                        .font(SeeleTypography.monoXSmall)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(SeeleColors.surfaceElevated, in: Capsule())
                }

                Spacer()

                if isExpanded {
                    Button {
                        activityLog.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 8))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    private func peekLine(_ event: ActivityLog.ActivityEvent) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: event.type.icon)
                .font(.system(size: 7))
                .foregroundStyle(event.type.color)

            Text(event.title)
                .font(SeeleTypography.monoXSmall)
                .foregroundStyle(SeeleColors.textTertiary)
                .lineLimit(1)

            Spacer()

            Text(formatTime(event.timestamp))
                .font(SeeleTypography.monoXSmall)
                .foregroundStyle(SeeleColors.textTertiary.opacity(0.6))
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.bottom, SeeleSpacing.sm)
        .opacity(0.7)
    }

    private func consoleRow(_ event: ActivityLog.ActivityEvent) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: event.type.icon)
                .font(.system(size: 8))
                .foregroundStyle(event.type.color)
                .frame(width: 12)

            Text(formatTime(event.timestamp))
                .font(SeeleTypography.monoXSmall)
                .foregroundStyle(SeeleColors.textTertiary)

            Text(event.title)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, 1)
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - Previews
//
// The console reads from `ActivityLog.shared`, a @MainActor singleton, which
// starts empty. Each preview clears the log and seeds a representative event
// mix, then renders at the sidebar's real width (220pt). Expand/collapse is
// interactive in the Xcode canvas — click the chevron to switch states.

private func seedConsolePreview(_ events: () -> Void) {
    let log = ActivityLog.shared
    log.clear()
    events()
}

#Preview("Empty") {
    SidebarConsoleView()
        .frame(width: 220, height: 80)
        .background(SeeleColors.surface)
        .onAppear {
            seedConsolePreview {}
        }
}

#Preview("Collapsed — one recent event") {
    SidebarConsoleView()
        .frame(width: 220, height: 80)
        .background(SeeleColors.surface)
        .onAppear {
            seedConsolePreview {
                let log = ActivityLog.shared
                log.logPeerConnected(username: "musicfan42", ip: "192.168.1.100")
            }
        }
}

#Preview("Collapsed — mixed activity") {
    SidebarConsoleView()
        .frame(width: 220, height: 80)
        .background(SeeleColors.surface)
        .onAppear {
            seedConsolePreview {
                let log = ActivityLog.shared
                log.logPeerConnected(username: "vinylcollector", ip: "10.0.0.42")
                log.logSearchStarted(query: "pink floyd dark side flac")
                log.logSearchResults(query: "pink floyd dark side flac", count: 47, user: "vinylcollector")
                log.logDownloadStarted(filename: "Speak to Me.flac", from: "vinylcollector")
            }
        }
}

#Preview("Expanded — full log (click chevron)") {
    SidebarConsoleView()
        .frame(width: 500, height: 800)
        .background(SeeleColors.surface)
        .onAppear {
            seedConsolePreview {
                let log = ActivityLog.shared
                log.logConnectionSuccess(username: "demo_user", server: "server.slsknet.org")
                log.logPeerConnected(username: "vinylcollector", ip: "10.0.0.42")
                log.logSearchStarted(query: "cindy lee diamond jubilee")
                log.logSearchResults(query: "cindy lee diamond jubilee", count: 12, user: "trackhunter")
                log.logSearchResults(query: "cindy lee diamond jubilee", count: 8, user: "archivist99")
                log.logDownloadStarted(filename: "01 - Diamond Jubilee.flac", from: "trackhunter")
                log.logChatMessage(from: "djmixer", room: "Electronic")
                log.logUploadStarted(filename: "Loveless - 01.flac", to: "mbvdevotee")
                log.logDownloadCompleted(filename: "01 - Diamond Jubilee.flac")
                log.logRoomJoined(room: "Electronic", userCount: 834)
                log.logError("Connection refused", detail: "peer unavailable: 203.0.113.1:2234")
                log.logPeerDisconnected(username: "archivist99")
                log.logInfo("NAT mapped port 2234")
            }
        }
}
