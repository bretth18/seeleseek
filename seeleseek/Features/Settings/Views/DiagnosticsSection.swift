import SwiftUI
import Network
import Synchronization
import SeeleseekCore

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
                diagRow("Local IP", value: appState.networkClient.localIP ?? "-")
                diagRow("External IP", value: appState.networkClient.externalIP ?? "Unknown")
                diagRow("Configured Port", value: "\(appState.settings.listenPort)")
                diagRow("UPnP Enabled", value: appState.settings.enableUPnP ? "Yes" : "No")
            }

            settingsGroup("NAT / Reachability") {
                diagRow("Reachability",
                        value: appState.networkClient.reachability.label,
                        color: reachabilityColor(appState.networkClient.reachability))
                diagRow("Gateway", value: appState.networkClient.natGateway ?? "-")
                diagRow("Port Mappings", value: mappingSummary(appState.networkClient.natMappings))
                if !appState.networkClient.natMappings.isEmpty {
                    settingsRow {
                        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                            ForEach(appState.networkClient.natMappings, id: \.internalPort) { mapping in
                                Text("\(mapping.proto) \(mapping.internalPort) → \(mapping.externalPort)")
                                    .font(SeeleTypography.mono)
                                    .foregroundStyle(SeeleColors.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                settingsRow {
                    Text(reachabilityHint(appState.networkClient.reachability))
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
            }

            settingsGroup("Peer Connections") {
                let pool = appState.networkClient.peerConnectionPool
                diagRow("Active / Total", value: "\(pool.activeConnections) / \(pool.totalConnections)")
                diagRow("Max Connections", value: "\(pool.maxConnections)")

                // Direct inbound reachability — the real "can peers reach my port" signal.
                diagRow("Direct Inbound (PeerInit)", value: "\(pool.peerInitCount)",
                       color: pool.peerInitCount > 0 ? SeeleColors.success : SeeleColors.textSecondary)

                // ConnectToPeer count: the OPPOSITE signal — each one is proof
                // a peer tried direct and failed, so they asked the server to
                // forward. Good when zero, bad when nonzero.
                diagRow("Server-Forwarded (ConnectToPeer)", value: "\(pool.connectToPeerCount)",
                       color: pool.connectToPeerCount == 0 ? SeeleColors.textSecondary :
                              pool.peerInitCount > 0 ? SeeleColors.warning : SeeleColors.error)

                // PierceFirewall received: unrelated direction — peers responding
                // to our own outbound ConnectToPeer requests. Surface for
                // completeness but not as a primary metric.
                diagRow("PierceFirewall Received", value: "\(pool.pierceFirewallCount)")

                diagRow("Avg Connection Duration", value: formatDuration(pool.averageConnectionDuration))
                diagRow("Total Received", value: pool.totalBytesReceived.formattedBytes)
                diagRow("Total Sent", value: pool.totalBytesSent.formattedBytes)

                settingsRow {
                    VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                        Text("Direct Inbound is the definitive reachability signal — if it's > 0, your port is open to at least some peers.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                        Text("Server-Forwarded counts peers who couldn't reach your port directly and fell back to the server. High values = port problem.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }
            }

            settingsGroup("Session") {
                let stats = appState.statisticsState
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    diagRow("Uptime", value: stats.formattedSessionDuration)
                }
                diagRow("Downloads", value: "\(stats.filesDownloaded)")
                diagRow("Uploads", value: "\(stats.filesUploaded)")
                diagRow("Searches Performed", value: "\(stats.searchesPerformed)")
                let uniqueUsers = stats.uniqueUsersDownloadedFrom.count + stats.uniqueUsersUploadedTo.count
                diagRow("Unique Peers (Session)", value: "\(uniqueUsers)")
            }

            settingsGroup("Distributed Network") {
                diagRow("Accept Children", value: appState.networkClient.acceptDistributedChildren ? "Yes" : "No")
                diagRow("Branch Level", value: "\(appState.networkClient.distributedBranchLevel)")
                diagRow("Branch Root",
                       value: appState.networkClient.distributedBranchRoot.isEmpty ? "-" : appState.networkClient.distributedBranchRoot)
                diagRow("Children", value: "\(appState.networkClient.distributedChildren.count)")
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

    private func reachabilityColor(_ r: NetworkClient.Reachability) -> Color {
        switch r {
        case .direct, .upnpMapped: return SeeleColors.success
        case .partial: return SeeleColors.warning
        case .unreachable: return SeeleColors.error
        case .unknown: return SeeleColors.textSecondary
        }
    }

    private func reachabilityHint(_ r: NetworkClient.Reachability) -> String {
        switch r {
        case .direct:
            return "Your listen port is open to the internet. Peers are connecting directly."
        case .upnpMapped:
            return "Direct connections are working and your router has a UPnP/NAT-PMP mapping active."
        case .partial:
            return "Your port is reachable — some peers connect directly — but others can't and fall back to the server. Usually their NAT is the issue, not yours."
        case .unreachable:
            return "No peer has reached your port directly. Check: (1) Listen Port matches the one you forwarded in your router; (2) macOS firewall allows SeeleSeek; (3) you're not behind double NAT (ISP modem + router both NAT'ing)."
        case .unknown:
            return "No peers have tried to reach us yet. Trigger a search or browse to generate activity, then check back."
        }
    }

    private func mappingSummary(_ mappings: [NATService.PortMapping]) -> String {
        if mappings.isEmpty { return "None" }
        return "\(mappings.count) active"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "-" }
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h \(Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60))m"
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
                    // Convert [CChar] (Int8) to [UInt8] and decode as UTF-8, truncating at the first null terminator
                    if let nulIndex = hostname.firstIndex(of: 0) {
                        let prefix = hostname.prefix(upTo: nulIndex)
                        let bytes = prefix.map { UInt8(bitPattern: $0) }
                        addresses.append(String(decoding: bytes, as: UTF8.self))
                    } else {
                        let bytes = hostname.map { UInt8(bitPattern: $0) }
                        addresses.append(String(decoding: bytes, as: UTF8.self))
                    }
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
