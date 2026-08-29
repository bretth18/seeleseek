import Foundation

// MARK: - Server Command Facade
//
// Thin request senders: validate/sanitize, build the frame via
// MessageBuilder, send on the live server connection. No state beyond the
// connection guard lives here — replies arrive via the server-message
// dispatch and are published on the event bus.
extension NetworkClient {
    // MARK: - Server Commands

    // SECURITY: Maximum search query length
    private static let maxSearchQueryLength = 500

    func requireConnectedServerConnection() throws -> ServerConnection {
        guard isConnected, let connection = serverConnection else {
            throw NetworkError.notConnected
        }
        return connection
    }

    public func search(query: String, token: UInt32) async throws {
        let connection = try requireConnectedServerConnection()

        // Sanitize: truncate, normalize Unicode, and clean for SoulSeek compatibility
        let sanitizedQuery = Self.sanitizeSearchQuery(query)

        guard !sanitizedQuery.isEmpty else {
            throw NetworkError.invalidResponse
        }

        let message = MessageBuilder.fileSearchMessage(token: token, query: sanitizedQuery)
        try await connection.send(message)
        logger.info("Sent search request: query='\(sanitizedQuery)' token=\(token)")
    }

    /// Sanitize a search query for SoulSeek protocol compatibility
    private static func sanitizeSearchQuery(_ query: String) -> String {
        var q = String(query.prefix(maxSearchQueryLength))

        // Normalize Unicode: smart/curly quotes → ASCII, em-dash → hyphen, etc.
        // NFKD decomposes compatibility characters, then we replace known offenders
        q = q.precomposedStringWithCompatibilityMapping
        q = q.replacingOccurrences(of: "\u{2018}", with: "'")  // left single quote
            .replacingOccurrences(of: "\u{2019}", with: "'")    // right single quote
            .replacingOccurrences(of: "\u{201C}", with: "\"")   // left double quote
            .replacingOccurrences(of: "\u{201D}", with: "\"")   // right double quote
            .replacingOccurrences(of: "\u{2013}", with: "-")    // en-dash
            .replacingOccurrences(of: "\u{2014}", with: "-")    // em-dash

        // Collapse multiple spaces
        while q.contains("  ") {
            q = q.replacingOccurrences(of: "  ", with: " ")
        }

        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func getRoomList() async throws {
        let connection = try requireConnectedServerConnection()

        let message = MessageBuilder.getRoomListMessage()
        try await connection.send(message)
    }

    public func joinRoom(_ name: String, isPrivate: Bool = false) async throws {
        let connection = try requireConnectedServerConnection()

        let message = MessageBuilder.joinRoomMessage(roomName: name, isPrivate: isPrivate)
        try await connection.send(message)
    }

    public func leaveRoom(_ name: String) async throws {
        let connection = try requireConnectedServerConnection()

        let message = MessageBuilder.leaveRoomMessage(roomName: name)
        try await connection.send(message)
    }

    // SECURITY: Maximum chat message length
    private static let maxMessageLength = 2000
    // SECURITY: Maximum username/room name length
    private static let maxNameLength = 100

    public func sendRoomMessage(_ room: String, message: String) async throws {
        let connection = try requireConnectedServerConnection()

        // SECURITY: Validate and sanitize input
        let sanitizedRoom = String(room.prefix(Self.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = String(message.prefix(Self.maxMessageLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedRoom.isEmpty, !sanitizedMessage.isEmpty else {
            return
        }

        let data = MessageBuilder.sayInChatRoomMessage(roomName: sanitizedRoom, message: sanitizedMessage)
        try await connection.send(data)
    }

    public func sendPrivateMessage(to username: String, message: String) async throws {
        let connection = try requireConnectedServerConnection()

        // SECURITY: Validate and sanitize input
        let sanitizedUsername = String(username.prefix(Self.maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedMessage = String(message.prefix(Self.maxMessageLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedUsername.isEmpty, !sanitizedMessage.isEmpty else {
            return
        }

        let data = MessageBuilder.privateMessageMessage(username: sanitizedUsername, message: sanitizedMessage)
        try await connection.send(data)
    }

    public func getUserAddress(_ username: String) async throws {
        let connection = try requireConnectedServerConnection()

        let message = MessageBuilder.getUserAddress(username)
        try await connection.send(message)
    }

    public func setStatus(_ status: UserStatus) async throws {
        let connection = try requireConnectedServerConnection()

        let message = MessageBuilder.setOnlineStatusMessage(status: status)
        try await connection.send(message)
    }

    public func setSharedFilesCount(_ files: UInt32, directories: UInt32) async throws {
        let connection = try requireConnectedServerConnection()

        let message = MessageBuilder.sharedFoldersFilesMessage(folders: directories, files: files)
        try await connection.send(message)
    }

    /// Tell server we couldn't connect to a peer (used by peer responding to us)
    public func sendCantConnectToPeer(token: UInt32, username: String) async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.cantConnectToPeer(token: token, username: username)
        do {
            try await connection.send(message)
            logger.info("Sent CantConnectToPeer for \(username) token=\(token)")
        } catch {
            logger.error("Failed to send CantConnectToPeer: \(error.localizedDescription)")
        }
    }

    /// Acknowledge a private message to the server (code 23)
    public func acknowledgePrivateMessage(messageId: UInt32) async {
        guard let connection = serverConnection else {
            logger.error("Cannot acknowledge private message \(messageId) — no server connection")
            return
        }

        let message = MessageBuilder.acknowledgePrivateMessageMessage(messageId: messageId)
        do {
            try await connection.send(message)
            logger.info("Acknowledged private message \(messageId)")
        } catch {
            logger.error("Failed to acknowledge private message \(messageId): \(error.localizedDescription)")
        }
    }

    /// Request server to tell peer to connect to us (indirect connection request)
    /// Server will forward this to the peer, who will then send PierceFirewall to us
    public func sendConnectToPeer(token: UInt32, username: String, connectionType: String = "P") async {
        guard isConnected, let connection = serverConnection else { return }

        let message = MessageBuilder.connectToPeerMessage(token: token, username: username, connectionType: connectionType)
        do {
            try await connection.send(message)
            logger.info("Sent ConnectToPeer for \(username) token=\(token) type=\(connectionType)")
        } catch {
            logger.error("Failed to send ConnectToPeer: \(error.localizedDescription)")
        }
    }

    // MARK: - User Interests & Recommendations

    /// Add something I like
    public func addThingILike(_ item: String) async throws {
        let message = MessageBuilder.addThingILike(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added thing I like: \(item)")
    }

    /// Remove something I like
    public func removeThingILike(_ item: String) async throws {
        let message = MessageBuilder.removeThingILike(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removed thing I like: \(item)")
    }

    /// Add something I hate
    public func addThingIHate(_ item: String) async throws {
        let message = MessageBuilder.addThingIHate(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added thing I hate: \(item)")
    }

    /// Remove something I hate
    public func removeThingIHate(_ item: String) async throws {
        let message = MessageBuilder.removeThingIHate(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removed thing I hate: \(item)")
    }

    /// Get my recommendations
    public func getRecommendations() async throws {
        let message = MessageBuilder.getRecommendations()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested recommendations")
    }

    /// Get global (network-wide) recommendations - popular interests across all users
    public func getGlobalRecommendations() async throws {
        let message = MessageBuilder.getGlobalRecommendations()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested global recommendations")
    }

    /// Get a user's interests
    public func getUserInterests(_ username: String) async throws {
        let message = MessageBuilder.getUserInterests(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested interests for: \(username)")
    }

    /// Get similar users
    public func getSimilarUsers() async throws {
        let message = MessageBuilder.getSimilarUsers()
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested similar users")
    }

    /// Get recommendations for an item
    public func getItemRecommendations(_ item: String) async throws {
        let message = MessageBuilder.getItemRecommendations(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested recommendations for item: \(item)")
    }

    /// Get similar users for an item
    public func getItemSimilarUsers(_ item: String) async throws {
        let message = MessageBuilder.getItemSimilarUsers(item)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested similar users for item: \(item)")
    }

    // MARK: - User Watching (Buddy List)

    /// Watch a user (receive status updates)
    public func watchUser(_ username: String) async throws {
        let message = MessageBuilder.watchUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Watching user: \(username)")
    }

    /// Stop watching a user
    public func unwatchUser(_ username: String) async throws {
        let message = MessageBuilder.unwatchUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Unwatched user: \(username)")
    }

    /// Ignore user (server code 11)
    public func ignoreUser(_ username: String) async throws {
        let message = MessageBuilder.ignoreUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Ignored user: \(username)")
    }

    /// Unignore user (server code 12)
    public func unignoreUser(_ username: String) async throws {
        let message = MessageBuilder.unignoreUserMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Unignored user: \(username)")
    }

    /// Get a user's current status
    public func getUserStatus(_ username: String) async throws {
        let message = MessageBuilder.getUserStatusMessage(username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested status for: \(username)")
    }

    // MARK: - User Stats & Privileges

    /// Get user stats (speed, files, dirs)
    public func getUserStats(_ username: String) async throws {
        let message = MessageBuilder.getUserStats(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested stats for: \(username)")
    }

    /// Check our privilege time remaining
    public func checkPrivileges() async throws {
        let message = MessageBuilder.checkPrivileges()
        try await requireConnectedServerConnection().send(message)
        logger.info("Checking privileges")
    }

    /// Get a user's privilege status
    public func getUserPrivileges(_ username: String) async throws {
        let message = MessageBuilder.getUserPrivileges(username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Requested privileges for: \(username)")
    }

    // MARK: - Room Tickers

    /// Set a ticker message for a room
    public func setRoomTicker(room: String, ticker: String) async throws {
        let message = MessageBuilder.setRoomTicker(room: room, ticker: ticker)
        try await requireConnectedServerConnection().send(message)
        logger.info("Set ticker in \(room): \(ticker)")
    }

    // MARK: - Room Search & Wishlist

    /// Search within a specific room
    public func searchRoom(_ room: String, query: String, token: UInt32) async throws {
        let message = MessageBuilder.roomSearch(room: room, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Room search in \(room): \(query)")
    }

    /// Add a wishlist search (runs periodically)
    public func addWishlistSearch(query: String, token: UInt32) async throws {
        let message = MessageBuilder.wishlistSearch(token: token, query: query)
        try await requireConnectedServerConnection().send(message)
        logger.info("Added wishlist search: \(query)")
    }

    // MARK: - Private Rooms

    /// Add a member to a private room
    public func addPrivateRoomMember(room: String, username: String) async throws {
        let message = MessageBuilder.privateRoomAddMember(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Adding \(username) to private room \(room)")
    }

    /// Remove a member from a private room
    public func removePrivateRoomMember(room: String, username: String) async throws {
        let message = MessageBuilder.privateRoomRemoveMember(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removing \(username) from private room \(room)")
    }

    /// Leave a private room
    public func leavePrivateRoom(_ room: String) async throws {
        let message = MessageBuilder.privateRoomCancelMembership(room: room)
        try await requireConnectedServerConnection().send(message)
        logger.info("Leaving private room \(room)")
    }

    /// Give up ownership of a private room
    public func giveUpPrivateRoomOwnership(_ room: String) async throws {
        let message = MessageBuilder.privateRoomCancelOwnership(room: room)
        try await requireConnectedServerConnection().send(message)
        logger.info("Giving up ownership of \(room)")
    }

    /// Add an operator to a private room
    public func addPrivateRoomOperator(room: String, username: String) async throws {
        let message = MessageBuilder.privateRoomAddOperator(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Adding \(username) as operator in \(room)")
    }

    /// Remove an operator from a private room
    public func removePrivateRoomOperator(room: String, username: String) async throws {
        let message = MessageBuilder.privateRoomRemoveOperator(room: room, username: username)
        try await requireConnectedServerConnection().send(message)
        logger.info("Removing \(username) as operator from \(room)")
    }

    // MARK: - User Search

    /// Search a specific user's files
    public func userSearch(username: String, token: UInt32, query: String) async throws {
        let message = MessageBuilder.userSearchMessage(username: username, token: token, query: query)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Upload Speed & Privileges

    /// Report upload speed to server
    public func reportUploadSpeed(_ speed: UInt32) async throws {
        let message = MessageBuilder.sendUploadSpeedMessage(speed: speed)
        try await requireConnectedServerConnection().send(message)
    }

    /// Give privileges to another user
    public func givePrivileges(to username: String, days: UInt32) async throws {
        let message = MessageBuilder.givePrivilegesMessage(username: username, days: days)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Room Invitations

    /// Enable or disable room invitations
    public func enableRoomInvitations(_ enable: Bool) async throws {
        let message = MessageBuilder.enableRoomInvitationsMessage(enable: enable)
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Bulk Messaging

    /// Send a message to multiple users at once
    public func messageUsers(_ usernames: [String], message: String) async throws {
        let msg = MessageBuilder.messageUsersMessage(usernames: usernames, message: message)
        try await requireConnectedServerConnection().send(msg)
    }

    // MARK: - Global Room

    /// Join the global room
    public func joinGlobalRoom() async throws {
        let message = MessageBuilder.joinGlobalRoomMessage()
        try await requireConnectedServerConnection().send(message)
    }

    /// Leave the global room
    public func leaveGlobalRoom() async throws {
        let message = MessageBuilder.leaveGlobalRoomMessage()
        try await requireConnectedServerConnection().send(message)
    }

    // MARK: - Share Updates

    /// Re-broadcast `SharedFoldersFiles` using `ShareManager`'s current
    /// totals. Wired automatically via the `countsChangesStream`
    /// consumer in `init`. No-op while disconnected.
    public func updateShareCounts() async {
        guard isConnected, let connection = serverConnection else { return }

        let folders = await UInt32(shareManager.totalFolders)
        let files = await UInt32(shareManager.totalFiles)

        do {
            let message = MessageBuilder.sharedFoldersFilesMessage(folders: folders, files: files)
            try await connection.send(message)
            logger.info("Updated share counts: \(folders) folders, \(files) files")
        } catch {
            logger.error("Failed to update share counts: \(error.localizedDescription)")
        }
    }
}
