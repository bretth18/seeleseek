import SwiftUI

@Observable
@MainActor
final class ConnectionState {
    // MARK: - Connection Status
    var connectionStatus: ConnectionStatus = .disconnected
    var username: String?
    var serverIP: String?
    var serverGreeting: String?
    var errorMessage: String?

    // MARK: - Login Form
    var loginUsername: String = ""
    var loginPassword: String = ""
    var rememberCredentials: Bool = true

    // MARK: - Validation
    var isLoginValid: Bool {
        !loginUsername.trimmingCharacters(in: .whitespaces).isEmpty &&
        !loginPassword.isEmpty
    }

    // MARK: - Actions
    func setConnecting() {
        connectionStatus = .connecting
        errorMessage = nil
    }

    func setConnected(username: String, ip: String, greeting: String?) {
        self.connectionStatus = .connected
        self.username = username
        self.serverIP = ip
        self.serverGreeting = greeting
        self.errorMessage = nil
    }

    func setDisconnected() {
        connectionStatus = .disconnected
        username = nil
        serverIP = nil
        serverGreeting = nil
    }

    func setError(_ message: String) {
        connectionStatus = .error
        errorMessage = message
    }

    func clearError() {
        if connectionStatus == .error {
            connectionStatus = .disconnected
        }
        errorMessage = nil
    }
}

// MARK: - Credential Storage (Keychain-based)

import Security

enum CredentialStorage {
    private static let service = "com.seeleseek.credentials"
    private static let usernameKey = "seeleseek.username"

    static func save(username: String, password: String) {
        // Save username to UserDefaults (not sensitive)
        UserDefaults.standard.set(username, forKey: usernameKey)

        // Save password to Keychain (secure)
        saveToKeychain(password: password, account: username)
    }

    static func load() -> (username: String, password: String)? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey) else {
            return nil
        }

        guard let password = loadFromKeychain(account: username) else {
            return nil
        }

        return (username, password)
    }

    static func clear() {
        if let username = UserDefaults.standard.string(forKey: usernameKey) {
            deleteFromKeychain(account: username)
        }
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    // MARK: - Keychain Operations

    private static func saveToKeychain(password: String, account: String) {
        guard let passwordData = password.data(using: .utf8) else { return }

        // Delete existing item first
        deleteFromKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Keychain save failed: \(status)")
        }
    }

    private static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }

        return password
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
