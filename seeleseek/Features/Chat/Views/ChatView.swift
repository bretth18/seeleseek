import SwiftUI
import SeeleseekCore

struct ChatView: View {
    @Environment(\.appState) private var appState
    @State private var showRoomBrowser = false
    /// Username whose DM history is pending delete confirmation.
    @State private var pendingHistoryDeletion: String?

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
        .focusedSceneValue(\.tabCommands, chatTabCommands)
        .confirmationDialog(
            "Delete chat history with \(pendingHistoryDeletion ?? "")?",
            isPresented: Binding(
                get: { pendingHistoryDeletion != nil },
                set: { if !$0 { pendingHistoryDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete History", role: .destructive) {
                if let username = pendingHistoryDeletion {
                    chatState.deleteConversationHistory(username)
                }
                pendingHistoryDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingHistoryDeletion = nil
            }
        } message: {
            Text("This permanently deletes the saved message history from the database. This cannot be undone.")
        }
    }

    // MARK: - Room/DM cycling

    /// Rooms and private chats behave as one ordered set of conversation
    /// tabs for Show Next/Previous Tab. Suppressed while the room browser
    /// sheet is up so its own tab bar is not shadowed.
    private var chatTabCommands: TabCommands? {
        guard !showRoomBrowser,
              !(chatState.joinedRooms.isEmpty && chatState.privateChats.isEmpty) else { return nil }
        return TabCommands(
            selectNext: { selectAdjacentConversation(forward: true) },
            selectPrevious: { selectAdjacentConversation(forward: false) },
            closeCurrent: nil
        )
    }

    private func selectAdjacentConversation(forward: Bool) {
        let rooms = chatState.joinedRooms.map(\.name)
        let chats = chatState.privateChats.map(\.username)
        let count = rooms.count + chats.count
        guard count > 0 else { return }

        let current: Int
        if let room = chatState.selectedRoom, let index = rooms.firstIndex(of: room) {
            current = index
        } else if let chat = chatState.selectedPrivateChat, let index = chats.firstIndex(of: chat) {
            current = rooms.count + index
        } else {
            // Nothing selected: next lands on the first entry, previous on the last.
            current = forward ? -1 : 0
        }

        let target = forward
            ? TabCycler.wrappedNext(current, count: count)
            : TabCycler.wrappedPrevious(current, count: count)
        if target < rooms.count {
            chatState.selectRoom(rooms[target])
        } else {
            chatState.selectPrivateChat(chats[target - rooms.count])
        }
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
                .accessibilityLabel("Browse rooms")
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
                .accessibilityAddTraits(.isHeader)
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

                UnreadCountBadge(count: room.unreadCount)
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
        .accessibilityLabel(roomRowAccessibilityLabel(room))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityActions {
            if room.isPrivate {
                Button("Room info") {
                    chatState.selectRoom(room.name)
                    chatState.showRoomManagement = true
                }
            }
            Button("Leave room") {
                chatState.leaveRoom(room.name)
            }
        }
    }

    private func roomRowAccessibilityLabel(_ room: ChatRoom) -> String {
        var parts: [String] = [room.name]
        if chatState.isOwner(of: room.name) {
            parts.append("owned room")
        } else if chatState.operatedRoomNames.contains(room.name) {
            parts.append("operated room")
        } else if room.isPrivate {
            parts.append("private room")
        }
        parts.append("\(room.userCount) users")
        if room.unreadCount > 0 {
            parts.append("\(room.unreadCount) unread")
        }
        return parts.joined(separator: ", ")
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
                StandardStatusDot(isOnline: chat.isOnline, size: SeeleSpacing.statusDotSmall)
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

                UnreadCountBadge(count: chat.unreadCount)
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(isSelected ? SeeleColors.surfaceSecondary : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            UserContextMenuItems(username: chat.username)

            Divider()

            Button(role: .destructive) {
                pendingHistoryDeletion = chat.username
            } label: {
                Label("Delete History", systemImage: "trash")
            }

            Button(role: .destructive) {
                chatState.closePrivateChat(chat.username)
            } label: {
                Label("Close Chat", systemImage: "xmark")
            }
        }
        // VoiceOver cannot see the context menu. The label replaces
        // the default one, which spoke the status twice.
        .accessibilityLabel(dmRowAccessibilityLabel(chat))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityActions {
            UserAccessibilityActions(username: chat.username)

            Button("Delete history") {
                pendingHistoryDeletion = chat.username
            }
            Button("Close chat") {
                chatState.closePrivateChat(chat.username)
            }
        }
    }

    private func dmRowAccessibilityLabel(_ chat: PrivateChat) -> String {
        var parts: [String] = [chat.username, chat.isOnline ? "online" : "offline"]
        if chat.unreadCount > 0 {
            parts.append("\(chat.unreadCount) unread")
        }
        return parts.joined(separator: ", ")
    }

    private var emptyListView: some View {
        VStack(spacing: SeeleSpacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: SeeleSpacing.iconSizeXL, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)
                .accessibilityHidden(true)

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
