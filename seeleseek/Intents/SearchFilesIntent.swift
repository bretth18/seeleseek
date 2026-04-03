import AppIntents
import SeeleseekCore

struct SearchFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Files"
    static var description = IntentDescription("Search for files on the SoulSeek network. Returns results after waiting for responses.")

    @Parameter(title: "Query")
    var query: String

    @Parameter(title: "Wait Duration (seconds)", default: 10)
    var waitDuration: Int

    @Parameter(title: "Max Results", default: 50)
    var maxResults: Int

    @Dependency
    var appState: AppState

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let token = UInt32.random(in: 1..<0x8000_0000)
        let clampedWait = min(max(waitDuration, 3), 30)
        let clampedMax = min(max(maxResults, 1), 200)

        // Check connection and set up search on MainActor
        try await MainActor.run {
            guard appState.connection.connectionStatus == .connected else {
                throw IntentError.notConnected
            }
            appState.searchState.searchQuery = query
            appState.searchState.startSearch(token: token)
        }

        // Send request — @MainActor async, Swift hops automatically
        try await appState.networkClient.search(query: query, token: token)

        // Wait for results to accumulate from peers
        try await Task.sleep(for: .seconds(clampedWait))

        // Collect results on MainActor
        let results = await MainActor.run {
            appState.searchState.markSearchComplete(token: token)

            guard let searchQuery = appState.searchState.searches.first(where: { $0.token == token }) else {
                return [String]()
            }

            return Array(
                searchQuery.results
                    .prefix(clampedMax)
                    .map { "\($0.username): \($0.displayFilename) (\($0.formattedSize))" }
            )
        }

        return .result(value: results)
    }

    static var openAppWhenRun: Bool = false
}
