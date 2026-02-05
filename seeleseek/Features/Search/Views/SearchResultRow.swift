import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SearchResultRow: View {
    @Environment(\.appState) private var appState
    let result: SearchResult
    @State private var isHovered = false

    /// Check if this file is already queued/downloading
    private var downloadStatus: Transfer.TransferStatus? {
        appState.transferState.downloadStatus(for: result.filename, from: result.username)
    }

    private var isQueued: Bool {
        downloadStatus != nil && downloadStatus != .completed && downloadStatus != .cancelled && downloadStatus != .failed
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // File type icon
            fileIcon

            // File info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(result.displayFilename)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SeeleSpacing.md) {
                    HStack(spacing: SeeleSpacing.xxs) {
                        // Country flag (if available)
                        if let flag = countryFlag, !flag.isEmpty {
                            Text(flag)
                                .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                        }

                        Label(result.username, systemImage: "person")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }

                    if !result.folderPath.isEmpty {
                        Text(result.folderPath)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Metadata badges
            HStack(spacing: SeeleSpacing.sm) {
                if let bitrate = result.formattedBitrate {
                    metadataBadge(bitrate, color: bitrateColor)
                }

                if let duration = result.formattedDuration {
                    metadataBadge(duration, color: SeeleColors.textTertiary)
                }

                metadataBadge(result.formattedSize, color: SeeleColors.textTertiary)

                // Private/locked indicator (buddy-only)
                if result.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                        .foregroundStyle(SeeleColors.warning)
                        .help("Private file - only shared with buddies")
                }

                // Queue/slot indicator
                if result.freeSlots {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.success)
                } else {
                    HStack(spacing: SeeleSpacing.xxs) {
                        Image(systemName: "hourglass")
                            .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                        Text("\(result.queueLength)")
                            .font(SeeleTypography.monoSmall)
                    }
                    .foregroundStyle(SeeleColors.warning)
                }
            }

            // Browse user button
            Button {
                browseUser()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: SeeleSpacing.iconSizeMedium - 2))
                    .foregroundStyle(isHovered ? SeeleColors.textSecondary : SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Browse \(result.username)'s files")

            // Download button
            Button {
                if !isQueued {
                    downloadFile()
                }
            } label: {
                downloadButtonIcon
            }
            .buttonStyle(.plain)
            .disabled(isQueued)
            .help(downloadButtonHelp)
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(isHovered ? SeeleColors.surfaceSecondary : SeeleColors.surface)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                downloadFile()
            } label: {
                if isQueued {
                    Label("Downloading...", systemImage: "arrow.down.circle.fill")
                } else {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .disabled(isQueued)

            Button {
                downloadFolder()
            } label: {
                Label("Download folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                browseUser()
            } label: {
                Label("Browse \(result.username)", systemImage: "folder")
            }

            Button {
                browseFolder()
            } label: {
                Label("Browse folder", systemImage: "folder.badge.questionmark")
            }

            Divider()

            Button {
                copyFilename()
            } label: {
                Label("Copy filename", systemImage: "doc.on.doc")
            }

            Button {
                copyPath()
            } label: {
                Label("Copy full path", systemImage: "link")
            }
        }
    }

    private var fileIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                .fill(iconColor.opacity(0.15))
                .frame(width: SeeleSpacing.iconSizeXL + 4, height: SeeleSpacing.iconSizeXL + 4)

            Image(systemName: iconName)
                .font(.system(size: SeeleSpacing.iconSize))
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        if result.isLossless {
            return "waveform"
        } else if result.isAudioFile {
            return "music.note"
        } else {
            return "doc"
        }
    }

    private var iconColor: Color {
        if result.isLossless {
            return SeeleColors.success
        } else if result.isAudioFile {
            return SeeleColors.accent
        } else {
            return SeeleColors.textTertiary
        }
    }

    private var bitrateColor: Color {
        guard let bitrate = result.bitrate else { return SeeleColors.textTertiary }
        if bitrate >= 320 || result.isLossless {
            return SeeleColors.success
        } else if bitrate >= 256 {
            return SeeleColors.info
        } else if bitrate >= 192 {
            return SeeleColors.warning
        } else {
            return SeeleColors.textTertiary
        }
    }

    @ViewBuilder
    private var downloadButtonIcon: some View {
        switch downloadStatus {
        case .transferring:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: SeeleSpacing.iconSizeMedium))
                .foregroundStyle(SeeleColors.accent)
                .symbolEffect(.pulse)
        case .queued, .waiting, .connecting:
            Image(systemName: "clock.fill")
                .font(.system(size: SeeleSpacing.iconSizeMedium))
                .foregroundStyle(SeeleColors.warning)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: SeeleSpacing.iconSizeMedium))
                .foregroundStyle(SeeleColors.success)
        case .failed, .cancelled, nil:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: SeeleSpacing.iconSizeMedium))
                .foregroundStyle(isHovered ? SeeleColors.accent : SeeleColors.textSecondary)
        }
    }

    private var downloadButtonHelp: String {
        switch downloadStatus {
        case .transferring:
            return "Downloading..."
        case .queued, .waiting:
            return "Queued for download"
        case .connecting:
            return "Connecting..."
        case .completed:
            return "Download complete"
        case .failed:
            return "Download failed - click to retry"
        case .cancelled:
            return "Download cancelled - click to retry"
        case nil:
            return "Download file"
        }
    }

    private var countryFlag: String? {
        appState.networkClient.userInfoCache.flag(for: result.username)
    }

    private func metadataBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(SeeleTypography.monoSmall)
            .foregroundStyle(color)
            .padding(.horizontal, SeeleSpacing.xs)
            .padding(.vertical, SeeleSpacing.xxs)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }

    private func downloadFile() {
        print("Download: \(result.filename) from \(result.username)")
        appState.downloadManager.queueDownload(from: result)
    }

    private func browseUser() {
        print("Browse user: \(result.username)")
        appState.browseState.browseUser(result.username)
        appState.sidebarSelection = .browse
    }

    private func browseFolder() {
        print("Browse folder: \(result.folderPath) from \(result.username)")
        // Pass the full filename path so we can expand to the file's location
        appState.browseState.browseUser(result.username, targetPath: result.filename)
        appState.sidebarSelection = .browse
    }

    private func downloadFolder() {
        // Find all files from the same folder and user in current search results
        guard let currentSearch = appState.searchState.currentSearch else {
            // Fallback: just download this file
            downloadFile()
            return
        }

        let folderFiles = currentSearch.results.filter {
            $0.username == result.username && $0.folderPath == result.folderPath
        }

        print("📁 Download folder: \(result.folderPath) from \(result.username) (\(folderFiles.count) files)")

        var queuedCount = 0
        for file in folderFiles {
            // Skip if already queued
            if !appState.transferState.isFileQueued(filename: file.filename, username: file.username) {
                appState.downloadManager.queueDownload(from: file)
                queuedCount += 1
            }
        }

        if queuedCount > 0 {
            print("✅ Queued \(queuedCount) files from folder")
        } else {
            print("ℹ️ All files in folder already queued")
        }
    }

    private func copyFilename() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.displayFilename, forType: .string)
        #endif
    }

    private func copyPath() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.filename, forType: .string)
        #endif
    }
}

#Preview {
    VStack(spacing: 1) {
        SearchResultRow(result: SearchResult(
            username: "musiclover42",
            filename: "Music\\Albums\\Pink Floyd\\The Dark Side of the Moon\\03 - Time.flac",
            size: 45_000_000,
            bitrate: 1411,
            duration: 413,
            isVBR: false,
            freeSlots: true,
            uploadSpeed: 1_500_000,
            queueLength: 0
        ))

        SearchResultRow(result: SearchResult(
            username: "vinylcollector",
            filename: "Music\\MP3\\Pink Floyd - Time.mp3",
            size: 8_500_000,
            bitrate: 320,
            duration: 413,
            isVBR: false,
            freeSlots: false,
            uploadSpeed: 800_000,
            queueLength: 5
        ))

        SearchResultRow(result: SearchResult(
            username: "jazzfan",
            filename: "Downloads\\time.mp3",
            size: 4_200_000,
            bitrate: 128,
            duration: 413,
            isVBR: true,
            freeSlots: true,
            uploadSpeed: 256_000,
            queueLength: 0
        ))
    }
    .background(SeeleColors.background)
}
