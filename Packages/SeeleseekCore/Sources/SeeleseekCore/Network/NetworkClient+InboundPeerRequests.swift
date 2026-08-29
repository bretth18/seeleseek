import Foundation

// MARK: - Inbound Peer Request Serving
//
// Answers to requests peers make of us: share lists, folder contents, our
// user-info profile, and SeeleSeek-extension artwork. Buddy-only visibility
// gating is enforced here for every surface a peer could enumerate. The
// O(N) index walks run off-actor via `@concurrent` helpers.
extension NetworkClient {
    // MARK: - Folder Browsing

    /// Handle incoming folder contents request - respond with our files in that folder
    func handleFolderContentsRequest(username: String, token: UInt32, folder: String, connection: PeerConnection) async {
        let isBuddy = isBuddy(username)
        logger.info("Folder contents request from \(username) (buddy=\(isBuddy)) for: \(folder)")

        // Snapshot the index on the main actor, then run the O(N) filter +
        // mapping off-actor (`@concurrent`) — with large shares this walk
        // would otherwise occupy the client actor per incoming peer request.
        let fileIndex = await shareManager.fileIndex
        let files = await Self.buildFolderContents(fileIndex: fileIndex, folder: folder, isBuddy: isBuddy)

        if files.isEmpty {
            logger.info("No files found in folder: \(folder)")
            // Still send empty response
        }

        do {
            try await connection.sendFolderContents(token: token, folder: folder, files: files)
            logger.info("Sent folder contents: \(folder) (\(files.count) files)")
        } catch {
            logger.error("Failed to send folder contents: \(error.localizedDescription)")
        }
    }

