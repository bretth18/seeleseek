import SwiftUI
import SeeleseekCore

struct SearchFilterBar: View {
    @Bindable var searchState: SearchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            // Filter toggle
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    searchState.showFilters.toggle()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                        .foregroundStyle(searchState.showFilters ? SeeleColors.accent : SeeleColors.textSecondary)

                    if searchState.hasActiveFilters {
                        Circle()
                            .fill(SeeleColors.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters")
            .accessibilityValue(filterToggleAccessibilityValue)

            // Quick preset chips
            FilterChip(label: "MP3 320", isActive: searchState.isPresetActive(.mp3_320)) {
                searchState.applyPreset(.mp3_320)
            }
            FilterChip(label: "FLAC", isActive: searchState.isPresetActive(.flac)) {
                searchState.applyPreset(.flac)
            }
            FilterChip(label: "Lossless", isActive: searchState.isPresetActive(.lossless)) {
                searchState.applyPreset(.lossless)
            }
            FilterChip(label: "Hi-Res", isActive: searchState.isPresetActive(.hiRes)) {
                searchState.applyPreset(.hiRes)
            }

            Spacer()

            if searchState.hasActiveFilters {
                Text("\(searchState.activeFilterCount) active")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.accent)

                Button {
                    searchState.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filters")
            }
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.xs)
        .background(SeeleColors.surface.opacity(0.3))
    }

    private var filterToggleAccessibilityValue: String {
        var parts: [String] = [searchState.showFilters ? "expanded" : "collapsed"]
        if searchState.hasActiveFilters {
            parts.append("\(searchState.activeFilterCount) active")
        }
        return parts.joined(separator: ", ")
    }

}

// MARK: - Expanded Filter Panel (overlays results area)

struct SearchFilterPanel: View {
    @Bindable var searchState: SearchState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            // Format row
            filterRow("Format") {
                let formats = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "ape"]
                ForEach(formats, id: \.self) { ext in
                    FilterChip(label: ext.uppercased(), dimension: "Format", isActive: searchState.filterExtensions.contains(ext)) {
                        searchState.toggleExtension(ext)
                    }
                }
            }

            // Bitrate row
            filterRow("Bitrate") {
                let presets: [(String, Int?)] = [
                    ("Any", nil), ("128+", 128), ("192+", 192), ("256+", 256), ("320+", 320)
                ]
                ForEach(presets, id: \.0) { label, value in
                    FilterChip(label: label, dimension: "Bitrate", isActive: searchState.filterMinBitrate == value) {
                        searchState.filterMinBitrate = value
                    }
                }
            }

            // Sample rate row
            filterRow("Sample") {
                let presets: [(String, Int?)] = [
                    ("Any", nil), ("44.1k+", 44100), ("48k+", 48000), ("96k+", 96000)
                ]
                ForEach(presets, id: \.0) { label, value in
                    FilterChip(label: label, dimension: "Sample rate", isActive: searchState.filterMinSampleRate == value) {
                        searchState.filterMinSampleRate = value
                    }
                }
            }

            // Bit depth row
            filterRow("Depth") {
                let presets: [(String, Int?)] = [
                    ("Any", nil), ("16+", 16), ("24+", 24), ("32+", 32)
                ]
                ForEach(presets, id: \.0) { label, value in
                    FilterChip(label: label, dimension: "Bit depth", isActive: searchState.filterMinBitDepth == value) {
                        searchState.filterMinBitDepth = value
                    }
                }
            }

            // Options row
            HStack(spacing: SeeleSpacing.lg) {
                // The style renders the title itself; `.inline` keeps it beside
                // the switch instead of pinning the switch to the trailing edge.
                Toggle("Free slots only", isOn: $searchState.filterFreeSlotOnly)
                    .toggleStyle(SeeleToggleStyle(layout: .inline))
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .fixedSize()

                Toggle("Group by folder", isOn: $searchState.isGrouped)
                    .toggleStyle(SeeleToggleStyle(layout: .inline))
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .fixedSize()

                Spacer()

                // Sort order
                Menu {
                    ForEach(SearchState.SortOrder.allCases, id: \.self) { order in
                        Button {
                            searchState.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if searchState.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: SeeleSpacing.xs) {
                        Text("Sort: \(searchState.sortOrder.rawValue)")
                            .font(SeeleTypography.caption)
                        Image(systemName: "chevron.down")
                            .font(.system(size: SeeleSpacing.iconSizeXS))
                    }
                    .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm)
        .background(SeeleColors.surface.opacity(0.95))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    // MARK: - Components

    private func filterRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: SeeleSpacing.sm) {
            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .frame(width: 48, alignment: .leading)

            FlowLayout(spacing: SeeleSpacing.xs) {
                content()
            }
        }
    }
}

