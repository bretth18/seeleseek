import SwiftUI
import AppKit

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
                // Browse files triggers AppState browse
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

// MARK: - Room Content View

struct ChatRoomContentView: View {
    let room: ChatRoom
    @Bindable var chatState: ChatState
    var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Main content
            VStack(spacing: 0) {
                roomHeader

                // Ticker strip
                if !room.tickers.isEmpty {
                    tickerStrip
                }

                Divider().background(SeeleColors.surfaceSecondary)

                // Messages
                ScrollView {
                    LazyVStack(spacing: SeeleSpacing.sm) {
                        ForEach(room.messages) { message in
                            MessageBubble(message: message, chatState: chatState, appState: appState)
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

            // User list panel
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

            // User list toggle
            Button {
                chatState.showUserListPanel.toggle()
            } label: {
                Image(systemName: "person.2")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(chatState.showUserListPanel ? SeeleColors.accent : SeeleColors.textSecondary)
            }
            .buttonStyle(.plain)

            // Management gear (for private room owner/operator)
            if room.isPrivate && (chatState.isOwner(of: room.name) || chatState.isOperator(of: room.name)) {
                Button {
                    chatState.showRoomManagement = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Leave button
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
            // Header with label and collapse toggle
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

                Spacer()

                Button {
                    chatState.tickersCollapsed.toggle()
                } label: {
                    Image(systemName: chatState.tickersCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.xxs)

            // Ticker content (collapsible)
            if !chatState.tickersCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SeeleSpacing.lg) {
                        ForEach(Array(room.tickers), id: \.key) { username, ticker in
                            HStack(spacing: SeeleSpacing.xs) {
                                Text(username)
                                    .font(SeeleTypography.caption2)
                                    .foregroundStyle(SeeleColors.accent)
                                Text(ticker)
                                    .font(SeeleTypography.caption2)
                                    .foregroundStyle(SeeleColors.textTertiary)
                                    .lineLimit(1)
                            }
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

// MARK: - Private Chat Content View

struct PrivateChatContentView: View {
    let chat: PrivateChat
    @Bindable var chatState: ChatState
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(chat.isOnline ? SeeleColors.success : SeeleColors.textTertiary)
                    .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)

                Text(chat.username)
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    chatState.closePrivateChat(chat.username)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: SeeleSpacing.iconSizeXS))
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
                        MessageBubble(message: message, chatState: chatState, appState: appState)
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

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var chatState: ChatState
    var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: SeeleSpacing.sm) {
            if message.isOwn {
                Spacer()
            }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: SeeleSpacing.xxs) {
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
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                    .contextMenu {
                        if !message.isSystem {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            } label: {
                                Label("Copy Message", systemImage: "doc.on.doc")
                            }

                            if !message.isOwn {
                                Button {
                                    chatState.messageInput = "@\(message.username) "
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }

                                Divider()

                                Button {
                                    chatState.selectPrivateChat(message.username)
                                } label: {
                                    Label("Send Message", systemImage: "envelope")
                                }

                                Button {
                                    appState.browseState.browseUser(message.username)
                                } label: {
                                    Label("Browse Files", systemImage: "folder")
                                }
                            }
                        }
                    }

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

// MARK: - Message Input

struct MessageInput: View {
    @Binding var text: String
    let onSend: () -> Void

    private static let maxLength = 2000

    var body: some View {
        VStack(spacing: 0) {
            // Character count warning
            if text.count > 1500 {
                HStack {
                    Spacer()
                    Text("\(text.count)/\(Self.maxLength)")
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(text.count > 1900 ? SeeleColors.error : SeeleColors.warning)
                }
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.top, SeeleSpacing.xs)
            }

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
                        .font(.system(size: SeeleSpacing.iconSizeLarge))
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespaces).isEmpty ?
                            SeeleColors.textTertiary : SeeleColors.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(SeeleSpacing.md)
        }
        .background(SeeleColors.surface)
    }
}

#Preview {
    ChatView()
        .environment(\.appState, AppState())
        .frame(width: 900, height: 600)
}
