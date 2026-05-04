import Foundation

/// Events emitted by a PeerConnection actor via its AsyncStream.
/// Replaces the callback-based setOn* pattern for Swift 6 concurrency safety.
public enum PeerConnectionEvent: Sendable {
    case stateChanged(PeerConnection.State)
    case message(code: UInt32, payload: Data)
    case sharesReceived([SharedFile])
    case searchReply(token: UInt32, results: [SearchResult])
    case transferRequest(TransferRequest)
    case usernameDiscovered(username: String, token: UInt32)
    case fileTransferConnection(username: String, token: UInt32, connection: PeerConnection)
    case pierceFirewall(token: UInt32)
    case uploadDenied(username: String, filename: String, reason: String)
    case uploadFailed(username: String, filename: String)
    case queueUpload(username: String, filename: String)
    case transferResponse(token: UInt32, allowed: Bool, filesize: UInt64?, reason: String?)
    case folderContentsRequest(token: UInt32, folder: String)
    case folderContentsResponse(token: UInt32, folder: String, files: [SharedFile])
    case placeInQueueRequest(username: String, filename: String)
    case placeInQueueReply(filename: String, position: UInt32)
    case sharesRequest
    case userInfoRequest
    case userInfoReply(MessageParser.UserInfoReplyInfo)
    case seeleSeekVersionDiscovered(UInt8)
    case artworkRequest(token: UInt32, filePath: String)
    case artworkReply(token: UInt32, imageData: Data)
}
