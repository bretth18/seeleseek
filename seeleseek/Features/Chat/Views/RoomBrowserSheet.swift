import SwiftUI
import SeeleseekCore

struct RoomBrowserSheet: View {
    @Bindable var chatState: ChatState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rooms")
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    chatState.showCreateRoom.toggle()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create a room")

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeMedium))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            .padding(SeeleSpacing.lg)

            // Create room inline section
            if chatState.showCreateRoom {
                createRoomSection
            }

            // Tab bar
            tabBar

            // Search
            StandardSearchField(
                text: $chatState.roomSearchQuery,
                placeholder: "Search rooms..."
            )
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.bottom, SeeleSpacing.sm)

            Divider().background(SeeleColors.surfaceSecondary)

            // Room list — filter once per body eval instead of twice
            // (isEmpty check + ForEach).
            let rooms = chatState.filteredRooms

            if chatState.isLoadingRooms {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(SeeleColors.accent)
                    .accessibilityLabel("Loading rooms")
                Spacer()
            } else if let error = chatState.roomListError {
                Spacer()
                VStack(spacing: SeeleSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: SeeleSpacing.iconSizeLarge))
                        .foregroundStyle(SeeleColors.warning)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        chatState.requestRoomList()
                    }
                    .buttonStyle(.seelePrimary(.small))
                }
                .padding(SeeleSpacing.lg)
                Spacer()
            } else if rooms.isEmpty {
                Spacer()
                VStack(spacing: SeeleSpacing.sm) {
                    Text("No rooms found")
                        .font(SeeleTypography.subheadline)
                        .foregroundStyle(SeeleColors.textSecondary)
                    if chatState.roomListTab != .all {
                        Text("Try switching to \"All\" tab")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
                        ForEach(rooms) { room in
                            roomRow(room)
                        }
                    }
                }
            }
        }
        .frame(width: 440, height: 550)
        .background(SeeleColors.background)
        .onAppear {
            chatState.requestRoomList()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        StandardTabBar(selection: $chatState.roomListTab, showsBackground: false)
            .padding(.horizontal, SeeleSpacing.xs)
    }

    // MARK: - Create Room

    private var createRoomSection: some View {
        VStack(spacing: SeeleSpacing.sm) {
            HStack(spacing: SeeleSpacing.sm) {
                TextField("Room name", text: $chatState.createRoomName)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .padding(.horizontal, SeeleSpacing.md)
                    .padding(.vertical, SeeleSpacing.sm)
                    .background(SeeleColors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                    .accessibilityLabel("Room name")

                Button("Create") {
                    chatState.createRoom()
                    if chatState.createRoomError == nil {
                        isPresented = false
                    }
                }
                .buttonStyle(.seelePrimary(.small))
            }

            HStack {
                Toggle(isOn: $chatState.createRoomIsPrivate) {
                    Text("Private room")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .toggleStyle(SeeleToggleStyle())

                Spacer()

                if let error = chatState.createRoomError {
                    Text(error)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.error)
                }
            }
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.bottom, SeeleSpacing.sm)
    }

    // MARK: - Room Row

    private func roomRow(_ room: ChatRoom) -> some View {
        let isJoined = chatState.joinedRooms.contains { $0.name == room.name }
        let isOwned = chatState.ownedPrivateRooms.contains { $0.name == room.name }

        return HStack {
            HStack {
                if isOwned {
                    Image(systemName: "crown.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.warning)
                        .frame(width: SeeleSpacing.xl)
                } else if room.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.textTertiary)
                        .frame(width: SeeleSpacing.xl)
                }

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(room.name)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("\(room.userCount) users")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(roomRowAccessibilityLabel(room, isJoined: isJoined, isOwned: isOwned))
            .accessibilityAddTraits(.isStaticText)

            Spacer()

            if isJoined {
                Text("Joined")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.success)
                    // The combined info label already speaks "joined".
                    .accessibilityHidden(true)
            } else if isOwned {
                Button("Manage") {
                    chatState.joinRoom(room.name, isPrivate: true)
                    isPresented = false
                }
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.accent)
                .buttonStyle(.plain)
                .accessibilityLabel("Manage \(room.name)")
            } else {
                Button("Join") {
                    chatState.joinRoom(room.name, isPrivate: room.isPrivate)
                    isPresented = false
                }
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.accent)
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(room.name)")
            }
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface)
    }

    private func roomRowAccessibilityLabel(_ room: ChatRoom, isJoined: Bool, isOwned: Bool) -> String {
        var parts: [String] = [room.name]
        if isOwned {
            parts.append("owned room")
        } else if room.isPrivate {
            parts.append("private room")
        }
        parts.append("\(room.userCount) users")
        if isJoined {
            parts.append("joined")
        }
        return parts.joined(separator: ", ")
    }
}
