import Foundation
import CryptoKit

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
        let digest = Insecure.MD5.hash(data: hashInput.data(using: .utf8)!)
        let hashHex = digest.map { String(format: "%02x", $0) }.joined()
        payload.appendString(hashHex)

        // Minor version
        payload.appendUInt32(1)

        return wrapMessage(payload)
    }

    nonisolated static func setListenPortMessage(port: UInt32, obfuscatedPort: UInt32 = 0) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.setListenPort.rawValue)
        payload.appendUInt32(port)
        payload.appendUInt32(obfuscatedPort)
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

    nonisolated static func joinRoomMessage(roomName: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.joinRoom.rawValue)
        payload.appendString(roomName)
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

    nonisolated static func userInfoRequestMessage() -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.userInfoRequest.rawValue))
        return wrapMessage(payload)
    }

    nonisolated static func searchReplyMessage(
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

    nonisolated static func queueDownloadMessage(filename: String) -> Data {
        var payload = Data()
        payload.appendUInt32(UInt32(PeerMessageCode.queueDownload.rawValue))
        payload.appendString(filename)
        return wrapMessage(payload)
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

    // MARK: - NetworkClient Convenience Methods

    nonisolated static func login(username: String, password: String, version: UInt32, hash: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.login.rawValue)
        payload.appendString(username)
        payload.appendString(password)
        payload.appendUInt32(version)
        payload.appendString(hash)
        payload.appendUInt32(1) // minor version
        return wrapMessage(payload)
    }

    nonisolated static func fileSearch(token: UInt32, query: String) -> Data {
        fileSearchMessage(token: token, query: query)
    }

    nonisolated static func roomList() -> Data {
        getRoomListMessage()
    }

    nonisolated static func joinRoom(_ name: String) -> Data {
        joinRoomMessage(roomName: name)
    }

    nonisolated static func leaveRoom(_ name: String) -> Data {
        leaveRoomMessage(roomName: name)
    }

    nonisolated static func sayInRoom(room: String, message: String) -> Data {
        sayInChatRoomMessage(roomName: room, message: message)
    }

    nonisolated static func privateMessage(username: String, message: String) -> Data {
        privateMessageMessage(username: username, message: message)
    }

    nonisolated static func getUserAddress(_ username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.getPeerAddress.rawValue)
        payload.appendString(username)
        return wrapMessage(payload)
    }

    nonisolated static func setStatus(_ status: UserStatus) -> Data {
        setOnlineStatusMessage(status: status)
    }

    nonisolated static func sharedFoldersFiles(folders: UInt32, files: UInt32) -> Data {
        sharedFoldersFilesMessage(folders: folders, files: files)
    }

    nonisolated static func cantConnectToPeer(token: UInt32, username: String) -> Data {
        var payload = Data()
        payload.appendUInt32(ServerMessageCode.cantConnectToPeer.rawValue)
        payload.appendUInt32(token)
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

    // MARK: - Utilities

    nonisolated private static func wrapMessage(_ payload: Data) -> Data {
        var message = Data()
        message.appendUInt32(UInt32(payload.count))
        message.append(payload)
        return message
    }
}
