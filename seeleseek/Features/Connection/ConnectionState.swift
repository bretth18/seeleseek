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

// MARK: - Credential Storage

enum CredentialStorage {
    private static let usernameKey = "seeleseek.username"
    private static let passwordKey = "seeleseek.password"

    static func save(username: String, password: String) {
        UserDefaults.standard.set(username, forKey: usernameKey)
        // In production, use Keychain for password
        UserDefaults.standard.set(password, forKey: passwordKey)
    }

    static func load() -> (username: String, password: String)? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              let password = UserDefaults.standard.string(forKey: passwordKey) else {
            return nil
        }
        return (username, password)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
    }
}
