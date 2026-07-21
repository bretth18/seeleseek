import SwiftUI
import SeeleseekCore

/// Strip under the room header that shows join/leave events. This keeps
/// them out of the message transcript. Collapsed, it shows the latest
/// event. Expanded, it shows a scrollable list with a drag handle to
/// change the height.
struct RoomActivityPane: View {
    let events: [RoomEvent]

    @AppStorage("chat.activityPaneExpanded") private var isExpanded = false
    @AppStorage("chat.activityPaneHeight") private var paneHeight = 100.0
    @State private var dragBaseHeight: Double?

    private static let minHeight = 60.0
    private static let maxHeight = 240.0

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                eventList
                dragHandle
            }
        }
        .background(SeeleColors.surfaceSecondary.opacity(0.3))
    }

    private var header: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 9))
                .foregroundStyle(SeeleColors.textTertiary)
            Text("Activity")
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)
            Text("\(events.count)")
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)

            if !isExpanded, let latest = events.last {
                Text("\(latest.username) \(label(for: latest.kind)) · \(latest.formattedTime)")
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, SeeleSpacing.xs)
            }

            Spacer()

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse room activity" : "Expand room activity")
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.xxs)
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }

    private var eventList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                ForEach(events.reversed()) { event in
                    HStack(spacing: SeeleSpacing.xs) {
                        Image(systemName: event.kind == .joined ? "arrow.right.circle" : "arrow.left.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(event.kind == .joined ? SeeleColors.success : SeeleColors.textTertiary)
                        Text(event.username)
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.accent)
                        Text(label(for: event.kind))
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textSecondary)
                        Spacer()
                        Text(event.formattedTime)
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(event.username) \(label(for: event.kind)) at \(event.formattedTime)")
                }
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.xs)
        }
        .frame(height: paneHeight)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(SeeleColors.textTertiary.opacity(0.5))
            .frame(width: 36, height: 3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = dragBaseHeight ?? paneHeight
                        dragBaseHeight = base
                        paneHeight = (base + value.translation.height)
                            .clamped(to: Self.minHeight...Self.maxHeight)
                    }
                    .onEnded { _ in
                        dragBaseHeight = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func label(for kind: RoomEvent.Kind) -> String {
        kind == .joined ? "joined" : "left"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
