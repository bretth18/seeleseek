import SwiftUI

#if DEBUG
@MainActor
enum PreviewData {
    static var connectedAppState: AppState {
        let state = AppState()
        state.connection.setConnected(
            username: "previewuser",
            ip: "208.76.170.59",
            greeting: "Welcome to SoulSeek!"
        )
        return state
    }

    static var disconnectedAppState: AppState {
        AppState()
    }

    static var connectingAppState: AppState {
        let state = AppState()
        state.connection.setConnecting()
        state.connection.loginUsername = "testuser"
        return state
    }

    static var errorAppState: AppState {
        let state = AppState()
        state.connection.setError("Invalid username or password")
        state.connection.loginUsername = "testuser"
        return state
    }

    static var sampleUsers: [User] {
        [
            User(username: "musiclover42", status: .online, isPrivileged: true, averageSpeed: 1_500_000, fileCount: 15000, folderCount: 500),
            User(username: "vinylcollector", status: .online, isPrivileged: false, averageSpeed: 800_000, fileCount: 8500, folderCount: 200),
            User(username: "jazzfan", status: .away, isPrivileged: false, averageSpeed: 500_000, fileCount: 3200, folderCount: 150),
            User(username: "classicalmaster", status: .offline, isPrivileged: true, averageSpeed: 2_000_000, fileCount: 25000, folderCount: 1200),
        ]
    }
}

// MARK: - Preview Container

@MainActor
struct PreviewContainer<Content: View>: View {
    let appState: AppState
    let content: Content

    init(state: AppState, @ViewBuilder content: () -> Content) {
        self.appState = state
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.appState, appState)
            .preferredColorScheme(.dark)
    }
}

// MARK: - Device Preview

struct DevicePreview<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .preferredColorScheme(.dark)
    }
}
#endif
