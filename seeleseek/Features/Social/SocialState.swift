import SwiftUI
import os
import SeeleseekCore

@Observable
@MainActor
final class SocialState: PeerWatching {
    // MARK: - Buddy List
    var buddies: [Buddy] = []
    var selectedBuddy: String?
    var buddySearchQuery: String = ""
    var showAddBuddySheet = false

    // MARK: - Peer Status (live status for any watched user, buddy or not)
    /// Single source of truth for `peerStatus(for:)`. Holds the last-known
    /// status for every peer the app is currently watching, plus every
    /// buddy (seeded from the persisted buddy list on load and on add).
    /// `buddies[i].status` is a per-row mirror used by the buddy-list
    /// views (sorting, filtering, persistence) — both fields are written
    /// from the same MainActor handler so they cannot diverge.
    private(set) var peerStatuses: [String: BuddyStatus] = [:]
    /// Reference count per peer — the app may watch a peer because of a
    /// queued download *and* an upload simultaneously. We unwatch only
    /// when the last subscriber releases.
    private var peerWatchRefCounts: [String: Int] = [:]

    // MARK: - Blocklist
    var blockedUsers: [BlockedUser] = []
    var showBlockUserSheet = false
    var blockSearchQuery: String = ""
    var ignoredUsers: [IgnoredUser] = []
    var ignoreSearchQuery: String = ""
    var showIgnoreInput = false

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

    // MARK: - Privileges
    var privilegeTimeRemaining: UInt32 = 0

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

    var filteredIgnoredUsers: [IgnoredUser] {
        guard !ignoreSearchQuery.isEmpty else { return ignoredUsers }
        return ignoredUsers.filter { $0.username.localizedCaseInsensitiveContains(ignoreSearchQuery) }
    }

    func isBlocked(_ username: String) -> Bool {
        blockedUsers.contains { $0.username.lowercased() == username.lowercased() }
    }

    func isIgnored(_ username: String) -> Bool {
        ignoredUsers.contains { $0.username.lowercased() == username.lowercased() }
    }

    func isLeech(_ username: String) -> Bool {
        detectedLeeches.contains(username)
    }

    // MARK: - Peer Status

    /// Last known status for `username`, if the app has received one.
    /// Reads only from `peerStatuses` — buddies are seeded into the cache
    /// on load/add (and preserved across `unwatchPeer` for buddies), so
    /// no fallback to the buddy list is needed.
    func peerStatus(for username: String) -> BuddyStatus? {
        peerStatuses[username]
    }

