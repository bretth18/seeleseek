import SwiftUI

struct FileTreeRow: View {
    @Environment(\.appState) private var appState
    let file: SharedFile
    let depth: Int
    var browseState: BrowseState
    let username: String
    @State private var isHovered = false

    private var isExpanded: Bool {
        browseState.expandedFolders.contains(file.id)
    }

    private var downloadStatus: Transfer.TransferStatus? {
        guard !file.isDirectory else { return nil }
        return appState.transferState.downloadStatus(for: file.filename, from: username)
    }

    private var isQueued: Bool {
        guard let status = downloadStatus else { return false }
        return status != .completed && status != .cancelled && status != .failed
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            // Indentation
            if depth > 0 {
                Spacer()
                    .frame(width: CGFloat(depth) * 20)
            }

            // Expand/collapse for folders
            if file.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: SeeleSpacing.iconSizeXS, weight: .bold))
                    .foregroundStyle(SeeleColors.textTertiary)
                    .frame(width: SeeleSpacing.iconSize)
            } else {
                Spacer().frame(width: SeeleSpacing.iconSize)
            }

            // Icon
            Image(systemName: file.icon)
                .font(.system(size: SeeleSpacing.iconSize))
                .foregroundStyle(file.isDirectory ? SeeleColors.warning : SeeleColors.accent)

            // Name
            Text(file.displayName)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)

            // Private/locked indicator (buddy-only)
            if file.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.warning)
                    .help("Private file - only shared with buddies")
            }

            Spacer()

            // Size (for files) or file count (for folders)
            if file.isDirectory {
                if file.fileCount > 0 {
                    Text("\(file.fileCount) files")
                        .font(SeeleTypography.monoSmall)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                // Download folder button
                Button {
                    downloadFolder()
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: SeeleSpacing.iconSize))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .help("Download folder")
            } else {
                Text(file.formattedSize)
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)

                // Download button with status indicator
                Button {
                    if !isQueued {
                        downloadFile()
                    }
                } label: {
                    downloadButtonIcon
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isQueued ? 1 : 0)
                .disabled(isQueued)
                .help(downloadButtonHelp)
            }
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm)
        .background(isHovered ? SeeleColors.surfaceSecondary : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            browseState.selectFile(file)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }

    private func downloadFile() {
        print("📥 Browse download: \(file.filename) from \(username)")

        let result = SearchResult(
            username: username,
            filename: file.filename,
            size: file.size,
            bitrate: file.bitrate,
            duration: file.duration,
            isVBR: false,
            freeSlots: true,
            uploadSpeed: 0,
            queueLength: 0
        )

        appState.downloadManager.queueDownload(from: result)
    }

    private func downloadFolder() {
        guard file.isDirectory, let children = file.children else { return }

        let allFiles = SharedFile.collectAllFiles(in: children)
        print("📁 Browse download folder: \(file.displayName) (\(allFiles.count) files)")

        var queuedCount = 0
        for childFile in allFiles {
            if !appState.transferState.isFileQueued(filename: childFile.filename, username: username) {
                let result = SearchResult(
                    username: username,
                    filename: childFile.filename,
                    size: childFile.size,
                    bitrate: childFile.bitrate,
                    duration: childFile.duration,
                    isVBR: false,
                    freeSlots: true,
                    uploadSpeed: 0,
                    queueLength: 0
                )
                appState.downloadManager.queueDownload(from: result)
                queuedCount += 1
            }
        }

        if queuedCount > 0 {
            print("✅ Queued \(queuedCount) files from folder")
        } else {
            print("ℹ️ All files in folder already queued")
        }
    }

    private var downloadButtonIcon: some View {
        DownloadStatusIcon(status: downloadStatus, size: SeeleSpacing.iconSize)
    }

    private var downloadButtonHelp: String {
        DownloadStatusIcon(status: downloadStatus).helpText
    }
}
