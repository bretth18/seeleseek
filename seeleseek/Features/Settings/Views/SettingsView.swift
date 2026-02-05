import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case profile = "Profile"
        case general = "General"
        case network = "Network"
        case shares = "Shares"
        case metadata = "Metadata"
        case chat = "Chat"
        case privacy = "Privacy"
        case diagnostics = "Diagnostics"

        var icon: String {
            switch self {
            case .profile: "person.crop.circle"
            case .general: "gear"
            case .network: "network"
            case .shares: "folder"
            case .metadata: "music.note"
            case .chat: "bubble.left"
            case .privacy: "lock.shield"
            case .diagnostics: "ant"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Tab sidebar
            VStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    settingsTabButton(tab)
                }
                Spacer()
            }
            .frame(width: 180)
            .background(SeeleColors.surface)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.xl) {
                    switch selectedTab {
                    case .profile:
                        MyProfileView()
                    case .general:
                        GeneralSettingsSection(settings: appState.settings)
                    case .network:
                        NetworkSettingsSection(settings: appState.settings)
                    case .shares:
                        SharesSettingsSection(settings: appState.settings)
                    case .metadata:
                        MetadataSettingsSection(settings: appState.settings)
                    case .chat:
                        ChatSettingsSection(settings: appState.settings)
                    case .privacy:
                        PrivacySettingsSection(settings: appState.settings)
                    case .diagnostics:
                        DiagnosticsSection()
                    }
                }
                .padding(SeeleSpacing.xl)
            }
            .background(SeeleColors.background)
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(SeeleTypography.subheadline)

                Spacer()
            }
            .foregroundStyle(selectedTab == tab ? SeeleColors.accent : SeeleColors.textSecondary)
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
            .background(selectedTab == tab ? SeeleColors.surfaceSecondary : .clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Sections

struct GeneralSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("General")

            settingsGroup("Downloads") {
                folderPicker("Download Location", url: $settings.downloadLocation)
                folderPicker("Incomplete Files", url: $settings.incompleteLocation)
            }

            settingsGroup("Startup") {
                settingsToggle("Launch at login", isOn: $settings.launchAtLogin)
                settingsToggle("Show in menu bar", isOn: $settings.showInMenuBar)
            }
        }
    }
}

struct NetworkSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Network")

            settingsGroup("Connection") {
                settingsNumberField("Listen Port", value: $settings.listenPort, range: 1024...65535)
                settingsToggle("Enable UPnP", isOn: $settings.enableUPnP)
            }

            settingsGroup("Transfer Slots") {
                settingsStepper("Max Download Slots", value: $settings.maxDownloadSlots, range: 1...20)
                settingsStepper("Max Upload Slots", value: $settings.maxUploadSlots, range: 1...20)
            }

            settingsGroup("Speed Limits") {
                settingsNumberField("Upload Limit (KB/s)", value: $settings.uploadSpeedLimit, range: 0...100000, placeholder: "0 = Unlimited")
                settingsNumberField("Download Limit (KB/s)", value: $settings.downloadSpeedLimit, range: 0...100000, placeholder: "0 = Unlimited")
            }
        }
    }
}

struct SharesSettingsSection: View {
    @Bindable var settings: SettingsState
    @Environment(\.appState) private var appState

    private var shareManager: ShareManager {
        appState.networkClient.shareManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Shares")

            // Summary stats
            HStack(spacing: SeeleSpacing.xl) {
                StatBox(title: "Folders", value: "\(shareManager.totalFolders)", icon: "folder.fill", color: SeeleColors.warning)
                StatBox(title: "Files", value: "\(shareManager.totalFiles)", icon: "doc.fill", color: SeeleColors.accent)
                StatBox(title: "Size", value: ByteFormatter.format(Int64(shareManager.totalSize)), icon: "externaldrive.fill", color: SeeleColors.info)
            }

            settingsGroup("Shared Folders") {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    if shareManager.sharedFolders.isEmpty {
                        Text("No folders shared")
                            .font(SeeleTypography.subheadline)
                            .foregroundStyle(SeeleColors.textTertiary)
                            .padding(SeeleSpacing.md)
                    }

                    ForEach(shareManager.sharedFolders) { folder in
                        SharedFolderRow(folder: folder) {
                            shareManager.removeFolder(folder)
                        }
                    }

                    HStack(spacing: SeeleSpacing.md) {
                        Button {
                            showFolderPicker()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add Folder")
                            }
                            .font(SeeleTypography.subheadline)
                            .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if shareManager.isScanning {
                            HStack(spacing: SeeleSpacing.sm) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Scanning... \(Int(shareManager.scanProgress * 100))%")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        } else {
                            Button {
                                Task { await shareManager.rescanAll() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Rescan")
                                }
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, SeeleSpacing.sm)
                }
            }

            settingsGroup("Options") {
                settingsToggle("Rescan on startup", isOn: $settings.rescanOnStartup)
                settingsToggle("Share hidden files", isOn: $settings.shareHiddenFiles)
            }
        }
    }

