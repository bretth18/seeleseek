import Foundation

// MARK: - Server Message Codes
// SoulSeek protocol uses the same message codes for different purposes depending on direction.
// These are organized by their primary use case.
enum ServerMessageCode: UInt32 {
    // Authentication & Session
    case login = 1
    case setListenPort = 2
    case getPeerAddress = 3
    case watchUser = 5
    case unwatchUser = 6
    case getUserStatus = 7
    case sayInChatRoom = 13
    case joinRoom = 14
    case leaveRoom = 15
    case userJoinedRoom = 16
    case userLeftRoom = 17
    case connectToPeer = 18
    case privateMessages = 22
    case acknowledgePrivateMessage = 23
    case fileSearch = 26
    case setOnlineStatus = 28
    case ping = 32
    case sendConnectToken = 33
    case sendUploadSpeed = 34
    case sharedFoldersFiles = 35
    case getUserStats = 36
    case getMoreParents = 41
    case addThingILike = 51
    case removeThingILike = 52
    case recommendations = 54
    case userInterests = 57
    case roomList = 64
    case exactFileSearch = 65
    case adminMessage = 66
    case globalUserList = 67
    case tunneledMessage = 68
    case privilegedUsers = 69

    // Distributed network - client to server
    case haveNoParent = 71  // Tell server we need a distributed parent

    case parentMinSpeed = 83
    case parentSpeedRatio = 84
    case minParentsInCache = 86

    case addToPrivileged = 91
    case checkPrivileges = 92
    case embeddedMessage = 93  // Server sends us embedded distributed message

    // Distributed network - server to client
    case possibleParents = 102  // Server sends list of potential parents

    case wishlistSearch = 103
    case wishlistInterval = 104
    case similarUsers = 110
    case itemRecommendations = 111
    case itemSimilarUsers = 112
    case roomTickerState = 113
    case roomTickerAdd = 114
    case roomTickerRemove = 115
    case roomTickerSet = 116
    case addThingIHate = 117
    case removeThingIHate = 118
    case roomSearch = 120
    case sendUploadSpeedRequest = 121
    case userPrivileges = 122

    // Distributed network - branch info from client
    case childDepth = 125  // Tell server our child depth
    case branchLevel = 126  // Tell server our branch level
    case branchRoot = 127  // Tell server our branch root

    case acceptChildren = 100  // Tell server if we accept child nodes

    case resetDistributed = 130

    // Private rooms
    case privateRoomMembers = 133
    case privateRoomAddMember = 134
    case privateRoomRemoveMember = 135
    case privateRoomCancelMembership = 136
    case privateRoomCancelOwnership = 137
    case privateRoomAddOperator = 143
    case privateRoomRemoveOperator = 144
    case privateRoomOperatorGranted = 145
    case privateRoomOperatorRevoked = 146
    case privateRoomOperators = 148

    // Special codes (1000+)
    case cantConnectToPeer = 1001
    case cantCreateRoom = 1003

    nonisolated var description: String {
        switch self {
        case .login: "Login"
        case .setListenPort: "SetListenPort"
        case .getPeerAddress: "GetPeerAddress"
        case .watchUser: "WatchUser"
        case .unwatchUser: "UnwatchUser"
        case .getUserStatus: "GetUserStatus"
        case .sayInChatRoom: "SayInChatRoom"
        case .joinRoom: "JoinRoom"
        case .leaveRoom: "LeaveRoom"
        case .userJoinedRoom: "UserJoinedRoom"
        case .userLeftRoom: "UserLeftRoom"
        case .connectToPeer: "ConnectToPeer"
        case .privateMessages: "PrivateMessages"
        case .acknowledgePrivateMessage: "AcknowledgePrivateMessage"
        case .fileSearch: "FileSearch"
        case .setOnlineStatus: "SetOnlineStatus"
        case .ping: "Ping"
        case .sendConnectToken: "SendConnectToken"
        case .sendUploadSpeed: "SendUploadSpeed"
        case .sharedFoldersFiles: "SharedFoldersFiles"
        case .getUserStats: "GetUserStats"
        case .cantConnectToPeer: "CantConnectToPeer"
        case .cantCreateRoom: "CantCreateRoom"
        case .haveNoParent: "HaveNoParent"
        case .possibleParents: "PossibleParents"
        case .embeddedMessage: "EmbeddedMessage"
        case .resetDistributed: "ResetDistributed"
        case .branchLevel: "BranchLevel"
        case .branchRoot: "BranchRoot"
        case .acceptChildren: "AcceptChildren"
        case .roomList: "RoomList"
        default: "Code(\(rawValue))"
        }
    }
}

// MARK: - Peer Message Codes
enum PeerMessageCode: UInt8 {
    case pierceFirewall = 0
    case peerInit = 1

    // Peer messages (after connection established)
    case sharesRequest = 4
    case sharesReply = 5
    case searchRequest = 8
    case searchReply = 9
    case userInfoRequest = 15
    case userInfoReply = 16
    case folderContentsRequest = 36
    case folderContentsReply = 37
    case transferRequest = 40
    case transferReply = 41
    case uploadPlacehold = 42
    case queueDownload = 43        // QueueUpload in protocol docs
    case placeInQueueReply = 44    // PlaceInQueueResponse in protocol docs
    case uploadFailed = 46
    case uploadDenied = 50
    case placeInQueueRequest = 51

    nonisolated var description: String {
        switch self {
        case .pierceFirewall: "PierceFirewall"
        case .peerInit: "PeerInit"
        case .sharesRequest: "SharesRequest"
        case .sharesReply: "SharesReply"
        case .searchRequest: "SearchRequest"
        case .searchReply: "SearchReply"
        case .userInfoRequest: "UserInfoRequest"
        case .userInfoReply: "UserInfoReply"
        case .folderContentsRequest: "FolderContentsRequest"
        case .folderContentsReply: "FolderContentsReply"
        case .transferRequest: "TransferRequest"
        case .transferReply: "TransferReply"
        case .uploadPlacehold: "UploadPlacehold"
        case .queueDownload: "QueueUpload"
        case .placeInQueueReply: "PlaceInQueueResponse"
        case .uploadFailed: "UploadFailed"
        case .uploadDenied: "UploadDenied"
        case .placeInQueueRequest: "PlaceInQueueRequest"
        }
    }
}

// MARK: - Distributed Message Codes
enum DistributedMessageCode: UInt8 {
    case ping = 0
    case searchRequest = 3
    case branchLevel = 4
    case branchRoot = 5

    nonisolated var description: String {
        switch self {
        case .ping: "DistributedPing"
        case .searchRequest: "DistributedSearch"
        case .branchLevel: "BranchLevel"
        case .branchRoot: "BranchRoot"
        }
    }
}

// MARK: - File Transfer Codes
enum FileTransferDirection: UInt8, Sendable {
    case download = 0
    case upload = 1
}

// MARK: - User Status
enum UserStatus: UInt32, Sendable {
    case offline = 0
    case away = 1
    case online = 2

    nonisolated var description: String {
        switch self {
        case .offline: "Offline"
        case .away: "Away"
        case .online: "Online"
        }
    }
}

// MARK: - Login Response
enum LoginResult: Sendable {
    case success(greeting: String, ip: String, hash: String?)
    case failure(reason: String)
}
