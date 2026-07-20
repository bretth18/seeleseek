import SwiftUI
import AppKit
import SeeleseekCore

/// One-shot migration of settings from a Nicotine+ install. Auto-detects
/// the config, previews what was found grouped behind checkboxes, and
/// applies only the selected groups.
struct NicotineImportSheet: View {
    @Environment(\.appState) private var appState
    @Binding var isPresented: Bool

    @State private var configURL: URL?
    @State private var config: NicotineConfig?
    @State private var loadError: String?

    @State private var importCredentials = true
    @State private var importListenPort = true
    @State private var importDownloadDirs = true
    @State private var importTransferLimits = true
    @State private var importShares = true
    @State private var importIgnored = true
    @State private var joinRoomsNow = false

    private var isConnected: Bool {
        appState.connection.connectionStatus == .connected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Import from Nicotine+")
                .font(SeeleTypography.title)
                .foregroundStyle(SeeleColors.textPrimary)

            sourceRow

            if let error = loadError {
                Text(error)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.error)
            }

            if let config {
                if config.isEmpty {
                    Text("Nothing importable was found in this config.")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                            optionRows(config)
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Import") {
                    applyImport()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(config == nil || config?.isEmpty == true || nothingSelected)
            }
        }
        .padding(SeeleSpacing.lg)
        .frame(width: 460)
        .background(SeeleColors.background)
        .onAppear(perform: loadDefaultConfig)
    }

    private var nothingSelected: Bool {
        !(importCredentials || importListenPort || importDownloadDirs
            || importTransferLimits || importShares || importIgnored || joinRoomsNow)
    }

    // MARK: - Rows

    private var sourceRow: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Image(systemName: configURL == nil ? "questionmark.folder" : "doc.text")
                .foregroundStyle(SeeleColors.textSecondary)
            Text(configURL?.path ?? "No Nicotine+ config found at ~/.config/nicotine/config")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button("Choose File…") {
                chooseConfigFile()
            }
            .font(SeeleTypography.caption)
        }
    }

    @ViewBuilder
    private func optionRows(_ config: NicotineConfig) -> some View {
        if let username = config.username {
            optionRow(
                isOn: $importCredentials,
                title: "Login credentials",
                detail: config.password == nil
                    ? "\(username) (no saved password)"
                    : "\(username) (password saved to Keychain)"
            )
        }
        if let port = config.listenPort {
            optionRow(isOn: $importListenPort, title: "Listen port", detail: "\(port)")
        }
        if config.downloadDirectory != nil || config.incompleteDirectory != nil {
            optionRow(
                isOn: $importDownloadDirs,
                title: "Download folders",
                detail: [config.downloadDirectory, config.incompleteDirectory]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            )
        }
        if config.uploadSlots != nil || config.uploadSpeedLimit != nil || config.downloadSpeedLimit != nil {
            optionRow(
                isOn: $importTransferLimits,
                title: "Transfer limits",
                detail: transferLimitsDetail(config)
            )
        }
        if !config.sharedFolders.isEmpty {
            optionRow(
                isOn: $importShares,
                title: "Shared folders (\(config.sharedFolders.count))",
                detail: config.sharedFolders.joined(separator: "\n")
            )
        }
        if !config.ignoredUsers.isEmpty {
            optionRow(
                isOn: $importIgnored,
                title: "Ignored users (\(config.ignoredUsers.count))",
                detail: config.ignoredUsers.joined(separator: ", ")
            )
        }
        if !config.autojoinRooms.isEmpty {
            optionRow(
                isOn: $joinRoomsNow,
                title: "Join rooms now (\(config.autojoinRooms.count))",
                detail: config.autojoinRooms.joined(separator: ", ")
                    + (isConnected ? "" : " — connect first"),
                disabled: !isConnected
            )
        }
    }

    private func optionRow(isOn: Binding<Bool>, title: String, detail: String, disabled: Bool = false) -> some View {
        HStack(alignment: .top, spacing: SeeleSpacing.sm) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(disabled)

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(title)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                Text(detail)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .lineLimit(4)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .opacity(disabled ? 0.5 : 1)
    }

    private func transferLimitsDetail(_ config: NicotineConfig) -> String {
        var parts: [String] = []
        if let slots = config.uploadSlots { parts.append("\(slots) upload slots") }
        if let up = config.uploadSpeedLimit { parts.append("up \(up == 0 ? "unlimited" : "\(up) KB/s")") }
        if let down = config.downloadSpeedLimit { parts.append("down \(down == 0 ? "unlimited" : "\(down) KB/s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Loading

    private func loadDefaultConfig() {
        guard config == nil else { return }
        if let url = NicotineConfigImporter.defaultConfigURL() {
            load(url)
        }
    }

    private func chooseConfigFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/nicotine")
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    private func load(_ url: URL) {
        do {
            config = try NicotineConfigImporter.load(from: url)
            configURL = url
            loadError = nil
            joinRoomsNow = false
        } catch {
            loadError = "Couldn't read config: \(error.localizedDescription)"
        }
    }

    // MARK: - Apply

    private func applyImport() {
        guard let config else { return }
        let settings = appState.settings

        if importCredentials, let username = config.username, let password = config.password {
            CredentialStorage.save(username: username, password: password)
        }
        if importListenPort, let port = config.listenPort {
            settings.listenPort = port
        }
        if importDownloadDirs {
            if let path = config.downloadDirectory, isDirectory(path) {
                settings.downloadLocation = URL(fileURLWithPath: path)
            }
            if let path = config.incompleteDirectory, isDirectory(path) {
                settings.incompleteLocation = URL(fileURLWithPath: path)
            }
        }
        if importTransferLimits {
            if let slots = config.uploadSlots {
                settings.maxUploadSlots = slots
            }
            if let limit = config.uploadSpeedLimit {
                settings.uploadSpeedLimit = limit
            }
            if let limit = config.downloadSpeedLimit {
                settings.downloadSpeedLimit = limit
            }
        }
        if importShares {
            let shareManager = appState.networkClient.shareManager
            for path in config.sharedFolders where isDirectory(path) {
                shareManager.addFolder(URL(fileURLWithPath: path))
            }
        }
        if importIgnored {
            let users = config.ignoredUsers
            let socialState = appState.socialState
            Task {
                for user in users {
                    await socialState.ignoreUser(user, reason: "Imported from Nicotine+")
                }
            }
        }
        if joinRoomsNow, isConnected {
            for room in config.autojoinRooms {
                appState.chatState.joinRoom(room)
            }
        }
        settings.save()
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