    private func showFolderPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to share"
        panel.prompt = "Share"

        if panel.runModal() == .OK {
            for url in panel.urls {
                shareManager.addFolder(url)
            }
        }
        #endif
    }
}

struct SharedFolderRow: View {
    let folder: ShareManager.SharedFolder
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(SeeleColors.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                Text(folder.path)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(folder.fileCount) files")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)

                Text(ByteFormatter.format(Int64(folder.totalSize)))
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(SeeleColors.error)
            }
            .buttonStyle(.plain)
        }
        .padding(SeeleSpacing.sm)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall))
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: SeeleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)

            Text(value)
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

struct MetadataSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Metadata")

            settingsGroup("Auto-fetch") {
                settingsToggle("Fetch metadata automatically", isOn: $settings.autoFetchMetadata)
                settingsToggle("Fetch album art", isOn: $settings.autoFetchAlbumArt)
                    .disabled(!settings.autoFetchMetadata)
                settingsToggle("Embed album art in files", isOn: $settings.embedAlbumArt)
                    .disabled(!settings.autoFetchAlbumArt)
            }

            settingsGroup("Organization") {
                settingsToggle("Organize downloads automatically", isOn: $settings.organizeDownloads)

                if settings.organizeDownloads {
                    VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                        Text("Pattern")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)

                        TextField("", text: $settings.organizationPattern)
                            .textFieldStyle(SeeleTextFieldStyle())

                        Text("Available: {artist}, {album}, {track}, {title}, {year}")
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                }
            }
        }
    }
}

struct ChatSettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Chat")

            settingsGroup("Messages") {
                settingsToggle("Show join/leave messages", isOn: $settings.showJoinLeaveMessages)
            }

            settingsGroup("Notifications") {
                settingsToggle("Enable notifications", isOn: $settings.enableNotifications)
                settingsToggle("Play notification sound", isOn: $settings.notificationSound)
                    .disabled(!settings.enableNotifications)
            }
        }
    }
}

struct PrivacySettingsSection: View {
    @Bindable var settings: SettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            settingsHeader("Privacy")

