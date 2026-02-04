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

    // MARK: - Sample Files

    static var sampleSharedFiles: [SharedFile] {
        [
            SharedFile(filename: "Music\\Albums\\Pink Floyd - The Dark Side of the Moon (1973)\\01 - Speak to Me.flac", size: 15_234_567, bitrate: 1411, duration: 68, isDirectory: false),
            SharedFile(filename: "Music\\Albums\\Pink Floyd - The Dark Side of the Moon (1973)\\02 - Breathe.flac", size: 24_567_890, bitrate: 1411, duration: 163, isDirectory: false),
            SharedFile(filename: "Music\\Albums\\Radiohead - OK Computer (1997)\\01 - Airbag.mp3", size: 8_234_567, bitrate: 320, duration: 284, isDirectory: false),
            SharedFile(filename: "Music\\Albums\\Radiohead - OK Computer (1997)\\02 - Paranoid Android.mp3", size: 12_456_789, bitrate: 320, duration: 384, isDirectory: false),
            SharedFile(filename: "Music\\Albums\\Miles Davis - Kind of Blue (1959)\\01 - So What.mp3", size: 9_876_543, bitrate: 256, duration: 562, isDirectory: false),
        ]
    }

    static var sampleFolderStructure: [SharedFile] {
        [
            SharedFile(
                filename: "Music",
                isDirectory: true,
                children: [
                    SharedFile(
                        filename: "Music\\Albums",
                        isDirectory: true,
                        children: [
                            SharedFile(
                                filename: "Music\\Albums\\Pink Floyd - The Dark Side of the Moon (1973)",
                                isDirectory: true,
                                children: [
                                    SharedFile(filename: "Music\\Albums\\Pink Floyd - The Dark Side of the Moon (1973)\\01 - Speak to Me.flac", size: 15_234_567, bitrate: 1411, duration: 68),
                                    SharedFile(filename: "Music\\Albums\\Pink Floyd - The Dark Side of the Moon (1973)\\02 - Breathe.flac", size: 24_567_890, bitrate: 1411, duration: 163),
                                    SharedFile(filename: "Music\\Albums\\Pink Floyd - The Dark Side of the Moon (1973)\\03 - On the Run.flac", size: 18_123_456, bitrate: 1411, duration: 225),
                                ]
                            ),
                            SharedFile(
                                filename: "Music\\Albums\\Radiohead - OK Computer (1997)",
                                isDirectory: true,
                                children: [
                                    SharedFile(filename: "Music\\Albums\\Radiohead - OK Computer (1997)\\01 - Airbag.mp3", size: 8_234_567, bitrate: 320, duration: 284),
                                    SharedFile(filename: "Music\\Albums\\Radiohead - OK Computer (1997)\\02 - Paranoid Android.mp3", size: 12_456_789, bitrate: 320, duration: 384),
                                ]
                            ),
                        ]
                    ),
                    SharedFile(
                        filename: "Music\\Singles",
                        isDirectory: true,
                        children: [
                            SharedFile(filename: "Music\\Singles\\Aphex Twin - Windowlicker.mp3", size: 7_654_321, bitrate: 320, duration: 378),
                        ]
                    ),
                ]
            ),
        ]
    }

    // MARK: - Sample Peer Connections

    static var samplePeerConnections: [PeerConnectionPool.PeerConnectionInfo] {
        [
            PeerConnectionPool.PeerConnectionInfo(
                id: "musiclover42-1",
                username: "musiclover42",
                ip: "192.168.1.100",
                port: 2234,
                state: .connected,
                connectionType: .peer,
                bytesReceived: 45_678_901,
                bytesSent: 12_345_678,
                connectedAt: Date().addingTimeInterval(-3600),
                lastActivity: Date(),
                currentSpeed: 125_000
            ),
            PeerConnectionPool.PeerConnectionInfo(
                id: "vinylcollector-2",
                username: "vinylcollector",
                ip: "10.0.0.55",
                port: 2235,
                state: .connected,
                connectionType: .peer,
                bytesReceived: 23_456_789,
                bytesSent: 5_678_901,
                connectedAt: Date().addingTimeInterval(-1800),
                lastActivity: Date().addingTimeInterval(-60),
                currentSpeed: 85_000
            ),
            PeerConnectionPool.PeerConnectionInfo(
                id: "jazzfan-3",
                username: "jazzfan",
                ip: "172.16.0.25",
                port: 2236,
                state: .connecting,
                connectionType: .peer,
                connectedAt: nil,
                currentSpeed: 0
            ),
        ]
    }

    // MARK: - Sample Speed Samples

    static var sampleSpeedSamples: [PeerConnectionPool.SpeedSample] {
        let now = Date()
        return (0..<60).map { i in
            let time = now.addingTimeInterval(-Double(60 - i))
            let baseDownload = 100_000.0 + Double.random(in: -30000...30000)
            let baseUpload = 50_000.0 + Double.random(in: -15000...15000)
            return PeerConnectionPool.SpeedSample(
                timestamp: time,
                downloadSpeed: max(0, baseDownload + sin(Double(i) * 0.3) * 50000),
                uploadSpeed: max(0, baseUpload + cos(Double(i) * 0.2) * 25000)
            )
        }
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