// MARK: - Filter Chip

/// Capsule filter toggle shared by the preset bar and the expanded panel.
private struct FilterChip: View {
    let label: String
    var dimension: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SeeleTypography.caption)
                .padding(.horizontal, SeeleSpacing.sm)
                .padding(.vertical, SeeleSpacing.xs)
                .background(isActive ? SeeleColors.accent.opacity(0.2) : SeeleColors.surfaceElevated)
                .foregroundStyle(isActive ? SeeleColors.accent : SeeleColors.textSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isActive ? SeeleColors.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Spoken chip name. A short chip text such as "16+" or "Any" is
    /// ambiguous without its row title, so the dimension is prefixed.
    private var spokenLabel: String {
        var spoken = label
        if spoken.hasSuffix("+") {
            spoken = String(spoken.dropLast()) + " or more"
        }
        guard let dimension else { return spoken }
        return "\(dimension): \(spoken)"
    }
}

// MARK: - Previews

#if DEBUG
/// `SearchState` alone is enough for these — nothing in this subtree reads
/// `@Environment(\.appState)`, so the previews avoid constructing an
/// `AppState`, whose `@Entry` default spins up timers, UserDefaults reads and
/// an update client (see `PreviewHelpers`).
@MainActor
private func previewState(
    showFilters: Bool = false,
    preset: SearchState.FilterPreset? = nil,
    freeSlotsOnly: Bool = false,
    grouped: Bool = false
) -> SearchState {
    let state = SearchState()
    state.showFilters = showFilters
    state.filterFreeSlotOnly = freeSlotsOnly
    state.isGrouped = grouped
    if let preset { state.applyPreset(preset) }
    return state
}

#Preview("Bar — idle") {
    SearchFilterBar(searchState: previewState())
        .frame(width: 900)
        .background(SeeleColors.background)
}

#Preview("Bar — preset active") {
    // Exercises the accent dot on the toggle, the "N active" count and the
    // clear button, none of which are reachable from the idle state.
    SearchFilterBar(searchState: previewState(preset: .flac))
        .frame(width: 900)
        .background(SeeleColors.background)
}

#Preview("Bar — narrow") {
    // The preset chips and the active-filter cluster compete for width; this
    // is where they start colliding.
    SearchFilterBar(searchState: previewState(preset: .lossless))
        .frame(width: 480)
        .background(SeeleColors.background)
}

#Preview("Panel — expanded") {
    SearchFilterPanel(searchState: previewState())
        .frame(width: 900)
        .background(SeeleColors.background)
}

#Preview("Panel — filters applied") {
    SearchFilterPanel(
        searchState: previewState(preset: .hiRes, freeSlotsOnly: true, grouped: true)
    )
    .frame(width: 900)
    .background(SeeleColors.background)
}

#Preview("Panel — narrow, chips wrap") {
    // FlowLayout's whole job: the format row must wrap rather than clip.
    SearchFilterPanel(searchState: previewState())
        .frame(width: 420)
        .background(SeeleColors.background)
}

#Preview("Bar + panel together") {
    // How the two actually stack in SearchView.
    VStack(spacing: 0) {
        let state = previewState(showFilters: true, preset: .flac)
        SearchFilterBar(searchState: state)
        SearchFilterPanel(searchState: state)
        Spacer()
    }
    .frame(width: 900, height: 320)
    .background(SeeleColors.background)
}
#endif