            settingsGroup("Visibility") {
                settingsToggle("Show online status", isOn: $settings.showOnlineStatus)
                settingsToggle("Allow users to browse my files", isOn: $settings.allowBrowsing)
            }
        }
    }
}

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
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
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

                Text("Note: If ConnectToPeer is high but PierceFirewall is 0, your port is not reachable.")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .padding(.top, SeeleSpacing.xs)
            }

            settingsGroup("Port Reachability Test") {
                Text("Tests if your listen port is reachable from the internet.")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)

                if isTestingPort {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Testing port reachability...")
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                } else {
                    Button("Test Port Reachability") {
                        testPortReachability()
                    }
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

            settingsGroup("Browse Test") {
                Text("Test browsing a specific user to diagnose connection issues.")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)

                HStack {
                    TextField("Username", text: $browseTestUsername)
                        .textFieldStyle(.plain)
                        .padding(SeeleSpacing.sm)
                        .background(SeeleColors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if isTestingBrowse {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Test Browse") {
                            testBrowse()
                        }
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

            settingsGroup("Server Connection Test") {
                if isTesting {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Testing...")
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                } else {
                    Button("Test Server Connection") {
                        testConnection()
                    }
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

            settingsGroup("Troubleshooting Tips") {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    tipRow("Port Forwarding", "Ensure port \(appState.settings.listenPort) is forwarded in your router to this computer")
                    tipRow("Firewall", "Allow SeeleSeek through your firewall for incoming connections")
                    tipRow("NAT Type", "Strict NAT may prevent peers from connecting to you")
                    tipRow("UPnP", "Enable UPnP in your router settings for automatic port forwarding")
                }
            }
        }
    }

    private func diagRow(_ label: String, value: String, color: Color = SeeleColors.textSecondary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(SeeleColors.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func tipRow(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("• \(title)")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textPrimary)
            Text(description)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
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

            // Try to use an external port check service
            if let url = URL(string: "https://portchecker.co/check?port=\(port)") {
                results.append("Check manually at: portchecker.co")
            }

            // Check if we're receiving ConnectToPeer messages (indicates server knows our port)
            let ctpCount = appState.networkClient.peerConnectionPool.connectToPeerCount
            if ctpCount > 0 {
                results.append("✓ Receiving ConnectToPeer requests (\(ctpCount))")
                results.append("  Server knows our port, but peers may not be able to reach us")
            } else {
                results.append("⚠ No ConnectToPeer requests received yet")
                results.append("  Try searching first to trigger peer connections")
            }

            // Check active connections
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

            // Step 1: Get user status (would need to implement)
            results.append("Step 1: Requesting peer address...")

            do {
                let startTime = Date()

                // Try the browse
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

            // Test DNS resolution
            results.append("Testing DNS resolution...")
            let host = ServerConnection.defaultHost
            let port = ServerConnection.defaultPort

            do {
                let addresses = try await resolveDNS(host: host)
                results.append("✓ DNS resolved to: \(addresses.joined(separator: ", "))")
            } catch {
                results.append("✗ DNS resolution failed: \(error.localizedDescription)")
            }

            // Test TCP connection
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
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        return try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var didComplete = false

            connection.stateUpdateHandler = { state in
                guard !didComplete else { return }

                switch state {
                case .ready:
                    didComplete = true
                    connection.cancel()
                    continuation.resume()

                case .failed(let error):
                    didComplete = true
                    continuation.resume(throwing: error)

                case .cancelled:
                    if !didComplete {
                        didComplete = true
                        continuation.resume(throwing: NSError(domain: "Connection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection cancelled"]))
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global())

            Task {
                try? await Task.sleep(for: .seconds(10))
                if !didComplete {
                    didComplete = true
                    connection.cancel()
                    continuation.resume(throwing: NSError(domain: "Connection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timed out"]))
                }
            }
        }
    }
}

import Network

// MARK: - Settings Components

private func settingsHeader(_ title: String) -> some View {
    Text(title)
        .font(SeeleTypography.title2)
        .foregroundStyle(SeeleColors.textPrimary)
}

private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: SeeleSpacing.md) {
        Text(title)
            .font(SeeleTypography.headline)
            .foregroundStyle(SeeleColors.textSecondary)

        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            content()
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
    }
}

private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
        .toggleStyle(SeeleToggleStyle())
        .font(SeeleTypography.body)
        .foregroundStyle(SeeleColors.textPrimary)
}

private func settingsNumberField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, placeholder: String = "") -> some View {
    HStack {
        Text(title)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)

        Spacer()

        TextField(placeholder, value: value, format: .number)
            .textFieldStyle(SeeleTextFieldStyle())
            .frame(width: 100)
            .multilineTextAlignment(.trailing)
    }
}

private func settingsStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
    HStack {
        Text(title)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)

        Spacer()

        Stepper("\(value.wrappedValue)", value: value, in: range)
            .labelsHidden()

        Text("\(value.wrappedValue)")
            .font(SeeleTypography.mono)
            .foregroundStyle(SeeleColors.textPrimary)
            .frame(width: 30)
    }
}

private func folderPicker(_ title: String, url: Binding<URL>) -> some View {
    HStack {
        Text(title)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)

        Spacer()

        Text(url.wrappedValue.lastPathComponent)
            .font(SeeleTypography.mono)
            .foregroundStyle(SeeleColors.textSecondary)
            .lineLimit(1)

        Button("Choose...") {
            // Show folder picker
        }
        .font(SeeleTypography.caption)
        .foregroundStyle(SeeleColors.accent)
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environment(\.appState, AppState())
        .frame(width: 700, height: 500)
}
