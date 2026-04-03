import AppIntents
import SeeleseekCore

struct SendRoomMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Room Message"
    static var description = IntentDescription("Send a message to a SoulSeek chat room.")

    @Parameter(title: "Room")
    var room: String

    @Parameter(title: "Message")
    var message: String

    @Dependency
    var appState: AppState

    func perform() async throws -> some IntentResult {
        let connected = await MainActor.run {
            appState.connection.connectionStatus == .connected
        }
        guard connected else {
            throw IntentError.notConnected
        }

        let truncated = String(message.prefix(2000))
        try await appState.networkClient.sendRoomMessage(room, message: truncated)
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

struct SendPrivateMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Private Message"
    static var description = IntentDescription("Send a private message to a SoulSeek user.")

    @Parameter(title: "Username")
    var username: String

    @Parameter(title: "Message")
    var message: String

    @Dependency
    var appState: AppState

    func perform() async throws -> some IntentResult {
        let connected = await MainActor.run {
            appState.connection.connectionStatus == .connected
        }
        guard connected else {
            throw IntentError.notConnected
        }

        let truncated = String(message.prefix(2000))
        try await appState.networkClient.sendPrivateMessage(to: username, message: truncated)
        return .result()
    }

    static var openAppWhenRun: Bool = false
}
