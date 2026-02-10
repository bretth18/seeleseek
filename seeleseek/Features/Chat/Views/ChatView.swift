import SwiftUI

struct ChatView: View {
    @Environment(\.appState) private var appState
    @State private var showRoomBrowser = false

    private var chatState: ChatState {
        appState.chatState
    }

    var body: some View {
        HSplitView {
            chatSidebar
                .frame(minWidth: 200, maxWidth: 280)

            chatContent
        }
        .background(SeeleColors.background)
    }

    // MARK: - Sidebar

    private var chatSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    showRoomBrowser = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: SeeleSpacing.iconSize))
                        .foregroundStyle(SeeleColors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surface)

            Divider().background(SeeleColors.surfaceSecondary)

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Joined Rooms
                    if !chatState.joinedRooms.isEmpty {
                        sectionHeader("Rooms", count: chatState.joinedRooms.count)

                        ForEach(chatState.joinedRooms) { room in
                            roomSidebarRow(room)
                        }
                    }

                    // Private Chats
                    if !chatState.privateChats.isEmpty {
                        sectionHeader("Messages", count: chatState.privateChats.count)

                        ForEach(chatState.privateChats) { chat in
                            dmSidebarRow(chat)
                        }
                    }

                    if chatState.joinedRooms.isEmpty && chatState.privateChats.isEmpty {
                        emptyListView
                    }
                }
            }
        }
        .background(SeeleColors.surface)
        .sheet(isPresented: $showRoomBrowser) {
            RoomBrowserSheet(chatState: chatState, isPresented: $showRoomBrowser)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text("\(title) (\(count))")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
    }

    // MARK: - Room Sidebar Row

    private func roomSidebarRow(_ room: ChatRoom) -> some View {
        let isSelected = chatState.selectedRoom == room.name

        return Button {
            chatState.selectRoom(room.name)
        } label: {
            HStack(spacing: SeeleSpacing.sm) {
                // Icon: lock for private, crown for owned, wrench for operated, default group
                roomIcon(room)
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textSecondary)
                    .frame(width: SeeleSpacing.xl)

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(room.name)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textPrimary)

                    Text("\(room.userCount) users")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Spacer()

                if room.unreadCount > 0 {
                    Text("\(room.unreadCount)")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textOnAccent)
                        .padding(.horizontal, SeeleSpacing.rowVertical)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(SeeleColors.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(isSelected ? SeeleColors.surfaceSecondary : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                if room.isPrivate {
                    chatState.selectRoom(room.name)
                    chatState.showRoomManagement = true
                }
            } label: {
                Label("Room Info", systemImage: "info.circle")
            }
            .disabled(!room.isPrivate)

            Divider()

            Button(role: .destructive) {
                chatState.leaveRoom(room.name)
            } label: {
                Label("Leave Room", systemImage: "arrow.right.square")
            }
        }
    }

    @ViewBuilder
    private func roomIcon(_ room: ChatRoom) -> some View {
        if chatState.isOwner(of: room.name) {
            Image(systemName: "crown.fill")
        } else if chatState.operatedRoomNames.contains(room.name) {
            Image(systemName: "wrench.fill")
        } else if room.isPrivate {
            Image(systemName: "lock.fill")
        } else {
            Image(systemName: "person.3")
        }
    }

    // MARK: - DM Sidebar Row

    private func dmSidebarRow(_ chat: PrivateChat) -> some View {
        let isSelected = chatState.selectedPrivateChat == chat.username

        return Button {
            chatState.selectPrivateChat(chat.username)
        } label: {
            HStack(spacing: SeeleSpacing.sm) {
                // Online status dot
                Circle()
                    .fill(chat.isOnline ? SeeleColors.success : SeeleColors.textTertiary)
                    .frame(width: SeeleSpacing.statusDotSmall, height: SeeleSpacing.statusDotSmall)
                    .frame(width: SeeleSpacing.xl)

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(chat.username)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textPrimary)

                    Text(chat.isOnline ? "Online" : "Offline")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Spacer()

                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textOnAccent)
                        .padding(.horizontal, SeeleSpacing.rowVertical)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(SeeleColors.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(isSelected ? SeeleColors.surfaceSecondary : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await appState.socialState.loadProfile(for: chat.username) }
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }

            Button {
                appState.browseState.browseUser(chat.username)
            } label: {
                Label("Browse Files", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) {
                chatState.deleteConversationHistory(chat.username)
            } label: {
                Label("Delete History", systemImage: "trash")
            }

            Button(role: .destructive) {
                chatState.closePrivateChat(chat.username)
            } label: {
                Label("Close Chat", systemImage: "xmark")
            }
        }
    }

    private var emptyListView: some View {
        VStack(spacing: SeeleSpacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: SeeleSpacing.iconSizeXL, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No chats yet")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

            Button("Join a Room") {
                showRoomBrowser = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(SeeleColors.accent)
        }
        .padding(SeeleSpacing.xl)
    }

    // MARK: - Content

    @ViewBuilder
    private var chatContent: some View {
        if let room = chatState.currentRoom {
            ChatRoomContentView(room: room, chatState: chatState, appState: appState)
        } else if let chat = chatState.currentPrivateChat {
            PrivateChatContentView(chat: chat, chatState: chatState, appState: appState)
        } else {
            noChatSelectedView
        }
    }

    private var noChatSelectedView: some View {
        StandardEmptyState(
            icon: "bubble.left.and.bubble.right",
            title: "Select a chat",
            subtitle: "Choose a room or start a private conversation"
        )
    }
}

#Preview {
    ChatView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 600)
}
