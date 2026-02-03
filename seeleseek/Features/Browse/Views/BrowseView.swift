import SwiftUI

struct BrowseView: View {
    @Environment(\.appState) private var appState
    @State private var browseState = BrowseState()

    var body: some View {
        VStack(spacing: 0) {
            browseBar
            Divider().background(SeeleColors.surfaceSecondary)
            contentArea
        }
        .background(SeeleColors.background)
    }

    private var browseBar: some View {
        HStack(spacing: SeeleSpacing.md) {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "person")
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Enter username to browse...", text: $browseState.currentUser)
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
        } else if let shares = browseState.userShares {
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

            Text("Connecting to \(browseState.currentUser)")
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

            if let error = browseState.userShares?.error {
                Text(error)
                    .font(SeeleTypography.subheadline)
                    .foregroundStyle(SeeleColors.textSecondary)
            }

            SecondaryButton("Try Again", icon: "arrow.clockwise") {
                browseUser()
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

            Text("\(browseState.currentUser) has no files shared")
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

    private func fileTreeView(shares: UserShares) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(shares.username)'s files")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text("(\(shares.totalFiles) files)")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)

                Spacer()
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
                            browseState: browseState
                        )
                    }
                }
            }
        }
    }

    private func browseUser() {
        guard browseState.canBrowse else { return }
        browseState.browseUser(browseState.currentUser)

        // Simulate loading for now - in real implementation this would
        // request shares from the peer
        Task {
            try? await Task.sleep(for: .seconds(2))
            // For demo, show empty or mock data
            browseState.setShares([])
        }
    }
}

struct FileTreeRow: View {
    let file: SharedFile
    let depth: Int
    @Bindable var browseState: BrowseState
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
                        // Download file
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
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
                        browseState: browseState
                    )
                }
            }
        }
    }
}

#Preview {
    BrowseView()
        .environment(\.appState, AppState())
        .frame(width: 800, height: 600)
}
