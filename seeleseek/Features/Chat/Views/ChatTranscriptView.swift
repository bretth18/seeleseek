import SwiftUI
import SeeleseekCore

/// Chat transcript with smart autoscroll. The view follows new messages
/// only when the user is at the bottom. If the user scrolls up, new
/// messages collect behind a jump-to-latest pill. A sent message pins
/// the view to the bottom again.
struct ChatTranscriptView: View {
    let messages: [ChatMessage]
    /// Room name or DM username. A change resets the scroll state.
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
            // Observe the last id, not the count. At the 1000-message
            // cap, the count stays constant but the ids change.
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
