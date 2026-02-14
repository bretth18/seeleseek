import Foundation

// MARK: - Server Message Codes
// SoulSeek protocol uses the same message codes for different purposes depending on direction.
// These are organized by their primary use case.
enum ServerMessageCode: UInt32 {
    // Authentication & Session
    case login = 1
    case setListenPort = 2
    case getPeerAddress = 3
    case ignoreUser = 11
    case unignoreUser = 12
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
    case fileSearchRoom = 25
    case fileSearch = 26
    case setOnlineStatus = 28
    case ping = 32
    case sendConnectToken = 33
    case sendDownloadSpeed = 34
    case sharedFoldersFiles = 35
    case getUserStats = 36
    case uploadSlotsFull = 40
    case relogged = 41
    case userSearch = 42
    case similarRecommendations = 50
    case addThingILike = 51
    case removeThingILike = 52
    case recommendations = 54
    case myRecommendations = 55
    case globalRecommendations = 56
    case userInterests = 57
    case adminCommand = 58
    case placeInLineRequest = 59
    case placeInLineResponse = 60
    case roomAdded = 62
    case roomRemoved = 63
    case roomList = 64
    case exactFileSearch = 65
    case adminMessage = 66
    case globalUserList = 67
    case tunneledMessage = 68
    case privilegedUsers = 69

    // Distributed network - client to server
    case haveNoParent = 71  // Tell server we need a distributed parent
    case searchParent = 73

    case parentMinSpeed = 83
    case parentSpeedRatio = 84
    case minParentsInCache = 86
    case searchInactivityTimeout = 87
    case minParentsInCacheDeprecated = 88
    case distribPingInterval = 90

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
    case givePrivileges = 123
    case privateRoomUnknown124 = 124

    // Distributed network - branch info from client
    case childDepth = 125  // Tell server our child depth
    case branchLevel = 126  // Tell server our branch level
    case branchRoot = 127  // Tell server our branch root

    case acceptChildren = 100  // Tell server if we accept child nodes

    case resetDistributed = 130
    case privateRoomUnknown129 = 129

    // Private rooms
    case privateRoomMembers = 133
    case privateRoomAddMember = 134
    case privateRoomRemoveMember = 135
    case privateRoomCancelMembership = 136
    case privateRoomCancelOwnership = 137
    case privateRoomUnknown138 = 138
    case privateRoomAddOperator = 143
    case privateRoomRemoveOperator = 144
    case privateRoomOperatorGranted = 145
    case privateRoomOperatorRevoked = 146
    case privateRoomOperators = 148
    case messageUsers = 149
    case joinGlobalRoom = 150
    case leaveGlobalRoom = 151

    // Room membership & invitations
    case roomMembershipGranted = 139
    case roomMembershipRevoked = 140
    case enableRoomInvitations = 141
    case newPassword = 142

    // Global room messages
    case globalRoomMessage = 152
    case roomUnknown153 = 153

    // Search
    case excludedSearchPhrases = 160

    // Special codes (1000+)
    case cantConnectToPeer = 1001
    case cantCreateRoom = 1003

    nonisolated var description: String {
        switch self {
        case .login: "Login"
        case .setListenPort: "SetListenPort"
        case .getPeerAddress: "GetPeerAddress"
        case .ignoreUser: "IgnoreUser"
        case .unignoreUser: "UnignoreUser"
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
        case .fileSearchRoom: "FileSearchRoom"
        case .fileSearch: "FileSearch"
        case .setOnlineStatus: "SetOnlineStatus"
        case .ping: "Ping"
        case .sendConnectToken: "SendConnectToken"
        case .sendDownloadSpeed: "SendDownloadSpeed"
        case .sharedFoldersFiles: "SharedFoldersFiles"
        case .getUserStats: "GetUserStats"
        case .uploadSlotsFull: "UploadSlotsFull"
        case .relogged: "Relogged"
        case .userSearch: "UserSearch"
        case .similarRecommendations: "SimilarRecommendations"
        case .myRecommendations: "MyRecommendations"
        case .adminCommand: "AdminCommand"
        case .placeInLineRequest: "PlaceInLineRequest"
        case .placeInLineResponse: "PlaceInLineResponse"
        case .roomAdded: "RoomAdded"
        case .roomRemoved: "RoomRemoved"
        case .cantConnectToPeer: "CantConnectToPeer"
        case .cantCreateRoom: "CantCreateRoom"
        case .haveNoParent: "HaveNoParent"
        case .searchParent: "SearchParent"
        case .searchInactivityTimeout: "SearchInactivityTimeout"
        case .minParentsInCacheDeprecated: "MinParentsInCacheDeprecated"
        case .distribPingInterval: "DistribPingInterval"
        case .possibleParents: "PossibleParents"
        case .embeddedMessage: "EmbeddedMessage"
        case .privateRoomUnknown124: "PrivateRoomUnknown124"
        case .privateRoomUnknown129: "PrivateRoomUnknown129"
        case .privateRoomUnknown138: "PrivateRoomUnknown138"
        case .roomUnknown153: "RoomUnknown153"
        case .resetDistributed: "ResetDistributed"
        case .branchLevel: "BranchLevel"
        case .branchRoot: "BranchRoot"
        case .acceptChildren: "AcceptChildren"
        case .roomList: "RoomList"
        case .excludedSearchPhrases: "ExcludedSearchPhrases"
        case .roomMembershipGranted: "RoomMembershipGranted"
        case .roomMembershipRevoked: "RoomMembershipRevoked"
        case .enableRoomInvitations: "EnableRoomInvitations"
        case .newPassword: "NewPassword"
        case .givePrivileges: "GivePrivileges"
        case .messageUsers: "MessageUsers"
        case .joinGlobalRoom: "JoinGlobalRoom"
        case .leaveGlobalRoom: "LeaveGlobalRoom"
        case .globalRoomMessage: "GlobalRoomMessage"
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
    case uploadQueueNotification = 52

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
        case .uploadQueueNotification: "UploadQueueNotification"
        }
    }
}

// MARK: - Distributed Message Codes
enum DistributedMessageCode: UInt8 {
    case ping = 0
    case searchRequest = 3
    case branchLevel = 4
    case branchRoot = 5
    case childDepth = 7
    case embeddedMessage = 93

    nonisolated var description: String {
        switch self {
        case .ping: "DistributedPing"
        case .searchRequest: "DistributedSearch"
        case .branchLevel: "BranchLevel"
        case .branchRoot: "BranchRoot"
        case .childDepth: "ChildDepth"
        case .embeddedMessage: "EmbeddedMessage"
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
