import SwiftUI
import SeeleseekCore

/// Shared chat transcript with smart autoscroll: follows new messages only
/// while the user is at the bottom. Scrolling up pauses following and new
/// messages accumulate behind a jump-to-latest pill instead of yanking the
/// view down. Sending your own message always re-pins.
struct ChatTranscriptView: View {
    let messages: [ChatMessage]
    /// Room name or DM username — resets scroll state when it changes.
    let conversationID: String
    var chatState: ChatState
    var appState: AppState

    @State private var isPinnedToBottom = true
    @State private var unseenCount = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SeeleSpacing.sm) {
                    ForEach(messages) { message in
                        MessageBubble(message: message, chatState: chatState, appState: appState)
                            .id(message.id)
                    }
                }
                .padding(SeeleSpacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 60
            } action: { _, nearBottom in
                isPinnedToBottom = nearBottom
                if nearBottom {
                    unseenCount = 0
                }
            }
            // Keyed on last id, not count — the message cap drops from the
            // head at 1000, leaving the count constant while ids still change.
            .onChange(of: messages.last?.id) {
                guard let last = messages.last else { return }
                if last.isOwn || isPinnedToBottom {
                    proxy.scrollTo(last.id, anchor: .bottom)
                    isPinnedToBottom = true
                    unseenCount = 0
                } else {
                    unseenCount += 1
                }
            }
            .onChange(of: conversationID) {
                isPinnedToBottom = true
                unseenCount = 0
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    jumpToLatestButton(proxy: proxy)
                }
            }
        }
    }

    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        Button {
            if let last = messages.last {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            isPinnedToBottom = true
            unseenCount = 0
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                if unseenCount > 0 {
                    Text("\(unseenCount) new message\(unseenCount == 1 ? "" : "s")")
                        .font(SeeleTypography.caption)
                }
                Image(systemName: "arrow.down")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .semibold))
            }
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.xs)
            .foregroundStyle(SeeleColors.textOnAccent)
            .background(SeeleColors.accent.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(SeeleSpacing.md)
        .accessibilityLabel(
            unseenCount > 0
                ? "\(unseenCount) new messages, jump to latest"
                : "Jump to latest message"
        )
    }
}
