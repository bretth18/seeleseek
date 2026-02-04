import SwiftUI
import os

@Observable
@MainActor
final class BrowseState {
    // MARK: - Tabbed Browses
    /// All active browse tabs
    var browses: [UserShares] = []

    /// Currently selected browse tab index
    var selectedBrowseIndex: Int = 0

    /// The currently selected browse (convenience accessor)
    var currentBrowse: UserShares? {
        get {
            guard selectedBrowseIndex >= 0, selectedBrowseIndex < browses.count else { return nil }
            return browses[selectedBrowseIndex]
        }
        set {
            guard selectedBrowseIndex >= 0, selectedBrowseIndex < browses.count, let newValue else { return }
            browses[selectedBrowseIndex] = newValue
        }
    }

    // MARK: - Input State
    var currentUser: String = ""

    // MARK: - UI State
    var expandedFolders: Set<UUID> = []
    var selectedFile: SharedFile?

    // MARK: - History
    var browseHistory: [String] = []

    // MARK: - Active Tasks (kept alive to prevent cancellation)
    private var activeBrowseTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Network Client Reference
    weak var networkClient: NetworkClient?

    // MARK: - Cache Settings
    private let browseCacheTTL: TimeInterval = 86400 // 24 hours
    private let logger = Logger(subsystem: "com.seeleseek", category: "BrowseState")

    // MARK: - Computed Properties

    /// Legacy compatibility - returns current browse
    var userShares: UserShares? {
        currentBrowse
    }

    var isLoading: Bool {
        currentBrowse?.isLoading ?? false
    }

    var hasError: Bool {
        currentBrowse?.error != nil
    }

