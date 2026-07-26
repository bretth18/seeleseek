import SwiftUI
import SeeleseekCore

/// Reusable context menu items for user actions (View Profile, Browse Files, Send Message, Add Buddy)
/// Used across TransferRow, HistoryRow, RoomUserListPanel, ChatView, SearchResultRow, etc.
struct UserContextMenuItems: View {
    @Environment(\.appState) private var appState
    let username: String
    var showAddBuddy: Bool = false
    var showBlock: Bool = false
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

        if showBlock {
            if appState.socialState.isBlocked(username) {
                Button {
                    Task { await appState.socialState.unblockUser(username) }
                } label: {
                    Label("Unblock User", systemImage: "checkmark.shield")
                }
            } else {
                Button(role: .destructive) {
                    Task { await appState.socialState.blockUser(username) }
                } label: {
                    Label("Block from Connecting", systemImage: "nosign")
                }
            }
        }
    }
}

/// Rotor actions that mirror `UserContextMenuItems`. Context menus
/// are not visible to VoiceOver. A row that shows the menu items in
/// a context menu must also place this view inside its
/// `.accessibilityActions {}` block so the same commands stay
/// available to VoiceOver users.
struct UserAccessibilityActions: View {
    @Environment(\.appState) private var appState
    let username: String
    var showAddBuddy: Bool = false
    var showBlock: Bool = false
    var navigateOnBrowse: Bool = false
    var navigateOnMessage: Bool = false

    var body: some View {
        Button("View Profile") {
            Task { await appState.socialState.loadProfile(for: username) }
        }

        Button("Browse Files") {
            appState.browseState.browseUser(username)
            if navigateOnBrowse { appState.sidebarSelection = .browse }
        }

        Button("Send Message") {
            appState.chatState.selectPrivateChat(username)
            if navigateOnMessage { appState.sidebarSelection = .chat }
        }

        if showAddBuddy {
            Button("Add Buddy") {
                Task { await appState.socialState.addBuddy(username) }
            }
        }

        if appState.socialState.isIgnored(username) {
            Button("Unignore User") {
                Task { await appState.socialState.unignoreUser(username) }
            }
        } else {
            Button("Ignore User") {
                Task { await appState.socialState.ignoreUser(username) }
            }
        }

        if showBlock {
            if appState.socialState.isBlocked(username) {
                Button("Unblock User") {
                    Task { await appState.socialState.unblockUser(username) }
                }
            } else {
                Button("Block from Connecting") {
                    Task { await appState.socialState.blockUser(username) }
                }
            }
        }
    }
}