    /// Begin watching `username` for live status updates. Ref-counted —
    /// callers must pair each call with `unwatchPeer`. Buddies don't need
    /// `watchUser` (the server auto-pushes), but we still issue an
    /// explicit `getUserStatus` to pull a fresh reading into the cache.
    func watchPeer(_ username: String) {
        guard !username.isEmpty else { return }
        let count = (peerWatchRefCounts[username] ?? 0) + 1
        peerWatchRefCounts[username] = count
        guard count == 1 else { return }   // already subscribed
        let isBuddy = buddies.contains(where: { $0.username == username })
        Task { [weak self] in
            guard let self, let client = self.networkClient else { return }
            do {
                if !isBuddy {
                    try await client.watchUser(username)
                }
                // Pull a status immediately rather than waiting for the
                // server to push one — ensures rows for failed persisted
                // transfers reflect offline state as soon as we connect.
                try await client.getUserStatus(username)
            } catch {
                self.logger.error("watchPeer(\(username)) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Re-send `watchUser` + `getUserStatus` for every currently-held
    /// peer subscription. Call this when the server connection has just
    /// come up: earlier subscribe attempts made while disconnected
    /// silently fail, and the server doesn't remember them across
    /// reconnects.
    func resubscribeWatchedPeers() {
        let peers = Array(peerWatchRefCounts.keys)
        guard !peers.isEmpty else { return }
        Task { [weak self] in
            guard let self, let client = self.networkClient else { return }
            for peer in peers {
                let isBuddy = self.buddies.contains(where: { $0.username == peer })
                do {
                    if !isBuddy {
                        try await client.watchUser(peer)
                    }
                    try await client.getUserStatus(peer)
                } catch {
                    self.logger.error("resubscribeWatchedPeers(\(peer)) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Release one watch on `username`. When the refcount hits zero the
    /// server subscription is torn down. For buddies we keep the
    /// `peerStatuses` entry around (it's seeded from the buddy list and
    /// kept fresh by the auto-pushed buddy status updates) so the buddy's
    /// row still shows a status after the last transfer goes away.
    func unwatchPeer(_ username: String) {
        guard !username.isEmpty else { return }
        let count = (peerWatchRefCounts[username] ?? 0) - 1
        if count <= 0 {
            peerWatchRefCounts.removeValue(forKey: username)
            let isBuddy = buddies.contains(where: { $0.username == username })
            if !isBuddy {
                peerStatuses.removeValue(forKey: username)
                Task { [weak self] in
                    guard let self, let client = self.networkClient else { return }
                    do {
                        try await client.unwatchUser(username)
                    } catch {
                        self.logger.error("unwatchPeer(\(username)) failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            peerWatchRefCounts[username] = count
        }
    }

    // MARK: - Setup

    func setupCallbacks(client: NetworkClient) {
        self.networkClient = client
        logger.info("Setting up social callbacks with NetworkClient...")

        // User status updates (for watched users / buddies)
        client.addUserStatusHandler { [weak self] username, status, privileged in
            guard let self else { return }
            let buddyStatus = BuddyStatus(from: status)
            // Record live status for any watched peer (buddy or not)
            self.peerStatuses[username] = buddyStatus
            self.updateBuddyStatus(username: username, status: status, privileged: privileged)
            // Also update viewing profile if this is the user we're looking at
            if self.viewingProfile?.username == username {
                self.viewingProfile?.status = buddyStatus
                self.viewingProfile?.isPrivileged = privileged
            }
        }

        // User stats updates (multi-handler pattern)
        client.addUserStatsHandler { [weak self] username, avgSpeed, uploadNum, files, dirs in
            guard let self else { return }
            self.updateBuddyStats(username: username, speed: avgSpeed, files: files, dirs: dirs)
            // Also update viewing profile if this is the user we're looking at
            if self.viewingProfile?.username == username {
                self.viewingProfile?.averageSpeed = avgSpeed
                self.viewingProfile?.totalUploads = UInt32(uploadNum)
                self.viewingProfile?.sharedFiles = files
                self.viewingProfile?.sharedFolders = dirs
            }
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

        // Own privilege time remaining
        client.onPrivilegesChecked = { [weak self] timeLeft in
            self?.privilegeTimeRemaining = timeLeft
        }

        // Country-code resolutions: persist on the buddy record so the
        // flag is available immediately on next launch (otherwise the
        // GeoIP lookup has to run again the next time we hear the
        // peer's IP). Also keeps the currently-viewed profile in sync.
        client.userInfoCache.onCountryResolved = { [weak self] username, code in
            self?.handleCountryResolved(username: username, countryCode: code)
        }

        // Provide profile data for UserInfoResponse
        client.profileDataProvider = { [weak self] in
            let desc = self?.myDescription ?? ""
            let description = desc.isEmpty ? "SeeleSeek - Soulseek client for macOS" : desc
            return (description: description, picture: self?.myPicture)
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
            // Seed peerStatuses with each buddy's persisted last-known
            // status so `peerStatus(for:)` returns something for buddies
            // before the first live status message arrives.
            //
            // Same idea for the country flag: push each buddy's
            // persisted countryCode into the live UserInfoCache so all
            // the row-level views (which read from the cache) light up
            // immediately on launch instead of waiting for a fresh
            // PeerAddress message to come in.
            for buddy in buddies {
                peerStatuses[buddy.username] = buddy.status
                if let code = buddy.countryCode {
                    networkClient?.userInfoCache.seedCountry(code, for: buddy.username)
                }
            }
            logger.info("Loaded \(self.buddies.count) buddies from database")

            // Load blocked users
            blockedUsers = try await SocialRepository.fetchBlockedUsers()
            logger.info("Loaded \(self.blockedUsers.count) blocked users from database")

            // Load ignored users
            if let ignoredJSON = try await SocialRepository.getProfileSetting("ignoredUsers"),
               let data = ignoredJSON.data(using: .utf8) {
                ignoredUsers = try JSONDecoder().decode([IgnoredUser].self, from: data)
                logger.info("Loaded \(self.ignoredUsers.count) ignored users from database")
            }

            // Load interests
            let interests = try await SocialRepository.fetchInterests()
            myLikes = interests.likes
            myHates = interests.hates
            logger.info("Loaded \(self.myLikes.count) likes and \(self.myHates.count) hates")

            // Load my profile settings
            if let desc = try await SocialRepository.getProfileSetting("description") {
                myDescription = desc
            }
            if let picBase64 = try await SocialRepository.getProfileSetting("picture") {
                myPicture = Data(base64Encoded: picBase64)
            }

            // Load leech settings
            if let leechJson = try await SocialRepository.getProfileSetting("leechSettings"),
               let data = leechJson.data(using: .utf8) {
                leechSettings = try JSONDecoder().decode(LeechSettings.self, from: data)
            }

            // Request status updates for all buddies and re-register interests after a short delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                await rewatchAllBuddies()
                await reregisterInterests()
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
        // Seed the live cache so `peerStatus(for:)` returns something
        // immediately; the watch/getUserStatus calls below will replace
        // this with the real status as soon as the server responds.
        peerStatuses[username] = buddy.status

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
        // Drop the seeded live-cache entry too — but only if no transfer
        // is still holding a watch on this peer (otherwise the row's
        // status indicator would go blank).
        if peerWatchRefCounts[username] == nil {
            peerStatuses.removeValue(forKey: username)
        }

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

    /// Persist a freshly-resolved country code on the buddy record (if
    /// the user is a buddy) and surface it on the currently-viewed
    /// profile. Idempotent — does nothing when the value hasn't actually
    /// changed, so we don't churn the DB on repeat resolutions.
    private func handleCountryResolved(username: String, countryCode: String) {
        if let index = buddies.firstIndex(where: { $0.username == username }),
           buddies[index].countryCode != countryCode {
            buddies[index].countryCode = countryCode
            let snapshot = buddies[index]
            Task {
                do {
                    try await SocialRepository.saveBuddy(snapshot)
                } catch {
                    logger.error("Failed to persist country for \(username): \(error.localizedDescription)")
                }
            }
        }
        if viewingProfile?.username == username {
            viewingProfile?.countryCode = countryCode
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
            if let pictureData = myPicture {
                try await SocialRepository.setProfileSetting("picture", value: pictureData.base64EncodedString())
            } else {
                try await SocialRepository.deleteProfileSetting("picture")
            }
            logger.info("Saved profile")
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

    // MARK: - Privilege Actions

    func checkPrivileges() {
        Task {
            do {
                try await networkClient?.checkPrivileges()
            } catch {
                logger.error("Failed to check privileges: \(error.localizedDescription)")
            }
        }
    }

    func givePrivileges(to username: String, days: UInt32) {
        Task {
            do {
                try await networkClient?.givePrivileges(to: username, days: days)
                logger.info("Gave \(days) days of privileges to \(username)")
            } catch {
                logger.error("Failed to give privileges: \(error.localizedDescription)")
            }
        }
    }

    /// Format privilege time remaining as human-readable string
    var formattedPrivilegeTime: String {
        guard privilegeTimeRemaining > 0 else { return "No privileges" }
        let days = privilegeTimeRemaining / 86400
        let hours = (privilegeTimeRemaining % 86400) / 3600
        if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s"), \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let minutes = (privilegeTimeRemaining % 3600) / 60
            return "\(hours) hour\(hours == 1 ? "" : "s"), \(minutes) min"
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

    // MARK: - Re-register Interests (server forgets on disconnect)

    /// Send all stored interests to the server after login
    /// The SoulSeek server does not persist interests across sessions
    private func reregisterInterests() async {
        guard let networkClient else { return }

        var registered = 0
        for like in myLikes {
            do {
                try await networkClient.addThingILike(like)
                registered += 1
            } catch {
                logger.error("Failed to re-register like '\(like)': \(error.localizedDescription)")
            }
        }
        for hate in myHates {
            do {
                try await networkClient.addThingIHate(hate)
                registered += 1
            } catch {
                logger.error("Failed to re-register hate '\(hate)': \(error.localizedDescription)")
            }
        }

        logger.info("Re-registered \(registered) interests with server (\(self.myLikes.count) likes, \(self.myHates.count) hates)")
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

    // MARK: - Ignore Actions

    func ignoreUser(_ username: String, reason: String? = nil) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isIgnored(trimmed) else { return }

        do {
            try await networkClient?.ignoreUser(trimmed)
        } catch {
            logger.error("Failed to ignore user on server: \(error.localizedDescription)")
        }

        ignoredUsers.append(IgnoredUser(username: trimmed, reason: reason))
        await persistIgnoredUsers()
        logger.info("Ignored user \(trimmed)")
    }

    func unignoreUser(_ username: String) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await networkClient?.unignoreUser(trimmed)
        } catch {
            logger.error("Failed to unignore user on server: \(error.localizedDescription)")
        }

        ignoredUsers.removeAll { $0.username.lowercased() == trimmed.lowercased() }
        await persistIgnoredUsers()
        logger.info("Unignored user \(trimmed)")
    }

    private func persistIgnoredUsers() async {
        do {
            let data = try JSONEncoder().encode(ignoredUsers)
            if let json = String(data: data, encoding: .utf8) {
                try await SocialRepository.setProfileSetting("ignoredUsers", value: json)
            }
        } catch {
            logger.error("Failed to persist ignored users: \(error.localizedDescription)")
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
