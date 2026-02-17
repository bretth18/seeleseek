import SwiftUI
import os

/// Model representing a single wishlist entry
struct WishlistItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let query: String
    let createdAt: Date
    var enabled: Bool
    var lastSearchedAt: Date?
    var resultCount: Int

    init(
        id: UUID = UUID(),
        query: String,
        createdAt: Date = Date(),
        enabled: Bool = true,
        lastSearchedAt: Date? = nil,
        resultCount: Int = 0
    ) {
        self.id = id
        self.query = query
        self.createdAt = createdAt
        self.enabled = enabled
        self.lastSearchedAt = lastSearchedAt
        self.resultCount = resultCount
    }
}

@Observable
@MainActor
final class WishlistState {
    // MARK: - Data
    var items: [WishlistItem] = []
    var results: [UUID: [SearchResult]] = [:]

    // MARK: - Input
    var newQuery: String = ""

    // MARK: - Expanded item (for viewing results)
    var expandedItemId: UUID?

    // MARK: - Scheduler
    private var searchInterval: UInt32 = 720  // Server-provided (seconds)
    private var schedulerTask: Task<Void, Never>?
    private var tokenToWishlistId: [UInt32: UUID] = [:]
    private var nextToken: UInt32 = 0x8000_0000
    private var rotationIndex: Int = 0

    // MARK: - Network
    weak var networkClient: NetworkClient?

    private let logger = Logger(subsystem: "com.seeleseek", category: "WishlistState")

    // MARK: - Token Management

    /// Check if a search token belongs to a wishlist search
    func isWishlistToken(_ token: UInt32) -> Bool {
        let result = token >= 0x8000_0000
        if result {
            logger.info("isWishlistToken: token=\(String(format: "0x%08X", token)) → YES, mapped=\(self.tokenToWishlistId[token] != nil)")
        }
        return result
    }

    private func nextWishlistToken() -> UInt32 {
        let token = nextToken
        nextToken &+= 1
        if nextToken < 0x8000_0000 {
            nextToken = 0x8000_0000
        }
        return token
    }

    // MARK: - Setup

    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client

        client.onWishlistInterval = { [weak self] interval in
            self?.logger.info("Wishlist interval from server: \(interval)s")
            self?.searchInterval = interval
            self?.restartScheduler()
        }
    }

    // MARK: - Persistence

    func loadFromDatabase() async {
        do {
            let loaded = try await WishlistRepository.fetchAll()
            items = loaded
            logger.info("Loaded \(loaded.count) wishlist items from database")
        } catch {
            logger.error("Failed to load wishlists: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    func addItem() {
        let query = newQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        guard !items.contains(where: { $0.query.lowercased() == query.lowercased() }) else { return }

        let item = WishlistItem(query: query)
        items.append(item)
        newQuery = ""

        Task {
            do {
                try await WishlistRepository.save(item)
            } catch {
                logger.error("Failed to save wishlist item: \(error.localizedDescription)")
            }
        }

        // Send first search immediately
        searchNow(item: item)
        restartScheduler()
    }

    func removeItem(id: UUID) {
        tokenToWishlistId = tokenToWishlistId.filter { $0.value != id }
        items.removeAll { $0.id == id }
        results.removeValue(forKey: id)

        Task {
            do {
                try await WishlistRepository.delete(id: id)
            } catch {
                logger.error("Failed to delete wishlist item: \(error.localizedDescription)")
            }
        }

        restartScheduler()
    }

    func toggleEnabled(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].enabled.toggle()

        let item = items[index]
        Task {
            do {
                try await WishlistRepository.save(item)
            } catch {
                logger.error("Failed to update wishlist item: \(error.localizedDescription)")
            }
        }

        restartScheduler()
    }

    func searchNow(item: WishlistItem) {
        guard let client = networkClient else {
            logger.error("searchNow: networkClient is nil!")
            return
        }

        let token = nextWishlistToken()
        tokenToWishlistId[token] = item.id
        logger.info("searchNow: query='\(item.query)' token=\(String(format: "0x%08X", token)) itemId=\(item.id) activeTokens=\(self.tokenToWishlistId.count)")

        // Clear stale results from previous search cycle
        results[item.id] = []

        Task {
            do {
                try await client.addWishlistSearch(query: item.query, token: token)
                logger.info("Wishlist search sent: '\(item.query)' token=\(token)")
            } catch {
                logger.error("Failed to send wishlist search: \(error.localizedDescription)")
            }
        }

        // Update last searched time and reset result count
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].lastSearchedAt = Date()
            items[index].resultCount = 0
            let updated = items[index]
            Task {
                try? await WishlistRepository.updateLastSearched(
                    id: updated.id,
                    resultCount: 0
                )
            }
        }
    }

    // MARK: - Result Handling

    func handleSearchResults(token: UInt32, results: [SearchResult]) {
        logger.info("handleSearchResults: token=\(String(format: "0x%08X", token)) results=\(results.count) knownTokens=\(self.tokenToWishlistId.keys.map { String(format: "0x%08X", $0) })")
        guard let itemId = tokenToWishlistId[token] else {
            logger.warning("No wishlist item for token \(String(format: "0x%08X", token))")
            return
        }

        // Accumulate results
        var existing = self.results[itemId] ?? []
        existing.append(contentsOf: results)
        self.results[itemId] = existing

        logger.info("Wishlist results: +\(results.count) for item \(itemId) (total: \(existing.count))")

        // Update result count on the item
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].resultCount = existing.count
            let updated = items[index]
            Task {
                try? await WishlistRepository.updateLastSearched(
                    id: updated.id,
                    resultCount: updated.resultCount
                )
            }
        }
    }

    // MARK: - Scheduler

    func startScheduler() {
        restartScheduler()
    }

    private func restartScheduler() {
        schedulerTask?.cancel()

        let enabledItems = items.filter(\.enabled)
        guard !enabledItems.isEmpty else {
            logger.info("No enabled wishlist items, scheduler stopped")
            return
        }

        // Spread searches evenly: interval / count
        let perItemInterval = max(Double(searchInterval) / Double(enabledItems.count), 30)

        logger.info("Wishlist scheduler: \(enabledItems.count) items, \(perItemInterval)s between searches")

        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(perItemInterval))
                guard !Task.isCancelled else { break }
                self?.tickScheduler()
            }
        }
    }

    private func tickScheduler() {
        let enabledItems = items.filter(\.enabled)
        guard !enabledItems.isEmpty else { return }

        let index = rotationIndex % enabledItems.count
        let item = enabledItems[index]
        rotationIndex += 1

        searchNow(item: item)
    }

    // MARK: - Helpers

    func relativeTime(from date: Date?) -> String {
        guard let date else { return "Never" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
