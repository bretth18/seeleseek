import Foundation

/// Values SeeleSeek can adopt from another client's configuration.
/// Filled by `NicotineConfigImporter` and `SoulseekQtConfigImporter`;
/// applied by `ClientImportSheet`.
struct ImportedClientConfig: Equatable {
    var username: String?
    var password: String?
    var listenPort: Int?
    var downloadDirectory: String?
    var incompleteDirectory: String?
    var uploadSlots: Int?
    /// KB/s. 0 = unlimited. Same convention as SettingsState.
    var uploadSpeedLimit: Int?
    var downloadSpeedLimit: Int?
    var sharedFolders: [String] = []
    var autojoinRooms: [String] = []
    var ignoredUsers: [String] = []

    var isEmpty: Bool {
        username == nil && password == nil && listenPort == nil
            && downloadDirectory == nil && incompleteDirectory == nil
            && uploadSlots == nil && uploadSpeedLimit == nil && downloadSpeedLimit == nil
            && sharedFolders.isEmpty && autojoinRooms.isEmpty && ignoredUsers.isEmpty
    }
}
