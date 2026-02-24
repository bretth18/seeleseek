import Foundation
import os

/// Parser for SoulSeek protocol messages.
/// All types are Sendable to allow use across actor boundaries.
enum MessageParser {
    nonisolated static let logger = Logger(subsystem: "com.seeleseek", category: "MessageParser")

    // MARK: - Security Limits
    // These limits prevent DoS attacks via malicious payloads with large counts

    /// Maximum number of items in any list (files, rooms, users, etc.)
    nonisolated static let maxItemCount: UInt32 = 100_000
    /// Maximum number of attributes per file
    nonisolated static let maxAttributeCount: UInt32 = 100
    /// Maximum message size (reduced from 100MB)
    nonisolated static let maxMessageSize: UInt32 = 100_000_000  // 100MB - large share lists can exceed 10MB

    // MARK: - Frame Parsing

    struct ParsedFrame: Sendable {
        let code: UInt32
        let payload: Data
    }

    nonisolated static func parseFrame(from data: Data) -> (frame: ParsedFrame, consumed: Int)? {
        guard data.count >= 8 else { return nil }

        guard let length = data.readUInt32(at: 0) else { return nil }

        // SECURITY: Reject excessively large messages
        guard length <= maxMessageSize else { return nil }

        // Message must contain at least a 4-byte code
        guard length >= 4 else { return nil }

        let totalLength = 4 + Int(length)

        guard data.count >= totalLength else { return nil }
        guard let code = data.readUInt32(at: 4) else { return nil }

        // Use safe subdata extraction
        guard let payload = data.safeSubdata(in: 8..<totalLength) else { return nil }
        return (ParsedFrame(code: code, payload: payload), totalLength)
    }

    // MARK: - Server Message Parsing

    nonisolated static func parseLoginResponse(_ payload: Data) -> LoginResult? {
        var offset = 0

        guard let success = payload.readBool(at: offset) else { return nil }
        offset += 1

        if success {
            guard let (greeting, greetingLen) = payload.readString(at: offset) else { return nil }
            offset += greetingLen

            guard let ip = payload.readUInt32(at: offset) else { return nil }
            offset += 4

            let ipString = formatLittleEndianIPv4(ip)

            var hashString: String?
            if let (hash, _) = payload.readString(at: offset) {
                hashString = hash
            }

            return .success(greeting: greeting, ip: ipString, hash: hashString)
        } else {
            guard let (reason, _) = payload.readString(at: offset) else {
                return .failure(reason: "Unknown error")
            }
            return .failure(reason: reason)
        }
    }

    struct RoomListEntry: Sendable {
        let name: String
        let userCount: UInt32
    }

    nonisolated static func parseRoomList(_ payload: Data) -> [RoomListEntry]? {
        var offset = 0
        var rooms: [RoomListEntry] = []

        guard let roomCount = payload.readUInt32(at: offset) else { return nil }
        // SECURITY: Limit room count to prevent DoS
        guard roomCount <= maxItemCount else { return nil }
        offset += 4

        var roomNames: [String] = []
        for _ in 0..<roomCount {
            guard let (name, len) = payload.readString(at: offset) else { return nil }
            offset += len
            roomNames.append(name)
        }

        guard let userCountsCount = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        for i in 0..<Int(min(roomCount, userCountsCount)) {
            guard let userCount = payload.readUInt32(at: offset) else { return nil }
            offset += 4
            rooms.append(RoomListEntry(name: roomNames[i], userCount: userCount))
        }

        return rooms
    }

    struct PeerInfo: Sendable {
        let username: String
        let ip: String
        let port: UInt32
        let token: UInt32
        let privileged: Bool
    }

    nonisolated static func parseConnectToPeer(_ payload: Data) -> PeerInfo? {
        var offset = 0

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let (_, typeLen) = payload.readString(at: offset) else { return nil }
        offset += typeLen

        guard let ip = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let port = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let token = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        let privileged = payload.readBool(at: offset) ?? false

        let ipString = formatLittleEndianIPv4(ip)

        return PeerInfo(username: username, ip: ipString, port: port, token: token, privileged: privileged)
    }

    nonisolated private static func formatLittleEndianIPv4(_ ip: UInt32) -> String {
        // IP is stored in network byte order (big-endian) within a LE uint32:
        // high byte = first octet
        let b1 = (ip >> 24) & 0xFF
        let b2 = (ip >> 16) & 0xFF
        let b3 = (ip >> 8) & 0xFF
        let b4 = ip & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }

