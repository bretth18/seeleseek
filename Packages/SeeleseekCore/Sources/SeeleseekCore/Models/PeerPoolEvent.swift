import Foundation

/// Events emitted by PeerConnectionPool via its AsyncStream.
/// Consumed by NetworkClient. Replaces the on* callback properties.
public enum PeerPoolEvent: Sendable {
    case searchResults(token: UInt32, results: [SearchResult])
    case sharesReceived(username: String, files: [SharedFile])
    case transferRequest(TransferRequest)
    case incomingConnectionMatched(username: String, token: UInt32, connection: PeerConnection)
    case fileTransferConnection(username: String, token: UInt32, connection: PeerConnection)
    case pierceFirewall(token: UInt32, connection: PeerConnection)
    case uploadDenied(filename: String, reason: String)
    case uploadFailed(filename: String)
    case queueUpload(username: String, filename: String, connection: PeerConnection)
    case transferResponse(token: UInt32, allowed: Bool, filesize: UInt64?, connection: PeerConnection)
    case folderContentsRequest(username: String, token: UInt32, folder: String, connection: PeerConnection)
    case folderContentsResponse(token: UInt32, folder: String, files: [SharedFile])
    case placeInQueueRequest(username: String, filename: String, connection: PeerConnection)
    case placeInQueueReply(username: String, filename: String, position: UInt32)
    case sharesRequest(username: String, connection: PeerConnection)
    case userInfoRequest(username: String, connection: PeerConnection)
    case artworkRequest(username: String, token: UInt32, filePath: String, connection: PeerConnection)
    case userIPDiscovered(username: String, ip: String)
    case artworkReply(token: UInt32, imageData: Data)
}
