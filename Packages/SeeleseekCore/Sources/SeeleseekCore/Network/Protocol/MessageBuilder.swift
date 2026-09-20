import Foundation
import CryptoKit
import Compression

/// Message builder for SoulSeek protocol messages.
/// All methods are nonisolated to allow use from any actor context.
public enum MessageBuilder {
    // MARK: - Server Messages

    public nonisolated static func loginMessage(username: String, password: String) -> Data {
        serverMessage(.login) {
            $0.appendString(username)
            $0.appendString(password)

            // Client version
            $0.appendUInt32(169)

            // MD5 hash of username + password
            let hashInput = username + password
            let hashData = hashInput.data(using: .utf8) ?? Data()
            let digest = Insecure.MD5.hash(data: hashData)
            let hashHex = digest.map { String(format: "%02x", $0) }.joined()
            $0.appendString(hashHex)

            // Minor version
            $0.appendUInt32(3)
        }
    }

    public nonisolated static func setListenPortMessage(port: UInt32, obfuscatedPort: UInt32 = 0) -> Data {
        serverMessage(.setListenPort) {
            $0.appendUInt32(port)
            // The obfuscation block is optional on the wire. Only advertise if we
            // actually have a listener on the obfuscated port — otherwise peers
            // attempting obfuscated inbound would hit a dead port.
            if obfuscatedPort > 0 {
                $0.appendUInt32(ObfuscationType.rotated.rawValue)
                $0.appendUInt32(obfuscatedPort)
            }
        }
    }

    public nonisolated static func setOnlineStatusMessage(status: UserStatus) -> Data {
        serverMessage(.setOnlineStatus) { $0.appendUInt32(status.rawValue) }
    }

    public nonisolated static func sharedFoldersFilesMessage(folders: UInt32, files: UInt32) -> Data {
        serverMessage(.sharedFoldersFiles) {
            $0.appendUInt32(folders)
            $0.appendUInt32(files)
        }
    }

    public nonisolated static func pingMessage() -> Data {
        serverMessage(.ping)
    }

    public nonisolated static func fileSearchMessage(token: UInt32, query: String) -> Data {
        serverMessage(.fileSearch) {
            $0.appendUInt32(token)
            $0.appendString(query)
        }
    }

    public nonisolated static func joinRoomMessage(roomName: String, isPrivate: Bool = false) -> Data {
        serverMessage(.joinRoom) {
            $0.appendString(roomName)
            $0.appendUInt32(isPrivate ? 1 : 0)
        }
    }

    public nonisolated static func leaveRoomMessage(roomName: String) -> Data {
        serverMessage(.leaveRoom) { $0.appendString(roomName) }
    }

    public nonisolated static func sayInChatRoomMessage(roomName: String, message: String) -> Data {
        serverMessage(.sayInChatRoom) {
            $0.appendString(roomName)
            $0.appendString(message)
        }
    }

    public nonisolated static func privateMessageMessage(username: String, message: String) -> Data {
        serverMessage(.privateMessages) {
            $0.appendString(username)
            $0.appendString(message)
        }
    }

    public nonisolated static func acknowledgePrivateMessageMessage(messageId: UInt32) -> Data {
        serverMessage(.acknowledgePrivateMessage) { $0.appendUInt32(messageId) }
    }

    public nonisolated static func watchUserMessage(username: String) -> Data {
        serverMessage(.watchUser) { $0.appendString(username) }
    }

    public nonisolated static func unwatchUserMessage(username: String) -> Data {
        serverMessage(.unwatchUser) { $0.appendString(username) }
    }

    public nonisolated static func ignoreUserMessage(username: String) -> Data {
        serverMessage(.ignoreUser) { $0.appendString(username) }
    }

    public nonisolated static func unignoreUserMessage(username: String) -> Data {
        serverMessage(.unignoreUser) { $0.appendString(username) }
    }

