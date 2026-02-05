import Foundation

/// Parser for SoulSeek protocol messages.
/// All types are Sendable to allow use across actor boundaries.
enum MessageParser {
    // MARK: - Frame Parsing

    struct ParsedFrame: Sendable {
        let code: UInt32
        let payload: Data
    }

    nonisolated static func parseFrame(from data: Data) -> (frame: ParsedFrame, consumed: Int)? {
        guard data.count >= 8 else { return nil }

        guard let length = data.readUInt32(at: 0) else { return nil }

        // Sanity check - messages shouldn't be excessively large
        guard length <= 100_000_000 else { return nil }

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

            let ipString = "\(ip & 0xFF).\((ip >> 8) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 24) & 0xFF)"

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

        let ipString = "\(ip & 0xFF).\((ip >> 8) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 24) & 0xFF)"

        return PeerInfo(username: username, ip: ipString, port: port, token: token, privileged: privileged)
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

        init(filename: String, size: UInt64, extension: String, attributes: [FileAttribute], isPrivate: Bool = false) {
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
        // Note: Some clients may send an extra "free upload slots" uint32 after queueLength
        let remainingBytes = payload.count - offset
        if remainingBytes >= 4 {
            let potentialPrivateCount = payload.readUInt32(at: offset) ?? 0

            // Validate: private file count should be reasonable (not garbage data)
            // If it's 0 or suspiciously large (> 10000), it's likely not a private file count
            if potentialPrivateCount > 0 && potentialPrivateCount <= 10000 {
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
                    print("🔒 Parsed \(privateFilesParsed) private/buddy-only files from \(username)")
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
        print("📦 TransferRequest raw (\(payload.count) bytes): \(preview)")

        // Need at least 4 (direction) + 4 (token) + 4 (filename length) = 12 bytes minimum
        guard payload.count >= 12 else {
            print("📦 Payload too short: \(payload.count) bytes, need at least 12")
            return nil
        }

        guard let directionRaw = payload.readUInt32(at: offset) else {
            print("📦 Failed to read direction at offset \(offset)")
            return nil
        }
        print("📦 direction raw: \(directionRaw) at offset \(offset)")
        offset += 4

        guard let direction = FileTransferDirection(rawValue: UInt8(directionRaw)) else {
            print("📦 Invalid direction: \(directionRaw)")
            return nil
        }

        guard let token = payload.readUInt32(at: offset) else {
            print("📦 Failed to read token at offset \(offset)")
            return nil
        }
        print("📦 token: \(token) at offset \(offset)")
        offset += 4

        guard let (filename, filenameLen) = payload.readString(at: offset) else {
            print("📦 Failed to read filename at offset \(offset)")
            return nil
        }
        print("📦 filename: '\(filename)' (consumed=\(filenameLen) bytes) at offset \(offset)")
        offset += filenameLen

        var fileSize: UInt64?
        if direction == .upload {
            // For upload direction, file size should follow the filename
            // Check if we have enough bytes remaining (need 8 bytes for UInt64)
            let remainingBytes = payload.count - offset
            print("📦 Remaining bytes after filename: \(remainingBytes), need 8 for fileSize")

            if remainingBytes >= 8 {
                // Debug: show the 8 bytes we're reading for file size
                let sizeBytes = payload.dropFirst(offset).prefix(8)
                let sizeBytesHex = sizeBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("📦 fileSize bytes at offset \(offset): \(sizeBytesHex)")

                fileSize = payload.readUInt64(at: offset)
                print("📦 fileSize parsed: \(fileSize ?? 0)")

                // Validate: file size of 0 for upload direction is suspicious
                if fileSize == 0 {
                    print("⚠️ TransferRequest: fileSize is 0 for upload direction - this may indicate parsing issue")
                    print("⚠️ Full payload hex dump: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                }
            } else {
                print("⚠️ TransferRequest: Not enough bytes for fileSize! Have \(remainingBytes), need 8")
                print("⚠️ Full payload hex dump: \(payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
                // Still return what we have - fileSize will be nil
            }
        }

        return TransferRequestInfo(direction: direction, token: token, filename: filename, fileSize: fileSize)
    }
}
