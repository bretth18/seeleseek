import SwiftUI
import Network
import Synchronization

struct DiagnosticsSection: View {
    @Environment(\.appState) private var appState
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false
    @State private var portTestResult: String = ""
    @State private var isTestingPort: Bool = false
    @State private var browseTestUsername: String = ""
    @State private var browseTestResult: String = ""
    @State private var isTestingBrowse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sectionSpacing) {
            settingsHeader("Diagnostics")

            settingsGroup("Connection Status") {
                diagRow("Server Connected", value: appState.networkClient.isConnected ? "Yes" : "No",
                       color: appState.networkClient.isConnected ? SeeleColors.success : SeeleColors.error)
                diagRow("Logged In", value: appState.networkClient.loggedIn ? "Yes" : "No",
                       color: appState.networkClient.loggedIn ? SeeleColors.success : SeeleColors.error)
                diagRow("Username", value: appState.networkClient.username.isEmpty ? "-" : appState.networkClient.username)

                if let error = appState.networkClient.connectionError {
                    diagRow("Last Error", value: error, color: SeeleColors.error)
                }
            }

            settingsGroup("Network Configuration") {
                diagRow("Listen Port", value: appState.networkClient.listenPort > 0 ? "\(appState.networkClient.listenPort)" : "-")
                diagRow("Obfuscated Port", value: appState.networkClient.obfuscatedPort > 0 ? "\(appState.networkClient.obfuscatedPort)" : "-")
                diagRow("External IP", value: appState.networkClient.externalIP ?? "Unknown")
                diagRow("Configured Port", value: "\(appState.settings.listenPort)")
                diagRow("UPnP Enabled", value: appState.settings.enableUPnP ? "Yes" : "No")
            }

            settingsGroup("Peer Connections") {
                diagRow("Active Connections", value: "\(appState.networkClient.peerConnectionPool.activeConnections)")
                diagRow("Max Connections", value: "\(appState.networkClient.peerConnectionPool.maxConnections)")
                diagRow("ConnectToPeer Received", value: "\(appState.networkClient.peerConnectionPool.connectToPeerCount)")
                diagRow("PierceFirewall Received", value: "\(appState.networkClient.peerConnectionPool.pierceFirewallCount)",
                       color: appState.networkClient.peerConnectionPool.pierceFirewallCount > 0 ? SeeleColors.success : SeeleColors.textSecondary)
                settingsRow {
                    Text("Note: If ConnectToPeer is high but PierceFirewall is 0, your port is not reachable.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            settingsGroup("Port Reachability Test") {
                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        Text("Tests if your listen port is reachable from the internet.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        if isTestingPort {
                            HStack(spacing: SeeleSpacing.sm) {
                                ProgressView().scaleEffect(0.7)
                                Text("Testing port reachability...")
                                    .font(SeeleTypography.body)
                                    .foregroundStyle(SeeleColors.textSecondary)
                            }
                        } else {
                            Button("Test Port Reachability") {
                                testPortReachability()
                            }
                            .font(SeeleTypography.body)
                            .buttonStyle(.plain)
                            .foregroundStyle(SeeleColors.accent)
                        }

                        if !portTestResult.isEmpty {
                            Text(portTestResult)
                                .font(SeeleTypography.mono)
                                .foregroundStyle(SeeleColors.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            settingsGroup("Browse Test") {
                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        Text("Test browsing a specific user to diagnose connection issues.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        HStack(spacing: SeeleSpacing.sm) {
                            TextField("Username", text: $browseTestUsername)
                                .textFieldStyle(SeeleTextFieldStyle())

                            if isTestingBrowse {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button("Test Browse") {
                                    testBrowse()
                                }
                                .font(SeeleTypography.body)
                                .buttonStyle(.plain)
                                .foregroundStyle(SeeleColors.accent)
                                .disabled(browseTestUsername.isEmpty)
                            }
                        }

                        if !browseTestResult.isEmpty {
                            Text(browseTestResult)
                                .font(SeeleTypography.mono)
                                .foregroundStyle(SeeleColors.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            settingsGroup("Server Connection Test") {
                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        if isTesting {
                            HStack(spacing: SeeleSpacing.sm) {
                                ProgressView().scaleEffect(0.7)
                                Text("Testing...")
                                    .font(SeeleTypography.body)
                                    .foregroundStyle(SeeleColors.textSecondary)
                            }
                        } else {
                            Button("Test Server Connection") {
                                testConnection()
                            }
                            .font(SeeleTypography.body)
                            .buttonStyle(.plain)
                            .foregroundStyle(SeeleColors.accent)
                        }

                        if !testResult.isEmpty {
                            Text(testResult)
                                .font(SeeleTypography.mono)
                                .foregroundStyle(SeeleColors.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            settingsGroup("Troubleshooting Tips") {
                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                        tipRow("Port Forwarding", "Ensure port \(appState.settings.listenPort) is forwarded in your router to this computer")
                        tipRow("Firewall", "Allow SeeleSeek through your firewall for incoming connections")
                        tipRow("NAT Type", "Strict NAT may prevent peers from connecting to you")
                        tipRow("UPnP", "Enable UPnP in your router settings for automatic port forwarding")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func diagRow(_ label: String, value: String, color: Color = SeeleColors.textSecondary) -> some View {
        settingsRow {
            HStack {
                Text(label)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                Spacer()
                Text(value)
                    .font(SeeleTypography.body)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
    }

    private func tipRow(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text("• \(title)")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
            Text(description)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .padding(.leading, SeeleSpacing.md)
        }
    }

    private func testPortReachability() {
        isTestingPort = true
        portTestResult = ""

        Task {
            var results: [String] = []
            let port = appState.networkClient.listenPort
            let externalIP = appState.networkClient.externalIP ?? "unknown"

            results.append("Testing port \(port) reachability...")
            results.append("External IP: \(externalIP)")

            if let _ = URL(string: "https://portchecker.co/check?port=\(port)") {
                results.append("Check manually at: portchecker.co")
            }

            let ctpCount = appState.networkClient.peerConnectionPool.connectToPeerCount
            if ctpCount > 0 {
                results.append("✓ Receiving ConnectToPeer requests (\(ctpCount))")
                results.append("  Server knows our port, but peers may not be able to reach us")
            } else {
                results.append("⚠ No ConnectToPeer requests received yet")
                results.append("  Try searching first to trigger peer connections")
            }

            let activeCount = appState.networkClient.peerConnectionPool.activeConnections
            results.append("Active peer connections: \(activeCount)")

            if activeCount == 0 && ctpCount > 10 {
                results.append("")
                results.append("⚠ HIGH ConnectToPeer but NO active connections")
                results.append("  Your port is likely NOT reachable from internet")
                results.append("  → Check router port forwarding")
                results.append("  → Check firewall settings")
                results.append("  → Try enabling UPnP")
            }

            await MainActor.run {
                portTestResult = results.joined(separator: "\n")
                isTestingPort = false
            }
        }
    }

    private func testBrowse() {
        guard !browseTestUsername.isEmpty else { return }
        isTestingBrowse = true
        browseTestResult = ""

        Task {
            var results: [String] = []
            let username = browseTestUsername.trimmingCharacters(in: .whitespaces)

            results.append("Testing browse for: \(username)")
            results.append("")

            results.append("Step 1: Requesting peer address...")

            do {
                let startTime = Date()
                let files = try await appState.networkClient.browseUser(username)
                let elapsed = Date().timeIntervalSince(startTime)
                results.append("✓ Browse successful in \(String(format: "%.1f", elapsed))s")
                results.append("✓ Received \(files.count) files/folders")
            } catch {
                results.append("✗ Browse failed: \(error.localizedDescription)")
                results.append("")
                results.append("Possible causes:")
                results.append("• User is offline")
                results.append("• User has browsing disabled")
                results.append("• Network connectivity issue")
                results.append("• Both peers behind strict NAT")
            }

            await MainActor.run {
                browseTestResult = results.joined(separator: "\n")
                isTestingBrowse = false
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = ""

        Task {
            var results: [String] = []

            results.append("Testing DNS resolution...")
            let host = ServerConnection.defaultHost
            let port = ServerConnection.defaultPort

            do {
                let addresses = try await resolveDNS(host: host)
                results.append("✓ DNS resolved to: \(addresses.joined(separator: ", "))")
            } catch {
                results.append("✗ DNS resolution failed: \(error.localizedDescription)")
            }

            results.append("\nTesting TCP connection to \(host):\(port)...")
            do {
                try await testTCPConnection(host: host, port: port)
                results.append("✓ TCP connection successful")
            } catch {
                results.append("✗ TCP connection failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                testResult = results.joined(separator: "\n")
                isTesting = false
            }
        }
    }

    private func resolveDNS(host: String) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM

            var result: UnsafeMutablePointer<addrinfo>?

            let status = getaddrinfo(host, nil, &hints, &result)
            if status != 0 {
                continuation.resume(throwing: NSError(domain: "DNS", code: Int(status)))
                return
            }

            var addresses: [String] = []
            var ptr = result
            while ptr != nil {
                if let addr = ptr?.pointee.ai_addr {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr, socklen_t(ptr!.pointee.ai_addrlen),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST)
                    addresses.append(String(cString: hostname))
                }
                ptr = ptr?.pointee.ai_next
            }
            freeaddrinfo(result)

            continuation.resume(returning: Array(Set(addresses)))
        }
    }

    private func testTCPConnection(host: String, port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "DiagnosticsSection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"])
        }
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        let didComplete = Mutex(false)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard didComplete.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    connection.cancel()
                    continuation.resume()

                case .failed(let error):
                    guard didComplete.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: error)

                case .cancelled:
                    guard didComplete.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: NSError(domain: "Connection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"]))

                default:
                    break
                }
            }

            connection.start(queue: .global())

            Task {
                try? await Task.sleep(for: .seconds(10))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                connection.cancel()
                continuation.resume(throwing: NSError(domain: "Connection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timed out"]))
            }
        }
    }
}

#Preview {
    ScrollView {
        DiagnosticsSection()
            .padding()
    }
    .environment(\.appState, AppState())
    .frame(width: 500, height: 600)
    .background(SeeleColors.background)
}