    struct UserStatusInfo: Sendable {
        let username: String
        let status: UserStatus
        let privileged: Bool
    }

    nonisolated static func parseGetUserStatus(_ payload: Data) -> UserStatusInfo? {
        var offset = 0

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let statusRaw = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        let privileged = payload.readBool(at: offset) ?? false

        let status = UserStatus(rawValue: statusRaw) ?? .offline

        return UserStatusInfo(username: username, status: status, privileged: privileged)
    }

    struct PrivateMessageInfo: Sendable {
        let id: UInt32
        let timestamp: UInt32
        let username: String
        let message: String
        let isAdmin: Bool
    }

    nonisolated static func parsePrivateMessage(_ payload: Data) -> PrivateMessageInfo? {
        var offset = 0

        guard let id = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let timestamp = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let (message, messageLen) = payload.readString(at: offset) else { return nil }
        offset += messageLen

        let isAdmin = payload.readBool(at: offset) ?? false

        return PrivateMessageInfo(id: id, timestamp: timestamp, username: username, message: message, isAdmin: isAdmin)
    }

    struct ChatRoomMessageInfo: Sendable {
        let roomName: String
        let username: String
        let message: String
    }

    nonisolated static func parseSayInChatRoom(_ payload: Data) -> ChatRoomMessageInfo? {
        var offset = 0

        guard let (roomName, roomLen) = payload.readString(at: offset) else { return nil }
        offset += roomLen

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let (message, _) = payload.readString(at: offset) else { return nil }

        return ChatRoomMessageInfo(roomName: roomName, username: username, message: message)
    }

    // MARK: - Peer Message Parsing

    struct SearchResultFile: Sendable {
        let filename: String
        let size: UInt64
        let `extension`: String
        let attributes: [FileAttribute]
        let isPrivate: Bool  // Buddy-only / locked file

        nonisolated init(filename: String, size: UInt64, extension: String, attributes: [FileAttribute], isPrivate: Bool = false) {
            self.filename = filename
            self.size = size
            self.extension = `extension`
            self.attributes = attributes
            self.isPrivate = isPrivate
        }
    }

    struct FileAttribute: Sendable {
        let type: UInt32
        let value: UInt32

        var description: String {
            switch type {
            case 0: "Bitrate: \(value) kbps"
            case 1: "Duration: \(value) seconds"
            case 2: "VBR: \(value == 1 ? "Yes" : "No")"
            case 4: "Sample Rate: \(value) Hz"
            case 5: "Bit Depth: \(value) bits"
            default: "Unknown(\(type)): \(value)"
            }
        }
    }

    struct SearchReplyInfo: Sendable {
        let username: String
        let token: UInt32
        let files: [SearchResultFile]
        let freeSlots: Bool
        let uploadSpeed: UInt32
        let queueLength: UInt32
    }

