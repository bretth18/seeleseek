import SwiftUI

struct SearchFilterBar: View {
    @Bindable var searchState: SearchState

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible row
            HStack(spacing: SeeleSpacing.sm) {
                // Filter toggle
                Button {
                    withAnimation(.easeInOut(duration: SeeleSpacing.animationFast)) {
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

                // Quick preset chips
                filterChip("MP3 320", isActive: searchState.isPresetActive(.mp3_320)) {
                    searchState.applyPreset(.mp3_320)
                }
                filterChip("FLAC", isActive: searchState.isPresetActive(.flac)) {
                    searchState.applyPreset(.flac)
                }
                filterChip("Lossless", isActive: searchState.isPresetActive(.lossless)) {
                    searchState.applyPreset(.lossless)
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
                }
            }
            .padding(.horizontal, SeeleSpacing.lg)
            .padding(.vertical, SeeleSpacing.xs)
            .background(SeeleColors.surface.opacity(0.3))

            // Expanded filter panel
            if searchState.showFilters {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    // Format row
                    filterRow("Format") {
                        let formats = ["mp3", "flac", "ogg", "m4a", "aac", "wav", "aiff", "ape"]
                        ForEach(formats, id: \.self) { ext in
                            filterChip(ext.uppercased(), isActive: searchState.filterExtensions.contains(ext)) {
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
                            filterChip(label, isActive: searchState.filterMinBitrate == value) {
                                searchState.filterMinBitrate = value
                            }
                        }
                    }

                    // Options row
                    HStack(spacing: SeeleSpacing.lg) {
                        HStack(spacing: SeeleSpacing.sm) {
                            Text("Free slots only")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textSecondary)
                            Toggle("", isOn: $searchState.filterFreeSlotOnly)
                                .toggleStyle(SeeleToggleStyle())
                                .labelsHidden()
                        }

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
                    }
                }
                .padding(.horizontal, SeeleSpacing.lg)
                .padding(.vertical, SeeleSpacing.sm)
                .background(SeeleColors.surface.opacity(0.5))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Components

    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(SeeleTypography.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? SeeleColors.accent.opacity(0.2) : SeeleColors.surfaceElevated)
                .foregroundStyle(isActive ? SeeleColors.accent : SeeleColors.textSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isActive ? SeeleColors.accent.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

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
