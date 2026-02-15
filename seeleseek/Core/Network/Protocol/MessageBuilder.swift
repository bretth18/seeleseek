import Foundation
import CryptoKit
import Compression

/// Message builder for SoulSeek protocol messages.
/// All methods are nonisolated to allow use from any actor context.
enum MessageBuilder {
    // MARK: - Server Messages

    nonisolated static func loginMessage(username: String, password: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.login.rawValue)
        payload.appendString(username)
        payload.appendString(password)

        // Client version
        payload.appendUInt32(160)

        // MD5 hash of username + password
        let hashInput = username + password
        let hashData = hashInput.data(using: .utf8) ?? Data()
        let digest = Insecure.MD5.hash(data: hashData)
        let hashHex = digest.map { String(format: "%02x", $0) }.joined()
        payload.appendString(hashHex)

        // Minor version
        payload.appendUInt32(3)

        return wrapMessage(payload)
    }

    nonisolated static func setListenPortMessage(port: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.setListenPort.rawValue)
        payload.appendUInt32(port)
        return wrapMessage(payload)
    }

    nonisolated static func setOnlineStatusMessage(status: UserStatus) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.setOnlineStatus.rawValue)
        payload.appendUInt32(status.rawValue)
        return wrapMessage(payload)
    }

    nonisolated static func sharedFoldersFilesMessage(folders: UInt32, files: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.sharedFoldersFiles.rawValue)
        payload.appendUInt32(folders)
        payload.appendUInt32(files)
        return wrapMessage(payload)
    }

    nonisolated static func pingMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.ping.rawValue)
        return wrapMessage(payload)
    }

    nonisolated static func fileSearchMessage(token: UInt32, query: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.fileSearch.rawValue)
        payload.appendUInt32(token)
        payload.appendString(query)
        return wrapMessage(payload)
    }

    nonisolated static func joinRoomMessage(roomName: String, isPrivate: Bool = false) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.joinRoom.rawValue)
        payload.appendString(roomName)
        payload.appendUInt32(isPrivate ? 1 : 0)
        return wrapMessage(payload)
    }

    nonisolated static func leaveRoomMessage(roomName: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.leaveRoom.rawValue)
        payload.appendString(roomName)
        return wrapMessage(payload)
    }

    nonisolated static func sayInChatRoomMessage(roomName: String, message: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.sayInChatRoom.rawValue)
        payload.appendString(roomName)
        payload.appendString(message)
        return wrapMessage(payload)
    }

    nonisolated static func privateMessageMessage(username: String, message: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateMessages.rawValue)
        payload.appendString(username)
        payload.appendString(message)
        return wrapMessage(payload)
    }

    nonisolated static func acknowledgePrivateMessageMessage(messageId: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.acknowledgePrivateMessage.rawValue)
        payload.appendUInt32(messageId)
        return wrapMessage(payload)
    }

    nonisolated static func watchUserMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.watchUser.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func unwatchUserMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.unwatchUser.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func ignoreUserMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.ignoreUser.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func unignoreUserMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.unignoreUser.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func getUserStatusMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.getUserStatus.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func connectToPeerMessage(token: UInt32, username: String, connectionType: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.connectToPeer.rawValue)
        payload.appendUInt32(token)
        payload.appendString(username)
        payload.appendString(connectionType)
        return wrapMessage(payload)
    }

    nonisolated static func getRoomListMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.roomList.rawValue)
        return wrapMessage(payload)
    }

    // MARK: - Peer Messages

    nonisolated static func peerInitMessage(username: String, connectionType: String, token: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt8(PeerMessageCode.peerInit.rawValue)
        payload.appendString(username)
        payload.appendString(connectionType)
        payload.appendUInt32(token)
        return wrapMessage(payload)
    }

    nonisolated static func pierceFirewallMessage(token: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt8(PeerMessageCode.pierceFirewall.rawValue)
        payload.appendUInt32(token)
        return wrapMessage(payload)
    }

    nonisolated static func sharesRequestMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.sharesRequest.rawValue))
        return wrapMessage(payload)
    }

    /// Build shares reply message (code 5) - zlib compressed
    /// Format: directory count, then for each directory: name, file count, files
    nonisolated static func sharesReplyMessage(files: [(directory: String, files: [(filename: String, size: UInt64, bitrate: UInt32?, duration: UInt32?)])]) -> Data {
        var uncompressedPayload = Data()

        // Directory count
        uncompressedPayload.appendUInt32(UInt32(files.count))

        for dir in files {
            // Directory name
            uncompressedPayload.appendString(dir.directory)
            // File count
            uncompressedPayload.appendUInt32(UInt32(dir.files.count))

            for file in dir.files {
                // Code byte
                uncompressedPayload.appendUInt8(1)
                // Filename (just the name, not full path)
                uncompressedPayload.appendString(file.filename)
                // Size
                uncompressedPayload.appendUInt64(file.size)
                // Extension
                let ext = URL(fileURLWithPath: file.filename).pathExtension
                uncompressedPayload.appendString(ext)

                // Attributes
                var attrs: [(UInt32, UInt32)] = []
                if let bitrate = file.bitrate {
                    attrs.append((0, bitrate))
                }
                if let duration = file.duration {
                    attrs.append((1, duration))
                }
                uncompressedPayload.appendUInt32(UInt32(attrs.count))
                for attr in attrs {
                    uncompressedPayload.appendUInt32(attr.0)
                    uncompressedPayload.appendUInt32(attr.1)
                }
            }
        }

        // Unknown uint32 (always 0 per protocol)
        uncompressedPayload.appendUInt32(0)

        // Private directory count (0 = no private shares)
        uncompressedPayload.appendUInt32(0)

        // Compress with zlib
        guard let compressed = compressZlib(uncompressedPayload) else {
            // Fallback: send uncompressed (not ideal but better than nothing)
            var payload = Data()
            payload.appendUInt32(UInt32(PeerMessageCode.sharesReply.rawValue))
            payload.append(uncompressedPayload)
            return wrapMessage(payload)
        }

        // Build final message
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.sharesReply.rawValue))
        payload.append(compressed)

        return wrapMessage(payload)
    }

    nonisolated static func userInfoRequestMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.userInfoRequest.rawValue))
        return wrapMessage(payload)
    }

    /// UserInfoResponse (code 16) - respond to peer's request for our user info
    nonisolated static func userInfoResponseMessage(
        description: String,
        picture: Data? = nil,
        totalUploads: UInt32,
        queueSize: UInt32,
        hasFreeSlots: Bool
    ) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.userInfoReply.rawValue))
        payload.appendString(description)

        if let picture = picture, !picture.isEmpty {
            payload.appendUInt8(1)  // has picture = true
            payload.appendUInt32(UInt32(picture.count))
            payload.append(picture)
        } else {
            payload.appendUInt8(0)  // has picture = false
        }

        payload.appendUInt32(totalUploads)
        payload.appendUInt32(queueSize)
        payload.appendUInt8(hasFreeSlots ? 1 : 0)

        return wrapMessage(payload)
    }

    nonisolated static func searchReplyMessage(
        username: String,
        token: UInt32,
        results: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])],
        hasFreeSlots: Bool = true,
        uploadSpeed: UInt32 = 0,
        queueLength: UInt32 = 0
    ) -> Data {
        var uncompressedPayload = Data()

        uncompressedPayload.appendString(username)
        uncompressedPayload.appendUInt32(token)
        uncompressedPayload.appendUInt32(UInt32(results.count))

        for result in results {
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

        uncompressedPayload.appendBool(hasFreeSlots)
        uncompressedPayload.appendUInt32(uploadSpeed)
        uncompressedPayload.appendUInt32(queueLength)

        // Unknown uint32 (always 0 per protocol)
        uncompressedPayload.appendUInt32(0)

        // Private results count (0 = no private results)
        uncompressedPayload.appendUInt32(0)

        // Compress with zlib
        guard let compressed = compressZlib(uncompressedPayload) else {
            // Fallback: send uncompressed (not ideal but better than nothing)
            var payload = Data()
            payload.appendUInt32(UInt32(PeerMessageCode.searchReply.rawValue))
            payload.append(uncompressedPayload)
            return wrapMessage(payload)
        }

        // Build final message
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.searchReply.rawValue))
        payload.append(compressed)

        return wrapMessage(payload)
    }

    nonisolated static func queueDownloadMessage(filename: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.queueDownload.rawValue))
        payload.appendString(filename)
        return wrapMessage(payload)
    }

    /// Request contents of a specific folder (code 36)
    nonisolated static func folderContentsRequestMessage(token: UInt32, folder: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.folderContentsRequest.rawValue))
        payload.appendUInt32(token)
        payload.appendString(folder)
        return wrapMessage(payload)
    }

    /// Response with folder contents (code 37) - zlib compressed
    nonisolated static func folderContentsResponseMessage(token: UInt32, folder: String, files: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])]) -> Data {
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

        // Compress with zlib
        let compressedPayload = compressZlib(uncompressedPayload) ?? uncompressedPayload

        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.folderContentsReply.rawValue))
        payload.append(compressedPayload)

        return wrapMessage(payload)
    }

    /// Compress data using zlib
    nonisolated private static func compressZlib(_ data: Data) -> Data? {
        var compressed = Data()
        // Add zlib header
        compressed.append(0x78)  // CMF: compression method 8 (deflate), window size 7
        compressed.append(0x9C)  // FLG: default compression level

        let bufferSize = max(65536, data.count)  // At least 64KB, or input size
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

        guard compressedSize > 0 else { return nil }
        compressed.append(Data(compressedBuffer.prefix(compressedSize)))

        // Add Adler-32 checksum
        let checksum = adler32(data)
        var bigEndianChecksum = checksum.bigEndian
        compressed.append(Data(bytes: &bigEndianChecksum, count: 4))

        return compressed
    }

    /// Calculate Adler-32 checksum for zlib
    nonisolated private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        let MOD_ADLER: UInt32 = 65521

        for byte in data {
            a = (a + UInt32(byte)) % MOD_ADLER
            b = (b + a) % MOD_ADLER
        }

        return (b << 16) | a
    }

    nonisolated static func transferRequestMessage(direction: FileTransferDirection, token: UInt32, filename: String, fileSize: UInt64? = nil) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.transferRequest.rawValue))
        payload.appendUInt32(UInt32(direction.rawValue))
        payload.appendUInt32(token)
        payload.appendString(filename)
        if direction == .upload, let size = fileSize {
            payload.appendUInt64(size)
        }
        return wrapMessage(payload)
    }

    /// Reply to a transfer request - allowed=true means we accept the transfer.
    /// For deprecated download-response flow (peer code 41a), include fileSize when allowed.
    nonisolated static func transferReplyMessage(token: UInt32, allowed: Bool, fileSize: UInt64? = nil, reason: String? = nil) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.transferReply.rawValue))
        payload.appendUInt32(token)
        payload.appendBool(allowed)
        if allowed, let fileSize {
            payload.appendUInt64(fileSize)
        } else if !allowed, let reason {
            payload.appendString(reason)
        }
        return wrapMessage(payload)
    }

    /// Send place in queue response (code 44)
    nonisolated static func placeInQueueResponseMessage(filename: String, place: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.placeInQueueReply.rawValue))
        payload.appendString(filename)
        payload.appendUInt32(place)
        return wrapMessage(payload)
    }

    /// Send place in queue request (code 51) - ask uploader for our queue position
    nonisolated static func placeInQueueRequestMessage(filename: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.placeInQueueRequest.rawValue))
        payload.appendString(filename)
        return wrapMessage(payload)
    }

    /// Send upload denied response (code 50)
    nonisolated static func uploadDeniedMessage(filename: String, reason: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.uploadDenied.rawValue))
        payload.appendString(filename)
        payload.appendString(reason)
        return wrapMessage(payload)
    }

    /// Send upload failed response (code 46)
    nonisolated static func uploadFailedMessage(filename: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.uploadFailed.rawValue))
        payload.appendString(filename)
        return wrapMessage(payload)
    }

    // MARK: - Additional Server Messages

    nonisolated static func getUserAddress(_ username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.getPeerAddress.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func cantConnectToPeer(token: UInt32, username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.cantConnectToPeer.rawValue)
        payload.appendUInt32(token)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    // MARK: - User Interests & Recommendations

    /// Add something I like (code 51)
    nonisolated static func addThingILike(_ item: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.addThingILike.rawValue)
        payload.appendString(item)
        return wrapMessage(payload)
    }

    /// Remove something I like (code 52)
    nonisolated static func removeThingILike(_ item: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.removeThingILike.rawValue)
        payload.appendString(item)
        return wrapMessage(payload)
    }

    /// Get my recommendations (code 54)
    nonisolated static func getRecommendations() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.recommendations.rawValue)
        return wrapMessage(payload)
    }

    /// Get global network-wide recommendations (code 56)
    nonisolated static func getGlobalRecommendations() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.globalRecommendations.rawValue)
        return wrapMessage(payload)
    }

    /// Get user's interests (code 57)
    nonisolated static func getUserInterests(_ username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.userInterests.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    /// Get similar users (code 110)
    nonisolated static func getSimilarUsers() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.similarUsers.rawValue)
        return wrapMessage(payload)
    }

    /// Get item recommendations (code 111)
    nonisolated static func getItemRecommendations(_ item: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.itemRecommendations.rawValue)
        payload.appendString(item)
        return wrapMessage(payload)
    }

    /// Get similar users for item (code 112)
    nonisolated static func getItemSimilarUsers(_ item: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.itemSimilarUsers.rawValue)
        payload.appendString(item)
        return wrapMessage(payload)
    }

    /// Add something I hate (code 117)
    nonisolated static func addThingIHate(_ item: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.addThingIHate.rawValue)
        payload.appendString(item)
        return wrapMessage(payload)
    }

    /// Remove something I hate (code 118)
    nonisolated static func removeThingIHate(_ item: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.removeThingIHate.rawValue)
        payload.appendString(item)
        return wrapMessage(payload)
    }

    // MARK: - User Stats & Privileges

    /// Get user stats (code 36)
    nonisolated static func getUserStats(_ username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.getUserStats.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    /// Check our privileges (code 92)
    nonisolated static func checkPrivileges() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.checkPrivileges.rawValue)
        return wrapMessage(payload)
    }

    /// Get user privileges (code 122)
    nonisolated static func getUserPrivileges(_ username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.userPrivileges.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    // MARK: - Room Tickers

    /// Set room ticker (code 116)
    nonisolated static func setRoomTicker(room: String, ticker: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.roomTickerSet.rawValue)
        payload.appendString(room)
        payload.appendString(ticker)
        return wrapMessage(payload)
    }

    // MARK: - Room Search & Wishlist

    /// Search in a specific room (code 120)
    nonisolated static func roomSearch(room: String, token: UInt32, query: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.roomSearch.rawValue)
        payload.appendString(room)
        payload.appendUInt32(token)
        payload.appendString(query)
        return wrapMessage(payload)
    }

    /// Legacy room search code 25 (still used by some peers/servers)
    nonisolated static func fileSearchRoomMessage(room: String, token: UInt32, query: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.fileSearchRoom.rawValue)
        payload.appendString(room)
        payload.appendUInt32(token)
        payload.appendString(query)
        return wrapMessage(payload)
    }

    /// Add a wishlist search (code 103)
    nonisolated static func wishlistSearch(token: UInt32, query: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.wishlistSearch.rawValue)
        payload.appendUInt32(token)
        payload.appendString(query)
        return wrapMessage(payload)
    }

    // MARK: - Private Rooms

    /// Add a member to a private room (code 134)
    nonisolated static func privateRoomAddMember(room: String, username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateRoomAddMember.rawValue)
        payload.appendString(room)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    /// Remove a member from a private room (code 135)
    nonisolated static func privateRoomRemoveMember(room: String, username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateRoomRemoveMember.rawValue)
        payload.appendString(room)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    /// Leave a private room (code 136)
    nonisolated static func privateRoomCancelMembership(room: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateRoomCancelMembership.rawValue)
        payload.appendString(room)
        return wrapMessage(payload)
    }

    /// Give up ownership of a private room (code 137)
    nonisolated static func privateRoomCancelOwnership(room: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateRoomCancelOwnership.rawValue)
        payload.appendString(room)
        return wrapMessage(payload)
    }

    /// Add an operator to a private room (code 143)
    nonisolated static func privateRoomAddOperator(room: String, username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateRoomAddOperator.rawValue)
        payload.appendString(room)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    /// Remove an operator from a private room (code 144)
    nonisolated static func privateRoomRemoveOperator(room: String, username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateRoomRemoveOperator.rawValue)
        payload.appendString(room)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    // MARK: - Distributed Network Messages

    /// Tell server we have no distributed parent and need one
    nonisolated static func haveNoParent(_ haveNoParent: Bool) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.haveNoParent.rawValue)
        payload.appendBool(haveNoParent)
        return wrapMessage(payload)
    }

    /// Tell server whether we accept child connections
    nonisolated static func acceptChildren(_ accept: Bool) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.acceptChildren.rawValue)
        payload.appendBool(accept)
        return wrapMessage(payload)
    }

    /// Tell server our branch level in the distributed network
    nonisolated static func branchLevel(_ level: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.branchLevel.rawValue)
        payload.appendUInt32(level)
        return wrapMessage(payload)
    }

    /// Tell server our branch root username
    nonisolated static func branchRoot(_ username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.branchRoot.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    /// Tell server our child depth
    nonisolated static func childDepth(_ depth: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.childDepth.rawValue)
        payload.appendUInt32(depth)
        return wrapMessage(payload)
    }

    // MARK: - User Search

    /// Search a specific user's files (code 42)
    nonisolated static func userSearchMessage(username: String, token: UInt32, query: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.userSearch.rawValue)
        payload.appendString(username)
        payload.appendUInt32(token)
        payload.appendString(query)
        return wrapMessage(payload)
    }

    // MARK: - Upload Speed & Privileges

    /// Report upload speed to server (code 121)
    nonisolated static func sendUploadSpeedMessage(speed: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.sendUploadSpeedRequest.rawValue)
        payload.appendUInt32(speed)
        return wrapMessage(payload)
    }

    /// Give privileges to another user (code 123)
    nonisolated static func givePrivilegesMessage(username: String, days: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.givePrivileges.rawValue)
        payload.appendString(username)
        payload.appendUInt32(days)
        return wrapMessage(payload)
    }

    // MARK: - Room Invitations

    /// Enable or disable room invitations (code 141)
    nonisolated static func enableRoomInvitationsMessage(enable: Bool) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.enableRoomInvitations.rawValue)
        payload.appendBool(enable)
        return wrapMessage(payload)
    }

    // MARK: - Bulk Messaging

    /// Send a message to multiple users at once (code 149)
    nonisolated static func messageUsersMessage(usernames: [String], message: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.messageUsers.rawValue)
        payload.appendUInt32(UInt32(usernames.count))
        for username in usernames {
            payload.appendString(username)
        }
        payload.appendString(message)
        return wrapMessage(payload)
    }

    // MARK: - Global Room

    /// Join the global room (code 150)
    nonisolated static func joinGlobalRoomMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.joinGlobalRoom.rawValue)
        return wrapMessage(payload)
    }

    /// Leave the global room (code 151)
    nonisolated static func leaveGlobalRoomMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.leaveGlobalRoom.rawValue)
        return wrapMessage(payload)
    }

    // MARK: - SeeleSeek Extension Messages

    /// SeeleSeek handshake (code 10000) — identify ourselves as a SeeleSeek client.
    /// Sent right after PeerInit. Payload: uint8 version (currently 1).
    nonisolated static func seeleseekHandshakeMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(SeeleSeekPeerCode.handshake.rawValue)
        payload.appendUInt8(1) // protocol version
        return wrapMessage(payload)
    }

    /// Artwork request (code 10001) — ask peer for album art embedded in a file.
    nonisolated static func artworkRequestMessage(token: UInt32, filePath: String) -> Data {
        var payload = Data()
        payload.appendUInt32(SeeleSeekPeerCode.artworkRequest.rawValue)
        payload.appendUInt32(token)
        payload.appendString(filePath)
        return wrapMessage(payload)
    }

    /// Artwork reply (code 10002) — respond with image data (or empty if none found).
    nonisolated static func artworkReplyMessage(token: UInt32, imageData: Data) -> Data {
        var payload = Data()
        payload.appendUInt32(SeeleSeekPeerCode.artworkReply.rawValue)
        payload.appendUInt32(token)
        // Write raw image bytes (length is implicit from message frame)
        payload.append(imageData)
        return wrapMessage(payload)
    }

    // MARK: - Utilities

    nonisolated private static func wrapMessage(_ payload: Data) -> Data {
        var message = Data()
        message.appendUInt32(UInt32(payload.count))
        message.append(payload)
        return message
    }
}
