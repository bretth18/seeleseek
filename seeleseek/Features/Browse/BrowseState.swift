import SwiftUI

@Observable
@MainActor
final class BrowseState {
    // MARK: - Browse State
    var currentUser: String = ""
    var userShares: UserShares?
    var expandedFolders: Set<UUID> = []
    var selectedFile: SharedFile?

    // MARK: - History
    var browseHistory: [String] = []

    // MARK: - Computed Properties
    var isLoading: Bool {
        userShares?.isLoading ?? false
    }

    var hasError: Bool {
        userShares?.error != nil
    }

    var canBrowse: Bool {
        !currentUser.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions
    func browseUser(_ username: String) {
        currentUser = username
        userShares = UserShares(username: username)
        expandedFolders = []
        selectedFile = nil

        // Add to history
        if !browseHistory.contains(username) {
            browseHistory.insert(username, at: 0)
            if browseHistory.count > 20 {
                browseHistory.removeLast()
            }
        }
    }

    func setShares(_ folders: [SharedFile]) {
        userShares?.folders = folders
        userShares?.isLoading = false
    }

    func setError(_ message: String) {
        userShares?.error = message
        userShares?.isLoading = false
    }

    func toggleFolder(_ id: UUID) {
        if expandedFolders.contains(id) {
            expandedFolders.remove(id)
        } else {
            expandedFolders.insert(id)
        }
    }

    func selectFile(_ file: SharedFile) {
        if file.isDirectory {
            toggleFolder(file.id)
        } else {
            selectedFile = file
        }
    }

    func clear() {
        currentUser = ""
        userShares = nil
        expandedFolders = []
        selectedFile = nil
    }
}
