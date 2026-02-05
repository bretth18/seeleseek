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

    /// Target path to auto-expand after browse loads (e.g., "@@music\\Artist\\Album")
    private var targetPath: String?

    /// Current folder path being viewed (nil = show all shares from root)
    /// When set, only shows contents of this specific folder
    var currentFolderPath: String?

    /// The folders to display (filtered by currentFolderPath if set)
    var displayedFolders: [SharedFile] {
        guard let browse = currentBrowse else { return [] }

        // If no folder filter, show all root folders
        guard let folderPath = currentFolderPath else {
            return browse.folders
        }

        // Find the target folder and return its contents
        return findFolder(at: folderPath, in: browse.folders)?.children ?? []
    }

    /// Find a folder by its path in the tree
    private func findFolder(at path: String, in folders: [SharedFile]) -> SharedFile? {
        let pathComponents = path.split(separator: "\\").map(String.init)
        guard !pathComponents.isEmpty else { return nil }

        var currentFiles = folders

        for (index, component) in pathComponents.enumerated() {
            guard let match = currentFiles.first(where: {
                $0.displayName.lowercased() == component.lowercased() ||
                $0.filename.split(separator: "\\").last?.lowercased() == component.lowercased()
            }) else {
                return nil
            }

            if index == pathComponents.count - 1 {
                // Found the target folder
                return match.isDirectory ? match : nil
            }

            // Move to children
            guard let children = match.children else { return nil }
            currentFiles = children
        }

        return nil
    }

    /// Navigate up one folder level (or to root if at top level)
    func navigateUp() {
        guard let path = currentFolderPath else { return }

        let components = path.split(separator: "\\")
        if components.count <= 1 {
            // Already at top level, go to root
            currentFolderPath = nil
        } else {
            // Go up one level
            currentFolderPath = components.dropLast().joined(separator: "\\")
        }
    }

    /// Navigate to root (show all shares)
    func navigateToRoot() {
        currentFolderPath = nil
    }

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
        browseUser(username, targetPath: nil)
    }

    /// Browse a user and auto-expand to a specific folder path
    /// - Parameters:
    ///   - username: The user to browse
    ///   - targetPath: Optional path to auto-expand to (e.g., "@@music\\Artist\\Album\\song.mp3")
    func browseUser(_ username: String, targetPath: String?) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else { return }

        currentUser = trimmedUsername
        self.targetPath = targetPath

        // Extract folder path from target (remove filename if present)
        if let targetPath = targetPath {
            let components = targetPath.split(separator: "\\")
            if components.count > 1 {
                // Set folder path (excluding the filename)
                currentFolderPath = components.dropLast().joined(separator: "\\")
                print("📂 BrowseState: Set currentFolderPath to: \(currentFolderPath ?? "nil")")
            }
        } else {
            currentFolderPath = nil
        }

        // Check if we already have a tab for this user
        if let existingIndex = browses.firstIndex(where: { $0.username.lowercased() == trimmedUsername.lowercased() }) {
            // Switch to existing tab
            selectedBrowseIndex = existingIndex

            // If it failed before, retry
            if browses[existingIndex].error != nil {
                browses[existingIndex] = UserShares(username: trimmedUsername)
                startBrowseRequest(for: trimmedUsername, at: existingIndex)
            } else if targetPath != nil {
                // Check if data needs tree rebuild (flat data has no directories)
                let folders = browses[existingIndex].folders
                let hasTreeStructure = folders.contains { $0.isDirectory }

                if !hasTreeStructure && !folders.isEmpty {
                    // Rebuild tree from flat data
                    print("📂 BrowseState: Rebuilding tree for existing tab (had flat data)")
                    let treeFiles = SharedFile.buildTree(from: folders)
                    browses[existingIndex].folders = treeFiles
                    expandToTargetPath(in: treeFiles)
                } else {
                    // Already has tree structure, just expand
                    expandToTargetPath(in: folders)
                }
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
        print("📂 BrowseState: Created new tab for \(trimmedUsername) at index \(newIndex)")

        // Check cache first, then fetch if not cached
        Task {
            print("📂 BrowseState: Checking cache for \(trimmedUsername)...")
            if let cached = await checkCache(for: trimmedUsername) {
                // Use cached data
                print("📂 BrowseState: Found cache for \(trimmedUsername) with \(cached.folders.count) folders")
                if newIndex < browses.count && browses[newIndex].username.lowercased() == trimmedUsername.lowercased() {
                    browses[newIndex] = cached
                    logger.info("Using cached browse for \(trimmedUsername)")

                    // Auto-expand to target path if set
                    if targetPath != nil {
                        expandToTargetPath(in: cached.folders)
                    }
                }
            } else {
                // Fetch fresh data
                print("📂 BrowseState: No cache for \(trimmedUsername), starting network request...")
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
                // This is the actual network call - returns flat files
                let flatFiles = try await networkClient.browseUser(username)

                // Build hierarchical tree structure (do this off main thread for large file lists)
                let treeFiles = SharedFile.buildTree(from: flatFiles)

                // Pre-compute stats off main thread
                var userShares = UserShares(id: browseId, username: username, folders: treeFiles, isLoading: false)
                userShares.computeStats()
                let precomputedShares = userShares

                // Update on main actor
                await MainActor.run {
                    guard let self else { return }
                    // Find the browse by ID (index may have changed)
                    if let idx = self.browses.firstIndex(where: { $0.id == browseId }) {
                        self.browses[idx] = precomputedShares
                        self.logger.info("Got \(flatFiles.count) files -> \(treeFiles.count) root folders for \(username)")
                        print("📂 BrowseState: Built tree with \(treeFiles.count) root folders from \(flatFiles.count) flat files")

                        // Cache the results
                        self.cacheUserShares(self.browses[idx])

                        // Auto-expand to target path if set
                        if self.targetPath != nil {
                            self.expandToTargetPath(in: treeFiles)
                        }
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
        currentFolderPath = nil  // Show root when switching tabs
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
        targetPath = nil
        currentFolderPath = nil
    }

    // MARK: - Auto-Expand to Path

    /// Expand all folders in the path to reveal a target file/folder
    /// - Parameter folders: The root folders to search in
    private func expandToTargetPath(in folders: [SharedFile]) {
        guard let targetPath = targetPath else { return }

        print("📂 BrowseState: Expanding to target path: \(targetPath)")
        print("📂 BrowseState: Root folders count: \(folders.count)")
        if folders.count <= 10 {
            print("📂 BrowseState: Root folder names: \(folders.map { $0.displayName })")
        } else {
            print("📂 BrowseState: First 5 root folders: \(folders.prefix(5).map { $0.displayName })")
        }

        // Parse the target path into components (e.g., "@@music\\Artist\\Album\\song.mp3")
        let pathComponents = targetPath.split(separator: "\\").map(String.init)
        guard !pathComponents.isEmpty else { return }

        print("📂 BrowseState: Path components: \(pathComponents)")

        // Find and expand folders along the path
        var currentFiles = folders
        var expandedCount = 0

        for (index, component) in pathComponents.enumerated() {
            print("📂 BrowseState: Looking for '\(component)' in \(currentFiles.count) items (isDirectory counts: \(currentFiles.filter { $0.isDirectory }.count))")

            // Find matching folder/file at this level
            if let match = currentFiles.first(where: { $0.displayName.lowercased() == component.lowercased() }) {
                if match.isDirectory {
                    // Expand this folder
                    expandedFolders.insert(match.id)
                    expandedCount += 1
                    print("📂 BrowseState: Expanded folder: \(match.displayName)")

                    // Move to children for next iteration
                    if let children = match.children {
                        currentFiles = children
                    } else {
                        break
                    }
                } else {
                    // Found the target file - select it
                    selectedFile = match
                    print("📂 BrowseState: Selected file: \(match.displayName)")
                    break
                }
            } else {
                // Try matching by full path component (for root shares like "@@music")
                if let match = currentFiles.first(where: { file in
                    let fileComponents = file.filename.split(separator: "\\").map(String.init)
                    return fileComponents.last?.lowercased() == component.lowercased()
                }) {
                    if match.isDirectory {
                        expandedFolders.insert(match.id)
                        expandedCount += 1
                        print("📂 BrowseState: Expanded folder (by filename): \(match.displayName)")

                        if let children = match.children {
                            currentFiles = children
                        } else {
                            break
                        }
                    } else if index == pathComponents.count - 1 {
                        selectedFile = match
                        print("📂 BrowseState: Selected file (by filename): \(match.displayName)")
                    }
                } else {
                    print("📂 BrowseState: Could not find '\(component)' in current level")
                    print("📂 BrowseState: Available names at this level: \(currentFiles.prefix(10).map { $0.displayName })")
                    break
                }
            }
        }

        print("📂 BrowseState: Auto-expanded \(expandedCount) folders")
        self.targetPath = nil // Clear after processing
    }
}
