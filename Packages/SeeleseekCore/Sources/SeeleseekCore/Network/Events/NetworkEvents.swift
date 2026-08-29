import Foundation

// Domain event enums published on `NetworkEventBus`.
//
// Domains are split so each app state object owns exactly one serial
// consumer loop: in-domain ordering is guaranteed (one producer, FIFO
// AsyncStream per subscriber), cross-domain ordering is not — nothing
// order-sensitive spans domains.

/// Chat, rooms, tickers, and private-room administration.
public enum ChatEvent: Sendable {
    case roomList(publicRooms: [ChatRoom], ownedPrivate: [ChatRoom], memberPrivate: [ChatRoom], operated: [String])
    case roomJoined(room: String, users: [String], owner: String?, operators: [String])
    case roomLeft(room: String)
    case roomMessage(room: String, message: ChatMessage)
    case privateMessage(username: String, message: ChatMessage)
    case userJoinedRoom(room: String, username: String)
    case userLeftRoom(room: String, username: String)
    case roomTickerState(room: String, tickers: [(username: String, ticker: String)])
    case roomTickerAdd(room: String, username: String, ticker: String)
    case roomTickerRemove(room: String, username: String)
    case privateRoomMembers(room: String, members: [String])
    case privateRoomMemberAdded(room: String, username: String)
    case privateRoomMemberRemoved(room: String, username: String)
    case privateRoomOperatorGranted(room: String)
    case privateRoomOperatorRevoked(room: String)
    case privateRoomOperators(room: String, operators: [String])
    case roomMembershipGranted(room: String)
    case roomMembershipRevoked(room: String)
    case roomInvitationsEnabled(Bool)
    case passwordChanged(String)
    case roomAdded(room: String)
    case roomRemoved(room: String)
    case cantCreateRoom(room: String)
    case globalRoomMessage(room: String, username: String, message: String)
}

/// Buddies, statuses, stats, interests, recommendations, privileges.
public enum SocialEvent: Sendable {
    case userStatus(username: String, status: UserStatus, privileged: Bool)
    case userStats(username: String, avgSpeed: UInt32, uploadNum: UInt64, files: UInt32, dirs: UInt32)
    case userInfoReply(username: String, info: MessageParser.UserInfoReplyInfo)
    case userInterests(username: String, likes: [String], hates: [String])
    case recommendations(recommendations: [(item: String, score: Int32)], unrecommendations: [(item: String, score: Int32)])
    case globalRecommendations(recommendations: [(item: String, score: Int32)], unrecommendations: [(item: String, score: Int32)])
    case itemRecommendations(item: String, recommendations: [(item: String, score: Int32)])
    case similarUsers([(username: String, rating: UInt32)])
    case itemSimilarUsers(item: String, users: [String])
    case privilegesChecked(secondsLeft: UInt32)
    case userPrivileges(username: String, privileged: Bool)
    case privilegedUsers([String])
    case adminMessage(String)
}

/// Search results and search-adjacent server state.
public enum SearchEvent: Sendable {
    case results(token: UInt32, results: [SearchResult])
    case excludedPhrases([String])
    case wishlistInterval(seconds: UInt32)
    case folderContentsResponse(token: UInt32, folder: String, files: [SharedFile])
}

/// Server connection lifecycle.
public enum ConnectionEvent: Sendable {
    case statusChanged(ConnectionStatus)
    case protocolNotice(code: UInt32, payload: Data)
}

/// Transfer control-plane events consumed by DownloadManager /
/// UploadManager. Payloads carry the live `PeerConnection` actor the
/// message arrived on — peers can deliver TransferRequests on a
/// different connection than the one cached at queue time, and the
/// handoff paths need the actual socket.
///
/// The managers' consumers spawn a Task per event, so a slow transfer
/// setup never stalls subsequent transfer events.
public enum TransferEvent: Sendable {
    case fileTransferConnection(username: String, token: UInt32, connection: PeerConnection)
    case pierceFirewall(token: UInt32, connection: PeerConnection)
    case queueUpload(username: String, filename: String, connection: PeerConnection)
    case transferResponse(token: UInt32, allowed: Bool, filesize: UInt64?, reason: String?, connection: PeerConnection)
    case transferRequest(TransferRequest, connection: PeerConnection)
    case placeInQueueRequest(username: String, filename: String, connection: PeerConnection)
    case placeInQueueReply(username: String, filename: String, position: UInt32)
}

/// Fire-and-forget transfer notices (informational).
public enum TransferNoticeEvent: Sendable {
    case uploadDenied(username: String, filename: String, reason: String)
    case uploadFailed(username: String, filename: String)
    case cantConnectToPeer(token: UInt32)
    case peerAddress(username: String, ip: String, port: Int)
}
