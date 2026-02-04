import SwiftUI

struct BrowseView: View {
    @Environment(\.appState) private var appState

    private var browseState: BrowseState {
        appState.browseState
    }

    var body: some View {
        @Bindable var browseBinding = appState.browseState

        VStack(spacing: 0) {
            // Tab bar (if there are tabs)
            if !browseState.browses.isEmpty {
                browseTabBar
            }

            browseBarView(currentUserBinding: $browseBinding.currentUser)
            Divider().background(SeeleColors.surfaceSecondary)
            contentArea
        }
        .background(SeeleColors.background)
    }

    // MARK: - Tab Bar

    private var browseTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(browseState.browses.enumerated()), id: \.element.id) { index, browse in
                    BrowseTabButton(
                        browse: browse,
                        isSelected: index == browseState.selectedBrowseIndex,
                        onSelect: {
                            browseState.selectBrowse(at: index)
                        },
                        onClose: {
                            browseState.closeBrowse(at: index)
                        }
                    )
                }
            }
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm)
        }
        .background(SeeleColors.surface.opacity(0.3))
    }

    private func browseBarView(currentUserBinding: Binding<String>) -> some View {
        HStack(spacing: SeeleSpacing.md) {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "person")
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Enter username to browse...", text: currentUserBinding)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .onSubmit {
                        if browseState.canBrowse {
                            browseUser()
                        }
                    }

                if !browseState.currentUser.isEmpty {
                    Button {
                        browseState.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))

            Button {
                browseUser()
            } label: {
                Text("Browse")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.md)
                    .background(browseState.canBrowse ? SeeleColors.accent : SeeleColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!browseState.canBrowse)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface.opacity(0.5))
    }

    @ViewBuilder
    private var contentArea: some View {
        if browseState.isLoading {
            loadingView
        } else if browseState.hasError {
            errorView
        } else if let shares = browseState.currentBrowse {
            if shares.folders.isEmpty {
                emptySharesView
            } else {
                fileTreeView(shares: shares)
            }
        } else {
            emptyStateView
        }
    }

    private var loadingView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(SeeleColors.accent)

            Text("Loading shares...")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            Text("Connecting to \(browseState.currentBrowse?.username ?? browseState.currentUser)")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.error)

            Text("Failed to load shares")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textPrimary)

            if let error = browseState.currentBrowse?.error {
                Text(error)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            SecondaryButton("Try Again", icon: "arrow.clockwise") {
                browseState.retryCurrentBrowse()
            }
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySharesView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No shared files")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("\(browseState.currentBrowse?.username ?? "User") has no files shared")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("Browse User Files")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Enter a username above to see their shared files")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)

            if !browseState.browseHistory.isEmpty {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    Text("Recent")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .padding(.top, SeeleSpacing.lg)

                    ForEach(browseState.browseHistory.prefix(5), id: \.self) { username in
                        Button {
                            browseState.currentUser = username
                            browseUser()
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(SeeleColors.textTertiary)
                                Text(username)
                                    .foregroundStyle(SeeleColors.textSecondary)
                                Spacer()
                            }
                            .padding(.vertical, SeeleSpacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SeeleSpacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @State private var showVisualizations = true

    private func fileTreeView(shares: UserShares) -> some View {
        HSplitView {
            // File tree
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\(shares.username)'s files")
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("(\(shares.totalFiles) files, \(ByteFormatter.format(Int64(shares.totalSize))))")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Spacer()

                    Button {
                        withAnimation {
                            showVisualizations.toggle()
                        }
                    } label: {
                        Image(systemName: showVisualizations ? "chart.bar.fill" : "chart.bar")
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SeeleSpacing.lg)
                .padding(.vertical, SeeleSpacing.sm)
                .background(SeeleColors.surface.opacity(0.3))

                // File tree
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shares.folders) { folder in
                            FileTreeRow(
                                file: folder,
                                depth: 0,
                                browseState: browseState,
                                username: shares.username
                            )
                        }
                    }
                }
            }

            // Visualizations panel
            if showVisualizations {
                SharesVisualizationPanel(shares: shares)
                    .frame(minWidth: 300, maxWidth: 400)
            }
        }
    }

    private func browseUser() {
        guard browseState.canBrowse else { return }
        let username = browseState.currentUser
        print("📂 BrowseView: Starting browse for \(username)")

        // Delegate to BrowseState - it manages the task lifecycle
        browseState.browseUser(username)
    }
}

// MARK: - Browse Tab Button