    public nonisolated static func getUserStatusMessage(username: String) -> Data {
        serverMessage(.getUserStatus) { $0.appendString(username) }
    }

    public nonisolated static func connectToPeerMessage(token: UInt32, username: String, connectionType: String) -> Data {
        serverMessage(.connectToPeer) {
            $0.appendUInt32(token)
            $0.appendString(username)
            $0.appendString(connectionType)
        }
    }

    public nonisolated static func getRoomListMessage() -> Data {
        serverMessage(.roomList)
    }

    // MARK: - Peer Messages

    public nonisolated static func peerInitMessage(username: String, connectionType: String, token: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt8(PeerMessageCode.peerInit.rawValue)
        payload.appendString(username)
        payload.appendString(connectionType)
        payload.appendUInt32(token)
        return wrapMessage(payload)
    }

    public nonisolated static func pierceFirewallMessage(token: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt8(PeerMessageCode.pierceFirewall.rawValue)
        payload.appendUInt32(token)
        return wrapMessage(payload)
    }

    public nonisolated static func sharesRequestMessage() -> Data {
        peerMessage(.sharesRequest)
    }

    /// Build shares reply message (code 5) - zlib compressed.
    ///
    /// Protocol format (see `PROTOCOL_REFERENCE_FULL.md` Peer Code 5):
    ///   - uint32 directory count
    ///   - iterate directories (public)
    ///   - uint32 unknown (always 0)
    ///   - uint32 private directory count
    ///   - iterate directories (private / buddy-only)
    ///
    /// `privateFiles` is the second section. Pass empty for non-buddies;
    /// receivers ignore it unless the entries carry meaningful content.
    public nonisolated static func sharesReplyMessage(
        files: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])],
        privateFiles: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])] = []
    ) -> Data {
        var uncompressedPayload = Data()

        // Emits one "directories" block at whatever count position we choose.
        // Captured as a closure so public and private sections share one writer.
        func appendDirectories(_ dirs: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])]) {
            uncompressedPayload.appendUInt32(UInt32(dirs.count))
            for dir in dirs {
                uncompressedPayload.appendString(dir.directory)
                uncompressedPayload.appendUInt32(UInt32(dir.files.count))
                for file in dir.files {
                    uncompressedPayload.appendUInt8(1) // code
                    uncompressedPayload.appendString(file.filename)
                    uncompressedPayload.appendUInt64(file.size)
                    let ext = URL(fileURLWithPath: file.filename).pathExtension
                    uncompressedPayload.appendString(ext)

                    var attrs: [(UInt32, UInt32)] = []
                    if let bitrate = file.bitrate { attrs.append((0, bitrate)) }
                    if let duration = file.duration { attrs.append((1, duration)) }
                    uncompressedPayload.appendUInt32(UInt32(attrs.count))
                    for attr in attrs {
                        uncompressedPayload.appendUInt32(attr.0)
                        uncompressedPayload.appendUInt32(attr.1)
                    }
                }
            }
        }

        // Public section
        appendDirectories(files)

        // Unknown uint32 (always 0 per protocol)
        uncompressedPayload.appendUInt32(0)

        // Private (buddy-only) section
        appendDirectories(privateFiles)

        // Compress with zlib (mandatory for code 5 — receivers inflate
        // unconditionally, so an uncompressed fallback can never parse)
        let compressed = compressZlib(uncompressedPayload)

        return peerMessage(.sharesReply) { $0.append(compressed) }
    }

    public nonisolated static func userInfoRequestMessage() -> Data {
        peerMessage(.userInfoRequest)
    }

    /// UserInfoResponse (code 16) - respond to peer's request for our user info
    public nonisolated static func userInfoResponseMessage(
        description: String,
        picture: Data? = nil,
        totalUploads: UInt32,
        queueSize: UInt32,
        hasFreeSlots: Bool
    ) -> Data {
        peerMessage(.userInfoReply) {
            $0.appendString(description)

            if let picture = picture, !picture.isEmpty {
                $0.appendUInt8(1)  // has picture = true
                $0.appendUInt32(UInt32(picture.count))
                $0.append(picture)
            } else {
                $0.appendUInt8(0)  // has picture = false
            }

            $0.appendUInt32(totalUploads)
            $0.appendUInt32(queueSize)
            $0.appendUInt8(hasFreeSlots ? 1 : 0)
        }
    }

    /// Build a FileSearchResponse (peer code 9). `privateResults` is the
    /// buddy-only tail section (see protocol ref Peer Code 9: it carries
    /// both a public result list and a `number of privately shared
    /// results` list in the same message). Pass `[]` for non-buddies.
    public nonisolated static func searchReplyMessage(
        username: String,
        token: UInt32,
        results: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])],
        hasFreeSlots: Bool = true,
        uploadSpeed: UInt32 = 0,
        queueLength: UInt32 = 0,
        privateResults: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])] = []
    ) -> Data {
        var uncompressedPayload = Data()

        uncompressedPayload.appendString(username)
        uncompressedPayload.appendUInt32(token)

        func appendResults(_ rs: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])]) {
            uncompressedPayload.appendUInt32(UInt32(rs.count))
            for result in rs {
                uncompressedPayload.appendUInt8(1) // code
                uncompressedPayload.appendString(result.filename)
                uncompressedPayload.appendUInt64(result.size)
                uncompressedPayload.appendString(result.extension_)
                uncompressedPayload.appendUInt32(UInt32(result.attributes.count))
                for attr in result.attributes {
                    uncompressedPayload.appendUInt32(attr.0)
                    uncompressedPayload.appendUInt32(attr.1)
                }
            }
        }

        // Public results
        appendResults(results)

        uncompressedPayload.appendBool(hasFreeSlots)
        uncompressedPayload.appendUInt32(uploadSpeed)
        uncompressedPayload.appendUInt32(queueLength)

        // Unknown uint32 (always 0 per protocol)
        uncompressedPayload.appendUInt32(0)

        // Private (buddy-only) results
        appendResults(privateResults)

        // Compress with zlib (mandatory for code 9)
        let compressed = compressZlib(uncompressedPayload)

        return peerMessage(.searchReply) { $0.append(compressed) }
    }

    public nonisolated static func queueDownloadMessage(filename: String) -> Data {
        peerMessage(.queueDownload) { $0.appendString(filename) }
    }

    /// Request contents of a specific folder (code 36)
    public nonisolated static func folderContentsRequestMessage(token: UInt32, folder: String) -> Data {
        peerMessage(.folderContentsRequest) {
            $0.appendUInt32(token)
            $0.appendString(folder)
        }
    }

    /// Response with folder contents (code 37) - zlib compressed
    public nonisolated static func folderContentsResponseMessage(token: UInt32, folder: String, files: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])]) -> Data {
        var uncompressedPayload = Data()

        // uint32 token
        uncompressedPayload.appendUInt32(token)

        // string folder
        uncompressedPayload.appendString(folder)

        // uint32 number of folders (1 - the requested folder)
        uncompressedPayload.appendUInt32(1)

        // Directory entry: string directory name
        uncompressedPayload.appendString(folder)

        // uint32 file count
        uncompressedPayload.appendUInt32(UInt32(files.count))

        for file in files {
            // uint8 code (always 1)
            uncompressedPayload.appendUInt8(1)
            // string filename
            uncompressedPayload.appendString(file.filename)
            // uint64 size
            uncompressedPayload.appendUInt64(file.size)
            // string extension
            uncompressedPayload.appendString(file.extension_)
            // uint32 attribute count + attributes
            uncompressedPayload.appendUInt32(UInt32(file.attributes.count))
            for attr in file.attributes {
                uncompressedPayload.appendUInt32(attr.0)
                uncompressedPayload.appendUInt32(attr.1)
            }
        }

        // Compress with zlib (mandatory for code 37)
        let compressedPayload = compressZlib(uncompressedPayload)
        return peerMessage(.folderContentsReply) { $0.append(compressedPayload) }
    }

    /// Compress data using zlib. Always produces a valid zlib stream —
    /// codes 5/9/37 are mandatorily compressed on the wire, so there is
    /// no legal uncompressed fallback.
    nonisolated private static func compressZlib(_ data: Data) -> Data {
        var compressed = Data()
        // Add zlib header
        compressed.append(0x78)  // CMF: compression method 8 (deflate), window size 7
        compressed.append(0x9C)  // FLG: default compression level

        // Deflate can EXPAND incompressible input (~5 bytes per 16KB block);
        // without headroom, encode returns 0 for >64KB payloads that don't
        // compress below input size.
        let bufferSize = data.count + data.count / 16 + 64 + 6
        var compressedBuffer = [UInt8](repeating: 0, count: bufferSize)

        let compressedSize = data.withUnsafeBytes { sourceBuffer -> Int in
            guard let baseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_encode_buffer(
                &compressedBuffer,
                bufferSize,
                baseAddress,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if compressedSize > 0 {
            compressed.append(Data(compressedBuffer.prefix(compressedSize)))
        } else {
            // Shouldn't be reachable with proper headroom (empty input is the
            // one known case) — emit DEFLATE stored blocks so the output is
            // still a stream the receiver can inflate.
            compressed.append(storedDeflateBlocks(data))
        }

        // Add Adler-32 checksum
        let checksum = ZlibDecompression.adler32(data)
        var bigEndianChecksum = checksum.bigEndian
        compressed.append(Data(bytes: &bigEndianChecksum, count: 4))

        return compressed
    }

    /// RFC 1951 stored (uncompressed) blocks: 1-byte BFINAL/BTYPE=00 header,
    /// LEN + NLEN (one's complement) little-endian, then raw bytes; max
    /// 65535 bytes per block.
    nonisolated private static func storedDeflateBlocks(_ data: Data) -> Data {
        var out = Data()
        var index = data.startIndex
        repeat {
            let chunkEnd = data.index(index, offsetBy: 65535, limitedBy: data.endIndex) ?? data.endIndex
            let chunk = data[index..<chunkEnd]
            let isFinal = chunkEnd == data.endIndex
            out.append(isFinal ? 0x01 : 0x00)
            let len = UInt16(chunk.count)
            out.append(UInt8(len & 0xFF))
            out.append(UInt8(len >> 8))
            let nlen = ~len
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8(nlen >> 8))
            out.append(chunk)
            index = chunkEnd
        } while index < data.endIndex
        return out
    }

    public nonisolated static func transferRequestMessage(direction: FileTransferDirection, token: UInt32, filename: String, fileSize: UInt64? = nil) -> Data {
        peerMessage(.transferRequest) {
            $0.appendUInt32(UInt32(direction.rawValue))
            $0.appendUInt32(token)
            $0.appendString(filename)
            if direction == .upload {
                // Mandatory per protocol: a code-40 upload request without the
                // uint64 size is truncated on the wire and the receiving peer
                // silently drops it. Zero-byte files legitimately send 0.
                assert(fileSize != nil, "upload TransferRequest requires fileSize")
                $0.appendUInt64(fileSize ?? 0)
            }
        }
    }

    /// Reply to a transfer request - allowed=true means we accept the transfer.
    /// For deprecated download-response flow (peer code 41a), include fileSize when allowed.
    public nonisolated static func transferReplyMessage(token: UInt32, allowed: Bool, fileSize: UInt64? = nil, reason: String? = nil) -> Data {
        peerMessage(.transferReply) {
            $0.appendUInt32(token)
            $0.appendBool(allowed)
            if allowed, let fileSize {
                $0.appendUInt64(fileSize)
            } else if !allowed, let reason {
                $0.appendString(reason)
            }
        }
    }

    /// Send place in queue response (code 44)
    public nonisolated static func placeInQueueResponseMessage(filename: String, place: UInt32) -> Data {
        peerMessage(.placeInQueueReply) {
            $0.appendString(filename)
            $0.appendUInt32(place)
        }
    }

    /// Send place in queue request (code 51) - ask uploader for our queue position
    public nonisolated static func placeInQueueRequestMessage(filename: String) -> Data {
        peerMessage(.placeInQueueRequest) { $0.appendString(filename) }
    }

    /// Send upload denied response (code 50)
    public nonisolated static func uploadDeniedMessage(filename: String, reason: String) -> Data {
        peerMessage(.uploadDenied) {
            $0.appendString(filename)
            $0.appendString(reason)
        }
    }

    /// Send upload failed response (code 46)
    public nonisolated static func uploadFailedMessage(filename: String) -> Data {
        peerMessage(.uploadFailed) { $0.appendString(filename) }
    }

    // MARK: - Additional Server Messages

    public nonisolated static func getUserAddress(_ username: String) -> Data {
        serverMessage(.getPeerAddress) { $0.appendString(username) }
    }

    public nonisolated static func cantConnectToPeer(token: UInt32, username: String) -> Data {
        serverMessage(.cantConnectToPeer) {
            $0.appendUInt32(token)
            $0.appendString(username)
        }
    }

    // MARK: - User Interests & Recommendations

    /// Add something I like (code 51)
    public nonisolated static func addThingILike(_ item: String) -> Data {
        serverMessage(.addThingILike) { $0.appendString(item) }
    }

    /// Remove something I like (code 52)
    public nonisolated static func removeThingILike(_ item: String) -> Data {
        serverMessage(.removeThingILike) { $0.appendString(item) }
    }

    /// Get my recommendations (code 54)
    public nonisolated static func getRecommendations() -> Data {
        serverMessage(.recommendations)
    }

    /// Get global network-wide recommendations (code 56)
    public nonisolated static func getGlobalRecommendations() -> Data {
        serverMessage(.globalRecommendations)
    }

    /// Get user's interests (code 57)
    public nonisolated static func getUserInterests(_ username: String) -> Data {
        serverMessage(.userInterests) { $0.appendString(username) }
    }

    /// Get similar users (code 110)
    public nonisolated static func getSimilarUsers() -> Data {
        serverMessage(.similarUsers)
    }

    /// Get item recommendations (code 111)
    public nonisolated static func getItemRecommendations(_ item: String) -> Data {
        serverMessage(.itemRecommendations) { $0.appendString(item) }
    }

    /// Get similar users for item (code 112)
    public nonisolated static func getItemSimilarUsers(_ item: String) -> Data {
        serverMessage(.itemSimilarUsers) { $0.appendString(item) }
    }

    /// Add something I hate (code 117)
    public nonisolated static func addThingIHate(_ item: String) -> Data {
        serverMessage(.addThingIHate) { $0.appendString(item) }
    }

    /// Remove something I hate (code 118)
    public nonisolated static func removeThingIHate(_ item: String) -> Data {
        serverMessage(.removeThingIHate) { $0.appendString(item) }
    }

    // MARK: - User Stats & Privileges

    /// Get user stats (code 36)
    public nonisolated static func getUserStats(_ username: String) -> Data {
        serverMessage(.getUserStats) { $0.appendString(username) }
    }

    /// Check our privileges (code 92)
    public nonisolated static func checkPrivileges() -> Data {
        serverMessage(.checkPrivileges)
    }

    /// Get user privileges (code 122)
    public nonisolated static func getUserPrivileges(_ username: String) -> Data {
        serverMessage(.userPrivileges) { $0.appendString(username) }
    }

    // MARK: - Room Tickers

    /// Set room ticker (code 116)
    public nonisolated static func setRoomTicker(room: String, ticker: String) -> Data {
        serverMessage(.roomTickerSet) {
            $0.appendString(room)
            $0.appendString(ticker)
        }
    }

    // MARK: - Room Search & Wishlist

    /// Search in a specific room (code 120)
    public nonisolated static func roomSearch(room: String, token: UInt32, query: String) -> Data {
        serverMessage(.roomSearch) {
            $0.appendString(room)
            $0.appendUInt32(token)
            $0.appendString(query)
        }
    }

    /// Add a wishlist search (code 103)
    public nonisolated static func wishlistSearch(token: UInt32, query: String) -> Data {
        serverMessage(.wishlistSearch) {
            $0.appendUInt32(token)
            $0.appendString(query)
        }
    }

    // MARK: - Private Rooms

    /// Add a member to a private room (code 134)
    public nonisolated static func privateRoomAddMember(room: String, username: String) -> Data {
        serverMessage(.privateRoomAddMember) {
            $0.appendString(room)
            $0.appendString(username)
        }
    }

    /// Remove a member from a private room (code 135)
    public nonisolated static func privateRoomRemoveMember(room: String, username: String) -> Data {
        serverMessage(.privateRoomRemoveMember) {
            $0.appendString(room)
            $0.appendString(username)
        }
    }

    /// Leave a private room (code 136)
    public nonisolated static func privateRoomCancelMembership(room: String) -> Data {
        serverMessage(.privateRoomCancelMembership) { $0.appendString(room) }
    }

    /// Give up ownership of a private room (code 137)
    public nonisolated static func privateRoomCancelOwnership(room: String) -> Data {
        serverMessage(.privateRoomCancelOwnership) { $0.appendString(room) }
    }

    /// Add an operator to a private room (code 143)
    public nonisolated static func privateRoomAddOperator(room: String, username: String) -> Data {
        serverMessage(.privateRoomAddOperator) {
            $0.appendString(room)
            $0.appendString(username)
        }
    }

    /// Remove an operator from a private room (code 144)
    public nonisolated static func privateRoomRemoveOperator(room: String, username: String) -> Data {
        serverMessage(.privateRoomRemoveOperator) {
            $0.appendString(room)
            $0.appendString(username)
        }
    }

    // MARK: - Distributed Network Messages

    /// Tell server we have no distributed parent and need one
    public nonisolated static func haveNoParent(_ haveNoParent: Bool) -> Data {
        serverMessage(.haveNoParent) { $0.appendBool(haveNoParent) }
    }

    /// Tell server whether we accept child connections
    public nonisolated static func acceptChildren(_ accept: Bool) -> Data {
        serverMessage(.acceptChildren) { $0.appendBool(accept) }
    }

    /// Tell server our branch level in the distributed network
    public nonisolated static func branchLevel(_ level: UInt32) -> Data {
        serverMessage(.branchLevel) { $0.appendUInt32(level) }
    }

    /// Tell server our branch root username
    public nonisolated static func branchRoot(_ username: String) -> Data {
        serverMessage(.branchRoot) { $0.appendString(username) }
    }

    /// Tell server our child depth
    public nonisolated static func childDepth(_ depth: UInt32) -> Data {
        serverMessage(.childDepth) { $0.appendUInt32(depth) }
    }

    // MARK: - User Search

    /// Search a specific user's files (code 42)
    public nonisolated static func userSearchMessage(username: String, token: UInt32, query: String) -> Data {
        serverMessage(.userSearch) {
            $0.appendString(username)
            $0.appendUInt32(token)
            $0.appendString(query)
        }
    }

    // MARK: - Upload Speed & Privileges

    /// Report upload speed to server (code 121)
    public nonisolated static func sendUploadSpeedMessage(speed: UInt32) -> Data {
        serverMessage(.sendUploadSpeedRequest) { $0.appendUInt32(speed) }
    }

    /// Give privileges to another user (code 123)
    public nonisolated static func givePrivilegesMessage(username: String, days: UInt32) -> Data {
        serverMessage(.givePrivileges) {
            $0.appendString(username)
            $0.appendUInt32(days)
        }
    }

    // MARK: - Room Invitations

    /// Enable or disable room invitations (code 141)
    public nonisolated static func enableRoomInvitationsMessage(enable: Bool) -> Data {
        serverMessage(.enableRoomInvitations) { $0.appendBool(enable) }
    }

    // MARK: - Bulk Messaging

    /// Send a message to multiple users at once (code 149)
    public nonisolated static func messageUsersMessage(usernames: [String], message: String) -> Data {
        serverMessage(.messageUsers) {
            $0.appendUInt32(UInt32(usernames.count))
            for username in usernames {
                $0.appendString(username)
            }
            $0.appendString(message)
        }
    }

    // MARK: - Global Room

    /// Join the global room (code 150)
    public nonisolated static func joinGlobalRoomMessage() -> Data {
        serverMessage(.joinGlobalRoom)
    }

    /// Leave the global room (code 151)
    public nonisolated static func leaveGlobalRoomMessage() -> Data {
        serverMessage(.leaveGlobalRoom)
    }

    // MARK: - SeeleSeek Extension Messages

    /// ExtendedClientInfo (code 10000) — advertise which extension codes we speak.
    ///
    /// `clientInfo` goes on the wire verbatim. Nothing in our own logic may
    /// depend on its value: peers choose it freely and can lie.
    public nonisolated static func extendedClientInfoMessage(
        advertising codes: [ExtendedClientInfoCode] = ExtendedClientInfoCode.advertised,
        clientInfo: String = ExtendedClientInfo.localClientInfo
    ) -> Data {
        extensionMessage(.extendedClientInfo) {
            $0.appendUInt32(ExtendedClientInfo.currentRevision)
            $0.appendString(clientInfo)
            $0.appendUInt32(UInt32(codes.count))
            for code in codes {
                $0.appendUInt32(code.rawValue)
                $0.appendString(code.wireName)
                $0.appendUInt32(0) // reserved
            }
        }
    }

    /// Artwork request (code 10001) — ask peer for album art embedded in a file.
    public nonisolated static func artworkRequestMessage(token: UInt32, filePath: String) -> Data {
        extensionMessage(.artworkRequest) {
            $0.appendUInt32(token)
            $0.appendString(filePath)
        }
    }

    /// Artwork reply (code 10002) — respond with image data (or empty if none found).
    public nonisolated static func artworkReplyMessage(token: UInt32, imageData: Data) -> Data {
        extensionMessage(.artworkReply) {
            $0.appendUInt32(token)
            // Write raw image bytes (length is implicit from message frame)
            $0.append(imageData)
        }
    }

    // MARK: - Utilities

    nonisolated private static func serverMessage(_ code: ServerMessageCode, _ fields: (inout Data) -> Void = { _ in }) -> Data {
        framed(code.rawValue, fields)
    }

    nonisolated private static func peerMessage(_ code: PeerMessageCode, _ fields: (inout Data) -> Void = { _ in }) -> Data {
        // PeerInit/PierceFirewall are one-byte codes with no uint32 frame.
        precondition(code != .peerInit && code != .pierceFirewall)
        return framed(UInt32(code.rawValue), fields)
    }

    nonisolated private static func extensionMessage(_ code: ExtendedClientInfoCode, _ fields: (inout Data) -> Void = { _ in }) -> Data {
        framed(code.rawValue, fields)
    }

    /// uint32 code, then `fields`, wrapped in the length prefix.
    nonisolated private static func framed(_ code: UInt32, _ fields: (inout Data) -> Void) -> Data {
        var payload = Data()
        payload.appendUInt32(code)
        fields(&payload)
        return wrapMessage(payload)
    }

    nonisolated private static func wrapMessage(_ payload: Data) -> Data {
        var message = Data()
        message.appendUInt32(UInt32(payload.count))
        message.append(payload)
        return message
    }
}
