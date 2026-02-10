import SwiftUI

struct BrowseView: View {
    @Environment(\.appState) private var appState

    private var browseState: BrowseState {
        appState.browseState
    }

    var body: some View {
        @Bindable var browseBinding = appState.browseState

        VStack(spacing: 0) {
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
            HStack(spacing: SeeleSpacing.xxs) {
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
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))

            Button {
                browseUser()
            } label: {
                Text("Browse")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textOnAccent)
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.md)
                    .background(browseState.canBrowse ? SeeleColors.accent : SeeleColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
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
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
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
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No shared files")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Try refreshing — this may be a stale cache")
                .font(SeeleTypography.subheadline)
                .foregroundStyle(SeeleColors.textTertiary)

            SecondaryButton("Refresh", icon: "arrow.clockwise") {
                browseState.refreshCurrentBrowse()
            }
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
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
            VStack(spacing: 0) {
                HStack {
                    Text("\(shares.username)'s files")
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text("(\(shares.totalFiles) files, \(ByteFormatter.format(Int64(shares.totalSize))))")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Spacer()

                    Button {
                        browseState.refreshCurrentBrowse()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh (bypass cache)")

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

                if let folderPath = browseState.currentFolderPath {
                    HStack(spacing: SeeleSpacing.xs) {
                        Button {
                            browseState.navigateToRoot()
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            browseState.navigateUp()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)

                        Text(folderPath.replacingOccurrences(of: "\\", with: " / "))
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()
                    }
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.xs)
                    .background(SeeleColors.surfaceSecondary)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(browseState.displayedFolders) { folder in
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
        browseState.browseUser(username)
    }
}

#Preview {
    BrowseView()
        .environment(\.appState, AppState())
        .frame(width: 1000, height: 600)
}
