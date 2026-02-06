import SwiftUI

struct RoomUserListPanel: View {
    let room: ChatRoom
    var chatState: ChatState
    var appState: AppState

    var filteredUsers: [String] {
        let query = chatState.userListSearchQuery
        let users = room.users.sorted()
        if query.isEmpty { return users }
        return users.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Users")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                Text("\(room.userCount)")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)

            // Search
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Filter...", text: Bindable(chatState).userListSearchQuery)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.xs)
            .background(SeeleColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusSM, style: .continuous))
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.bottom, SeeleSpacing.sm)

            Divider().background(SeeleColors.surfaceSecondary)

            // User list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredUsers, id: \.self) { username in
                        userRow(username)
                    }
                }
            }
        }
        .background(SeeleColors.surface)
    }

    private func userRow(_ username: String) -> some View {
        let isOwner = room.owner == username
        let isOp = room.operators.contains(username)

        return HStack(spacing: SeeleSpacing.sm) {
            Circle()
                .fill(SeeleColors.success)
                .frame(width: SeeleSpacing.statusDotSmall, height: SeeleSpacing.statusDotSmall)

            Text(username)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)

            if isOwner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(SeeleColors.warning)
            } else if isOp {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, SeeleSpacing.sm)
        .padding(.vertical, SeeleSpacing.xs)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                Task { await appState.socialState.loadProfile(for: username) }
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }

            Button {
                chatState.selectPrivateChat(username)
            } label: {
                Label("Send Message", systemImage: "envelope")
            }

            Button {
                appState.browseState.browseUser(username)
            } label: {
                Label("Browse Files", systemImage: "folder")
            }

            Button {
                Task { await appState.socialState.addBuddy(username) }
            } label: {
                Label("Add Buddy", systemImage: "person.badge.plus")
            }

            // Owner/operator actions for private rooms
            if room.isPrivate && chatState.isOwner(of: room.name) {
                Divider()

                if !isOp {
                    Button {
                        chatState.addOperator(room: room.name, username: username)
                    } label: {
                        Label("Make Operator", systemImage: "wrench")
                    }
                } else {
                    Button {
                        chatState.removeOperator(room: room.name, username: username)
                    } label: {
                        Label("Remove Operator", systemImage: "wrench.fill")
                    }
                }

                Button(role: .destructive) {
                    chatState.removeMember(room: room.name, username: username)
                } label: {
                    Label("Remove from Room", systemImage: "person.badge.minus")
                }
            }
        }
    }
}