    nonisolated static func parseSearchReply(_ payload: Data) -> SearchReplyInfo? {
        var offset = 0

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let token = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let fileCount = payload.readUInt32(at: offset) else { return nil }
        // SECURITY: Limit file count to prevent DoS
        guard fileCount <= maxItemCount else { return nil }
        offset += 4

        var files: [SearchResultFile] = []
        for _ in 0..<fileCount {
            guard payload.readUInt8(at: offset) != nil else { return nil }
            offset += 1

            guard let (filename, filenameLen) = payload.readString(at: offset) else { return nil }
            offset += filenameLen

            guard let size = payload.readUInt64(at: offset) else { return nil }
            offset += 8

            guard let (ext, extLen) = payload.readString(at: offset) else { return nil }
            offset += extLen

            guard let attrCount = payload.readUInt32(at: offset) else { return nil }
            // SECURITY: Limit attribute count to prevent DoS
            guard attrCount <= maxAttributeCount else { return nil }
            offset += 4

            var attributes: [FileAttribute] = []
            for _ in 0..<attrCount {
                guard let attrType = payload.readUInt32(at: offset) else { return nil }
                offset += 4
                guard let attrValue = payload.readUInt32(at: offset) else { return nil }
                offset += 4
                attributes.append(FileAttribute(type: attrType, value: attrValue))
            }

            files.append(SearchResultFile(filename: filename, size: size, extension: ext, attributes: attributes, isPrivate: false))
        }

        let freeSlots = payload.readBool(at: offset) ?? true
        offset += 1

        let uploadSpeed = payload.readUInt32(at: offset) ?? 0
        offset += 4

        let queueLength = payload.readUInt32(at: offset) ?? 0
        offset += 4

        // Parse privately shared results (buddy-only files)
        // These come after the regular file list and are only visible if we're on the user's buddy list
        // Format: uint32 unknown (always 0), uint32 private file count, then file entries
        // Skip the "unknown" uint32 first
        offset += 4

        let remainingBytes = payload.count - offset
        if remainingBytes >= 4 {
            let potentialPrivateCount = payload.readUInt32(at: offset) ?? 0

            // Validate: private file count should be reasonable (not garbage data)
            // SECURITY: Limit private file count
            if potentialPrivateCount > 0 && potentialPrivateCount <= maxItemCount {
                offset += 4
                var privateFilesParsed = 0

                for _ in 0..<potentialPrivateCount {
                    guard payload.readUInt8(at: offset) != nil else { break }
                    offset += 1

                    guard let (filename, filenameLen) = payload.readString(at: offset) else { break }
                    offset += filenameLen

                    guard let size = payload.readUInt64(at: offset) else { break }
                    offset += 8

                    guard let (ext, extLen) = payload.readString(at: offset) else { break }
                    offset += extLen

                    guard let attrCount = payload.readUInt32(at: offset) else { break }
                    // SECURITY: Limit attribute count
                    guard attrCount <= maxAttributeCount else { break }
                    offset += 4

                    var attributes: [FileAttribute] = []
                    for _ in 0..<attrCount {
                        guard let attrType = payload.readUInt32(at: offset) else { break }
                        offset += 4
                        guard let attrValue = payload.readUInt32(at: offset) else { break }
                        offset += 4
                        attributes.append(FileAttribute(type: attrType, value: attrValue))
                    }

                    files.append(SearchResultFile(filename: filename, size: size, extension: ext, attributes: attributes, isPrivate: true))
                    privateFilesParsed += 1
                }

                if privateFilesParsed > 0 {
                    logger.debug("Parsed \(privateFilesParsed) private/buddy-only files from \(username)")
                }
            }
        }

        return SearchReplyInfo(
            username: username,
            token: token,
            files: files,
            freeSlots: freeSlots,
            uploadSpeed: uploadSpeed,
            queueLength: queueLength
        )
    }

    struct TransferRequestInfo: Sendable {
        let direction: FileTransferDirection
        let token: UInt32
        let filename: String
        let fileSize: UInt64?
    }

