import SwiftUI
import os
import SeeleseekCore

private let logger = Logger(subsystem: "com.seeleseek", category: "BrowseView")

struct BrowseView: View {
    @Environment(\.appState) private var appState
    @FocusState private var isTabStripFocused: Bool

    private var browseState: BrowseState {
        appState.browseState
    }

    var body: some View {
        @Bindable var browseBinding = appState.browseState

        VStack(spacing: 0) {
            browseBarView(currentUserBinding: $browseBinding.currentUser)

            Divider().background(SeeleColors.surfaceSecondary)

            if !browseState.browses.isEmpty {
                browseTabBar
            }

            contentArea
        }
        .background(SeeleColors.background)
        .focusedSceneValue(\.tabCommands, browseTabCommands)
    }

    private var browseTabCommands: TabCommands? {
        guard !browseState.browses.isEmpty else { return nil }
        let state = browseState
        return TabCommands(
            selectNext: {
                state.selectBrowse(at: TabCycler.wrappedNext(state.selectedBrowseIndex, count: state.browses.count))
            },
            selectPrevious: {
                state.selectBrowse(at: TabCycler.wrappedPrevious(state.selectedBrowseIndex, count: state.browses.count))
            },
            closeCurrent: {
                state.closeBrowse(at: state.selectedBrowseIndex)
            }
        )
    }

    // MARK: - Tab Bar

    private var browseTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SeeleSpacing.xxs) {
                    ForEach(Array(browseState.browses.enumerated()), id: \.element.id) { index, browse in
                        BrowseTabButton(
                            browse: browse,
                            isSelected: index == browseState.selectedBrowseIndex,
                            showsFocusRing: isTabStripFocused,
                            onSelect: {
                                browseState.selectBrowse(at: index)
                            },
                            onClose: {
                                browseState.closeBrowse(at: index)
                            }
                        )
                        .id(browse.id)
                    }
                }
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.vertical, SeeleSpacing.sm)
            }
            .background(SeeleColors.surface.opacity(0.3))
            .focusable()
            .focused($isTabStripFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: browseState.selectBrowse(at: browseState.selectedBrowseIndex - 1)
                case .right: browseState.selectBrowse(at: browseState.selectedBrowseIndex + 1)
                default: break
                }
            }
            .onChange(of: browseState.selectedBrowseIndex) { _, index in
                guard browseState.browses.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(browseState.browses[index].id)
                }
            }
        }
    }

    private func browseBarView(currentUserBinding: Binding<String>) -> some View {
        StandardActionBar {
            StandardSearchField(
                text: currentUserBinding,
                placeholder: "Enter username to browse...",
                icon: "person",
                onSubmit: {
                    if browseState.canBrowse {
                        browseUser()
                    }
                },
                onClear: { browseState.clear() }
            )

            PrimaryButton("Browse", fullWidth: false) {
                browseUser()
            }
            .disabled(!browseState.canBrowse)
        }
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

            SecondaryButton("Try Again", icon: "arrow.clockwise", fullWidth: false) {
                browseState.retryCurrentBrowse()
            }
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

            SecondaryButton("Refresh", icon: "arrow.clockwise", fullWidth: false) {
                browseState.refreshCurrentBrowse()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        StandardEmptyState(
            icon: "folder.badge.person.crop",
            title: "Browse User Files",
            subtitle: "Enter a username above to see their shared files"
        ) {
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Match the subtitle's column so the rows read as part of
                // the centered block, not a full-width list.
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }

    @State private var showVisualizations = true

    private func fileTreeView(shares: UserShares) -> some View {
        @Bindable var browseBinding = appState.browseState

        return HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("\(shares.username)'s files")
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text("(\(shares.totalFiles) files, \(shares.totalSize.formattedBytes))")
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
                    .accessibilityLabel("Refresh shares")

                    Button {
                        withAnimation {
                            showVisualizations.toggle()
                        }
                    } label: {
                        Image(systemName: showVisualizations ? "chart.bar.fill" : "chart.bar")
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showVisualizations ? "Hide statistics panel" : "Show statistics panel")
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
                        .accessibilityLabel("Go to root folder")

                        Button {
                            browseState.navigateUp()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: SeeleSpacing.iconSizeSmall - 2))
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go up one folder")

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

                StandardSearchField(text: $browseBinding.filterQuery, placeholder: "Filter files...")
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.xs)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(browseState.filteredFlatTree) { item in
                            FileTreeRow(
                                file: item.file,
                                depth: item.depth,
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
        logger.info("Starting browse for \(username)")
        browseState.browseUser(username)
    }
}

#Preview {
    BrowseView()
        .environment(\.appState, AppState())
        .frame(width: 1000, height: 600)
}
