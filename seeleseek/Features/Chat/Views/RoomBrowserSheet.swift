import SwiftUI

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

                Spacer()

                Button {
                    chatState.showCreateRoom.toggle()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.accent)
                }
                .buttonStyle(.plain)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeMedium))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
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

            // Room list
            if chatState.isLoadingRooms {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(SeeleColors.accent)
                Spacer()
            } else if chatState.filteredRooms.isEmpty {
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
                        ForEach(chatState.filteredRooms) { room in
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
        HStack(spacing: SeeleSpacing.sm) {
            ForEach(RoomListTab.allCases, id: \.self) { tab in
                Button {
                    chatState.roomListTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(
                            chatState.roomListTab == tab ? SeeleColors.accent : SeeleColors.textSecondary
                        )
                        .padding(.horizontal, SeeleSpacing.md)
                        .padding(.vertical, SeeleSpacing.xs)
                        .background(
                            chatState.roomListTab == tab ?
                            SeeleColors.accent.opacity(SeeleColors.alphaLight) : .clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusSM, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm)
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

                Button("Create") {
                    chatState.createRoom()
                    if chatState.createRoomError == nil {
                        isPresented = false
                    }
                }
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textOnAccent)
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.vertical, SeeleSpacing.sm)
                .background(SeeleColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                .buttonStyle(.plain)
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
            // Room icon
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

            Spacer()

            if isJoined {
                Text("Joined")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.success)
            } else if isOwned {
                Button("Manage") {
                    chatState.joinRoom(room.name, isPrivate: true)
                    isPresented = false
                }
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.accent)
                .buttonStyle(.plain)
            } else {
                Button("Join") {
                    chatState.joinRoom(room.name, isPrivate: room.isPrivate)
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