    nonisolated static func parseTransferRequest(_ payload: Data) -> TransferRequestInfo? {
        var offset = 0

        // Debug: show raw bytes
        let preview = payload.prefix(min(100, payload.count)).map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.debug("TransferRequest raw (\(payload.count) bytes): \(preview)")

        // Need at least 4 (direction) + 4 (token) + 4 (filename length) = 12 bytes minimum
        guard payload.count >= 12 else {
            logger.debug("Payload too short: \(payload.count) bytes, need at least 12")
            return nil
        }

        guard let directionRaw = payload.readUInt32(at: offset) else {
            logger.debug("Failed to read direction at offset \(offset)")
            return nil
        }
        logger.debug("direction raw: \(directionRaw) at offset \(offset)")
        offset += 4

        guard let directionByte = UInt8(exactly: directionRaw),
              let direction = FileTransferDirection(rawValue: directionByte) else {
            logger.debug("Invalid direction: \(directionRaw)")
            return nil
        }

        guard let token = payload.readUInt32(at: offset) else {
            logger.debug("Failed to read token at offset \(offset)")
            return nil
        }
        logger.debug("token: \(token) at offset \(offset)")
        offset += 4

        guard let (filename, filenameLen) = payload.readString(at: offset) else {
            logger.debug("Failed to read filename at offset \(offset)")
            return nil
        }
        logger.debug("filename: '\(filename)' (consumed=\(filenameLen) bytes) at offset \(offset)")
        offset += filenameLen

        var fileSize: UInt64?
        if direction == .upload {
            // For upload direction, file size should follow the filename
            // Check if we have enough bytes remaining (need 8 bytes for UInt64)
            let remainingBytes = payload.count - offset
            logger.debug("Remaining bytes after filename: \(remainingBytes), need 8 for fileSize")

            if remainingBytes >= 8 {
                // Debug: show the 8 bytes we're reading for file size
                let sizeBytes = payload.dropFirst(offset).prefix(8)
                let sizeBytesHex = sizeBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.debug("fileSize bytes at offset \(offset): \(sizeBytesHex)")

                fileSize = payload.readUInt64(at: offset)
                logger.debug("fileSize parsed: \(fileSize ?? 0)")

                // Validate: file size of 0 for upload direction is suspicious
                if fileSize == 0 {
                    logger.warning("TransferRequest: fileSize is 0 for upload direction - this may indicate parsing issue")
                    logger.debug("Full payload hex dump: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                }
            } else {
                logger.warning("TransferRequest: Not enough bytes for fileSize! Have \(remainingBytes), need 8")
                logger.debug("Full payload hex dump: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                // Still return what we have - fileSize will be nil
            }
        }

        return TransferRequestInfo(direction: direction, token: token, filename: filename, fileSize: fileSize)
    }

    // MARK: - Peer Message Parsing (Extended)

    struct ShareFileInfo: Sendable {
        let filename: String
        let size: UInt64
        let bitrate: UInt32?
        let duration: UInt32?
        let isPrivate: Bool
    }

    struct SharesReplyInfo: Sendable {
        let files: [ShareFileInfo]
    }

    /// Parse decompressed SharesReply payload (code 5).
    /// The caller must decompress the zlib data before calling this.
    nonisolated static func parseSharesReply(_ decompressed: Data) -> SharesReplyInfo? {
        var offset = 0
        var files: [ShareFileInfo] = []

        guard let dirCount = decompressed.readUInt32(at: offset) else { return nil }
        guard dirCount <= maxItemCount else { return nil }
        offset += 4

        for _ in 0..<dirCount {
            guard let (dirName, dirLen) = decompressed.readString(at: offset) else { return nil }
            offset += dirLen

            guard let fileCount = decompressed.readUInt32(at: offset) else { return nil }
            guard fileCount <= maxItemCount else { return nil }
            offset += 4

            for _ in 0..<fileCount {
                guard decompressed.readByte(at: offset) != nil else { return nil }
                offset += 1

                guard let (filename, filenameLen) = decompressed.readString(at: offset) else { return nil }
                offset += filenameLen

                guard let size = decompressed.readUInt64(at: offset) else { return nil }
                offset += 8

                guard let (_, extLen) = decompressed.readString(at: offset) else { return nil }
                offset += extLen

                guard let attrCount = decompressed.readUInt32(at: offset) else { return nil }
                guard attrCount <= maxAttributeCount else { return nil }
                offset += 4

                var bitrate: UInt32?
                var duration: UInt32?

                for _ in 0..<attrCount {
                    guard let attrType = decompressed.readUInt32(at: offset) else { return nil }
                    offset += 4
                    guard let attrValue = decompressed.readUInt32(at: offset) else { return nil }
                    offset += 4

                    switch attrType {
                    case 0: bitrate = attrValue
                    case 1: duration = attrValue
                    default: break
                    }
                }

                files.append(ShareFileInfo(
                    filename: "\(dirName)\\\(filename)",
                    size: size,
                    bitrate: bitrate,
                    duration: duration,
                    isPrivate: false
                ))
            }
        }

        // Skip "unknown" uint32
        if offset + 4 <= decompressed.count {
            offset += 4
        }

        // Parse private directories
        if let privateDirCount = decompressed.readUInt32(at: offset),
           privateDirCount > 0, privateDirCount <= maxItemCount {
            offset += 4

            for _ in 0..<privateDirCount {
                guard let (dirName, dirLen) = decompressed.readString(at: offset) else { break }
                offset += dirLen

                guard let fileCount = decompressed.readUInt32(at: offset) else { break }
                guard fileCount <= maxItemCount else { break }
                offset += 4

                for _ in 0..<fileCount {
                    guard decompressed.readByte(at: offset) != nil else { break }
                    offset += 1

                    guard let (filename, filenameLen) = decompressed.readString(at: offset) else { break }
                    offset += filenameLen

                    guard let size = decompressed.readUInt64(at: offset) else { break }
                    offset += 8

                    guard let (_, extLen) = decompressed.readString(at: offset) else { break }
                    offset += extLen

                    guard let attrCount = decompressed.readUInt32(at: offset) else { break }
                    guard attrCount <= maxAttributeCount else { break }
                    offset += 4

                    var bitrate: UInt32?
                    var duration: UInt32?

                    for _ in 0..<attrCount {
                        guard let attrType = decompressed.readUInt32(at: offset) else { break }
                        offset += 4
                        guard let attrValue = decompressed.readUInt32(at: offset) else { break }
                        offset += 4

                        switch attrType {
                        case 0: bitrate = attrValue
                        case 1: duration = attrValue
                        default: break
                        }
                    }

                    files.append(ShareFileInfo(
                        filename: "\(dirName)\\\(filename)",
                        size: size,
                        bitrate: bitrate,
                        duration: duration,
                        isPrivate: true
                    ))
                }
            }
        }

        return SharesReplyInfo(files: files)
    }

    struct FolderContentsReplyInfo: Sendable {
        let token: UInt32
        let folder: String
        let files: [ShareFileInfo]
    }

    /// Parse decompressed FolderContentsReply payload (code 37).
    nonisolated static func parseFolderContentsReply(_ decompressed: Data) -> FolderContentsReplyInfo? {
        var offset = 0

        guard let token = decompressed.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let (folder, folderLen) = decompressed.readString(at: offset) else { return nil }
        offset += folderLen

        guard let folderCount = decompressed.readUInt32(at: offset) else { return nil }
        guard folderCount <= maxItemCount else { return nil }
        offset += 4

        var files: [ShareFileInfo] = []

        for _ in 0..<folderCount {
            guard let (_, dirLen) = decompressed.readString(at: offset) else { break }
            offset += dirLen

            guard let fileCount = decompressed.readUInt32(at: offset) else { break }
            guard fileCount <= maxItemCount else { break }
            offset += 4

            for _ in 0..<fileCount {
                guard decompressed.readByte(at: offset) != nil else { break }
                offset += 1

                guard let (filename, filenameLen) = decompressed.readString(at: offset) else { break }
                offset += filenameLen

                guard let size = decompressed.readUInt64(at: offset) else { break }
                offset += 8

                guard let (_, extLen) = decompressed.readString(at: offset) else { break }
                offset += extLen

                guard let attrCount = decompressed.readUInt32(at: offset) else { break }
                guard attrCount <= maxAttributeCount else { break }
                offset += 4

                var bitrate: UInt32?
                var duration: UInt32?

                for _ in 0..<attrCount {
                    guard let attrType = decompressed.readUInt32(at: offset) else { break }
                    offset += 4
                    guard let attrValue = decompressed.readUInt32(at: offset) else { break }
                    offset += 4

                    switch attrType {
                    case 0: bitrate = attrValue
                    case 1: duration = attrValue
                    default: break
                    }
                }

                files.append(ShareFileInfo(
                    filename: filename,
                    size: size,
                    bitrate: bitrate,
                    duration: duration,
                    isPrivate: false
                ))
            }
        }

        return FolderContentsReplyInfo(token: token, folder: folder, files: files)
    }

    struct UserInfoReplyInfo: Sendable {
        let description: String
        let hasPicture: Bool
        let pictureData: Data?
        let totalUploads: UInt32
        let queueSize: UInt32
        let hasFreeSlots: Bool
    }

    /// Parse UserInfoReply payload (code 16).
    nonisolated static func parseUserInfoReply(_ payload: Data) -> UserInfoReplyInfo? {
        var offset = 0

        guard let (description, descLen) = payload.readString(at: offset) else { return nil }
        offset += descLen

        guard let hasPicture = payload.readBool(at: offset) else { return nil }
        offset += 1

        var pictureData: Data?
        if hasPicture {
            guard let pictureLen = payload.readUInt32(at: offset) else { return nil }
            offset += 4
            guard offset + Int(pictureLen) <= payload.count else { return nil }
            pictureData = payload.safeSubdata(in: offset..<(offset + Int(pictureLen)))
            offset += Int(pictureLen)
        }

        guard let totalUploads = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let queueSize = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let hasFreeSlots = payload.readBool(at: offset) else { return nil }

        return UserInfoReplyInfo(
            description: description,
            hasPicture: hasPicture,
            pictureData: pictureData,
            totalUploads: totalUploads,
            queueSize: queueSize,
            hasFreeSlots: hasFreeSlots
        )
    }

    struct TransferReplyInfo: Sendable {
        let token: UInt32
        let allowed: Bool
        let fileSize: UInt64?
        let reason: String?
    }

    /// Parse TransferReply payload (code 41).
    nonisolated static func parseTransferReply(_ payload: Data) -> TransferReplyInfo? {
        var offset = 0

        guard let token = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let allowed = payload.readBool(at: offset) else { return nil }
        offset += 1

        var fileSize: UInt64?
        var reason: String?

        if allowed {
            fileSize = payload.readUInt64(at: offset)
        } else {
            reason = payload.readString(at: offset)?.string
        }

        return TransferReplyInfo(token: token, allowed: allowed, fileSize: fileSize, reason: reason)
    }

    // MARK: - Server Message Parsing (Extended)

    struct JoinRoomInfo: Sendable {
        let roomName: String
        let users: [String]
        let owner: String?
        let operators: [String]
    }

    /// Parse JoinRoom payload (code 14).
    nonisolated static func parseJoinRoom(_ payload: Data) -> JoinRoomInfo? {
        var offset = 0

        guard let (roomName, roomLen) = payload.readString(at: offset) else { return nil }
        offset += roomLen

        guard let userCount = payload.readUInt32(at: offset) else { return nil }
        guard userCount <= maxItemCount else { return nil }
        offset += 4

        var users: [String] = []
        for _ in 0..<userCount {
            guard let (username, usernameLen) = payload.readString(at: offset) else { break }
            users.append(username)
            offset += usernameLen
        }

        // Skip statuses (uint32 count + uint32 per user)
        if let statusCount = payload.readUInt32(at: offset) {
            guard statusCount <= maxItemCount else { return nil }
            offset += 4
            let bytesToSkip = Int(statusCount) * 4
            guard offset + bytesToSkip <= payload.count else { return nil }
            offset += bytesToSkip
        }

        // Skip user stats (uint32 count + 20 bytes per user)
        if let statsCount = payload.readUInt32(at: offset) {
            guard statsCount <= maxItemCount else { return nil }
            offset += 4
            let bytesToSkip = Int(statsCount) * 20
            guard offset + bytesToSkip <= payload.count else { return nil }
            offset += bytesToSkip
        }

        // Skip slotsfull (uint32 count + uint32 per user)
        if let slotsCount = payload.readUInt32(at: offset) {
            guard slotsCount <= maxItemCount else { return nil }
            offset += 4
            let bytesToSkip = Int(slotsCount) * 4
            guard offset + bytesToSkip <= payload.count else { return nil }
            offset += bytesToSkip
        }

        // Skip countries (uint32 count + string per user)
        if let countryCount = payload.readUInt32(at: offset) {
            guard countryCount <= maxItemCount else { return nil }
            offset += 4
            for _ in 0..<countryCount {
                guard let (_, countryLen) = payload.readString(at: offset) else { break }
                offset += countryLen
            }
        }

        // Private room data (optional)
        var owner: String?
        var operators: [String] = []

        if offset < payload.count {
            if let (ownerName, ownerLen) = payload.readString(at: offset) {
                owner = ownerName.isEmpty ? nil : ownerName
                offset += ownerLen

                if let opCount = payload.readUInt32(at: offset) {
                    guard opCount <= maxItemCount else { return nil }
                    offset += 4
                    for _ in 0..<opCount {
                        guard let (opName, opLen) = payload.readString(at: offset) else { break }
                        operators.append(opName)
                        offset += opLen
                    }
                }
            }
        }

        return JoinRoomInfo(roomName: roomName, users: users, owner: owner, operators: operators)
    }

    struct WatchUserInfo: Sendable {
        let username: String
        let exists: Bool
        let status: UserStatus?
        let avgSpeed: UInt32?
        let uploadNum: UInt32?
        let files: UInt32?
        let dirs: UInt32?
    }

    /// Parse WatchUser response payload (code 5 response).
    nonisolated static func parseWatchUser(_ payload: Data) -> WatchUserInfo? {
        var offset = 0

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let exists = payload.readBool(at: offset) else { return nil }
        offset += 1

        guard exists else {
            return WatchUserInfo(username: username, exists: false, status: nil, avgSpeed: nil, uploadNum: nil, files: nil, dirs: nil)
        }

        guard let statusRaw = payload.readUInt32(at: offset) else { return nil }
        offset += 4
        guard let avgSpeed = payload.readUInt32(at: offset) else { return nil }
        offset += 4
        guard let uploadNum = payload.readUInt32(at: offset) else { return nil }
        offset += 4
        // Skip unknown uint32
        guard payload.readUInt32(at: offset) != nil else { return nil }
        offset += 4
        guard let files = payload.readUInt32(at: offset) else { return nil }
        offset += 4
        guard let dirs = payload.readUInt32(at: offset) else { return nil }

        let status = UserStatus(rawValue: statusRaw) ?? .offline

        return WatchUserInfo(username: username, exists: true, status: status, avgSpeed: avgSpeed, uploadNum: uploadNum, files: files, dirs: dirs)
    }

    struct PossibleParentInfo: Sendable {
        let username: String
        let ip: String
        let port: UInt32
    }

    /// Parse PossibleParents payload (code 102).
    nonisolated static func parsePossibleParents(_ payload: Data) -> [PossibleParentInfo]? {
        var offset = 0

        guard let parentCount = payload.readUInt32(at: offset) else { return nil }
        guard parentCount <= maxItemCount else { return nil }
        offset += 4

        var parents: [PossibleParentInfo] = []
        for _ in 0..<parentCount {
            guard let (username, usernameLen) = payload.readString(at: offset) else { break }
            offset += usernameLen

            guard let ip = payload.readUInt32(at: offset) else { break }
            offset += 4

            guard let port = payload.readUInt32(at: offset) else { break }
            offset += 4

            let ipString = formatLittleEndianIPv4(ip)
            parents.append(PossibleParentInfo(username: username, ip: ipString, port: port))
        }

        return parents
    }

    struct RecommendationEntry: Sendable {
        let item: String
        let score: Int32
    }

    struct RecommendationsInfo: Sendable {
        let recommendations: [RecommendationEntry]
        let unrecommendations: [RecommendationEntry]
    }

    /// Parse Recommendations payload (code 54, 55, 56).
    nonisolated static func parseRecommendations(_ payload: Data) -> RecommendationsInfo? {
        var offset = 0

        guard let recCount = payload.readUInt32(at: offset) else { return nil }
        guard recCount <= maxItemCount else { return nil }
        offset += 4

        var recommendations: [RecommendationEntry] = []
        for _ in 0..<recCount {
            guard let (item, itemLen) = payload.readString(at: offset) else { break }
            offset += itemLen
            guard let score = payload.readInt32(at: offset) else { break }
            offset += 4
            recommendations.append(RecommendationEntry(item: item, score: score))
        }

        guard let unrecCount = payload.readUInt32(at: offset) else {
            // Return what we have if unrecommendations section is missing
            return RecommendationsInfo(recommendations: recommendations, unrecommendations: [])
        }
        guard unrecCount <= maxItemCount else { return nil }
        offset += 4

        var unrecommendations: [RecommendationEntry] = []
        for _ in 0..<unrecCount {
            guard let (item, itemLen) = payload.readString(at: offset) else { break }
            offset += itemLen
            guard let score = payload.readInt32(at: offset) else { break }
            offset += 4
            unrecommendations.append(RecommendationEntry(item: item, score: score))
        }

        return RecommendationsInfo(recommendations: recommendations, unrecommendations: unrecommendations)
    }

    struct UserInterestsInfo: Sendable {
        let username: String
        let likes: [String]
        let hates: [String]
    }

    /// Parse UserInterests payload (code 57).
    nonisolated static func parseUserInterests(_ payload: Data) -> UserInterestsInfo? {
        var offset = 0

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let likedCount = payload.readUInt32(at: offset) else { return nil }
        guard likedCount <= maxItemCount else { return nil }
        offset += 4

        var likes: [String] = []
        for _ in 0..<likedCount {
            guard let (interest, interestLen) = payload.readString(at: offset) else { break }
            likes.append(interest)
            offset += interestLen
        }

        guard let hatedCount = payload.readUInt32(at: offset) else { return nil }
        guard hatedCount <= maxItemCount else { return nil }
        offset += 4

        var hates: [String] = []
        for _ in 0..<hatedCount {
            guard let (interest, interestLen) = payload.readString(at: offset) else { break }
            hates.append(interest)
            offset += interestLen
        }

        return UserInterestsInfo(username: username, likes: likes, hates: hates)
    }

    struct SimilarUserEntry: Sendable {
        let username: String
        let rating: UInt32
    }

    /// Parse SimilarUsers payload (code 110).
    nonisolated static func parseSimilarUsers(_ payload: Data) -> [SimilarUserEntry]? {
        var offset = 0

        guard let userCount = payload.readUInt32(at: offset) else { return nil }
        guard userCount <= maxItemCount else { return nil }
        offset += 4

        var users: [SimilarUserEntry] = []
        for _ in 0..<userCount {
            guard let (username, usernameLen) = payload.readString(at: offset) else { break }
            offset += usernameLen
            guard let rating = payload.readUInt32(at: offset) else { break }
            offset += 4
            users.append(SimilarUserEntry(username: username, rating: rating))
        }

        return users
    }

    struct UserStatsInfo: Sendable {
        let username: String
        let avgSpeed: UInt32
        let uploadNum: UInt32
        let files: UInt32
        let dirs: UInt32
    }

    /// Parse GetUserStats payload (code 36 response).
    nonisolated static func parseGetUserStats(_ payload: Data) -> UserStatsInfo? {
        var offset = 0

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let avgSpeed = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let uploadNum = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        // Skip unknown uint32
        guard payload.readUInt32(at: offset) != nil else { return nil }
        offset += 4

        guard let files = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let dirs = payload.readUInt32(at: offset) else { return nil }

        return UserStatsInfo(username: username, avgSpeed: avgSpeed, uploadNum: uploadNum, files: files, dirs: dirs)
    }

    struct RoomTickerEntry: Sendable {
        let username: String
        let ticker: String
    }

    struct RoomTickerStateInfo: Sendable {
        let room: String
        let tickers: [RoomTickerEntry]
    }

    /// Parse RoomTickerState payload (code 113).
    nonisolated static func parseRoomTickerState(_ payload: Data) -> RoomTickerStateInfo? {
        var offset = 0

        guard let (room, roomLen) = payload.readString(at: offset) else { return nil }
        offset += roomLen

        guard let tickerCount = payload.readUInt32(at: offset) else { return nil }
        guard tickerCount <= maxItemCount else { return nil }
        offset += 4

        var tickers: [RoomTickerEntry] = []
        for _ in 0..<tickerCount {
            guard let (username, usernameLen) = payload.readString(at: offset) else { break }
            offset += usernameLen
            guard let (ticker, tickerLen) = payload.readString(at: offset) else { break }
            offset += tickerLen
            tickers.append(RoomTickerEntry(username: username, ticker: ticker))
        }

        return RoomTickerStateInfo(room: room, tickers: tickers)
    }

    struct RoomMembersInfo: Sendable {
        let room: String
        let members: [String]
    }

    /// Parse PrivateRoomMembers / PrivateRoomOperators payload (codes 133, 148).
    nonisolated static func parseRoomMembers(_ payload: Data) -> RoomMembersInfo? {
        var offset = 0

        guard let (room, roomLen) = payload.readString(at: offset) else { return nil }
        offset += roomLen

        guard let memberCount = payload.readUInt32(at: offset) else { return nil }
        guard memberCount <= maxItemCount else { return nil }
        offset += 4

        var members: [String] = []
        for _ in 0..<memberCount {
            guard let (username, usernameLen) = payload.readString(at: offset) else { break }
            members.append(username)
            offset += usernameLen
        }

        return RoomMembersInfo(room: room, members: members)
    }

    /// Parse ExcludedSearchPhrases payload (code 160).
    nonisolated static func parseExcludedSearchPhrases(_ payload: Data) -> [String]? {
        var offset = 0

        guard let count = payload.readUInt32(at: offset) else { return nil }
        guard count <= maxItemCount else { return nil }
        offset += 4

        var phrases: [String] = []
        for _ in 0..<count {
            guard let (phrase, phraseLen) = payload.readString(at: offset) else { break }
            phrases.append(phrase)
            offset += phraseLen
        }

        return phrases
    }

    struct DistributedSearchInfo: Sendable {
        let unknown: UInt32
        let username: String
        let token: UInt32
        let query: String
    }

    /// Parse distributed search request payload (distributed code 3).
    nonisolated static func parseDistributedSearch(_ payload: Data) -> DistributedSearchInfo? {
        var offset = 0

        guard let unknown = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let (username, usernameLen) = payload.readString(at: offset) else { return nil }
        offset += usernameLen

        guard let token = payload.readUInt32(at: offset) else { return nil }
        offset += 4

        guard let (query, _) = payload.readString(at: offset) else { return nil }

        return DistributedSearchInfo(unknown: unknown, username: username, token: token, query: query)
    }
}
