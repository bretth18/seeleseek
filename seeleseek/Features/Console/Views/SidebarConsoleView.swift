import SwiftUI

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
