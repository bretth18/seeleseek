import AppIntents
import SeeleseekCore

struct CheckUserStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check User Status"
    static let description = IntentDescription("Check if a SoulSeek user is online, away, or offline.")

    @Parameter(title: "Username")
    var username: String

    @Dependency
    var appState: AppState

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let connected = await MainActor.run {
            appState.connection.connectionStatus == .connected
        }
        guard connected else {
            throw IntentError.notConnected
        }

        // checkUserOnlineStatus is @MainActor async — Swift hops automatically
        let (status, privileged) = try await appState.networkClient.checkUserOnlineStatus(username)

        var description = status.description
        if privileged {
            description += " (privileged)"
        }
        return .result(value: description)
    }

    static let openAppWhenRun: Bool = false
}
