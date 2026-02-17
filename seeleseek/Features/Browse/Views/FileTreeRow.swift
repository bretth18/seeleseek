import SwiftUI

struct FileTreeRow: View {
    @Environment(\.appState) private var appState
    let file: SharedFile
    let depth: Int
    var browseState: BrowseState
    let username: String
    @State private var isHovered = false
    @State private var artworkData: Data?
    @State private var isLoadingArtwork = false
    @State private var showArtworkPopover = false

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
            if !file.isDirectory, let artworkData, let nsImage = NSImage(data: artworkData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: SeeleSpacing.iconSize, height: SeeleSpacing.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .popover(isPresented: $showArtworkPopover) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .padding(SeeleSpacing.sm)
                    }
                    .onTapGesture { showArtworkPopover.toggle() }
            } else {
                Image(systemName: file.icon)
                    .font(.system(size: SeeleSpacing.iconSize))
                    .foregroundStyle(file.isDirectory ? SeeleColors.warning : SeeleColors.accent)
            }

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
        .contextMenu {
            if file.isDirectory {
                Button {
                    downloadFolder()
                } label: {
                    Label("Download Folder", systemImage: "arrow.down.circle")
                }

                Divider()

                Button {
                    copyFilename()
                } label: {
                    Label("Copy folder name", systemImage: "doc.on.doc")
                }

                Button {
                    copyPath()
                } label: {
                    Label("Copy full path", systemImage: "link")
                }
            } else {
                Button {
                    if !isQueued { downloadFile() }
                } label: {
                    Label("Download File", systemImage: "arrow.down.circle")
                }
                .disabled(isQueued)

                Button {
                    downloadContainingFolder()
                } label: {
                    Label("Download Containing Folder", systemImage: "arrow.down.circle.fill")
                }

                if file.isAudioFile {
                    Button {
                        fetchArtwork()
                    } label: {
                        if isLoadingArtwork {
                            Label("Loading artwork...", systemImage: "photo")
                        } else if artworkData != nil {
                            Label("Show Album Art", systemImage: "photo.fill")
                        } else {
                            Label("Preview Album Art", systemImage: "photo")
                        }
                    }
                    .disabled(isLoadingArtwork)
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

            Divider()

            UserContextMenuItems(username: username)
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

    private func downloadContainingFolder() {
        // Derive parent folder path from the file's full path
        let components = file.filename.split(separator: "\\")
        guard components.count >= 2 else { return }
        let parentPath = components.dropLast().joined(separator: "\\")

        // Find the parent folder in the tree and download all its files
        let rootFolders = appState.browseState.currentBrowse?.folders ?? browseState.displayedFolders
        guard let parent = findFolder(at: parentPath, in: rootFolders),
              let children = parent.children else { return }

        let allFiles = SharedFile.collectAllFiles(in: children)
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
            }
        }
    }

    private func findFolder(at path: String, in folders: [SharedFile]) -> SharedFile? {
        for folder in folders {
            if folder.isDirectory && folder.filename == path {
                return folder
            }
            if let children = folder.children,
               let found = findFolder(at: path, in: children) {
                return found
            }
        }
        return nil
    }

    private func fetchArtwork() {
        if artworkData != nil {
            showArtworkPopover = true
            return
        }

        isLoadingArtwork = true
        appState.networkClient.requestArtwork(from: username, filePath: file.filename) { data in
            isLoadingArtwork = false
            if let data {
                artworkData = data
                showArtworkPopover = true
            }
        }
    }

    private func copyFilename() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.displayName, forType: .string)
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.filename, forType: .string)
    }
}