    /// Off-actor helper for `handleFolderContentsRequest`. Finds files
    /// in the requested folder, respecting per-folder visibility. Buddy-only
    /// files are dropped for non-buddies so they can't be enumerated via a
    /// folder-contents query that bypasses the shares-reply gate.
    @concurrent
    private nonisolated static func buildFolderContents(
        fileIndex: [ShareManager.IndexedFile],
        folder: String,
        isBuddy: Bool
    ) async -> [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] {
        fileIndex.compactMap { file -> (filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])? in
            guard file.sharedPath.hasPrefix(folder + "\\") || file.sharedPath == folder else { return nil }
            if file.visibility == .buddies && !isBuddy { return nil }
            var attributes: [(UInt32, UInt32)] = []
            if let bitrate = file.bitrate {
                attributes.append((0, bitrate))
            }
            if let duration = file.duration {
                attributes.append((1, duration))
            }
            return (
                filename: file.filename,
                size: file.size,
                extension_: file.fileExtension,
                attributes: attributes
            )
        }
    }

    // MARK: - Shares Request Handling

    /// Handle incoming shares request - respond with our shared file list.
    ///
    /// Folders marked `.buddies` are sent in the protocol's private
    /// directories section only when the requester is on our buddy
    /// list. Non-buddies get public folders only.
    func handleSharesRequest(username: String, connection: PeerConnection) async {
        let isBuddy = isBuddy(username)
        logger.info("Shares request from \(username) (buddy=\(isBuddy))")

        // Snapshot the index on the main actor, then run the full-index
        // walk + per-file split + sorts off-actor (`@concurrent`) — with
        // large shares this would otherwise occupy the client actor on
        // every incoming shares request.
        let fileIndex = await shareManager.fileIndex
        let (publicDirs, privateDirs) = await Self.buildSharesDirectories(fileIndex: fileIndex, isBuddy: isBuddy)

        logger.info("Sending \(publicDirs.count) public + \(privateDirs.count) private directories to \(username)")

        do {
            try await connection.sendShares(files: publicDirs, privateFiles: privateDirs)
            logger.info("Sent shares to \(username)")
        } catch {
            logger.error("Failed to send shares to \(username): \(error.localizedDescription)")
        }
    }

    private typealias DirBucket = (directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])

    /// Off-actor helper for `handleSharesRequest`: groups the index by
    /// directory and splits by visibility.
    @concurrent
    private nonisolated static func buildSharesDirectories(
        fileIndex: [ShareManager.IndexedFile],
        isBuddy: Bool
    ) async -> (publicDirs: [DirBucket], privateDirs: [DirBucket]) {
        var publicMap: [String: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)]] = [:]
        var privateMap: [String: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)]] = [:]

        for file in fileIndex {
            let components = file.sharedPath.split(separator: "\\")
            guard components.count > 1 else { continue }

            let directory = components.dropLast().joined(separator: "\\")
            let filename = String(components.last!)
            let entry = (filename: filename, size: file.size, bitrate: file.bitrate, duration: file.duration)

            switch file.visibility {
            case .public:
                publicMap[directory, default: []].append(entry)
            case .buddies:
                // Drop buddy-only files entirely for non-buddies; put
                // them in the private section for buddies so they show
                // up separately on the receiver.
                if isBuddy {
                    privateMap[directory, default: []].append(entry)
                }
            }
        }

        let publicDirs: [DirBucket] = publicMap.map { ($0.key, $0.value) }.sorted { $0.directory < $1.directory }
        let privateDirs: [DirBucket] = privateMap.map { ($0.key, $0.value) }.sorted { $0.directory < $1.directory }
        return (publicDirs, privateDirs)
    }

    // MARK: - User Info Request Handling

    /// Handle incoming user info request - respond with our profile info
    func handleUserInfoRequest(username: String, connection: PeerConnection) async {
        logger.info("UserInfoRequest from \(username)")

        let totalUploads = await UInt32(shareManager.totalFiles)
        let queueSize = UInt32(0)
        let hasFreeSlots = true

        // Profile data pushed down from SocialState (default when unset)
        let profileData = self.profileData

        do {
            try await connection.sendUserInfo(
                description: profileData.resolvedDescription,
                picture: profileData.picture,
                totalUploads: totalUploads,
                queueSize: queueSize,
                hasFreeSlots: hasFreeSlots
            )
            logger.info("Sent user info to \(username)")
        } catch {
            logger.error("Failed to send user info to \(username): \(error.localizedDescription)")
        }
    }

    // MARK: - SeeleSeek Artwork Request Handling

    /// Handle artwork request from an extension peer — look up the file and send back embedded artwork.
    func handleArtworkRequest(username: String, token: UInt32, filePath: String, connection: PeerConnection) async {
        // Gate on the code we are about to *send*, same rule as the outbound
        // side. Placed before the index scan rather than beside the reply:
        // servicing this means an O(N) walk of the share index plus a disk
        // read and image parse, which no peer gets to trigger on demand
        // without having advertised the exchange.
        guard await connection.supports(.artworkReply) else {
            logger.debug("ArtworkRequest from \(username) ignored — peer has not advertised the artwork extension")
            return
        }

        // Find the file in our share index by SoulSeek path. Snapshot on
        // the main actor, scan off-actor (`@concurrent`) — O(N) over a
        // large index per incoming request otherwise occupies the client
        // actor.
        let fileIndex = await shareManager.fileIndex
        let match = await Self.findShareIndexMatch(fileIndex: fileIndex, filePath: filePath)
        guard let indexedFile = match else {
            logger.warning("ArtworkRequest: file not found in shares: \(filePath)")
            // Send empty reply
            let reply = MessageBuilder.artworkReplyMessage(token: token, imageData: Data())
            try? await connection.send(extension: .artworkReply, reply)
            return
        }

        // Deny artwork for buddy-only files when the requester is not a
        // buddy. Album art is embedded inside the file bytes, so leaking
        // it is a data leak even if we stop short of serving the full
        // upload. Matches the gate in handleSharesRequest / search.
        if indexedFile.visibility == .buddies {
            let isBuddy = isBuddy(username)
            if !isBuddy {
                logger.info("ArtworkRequest denied (buddy-only file, non-buddy requester): \(filePath)")
                let reply = MessageBuilder.artworkReplyMessage(token: token, imageData: Data())
                try? await connection.send(extension: .artworkReply, reply)
                return
            }
        }

        let localURL = URL(fileURLWithPath: indexedFile.localPath)

        // Extract artwork off-main-thread via MetadataReader actor
        let imageData = await metadataReader?.extractArtwork(from: localURL) ?? Data()

        logger.info("ArtworkRequest: sending \(imageData.count) bytes for \(filePath)")
        let reply = MessageBuilder.artworkReplyMessage(token: token, imageData: imageData)
        try? await connection.send(extension: .artworkReply, reply)
    }

    /// Off-actor linear scan of the share index for `handleArtworkRequest`.
    @concurrent
    private nonisolated static func findShareIndexMatch(
        fileIndex: [ShareManager.IndexedFile],
        filePath: String
    ) async -> ShareManager.IndexedFile? {
        fileIndex.first(where: { $0.sharedPath == filePath })
    }
}
