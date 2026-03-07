import AppIntents

struct GetConnectionStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Connection Status"
    static var description = IntentDescription("Check if SeeleSeek is connected to the SoulSeek network.")

    @Dependency
    var appState: AppState

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (status, username) = await MainActor.run {
            (appState.connection.connectionStatus.rawValue, appState.connection.username)
        }

        if let username {
            return .result(value: "\(status) as \(username)")
        }
        return .result(value: status)
    }

    static var openAppWhenRun: Bool = false
}
