import SwiftUI
import SeeleseekCore

struct ChatRoomContentView: View {
    let room: ChatRoom
    @Bindable var chatState: ChatState
    var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                roomHeader

                if appState.settings.showJoinLeaveMessages && !room.events.isEmpty {
                    RoomActivityPane(events: room.events)
                }

                if !room.tickers.isEmpty {
                    tickerStrip
                }

                Divider().background(SeeleColors.surfaceSecondary)

                ChatTranscriptView(
                    messages: room.messages,
                    conversationID: room.name,
                    chatState: chatState,
                    appState: appState
                )

                Divider().background(SeeleColors.surfaceSecondary)

                MessageInput(text: $chatState.messageInput, completionCandidates: room.users) {
                    chatState.sendMessage()
                }
            }

            if chatState.showUserListPanel {
                Divider().background(SeeleColors.surfaceSecondary)
                RoomUserListPanel(room: room, chatState: chatState, appState: appState)
                    .frame(width: 200)
            }
        }
        .sheet(isPresented: $chatState.showRoomManagement) {
            if let currentRoom = chatState.currentRoom {
                RoomManagementSheet(room: currentRoom, chatState: chatState, isPresented: $chatState.showRoomManagement)
            }
        }
    }

    private var roomHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                HStack(spacing: SeeleSpacing.sm) {
                    Text(room.name)
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    if room.isPrivate {
                        Text("Private")
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textOnAccent)
                            .padding(.horizontal, SeeleSpacing.xs)
                            .padding(.vertical, SeeleSpacing.xxs)
                            .background(SeeleColors.accent.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }

                Text("\(room.userCount) users online")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
            }

            Spacer()

            Button {
                chatState.showUserListPanel.toggle()
            } label: {
                Image(systemName: "person.2")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(chatState.showUserListPanel ? SeeleColors.accent : SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chatState.showUserListPanel ? "Hide user list" : "Show user list")

            // Shown for every joined room, not just private ones you manage:
            // the sheet's ticker field is the only way to set your own ticker,
            // and tickers are per-user in any room (RoomTickerSet, code 116).
            // The owner-only sections inside the sheet gate themselves.
            Button {
                chatState.showRoomManagement = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Room settings")

            Button {
                chatState.leaveRoom(room.name)
            } label: {
                Text("Leave")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.error)
            }
            .buttonStyle(.plain)
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface)
    }

    private var tickerStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: SeeleSpacing.xs) {
                HStack(spacing: SeeleSpacing.xs) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 9))
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text("Tickers")
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text("\(room.tickers.count)")
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tickers, \(room.tickers.count)")
                .accessibilityAddTraits(.isStaticText)

                Spacer()

                Button {
                    chatState.tickersCollapsed.toggle()
                } label: {
                    Image(systemName: chatState.tickersCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chatState.tickersCollapsed ? "Expand tickers" : "Collapse tickers")
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.xxs)

            if !chatState.tickersCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SeeleSpacing.lg) {
                        ForEach(room.sortedTickers, id: \.key) { username, ticker in
                            HStack(spacing: SeeleSpacing.xs) {
                                Text(username)
                                    .font(SeeleTypography.caption2)
                                    .foregroundStyle(SeeleColors.accent)
                                Text(ticker)
                                    .font(SeeleTypography.caption2)
                                    .foregroundStyle(SeeleColors.textTertiary)
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Ticker from \(username): \(ticker)")
                            .accessibilityAddTraits(.isStaticText)
                        }
                    }
                    .padding(.horizontal, SeeleSpacing.md)
                }
                .frame(height: 18)
            }
        }
        .background(SeeleColors.surfaceSecondary.opacity(0.3))
    }
}
