import SwiftUI

struct ChatView: View {
    @Environment(\.appState) private var appState
    @State private var showRoomList = false

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

    private var chatSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    showRoomList = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
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
                        sectionHeader("Rooms")

                        ForEach(chatState.joinedRooms) { room in
                            chatListRow(
                                title: room.name,
                                subtitle: "\(room.userCount) users",
                                icon: "person.3",
                                unread: room.unreadCount,
                                isSelected: chatState.selectedRoom == room.name
                            ) {
                                chatState.selectRoom(room.name)
                            }
                        }
                    }

                    // Private Chats
                    if !chatState.privateChats.isEmpty {
                        sectionHeader("Messages")

                        ForEach(chatState.privateChats) { chat in
                            chatListRow(
                                title: chat.username,
                                subtitle: chat.isOnline ? "Online" : "Offline",
                                icon: "person",
                                unread: chat.unreadCount,
                                isSelected: chatState.selectedPrivateChat == chat.username
                            ) {
                                chatState.selectPrivateChat(chat.username)
                            }
                        }
                    }

                    if chatState.joinedRooms.isEmpty && chatState.privateChats.isEmpty {
                        emptyListView
                    }
                }
            }
        }
        .background(SeeleColors.surface)
        .sheet(isPresented: $showRoomList) {
            RoomListSheet(chatState: chatState, isPresented: $showRoomList)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
    }

    private func chatListRow(
        title: String,
        subtitle: String,
        icon: String,
        unread: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textPrimary)

                    Text(subtitle)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Spacer()

                if unread > 0 {
                    Text("\(unread)")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SeeleColors.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(isSelected ? SeeleColors.surfaceSecondary : .clear)
        }
        .buttonStyle(.plain)
    }

    private var emptyListView: some View {
        VStack(spacing: SeeleSpacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No chats yet")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)

            Button("Join a Room") {
                showRoomList = true
            }
            .font(SeeleTypography.caption)
            .foregroundStyle(SeeleColors.accent)
        }
        .padding(SeeleSpacing.xl)
    }

    @ViewBuilder
    private var chatContent: some View {
        if let room = chatState.currentRoom {
            ChatRoomContentView(room: room, chatState: chatState)
        } else if let chat = chatState.currentPrivateChat {
            PrivateChatContentView(chat: chat, chatState: chatState)
        } else {
            noChatSelectedView
        }
    }

    private var noChatSelectedView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("Select a chat")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Choose a room or start a private conversation")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChatRoomContentView: View {
    let room: ChatRoom
    @Bindable var chatState: ChatState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("\(room.userCount) users online")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

                Spacer()

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

            Divider().background(SeeleColors.surfaceSecondary)

            // Messages
            ScrollView {
                LazyVStack(spacing: SeeleSpacing.sm) {
                    ForEach(room.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(SeeleSpacing.md)
            }

            Divider().background(SeeleColors.surfaceSecondary)

            // Input
            MessageInput(text: $chatState.messageInput) {
                chatState.sendMessage()
            }
        }
    }
}

struct PrivateChatContentView: View {
    let chat: PrivateChat
    @Bindable var chatState: ChatState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(chat.isOnline ? SeeleColors.success : SeeleColors.textTertiary)
                    .frame(width: 8, height: 8)

                Text(chat.username)
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    chatState.closePrivateChat(chat.username)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surface)

            Divider().background(SeeleColors.surfaceSecondary)

            // Messages
            ScrollView {
                LazyVStack(spacing: SeeleSpacing.sm) {
                    ForEach(chat.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(SeeleSpacing.md)
            }

            Divider().background(SeeleColors.surfaceSecondary)

            // Input
            MessageInput(text: $chatState.messageInput) {
                chatState.sendMessage()
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: SeeleSpacing.sm) {
            if message.isOwn {
                Spacer()
            }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 2) {
                if !message.isOwn && !message.isSystem {
                    Text(message.username)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.accent)
                }

                Text(message.content)
                    .font(SeeleTypography.body)
                    .foregroundStyle(message.isSystem ? SeeleColors.textTertiary : SeeleColors.textPrimary)
                    .padding(.horizontal, SeeleSpacing.md)
                    .padding(.vertical, SeeleSpacing.sm)
                    .background(
                        message.isOwn ? SeeleColors.accent.opacity(0.2) :
                        message.isSystem ? .clear : SeeleColors.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))

                Text(message.formattedTime)
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            if !message.isOwn {
                Spacer()
            }
        }
    }
}

struct MessageInput: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            TextField("Type a message...", text: $text)
                .textFieldStyle(.plain)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSend()
                    }
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        text.trimmingCharacters(in: .whitespaces).isEmpty ?
                        SeeleColors.textTertiary : SeeleColors.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface)
    }
}

struct RoomListSheet: View {
    @Bindable var chatState: ChatState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Join a Room")
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(SeeleSpacing.lg)

            // Search
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Search rooms...", text: $chatState.roomSearchQuery)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
            }
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
            .padding(.horizontal, SeeleSpacing.lg)

            Divider()
                .background(SeeleColors.surfaceSecondary)
                .padding(.top, SeeleSpacing.md)

            // Room list
            if chatState.isLoadingRooms {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(SeeleColors.accent)
                Spacer()
            } else if chatState.filteredRooms.isEmpty {
                Spacer()
                Text("No rooms found")
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(chatState.filteredRooms) { room in
                            roomRow(room)
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .background(SeeleColors.background)
        .onAppear {
            chatState.requestRoomList()
        }
    }

    private func roomRow(_ room: ChatRoom) -> some View {
        let isJoined = chatState.joinedRooms.contains { $0.name == room.name }

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text("\(room.userCount) users")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
            }

            Spacer()

            if isJoined {
                Text("Joined")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.success)
            } else {
                Button("Join") {
                    chatState.joinRoom(room.name)
                    isPresented = false
                }
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface)
    }
}

#Preview {
    ChatView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 600)
}