struct BrowseTabButton: View {
    let browse: UserShares
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            // Status indicator
            if browse.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else if browse.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(SeeleColors.error)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(SeeleColors.warning)
            }

            Text(browse.username)
                .font(SeeleTypography.caption)
                .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
                .lineLimit(1)

            // File count badge
            if !browse.isLoading && browse.error == nil && !browse.folders.isEmpty {
                Text("\(browse.totalFiles)")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(isSelected ? SeeleColors.surface : SeeleColors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall)
                .stroke(isSelected ? SeeleColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SeeleSpacing.sm) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 20)
                }

                // Expand/collapse for folders
                if file.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SeeleColors.textTertiary)
                        .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }

                // Icon
                Image(systemName: file.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(file.isDirectory ? SeeleColors.warning : SeeleColors.accent)

                // Name
                Text(file.displayName)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Size (for files)
                if !file.isDirectory {
                    Text(file.formattedSize)
                        .font(SeeleTypography.monoSmall)
                        .foregroundStyle(SeeleColors.textTertiary)

                    // Download button
                    Button {
                        downloadFile()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                    .help("Download file")
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

            // Children (if expanded)
            if file.isDirectory, isExpanded, let children = file.children {
                ForEach(children) { child in
                    FileTreeRow(
                        file: child,
                        depth: depth + 1,
                        browseState: browseState,
                        username: username
                    )
                }
            }
        }
    }

    private func downloadFile() {
        print("📥 Browse download: \(file.filename) from \(username)")

        // Create a SearchResult from the SharedFile to use with DownloadManager
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
}

// MARK: - Shares Visualization Panel

struct SharesVisualizationPanel: View {
    let shares: UserShares

    private var allFiles: [SharedFile] {
        shares.folders.flatMap { collectFiles(from: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                // Quick stats
                quickStatsSection

                Divider().background(SeeleColors.surfaceSecondary)

                // File type distribution
                fileTypeSection

                Divider().background(SeeleColors.surfaceSecondary)

                // Bitrate distribution (for audio)
                if hasAudioFiles {
                    bitrateSection
                    Divider().background(SeeleColors.surfaceSecondary)
                }

                // Largest files
                largestFilesSection

                // Treemap visualization
                if !allFiles.isEmpty {
                    treemapSection
                }
            }
            .padding(SeeleSpacing.lg)
        }
        .background(SeeleColors.surface)
    }

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Overview")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: SeeleSpacing.md) {
                StatCard(
                    title: "Files",
                    value: "\(allFiles.count)",
                    icon: "doc.fill",
                    color: SeeleColors.accent
                )

                StatCard(
                    title: "Folders",
                    value: "\(shares.folders.count)",
                    icon: "folder.fill",
                    color: SeeleColors.warning
                )

                StatCard(
                    title: "Total Size",
                    value: ByteFormatter.format(Int64(shares.totalSize)),
                    icon: "externaldrive.fill",
                    color: SeeleColors.info
                )

                StatCard(
                    title: "Avg Size",
                    value: ByteFormatter.format(Int64(shares.totalSize / UInt64(max(allFiles.count, 1)))),
                    icon: "chart.bar.fill",
                    color: SeeleColors.success
                )
            }
        }
    }

    private var fileTypeSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("File Types")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            FileTypeDistribution(files: allFiles)
        }
    }

    private var bitrateSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Audio Quality")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            BitrateDistribution(files: audioFiles)
        }
    }

    private var largestFilesSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Largest Files")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            let topFiles = allFiles
                .filter { !$0.isDirectory }
                .sorted { $0.size > $1.size }
                .prefix(5)

            SizeComparisonBars(
                items: topFiles.map { ($0.displayFilename, $0.size) }
            )
        }
    }

    private var treemapSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Size Distribution")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            FileTreemap(
                files: Array(allFiles.filter { !$0.isDirectory }.prefix(50))
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadius))
        }
    }

    private var hasAudioFiles: Bool {
        !audioFiles.isEmpty
    }

    private var audioFiles: [SharedFile] {
        allFiles.filter { $0.isAudioFile }
    }

    private func collectFiles(from folder: SharedFile) -> [SharedFile] {
        var files: [SharedFile] = []

        if folder.isDirectory {
            if let children = folder.children {
                for child in children {
                    files.append(contentsOf: collectFiles(from: child))
                }
            }
        } else {
            files.append(folder)
        }

        return files
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: SeeleSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text(title)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }

                Spacer()
            }
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall))
    }
}

#Preview {
    BrowseView()
        .environment(\.appState, AppState())
        .frame(width: 1000, height: 600)
}
