import SwiftUI

struct WishlistView: View {
    @Environment(\.appState) private var appState

    private var wishlistState: WishlistState {
        appState.wishlistState
    }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            addBar(binding: $state.wishlistState.newQuery)
            Divider().background(SeeleColors.surfaceSecondary)
            itemsList
        }
        .background(SeeleColors.background)
    }

    // MARK: - Add Bar

    private func addBar(binding: Binding<String>) -> some View {
        HStack(spacing: SeeleSpacing.md) {
            HStack(spacing: SeeleSpacing.sm) {
                Image(systemName: "star")
                    .foregroundStyle(SeeleColors.textTertiary)

                TextField("Add wishlist search...", text: binding)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .onSubmit {
                        wishlistState.addItem()
                    }

                if !wishlistState.newQuery.isEmpty {
                    Button {
                        wishlistState.newQuery = ""
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
                wishlistState.addItem()
            } label: {
                Text("Add")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textOnAccent)
                    .padding(.horizontal, SeeleSpacing.lg)
                    .padding(.vertical, SeeleSpacing.md)
                    .background(!wishlistState.newQuery.trimmingCharacters(in: .whitespaces).isEmpty ? SeeleColors.accent : SeeleColors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(wishlistState.newQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface.opacity(0.5))
    }

    // MARK: - Items List

    private var itemsList: some View {
        Group {
            if wishlistState.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(wishlistState.items) { item in
                            WishlistItemRow(item: item)
                        }
                    }
                    .padding(.vertical, SeeleSpacing.sm)

                    // Expanded results
                    if let expandedId = wishlistState.expandedItemId,
                       let results = wishlistState.results[expandedId],
                       !results.isEmpty {
                        Divider().background(SeeleColors.surfaceSecondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Results")
                                .font(SeeleTypography.headline)
                                .foregroundStyle(SeeleColors.textSecondary)
                                .padding(.horizontal, SeeleSpacing.lg)
                                .padding(.vertical, SeeleSpacing.sm)

                            LazyVStack(spacing: 1) {
                                ForEach(results) { result in
                                    SearchResultRow(result: result)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: SeeleSpacing.lg) {
            Image(systemName: "star")
                .font(.system(size: SeeleSpacing.iconSizeHero, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)

            Text("No wishlists")
                .font(SeeleTypography.title2)
                .foregroundStyle(SeeleColors.textSecondary)

            Text("Add search queries that run automatically at regular intervals")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Wishlist Item Row

struct WishlistItemRow: View {
    @Environment(\.appState) private var appState
    let item: WishlistItem
    @State private var isHovered = false

    private var wishlistState: WishlistState {
        appState.wishlistState
    }

    private var isExpanded: Bool {
        wishlistState.expandedItemId == item.id
    }

    private var resultCount: Int {
        wishlistState.results[item.id]?.count ?? item.resultCount
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.md) {
            // Enable/disable toggle
            Button {
                wishlistState.toggleEnabled(id: item.id)
            } label: {
                Image(systemName: item.enabled ? "star.fill" : "star")
                    .font(.system(size: SeeleSpacing.iconSize))
                    .foregroundStyle(item.enabled ? SeeleColors.warning : SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .help(item.enabled ? "Disable" : "Enable")

            // Query info
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(item.query)
                    .font(SeeleTypography.body)
                    .foregroundStyle(item.enabled ? SeeleColors.textPrimary : SeeleColors.textTertiary)
                    .lineLimit(1)

                Text(wishlistState.relativeTime(from: item.lastSearchedAt))
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()

            // Result count badge
            if resultCount > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            wishlistState.expandedItemId = nil
                        } else {
                            wishlistState.expandedItemId = item.id
                        }
                    }
                } label: {
                    HStack(spacing: SeeleSpacing.xxs) {
                        Text("\(resultCount)")
                            .font(SeeleTypography.monoSmall)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(SeeleColors.textSecondary)
                    .padding(.horizontal, SeeleSpacing.sm)
                    .padding(.vertical, SeeleSpacing.xxs)
                    .background(SeeleColors.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Show results")
            } else {
                Text("0")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .padding(.horizontal, SeeleSpacing.sm)
                    .padding(.vertical, SeeleSpacing.xxs)
                    .background(SeeleColors.surfaceElevated, in: Capsule())
            }

            // Search now button
            Button {
                wishlistState.searchNow(item: item)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(isHovered ? SeeleColors.textSecondary : SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Search now")

            // Delete button
            Button {
                wishlistState.removeItem(id: item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(isHovered ? SeeleColors.error : SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(isHovered ? SeeleColors.surfaceSecondary : SeeleColors.surface)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    WishlistView()
        .environment(\.appState, {
            let state = AppState()
            state.wishlistState.items = [
                WishlistItem(query: "ambient electronic", lastSearchedAt: Date().addingTimeInterval(-300), resultCount: 42),
                WishlistItem(query: "boards of canada flac", lastSearchedAt: Date().addingTimeInterval(-120), resultCount: 128),
                WishlistItem(query: "autechre", resultCount: 0),
            ]
            return state
        }())
}
