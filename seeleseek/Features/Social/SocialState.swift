import SwiftUI
import os

@Observable
@MainActor
final class SocialState {
    // MARK: - Buddy List
    var buddies: [Buddy] = []
    var selectedBuddy: String?
    var buddySearchQuery: String = ""
    var showAddBuddySheet = false

    // MARK: - Blocklist
    var blockedUsers: [BlockedUser] = []
    var showBlockUserSheet = false
    var blockSearchQuery: String = ""

    // MARK: - Leech Detection
    var leechSettings = LeechSettings()
    var detectedLeeches: Set<String> = []  // Usernames flagged as leeches
    var warnedLeeches: Set<String> = []    // Leeches we've already warned/messaged

    // MARK: - Profiles
    var viewingProfile: UserProfile?
    var showProfileSheet = false
    var isLoadingProfile = false

    // MARK: - My Profile
    var myDescription: String = ""
    var myPicture: Data?

    // MARK: - Interests
    var myLikes: [String] = []
    var myHates: [String] = []
    var newInterest: String = ""

    // MARK: - Discovery
    var similarUsers: [(username: String, rating: UInt32)] = []
    var recommendations: [(item: String, score: Int32)] = []
    var unrecommendations: [(item: String, score: Int32)] = []
    var globalRecommendations: [(item: String, score: Int32)] = []  // Network-wide popular interests
    var isLoadingSimilar = false
    var isLoadingRecommendations = false

    // MARK: - Network
    weak var networkClient: NetworkClient?

    private let logger = Logger(subsystem: "com.seeleseek", category: "SocialState")

    // MARK: - Computed Properties

    var filteredBuddies: [Buddy] {
        let sorted = buddies.sorted { $0.status > $1.status }
        guard !buddySearchQuery.isEmpty else { return sorted }
        return sorted.filter { $0.username.localizedCaseInsensitiveContains(buddySearchQuery) }
    }

    var onlineBuddies: [Buddy] {
        buddies.filter { $0.status != .offline }
    }

    var offlineBuddies: [Buddy] {
        buddies.filter { $0.status == .offline }
    }

    var filteredBlockedUsers: [BlockedUser] {
        guard !blockSearchQuery.isEmpty else { return blockedUsers }
        return blockedUsers.filter { $0.username.localizedCaseInsensitiveContains(blockSearchQuery) }
    }

    func isBlocked(_ username: String) -> Bool {
        blockedUsers.contains { $0.username.lowercased() == username.lowercased() }
    }

    func isLeech(_ username: String) -> Bool {
        detectedLeeches.contains(username)
    }

    // MARK: - Setup

    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client
        logger.info("Setting up social callbacks with NetworkClient...")

        // User status updates (for watched users / buddies)
        client.addUserStatusHandler { [weak self] username, status, privileged in
            guard let self else { return }
            self.updateBuddyStatus(username: username, status: status, privileged: privileged)
            // Also update viewing profile if this is the user we're looking at
            if self.viewingProfile?.username == username {
                self.viewingProfile?.status = BuddyStatus(from: status)
                self.viewingProfile?.isPrivileged = privileged
            }
        }

        // User stats updates
        client.onUserStats = { [weak self] username, avgSpeed, uploadNum, files, dirs in
            guard let self else { return }
            self.updateBuddyStats(username: username, speed: avgSpeed, files: files, dirs: dirs)
            // Also update viewing profile if this is the user we're looking at
            if self.viewingProfile?.username == username {
                self.viewingProfile?.averageSpeed = avgSpeed
                self.viewingProfile?.totalUploads = UInt32(uploadNum)
                self.viewingProfile?.sharedFiles = files
                self.viewingProfile?.sharedFolders = dirs
            }
            // Check for leech
            self.checkForLeech(username: username, files: files, folders: dirs)
        }

        // User interests response
        client.onUserInterests = { [weak self] username, likes, hates in
            guard let self else { return }
            self.handleUserInterests(username: username, likes: likes, hates: hates)
        }

        // Similar users response
        client.onSimilarUsers = { [weak self] users in
            guard let self else { return }
            self.similarUsers = users
            self.isLoadingSimilar = false
            self.logger.info("Received \(users.count) similar users")
        }

        // Recommendations response
        client.onRecommendations = { [weak self] recs, unrecs in
            guard let self else { return }
            self.recommendations = recs
            self.unrecommendations = unrecs
            self.isLoadingRecommendations = false
            self.logger.info("Received \(recs.count) recommendations, \(unrecs.count) unrecommendations")
        }

