import SwiftUI

/// Reusable context menu items for user actions (View Profile, Browse Files, Send Message, Add Buddy)
/// Used across TransferRow, HistoryRow, RoomUserListPanel, ChatView, SearchResultRow, etc.
struct UserContextMenuItems: View {
    @Environment(\.appState) private var appState
    let username: String
    var showAddBuddy: Bool = false
    var navigateOnBrowse: Bool = false
    var navigateOnMessage: Bool = false

    var body: some View {
        Button {
            Task { await appState.socialState.loadProfile(for: username) }
        } label: {
            Label("View Profile", systemImage: "person.crop.circle")
        }

        Button {
            appState.browseState.browseUser(username)
            if navigateOnBrowse { appState.sidebarSelection = .browse }
        } label: {
            Label("Browse Files", systemImage: "folder")
        }

        Button {
            appState.chatState.selectPrivateChat(username)
            if navigateOnMessage { appState.sidebarSelection = .chat }
        } label: {
            Label("Send Message", systemImage: "envelope")
        }

        if showAddBuddy {
            Button {
                Task { await appState.socialState.addBuddy(username) }
            } label: {
                Label("Add Buddy", systemImage: "person.badge.plus")
            }
        }

        Divider()

        if appState.socialState.isIgnored(username) {
            Button {
                Task { await appState.socialState.unignoreUser(username) }
            } label: {
                Label("Unignore User", systemImage: "eye")
            }
        } else {
            Button {
                Task { await appState.socialState.ignoreUser(username) }
            } label: {
                Label("Ignore User", systemImage: "eye.slash")
            }
        }
    }
}