    var canBrowse: Bool {
        !currentUser.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Setup

    func configure(networkClient: NetworkClient) {
        self.networkClient = networkClient
        logger.info("Configured with NetworkClient")

        // Load cached usernames for history
        Task {
            await loadCachedHistory()
        }
    }

    // MARK: - Cache Operations

    /// Load browse history from cached usernames
    private func loadCachedHistory() async {
        do {
            let cachedUsers = try await BrowseRepository.fetchCachedUsernames()
            // Merge with existing history, prioritizing cached
            for username in cachedUsers {
                if !browseHistory.contains(where: { $0.lowercased() == username.lowercased() }) {
                    browseHistory.append(username)
                }
            }
            if browseHistory.count > 20 {
                browseHistory = Array(browseHistory.prefix(20))
            }
            logger.info("Loaded \(cachedUsers.count) cached usernames for browse history")
        } catch {
            logger.error("Failed to load cached browse history: \(error.localizedDescription)")
        }
    }

    /// Check for cached browse data
    private func checkCache(for username: String) async -> UserShares? {
        do {
            guard try await BrowseRepository.isCacheValid(username: username, ttl: browseCacheTTL) else {
                return nil
            }

            if let cached = try await BrowseRepository.fetch(username: username) {
                logger.info("Found cached browse for '\(username)' with \(cached.totalFiles) files")
                return cached
            }
        } catch {
            logger.error("Failed to check browse cache: \(error.localizedDescription)")
        }
        return nil
    }

    /// Save browse results to cache
    private func cacheUserShares(_ userShares: UserShares) {
        Task {
            do {
                try await BrowseRepository.save(userShares)
                logger.debug("Cached browse for '\(userShares.username)' with \(userShares.totalFiles) files")
            } catch {
                logger.error("Failed to cache browse: \(error.localizedDescription)")
            }
        }
    }

    /// Clean up expired browse cache
    func cleanupExpiredCache() {
        Task {
            do {
                try await BrowseRepository.deleteExpired(olderThan: browseCacheTTL)
                logger.debug("Cleaned up expired browse cache")
            } catch {
                logger.error("Failed to cleanup browse cache: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actions

    /// Start browsing a user - creates a new tab and initiates the request
    func browseUser(_ username: String) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else { return }

        currentUser = trimmedUsername

        // Check if we already have a tab for this user
        if let existingIndex = browses.firstIndex(where: { $0.username.lowercased() == trimmedUsername.lowercased() }) {
            // Switch to existing tab
            selectedBrowseIndex = existingIndex

            // If it failed before, retry
            if browses[existingIndex].error != nil {
                browses[existingIndex] = UserShares(username: trimmedUsername)
                startBrowseRequest(for: trimmedUsername, at: existingIndex)
            }
            return
        }

        // Create new browse tab with loading state
        let newBrowse = UserShares(username: trimmedUsername)
        browses.append(newBrowse)
        let newIndex = browses.count - 1
        selectedBrowseIndex = newIndex

        // Add to history
        if !browseHistory.contains(where: { $0.lowercased() == trimmedUsername.lowercased() }) {
            browseHistory.insert(trimmedUsername, at: 0)
            if browseHistory.count > 20 {
                browseHistory.removeLast()
            }
        }

        // Clear UI state for new browse
        expandedFolders = []
        selectedFile = nil

        logger.info("Created new tab for \(trimmedUsername) at index \(newIndex)")

        // Check cache first, then fetch if not cached
        Task {
            if let cached = await checkCache(for: trimmedUsername) {
                // Use cached data
                if newIndex < browses.count && browses[newIndex].username.lowercased() == trimmedUsername.lowercased() {
                    browses[newIndex] = cached
                    logger.info("Using cached browse for \(trimmedUsername)")
                }
            } else {
                // Fetch fresh data
                startBrowseRequest(for: trimmedUsername, at: newIndex)
            }
        }
    }

    /// Start the actual browse request in a detached task (won't be cancelled by view lifecycle)
    private func startBrowseRequest(for username: String, at index: Int) {
        guard let networkClient else {
            logger.error("NetworkClient not configured")
            if index < browses.count {
                browses[index].error = "Not connected"
                browses[index].isLoading = false
            }
            return
        }

        // Get the browse ID for tracking
        guard index < browses.count else { return }
        let browseId = browses[index].id

        // Cancel any existing task for this browse
        activeBrowseTasks[browseId]?.cancel()

        // Start a NEW detached task that won't be cancelled by view lifecycle
        // Using Task.detached ensures the task lives independently of the calling context
        let task = Task { [weak self] in
            self?.logger.info("Starting browse request for \(username)")

            do {
                // This is the actual network call
                let files = try await networkClient.browseUser(username)

                // Update on main actor
                await MainActor.run {
                    guard let self else { return }
                    // Find the browse by ID (index may have changed)
                    if let idx = self.browses.firstIndex(where: { $0.id == browseId }) {
                        self.browses[idx].folders = files
                        self.browses[idx].isLoading = false
                        self.browses[idx].error = nil
                        self.logger.info("Got \(files.count) files for \(username)")

                        // Cache the results
                        self.cacheUserShares(self.browses[idx])
                    }
                    self.activeBrowseTasks.removeValue(forKey: browseId)
                }
            } catch {
                // Check if cancelled
                if Task.isCancelled {
                    self?.logger.info("Browse request cancelled for \(username)")
                    return
                }

                await MainActor.run {
                    guard let self else { return }
                    if let idx = self.browses.firstIndex(where: { $0.id == browseId }) {
                        self.browses[idx].error = "Failed to browse \(username): \(error.localizedDescription)"
                        self.browses[idx].isLoading = false
                        self.logger.error("Browse error for \(username): \(error.localizedDescription)")
                    }
                    self.activeBrowseTasks.removeValue(forKey: browseId)
                }
            }
        }

        activeBrowseTasks[browseId] = task
    }

    /// Close a browse tab
    func closeBrowse(at index: Int) {
        guard index >= 0, index < browses.count else { return }

        let browse = browses[index]

        // Cancel any active task
        activeBrowseTasks[browse.id]?.cancel()
        activeBrowseTasks.removeValue(forKey: browse.id)

        browses.remove(at: index)

        // Adjust selected index
        if selectedBrowseIndex >= browses.count {
            selectedBrowseIndex = max(0, browses.count - 1)
        }

        logger.info("Closed tab at index \(index)")
    }

    /// Select a browse tab
    func selectBrowse(at index: Int) {
        guard index >= 0, index < browses.count else { return }
        selectedBrowseIndex = index
        currentUser = browses[index].username

        // Reset UI state when switching tabs
        expandedFolders = []
        selectedFile = nil
    }

    /// Retry a failed browse
    func retryCurrentBrowse() {
        guard let browse = currentBrowse, browse.error != nil else { return }

        // Reset state
        if selectedBrowseIndex < browses.count {
            browses[selectedBrowseIndex] = UserShares(username: browse.username)
            startBrowseRequest(for: browse.username, at: selectedBrowseIndex)
        }
    }

    /// Force refresh current browse (bypasses cache)
    func refreshCurrentBrowse() {
        guard let browse = currentBrowse else { return }

        // Clear cache for this user
        Task {
            try? await BrowseRepository.delete(username: browse.username)
        }

        // Reset and refetch
        if selectedBrowseIndex < browses.count {
            browses[selectedBrowseIndex] = UserShares(username: browse.username)
            startBrowseRequest(for: browse.username, at: selectedBrowseIndex)
        }
    }

    // MARK: - UI Actions

    func setShares(_ folders: [SharedFile]) {
        currentBrowse?.folders = folders
        currentBrowse?.isLoading = false
    }

    func setError(_ message: String) {
        currentBrowse?.error = message
        currentBrowse?.isLoading = false
    }

    func toggleFolder(_ id: UUID) {
        if expandedFolders.contains(id) {
            expandedFolders.remove(id)
        } else {
            expandedFolders.insert(id)
        }
    }

    func selectFile(_ file: SharedFile) {
        if file.isDirectory {
            toggleFolder(file.id)
        } else {
            selectedFile = file
        }
    }

    func clear() {
        currentUser = ""
        expandedFolders = []
        selectedFile = nil
    }
}