        // Global recommendations response (network-wide popular interests)
        client.onGlobalRecommendations = { [weak self] recs, _ in
            guard let self else { return }
            self.globalRecommendations = recs
            self.logger.info("Received \(recs.count) global recommendations")
        }

        // User privileges response (for viewing profiles)
        client.onUserPrivileges = { [weak self] username, privileged in
            guard let self else { return }
            // Update viewing profile if this is the user we're looking at
            if self.viewingProfile?.username == username {
                self.viewingProfile?.isPrivileged = privileged
            }
        }

        logger.info("Social callbacks configured")

        // Load persisted data
        Task {
            await loadPersistedData()
        }
    }

    // MARK: - Persistence

    private func loadPersistedData() async {
        do {
            // Load buddies from database
            buddies = try await SocialRepository.fetchBuddies()
            logger.info("Loaded \(self.buddies.count) buddies from database")

            // Load blocked users
            blockedUsers = try await SocialRepository.fetchBlockedUsers()
            logger.info("Loaded \(self.blockedUsers.count) blocked users from database")

            // Load interests
            let interests = try await SocialRepository.fetchInterests()
            myLikes = interests.likes
            myHates = interests.hates
            logger.info("Loaded \(self.myLikes.count) likes and \(self.myHates.count) hates")

            // Load my profile settings
            if let desc = try await SocialRepository.getProfileSetting("description") {
                myDescription = desc
            }

            // Load leech settings
            if let leechJson = try await SocialRepository.getProfileSetting("leechSettings"),
               let data = leechJson.data(using: .utf8) {
                leechSettings = try JSONDecoder().decode(LeechSettings.self, from: data)
            }

            // Request status updates for all buddies after a short delay to ensure connection is ready
            Task {
                try? await Task.sleep(for: .seconds(2))
                await rewatchAllBuddies()
            }
        } catch {
            logger.error("Failed to load persisted social data: \(error.localizedDescription)")
        }
    }

    // MARK: - Buddy Actions

    func addBuddy(_ username: String) async {
        guard !username.isEmpty else { return }
        guard !buddies.contains(where: { $0.username.lowercased() == username.lowercased() }) else {
            logger.warning("User \(username) is already a buddy")
            return
        }

        let buddy = Buddy(username: username)
        buddies.append(buddy)

        // Persist to database
        Task {
            do {
                try await SocialRepository.saveBuddy(buddy)
                logger.info("Saved buddy \(username) to database")
            } catch {
                logger.error("Failed to save buddy: \(error.localizedDescription)")
            }
        }

        // Watch user on server (get status updates)
        do {
            try await networkClient?.watchUser(username)
            logger.info("Watching user \(username)")

            // Request initial status
            await refreshBuddyStatus(username)
        } catch {
            logger.error("Failed to watch user: \(error.localizedDescription)")
        }
    }

    func removeBuddy(_ username: String) async {
        buddies.removeAll { $0.username == username }

        // Remove from database
        Task {
            do {
                try await SocialRepository.deleteBuddy(username)
                logger.info("Removed buddy \(username) from database")
            } catch {
                logger.error("Failed to remove buddy: \(error.localizedDescription)")
            }
        }

        // Unwatch user on server
        do {
            try await networkClient?.unwatchUser(username)
            logger.info("Unwatched user \(username)")
        } catch {
            logger.error("Failed to unwatch user: \(error.localizedDescription)")
        }
    }

    func refreshBuddyStatus(_ username: String) async {
        do {
            // Request user status
            try await networkClient?.getUserStatus(username)

            // Request user stats
            try await networkClient?.getUserStats(username)

            logger.debug("Requested status/stats for \(username)")
        } catch {
            logger.error("Failed to refresh buddy status: \(error.localizedDescription)")
        }
    }

    func updateBuddyStatus(username: String, status: UserStatus, privileged: Bool) {
        guard let index = buddies.firstIndex(where: { $0.username == username }) else { return }

        buddies[index].status = BuddyStatus(from: status)
        buddies[index].isPrivileged = privileged

        if status != .offline {
            buddies[index].lastSeen = Date()
        }

        // Update in database
        Task {
            do {
                try await SocialRepository.saveBuddy(buddies[index])
            } catch {
                logger.error("Failed to update buddy status in database: \(error.localizedDescription)")
            }
        }
    }

    private func updateBuddyStats(username: String, speed: UInt32, files: UInt32, dirs: UInt32) {
        guard let index = buddies.firstIndex(where: { $0.username == username }) else { return }

        buddies[index].averageSpeed = speed
        buddies[index].fileCount = files
        buddies[index].folderCount = dirs
    }

    func updateBuddyNotes(_ username: String, notes: String) {
        guard let index = buddies.firstIndex(where: { $0.username == username }) else { return }

        buddies[index].notes = notes.isEmpty ? nil : notes

        Task {
            do {
                try await SocialRepository.saveBuddy(buddies[index])
            } catch {
                logger.error("Failed to save buddy notes: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Profile Actions

    func loadProfile(for username: String) async {
        isLoadingProfile = true

        // Start with data from buddy list if available
        if let buddy = buddies.first(where: { $0.username == username }) {
            viewingProfile = UserProfile(
                username: username,
                averageSpeed: buddy.averageSpeed,
                sharedFiles: buddy.fileCount,
                sharedFolders: buddy.folderCount,
                status: buddy.status,
                isPrivileged: buddy.isPrivileged,
                countryCode: buddy.countryCode
            )
        } else {
            viewingProfile = UserProfile(username: username)
        }

        do {
            // Request user status first
            try await networkClient?.getUserStatus(username)

            // Request user interests
            try await networkClient?.getUserInterests(username)

            // Request user stats
            try await networkClient?.getUserStats(username)

            // Request user privileges
            try await networkClient?.getUserPrivileges(username)

            logger.info("Requested profile data for \(username)")
        } catch {
            logger.error("Failed to load profile: \(error.localizedDescription)")
        }

        isLoadingProfile = false
        showProfileSheet = true
    }

    private func handleUserInterests(username: String, likes: [String], hates: [String]) {
        // Update viewing profile if this is the user we're looking at
        if viewingProfile?.username == username {
            viewingProfile?.likedInterests = likes
            viewingProfile?.hatedInterests = hates
        }
    }

    func saveMyProfile() async {
        do {
            try await SocialRepository.setProfileSetting("description", value: myDescription)
            logger.info("Saved profile description")
        } catch {
            logger.error("Failed to save profile: \(error.localizedDescription)")
        }
    }

    // MARK: - Interest Actions

    func addLike(_ item: String) async {
        guard !item.isEmpty else { return }
        guard !myLikes.contains(where: { $0.lowercased() == item.lowercased() }) else { return }

        myLikes.append(item)

        // Save to database
        Task {
            do {
                try await SocialRepository.saveInterest(item, type: .like)
            } catch {
                logger.error("Failed to save like: \(error.localizedDescription)")
            }
        }

        // Send to server
        do {
            try await networkClient?.addThingILike(item)
            logger.info("Added like: \(item)")

            // Auto-refresh recommendations after adding an interest
            try await networkClient?.getRecommendations()
            try await networkClient?.getSimilarUsers()
        } catch {
            logger.error("Failed to add like on server: \(error.localizedDescription)")
        }
    }

    func removeLike(_ item: String) async {
        myLikes.removeAll { $0 == item }

        // Remove from database
        Task {
            do {
                try await SocialRepository.deleteInterest(item)
            } catch {
                logger.error("Failed to remove like from database: \(error.localizedDescription)")
            }
        }

        // Remove from server
        do {
            try await networkClient?.removeThingILike(item)
            logger.info("Removed like: \(item)")
        } catch {
            logger.error("Failed to remove like on server: \(error.localizedDescription)")
        }
    }

    func addHate(_ item: String) async {
        guard !item.isEmpty else { return }
        guard !myHates.contains(where: { $0.lowercased() == item.lowercased() }) else { return }

        myHates.append(item)

        // Save to database
        Task {
            do {
                try await SocialRepository.saveInterest(item, type: .hate)
            } catch {
                logger.error("Failed to save hate: \(error.localizedDescription)")
            }
        }

        // Send to server
        do {
            try await networkClient?.addThingIHate(item)
            logger.info("Added hate: \(item)")

            // Auto-refresh recommendations after adding an interest
            try await networkClient?.getRecommendations()
            try await networkClient?.getSimilarUsers()
        } catch {
            logger.error("Failed to add hate on server: \(error.localizedDescription)")
        }
    }

    func removeHate(_ item: String) async {
        myHates.removeAll { $0 == item }

        // Remove from database
        Task {
            do {
                try await SocialRepository.deleteInterest(item)
            } catch {
                logger.error("Failed to remove hate from database: \(error.localizedDescription)")
            }
        }

        // Remove from server
        do {
            try await networkClient?.removeThingIHate(item)
            logger.info("Removed hate: \(item)")
        } catch {
            logger.error("Failed to remove hate on server: \(error.localizedDescription)")
        }
    }

    // MARK: - Discovery Actions

    func loadSimilarUsers() async {
        isLoadingSimilar = true

        do {
            try await networkClient?.getSimilarUsers()
            logger.info("Requested similar users")
        } catch {
            logger.error("Failed to get similar users: \(error.localizedDescription)")
            isLoadingSimilar = false
        }
    }

    func loadRecommendations() async {
        isLoadingRecommendations = true

        do {
            try await networkClient?.getRecommendations()
            try await networkClient?.getGlobalRecommendations()
            logger.info("Requested recommendations and global recommendations")
        } catch {
            logger.error("Failed to get recommendations: \(error.localizedDescription)")
            isLoadingRecommendations = false
        }
    }

    // MARK: - Re-watch All Buddies (after reconnection)

    func rewatchAllBuddies() async {
        for buddy in buddies {
            do {
                try await networkClient?.watchUser(buddy.username)
                try await networkClient?.getUserStatus(buddy.username)
            } catch {
                logger.error("Failed to rewatch \(buddy.username): \(error.localizedDescription)")
            }
        }

        logger.info("Re-watched \(self.buddies.count) buddies")
    }

    // MARK: - Blocklist Actions

    func blockUser(_ username: String, reason: String? = nil) async {
        guard !isBlocked(username) else { return }

        let blocked = BlockedUser(username: username, reason: reason)
        blockedUsers.append(blocked)

        // Persist to database
        do {
            try await SocialRepository.saveBlockedUser(blocked)
            logger.info("Blocked user \(username)")
        } catch {
            logger.error("Failed to save blocked user: \(error.localizedDescription)")
        }

        // Note: Server-side ignore (code 11) is obsolete in the protocol
        // Blocking is handled client-side by filtering messages and denying transfers
    }

    func unblockUser(_ username: String) async {
        blockedUsers.removeAll { $0.username.lowercased() == username.lowercased() }

        // Remove from database
        do {
            try await SocialRepository.deleteBlockedUser(username)
            logger.info("Unblocked user \(username)")
        } catch {
            logger.error("Failed to remove blocked user: \(error.localizedDescription)")
        }
    }

    // MARK: - Leech Detection

    /// Check if a user is a leech based on their stats
    func checkForLeech(username: String, files: UInt32, folders: UInt32) {
        guard leechSettings.enabled else { return }
        guard !isBlocked(username) else { return }

        let isLeech = files < leechSettings.minSharedFiles || folders < leechSettings.minSharedFolders

        if isLeech {
            if !detectedLeeches.contains(username) {
                detectedLeeches.insert(username)
                logger.info("Detected leech: \(username) (files: \(files), folders: \(folders))")

                // Take action based on settings
                handleLeechDetected(username: username)
            }
        } else {
            // User is no longer a leech (they started sharing)
            detectedLeeches.remove(username)
            warnedLeeches.remove(username)
        }
    }

    private func handleLeechDetected(username: String) {
        switch leechSettings.action {
        case .ignore:
            // Just track, no action
            break

        case .warn:
            // UI will show warning indicator
            break

        case .message:
            // Send a polite message (only once per session)
            if !warnedLeeches.contains(username) {
                warnedLeeches.insert(username)
                Task {
                    try? await networkClient?.sendPrivateMessage(to: username, message: leechSettings.customMessage)
                    logger.info("Sent leech warning to \(username)")
                }
            }

        case .deny:
            // Upload manager will check isLeech() before allowing transfers
            break

        case .block:
            Task {
                await blockUser(username, reason: "Auto-blocked: No shared files")
            }
        }
    }

    /// Check if we should allow uploads to this user
    func shouldAllowUpload(to username: String) -> Bool {
        // Always deny if blocked
        if isBlocked(username) {
            return false
        }

        // Deny if leech and action is deny
        if leechSettings.enabled && leechSettings.action == .deny && isLeech(username) {
            return false
        }

        return true
    }

    func saveLeechSettings() async {
        do {
            let data = try JSONEncoder().encode(leechSettings)
            if let json = String(data: data, encoding: .utf8) {
                try await SocialRepository.setProfileSetting("leechSettings", value: json)
                logger.info("Saved leech settings")
            }
        } catch {
            logger.error("Failed to save leech settings: \(error.localizedDescription)")
        }
    }
}
