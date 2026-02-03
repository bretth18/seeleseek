import Foundation
import CryptoKit

struct MessageBuilder {
    // MARK: - Server Messages

    static func loginMessage(username: String, password: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.login.rawValue)
        payload.appendString(username)
        payload.appendString(password)

        // Client version
        payload.appendUInt32(160)

        // MD5 hash of username + password
        let hashInput = username + password
        let digest = Insecure.MD5.hash(data: hashInput.data(using: .utf8)!)
        let hashHex = digest.map { String(format: "%02x", $0) }.joined()
        payload.appendString(hashHex)

        // Minor version
        payload.appendUInt32(1)

        return wrapMessage(payload)
    }

    static func setListenPortMessage(port: UInt32, obfuscatedPort: UInt32 = 0) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.setListenPort.rawValue)
        payload.appendUInt32(port)
        payload.appendUInt32(obfuscatedPort)
        return wrapMessage(payload)
    }

    static func setOnlineStatusMessage(status: UserStatus) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.setOnlineStatus.rawValue)
        payload.appendUInt32(status.rawValue)
        return wrapMessage(payload)
    }

    static func sharedFoldersFilesMessage(folders: UInt32, files: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.sharedFoldersFiles.rawValue)
        payload.appendUInt32(folders)
        payload.appendUInt32(files)
        return wrapMessage(payload)
    }

    static func pingMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.ping.rawValue)
        return wrapMessage(payload)
    }

    static func fileSearchMessage(token: UInt32, query: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.fileSearch.rawValue)
        payload.appendUInt32(token)
        payload.appendString(query)
        return wrapMessage(payload)
    }

    static func joinRoomMessage(roomName: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.joinRoom.rawValue)
        payload.appendString(roomName)
        return wrapMessage(payload)
    }

    static func leaveRoomMessage(roomName: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.leaveRoom.rawValue)
        payload.appendString(roomName)
        return wrapMessage(payload)
    }

    static func sayInChatRoomMessage(roomName: String, message: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.sayInChatRoom.rawValue)
        payload.appendString(roomName)
        payload.appendString(message)
        return wrapMessage(payload)
    }

    static func privateMessageMessage(username: String, message: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.privateMessages.rawValue)
        payload.appendString(username)
        payload.appendString(message)
        return wrapMessage(payload)
    }

    static func acknowledgePrivateMessageMessage(messageId: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.acknowledgePrivateMessage.rawValue)
        payload.appendUInt32(messageId)
        return wrapMessage(payload)
    }

    static func watchUserMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.watchUser.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    static func unwatchUserMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.unwatchUser.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    static func getUserStatusMessage(username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.getUserStatus.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    static func connectToPeerMessage(token: UInt32, username: String, connectionType: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.connectToPeer.rawValue)
        payload.appendUInt32(token)
        payload.appendString(username)
        payload.appendString(connectionType)
        return wrapMessage(payload)
    }

    static func getRoomListMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.roomList.rawValue)
        return wrapMessage(payload)
    }

    // MARK: - Peer Messages

    static func peerInitMessage(username: String, connectionType: String, token: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt8(PeerMessageCode.peerInit.rawValue)
        payload.appendString(username)
        payload.appendString(connectionType)
        payload.appendUInt32(token)
        return wrapMessage(payload)
    }

    static func pierceFirewallMessage(token: UInt32) -> Data {
        var payload = Data()
        payload.appendUInt8(PeerMessageCode.pierceFirewall.rawValue)
        payload.appendUInt32(token)
        return wrapMessage(payload)
    }

    static func sharesRequestMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.sharesRequest.rawValue))
        return wrapMessage(payload)
    }

    static func userInfoRequestMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.userInfoRequest.rawValue))
        return wrapMessage(payload)
    }

    static func searchReplyMessage(
        username: String,
        token: UInt32,
        results: [(filename: String, size: UInt64, extension_: String, attributes: [(UInt32, UInt32)])]
    ) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.searchReply.rawValue))
        payload.appendString(username)
        payload.appendUInt32(token)
        payload.appendUInt32(UInt32(results.count))

        for result in results {
            payload.appendUInt8(1) // code
            payload.appendString(result.filename)
            payload.appendUInt64(result.size)
            payload.appendString(result.extension_)
            payload.appendUInt32(UInt32(result.attributes.count))
            for attr in result.attributes {
                payload.appendUInt32(attr.0)
                payload.appendUInt32(attr.1)
            }
        }

        payload.appendBool(true) // has free slots
        payload.appendUInt32(100) // upload speed
        payload.appendUInt32(0) // queue length

        return wrapMessage(payload)
    }

    static func queueDownloadMessage(filename: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.queueDownload.rawValue))
        payload.appendString(filename)
        return wrapMessage(payload)
    }

    static func transferRequestMessage(direction: FileTransferDirection, token: UInt32, filename: String, fileSize: UInt64? = nil) -> Data {
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

    // MARK: - Utilities

    private static func wrapMessage(_ payload: Data) -> Data {
        var message = Data()
        message.appendUInt32(UInt32(payload.count))
        message.append(payload)
        return message
    }
}
