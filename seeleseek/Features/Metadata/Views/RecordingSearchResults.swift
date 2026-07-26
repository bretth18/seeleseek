import SwiftUI
import SeeleseekCore

/// MusicBrainz recording search results list with score badges
struct RecordingSearchResults: View {
    @Bindable var state: MetadataState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Search MusicBrainz")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            // Search fields
            HStack(spacing: SeeleSpacing.sm) {
                // The labels disambiguate these fields from the
                // edit-pane Artist and Title fields.
                TextField("Artist", text: $state.detectedArtist)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search artist")

                TextField("Title", text: $state.detectedTitle)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search title")

                Button {
                    Task { await state.search() }
                } label: {
                    if state.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(state.isSearching)
                .accessibilityLabel(state.isSearching ? "Searching MusicBrainz" : "Search MusicBrainz")
            }

            if let error = state.searchError {
                Text(error)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.error)
            }

            // Results list
            if state.searchResults.isEmpty && !state.isSearching {
                ContentUnavailableView {
                    Label("No Results", systemImage: "music.note")
                } description: {
                    Text("Search for artist and title to find metadata")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: SeeleSpacing.xs) {
                        ForEach(state.searchResults) { recording in
                            RecordingRow(recording: recording, state: state)
                        }
                    }
                }
            }
        }
        // The inline error text is easy to miss without sight.
        .onChange(of: state.searchError) { _, error in
            if let error {
                VoiceOverAnnouncer.shared.announce(error)
            }
        }
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: MusicBrainzClient.MBRecording
    @Bindable var state: MetadataState

    private var isSelected: Bool {
        state.selectedRecording?.id == recording.id
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = [recording.title, recording.artist]
        if let release = recording.releaseTitle {
            parts.append(release)
        }
        parts.append("match score \(recording.score) percent")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            Task { await state.selectRecording(recording) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(recording.title)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: SeeleSpacing.sm) {
                        Text(recording.artist)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)

                        if let release = recording.releaseTitle {
                            Text("•")
                                .foregroundStyle(SeeleColors.textTertiary)
                            Text(release)
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    }
                    .lineLimit(1)
                }

                Spacer()

                // Score badge
                Text("\(recording.score)%")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(scoreColor(recording.score))
                    .padding(.horizontal, SeeleSpacing.xs)
                    .padding(.vertical, SeeleSpacing.xxs)
                    .background(scoreColor(recording.score).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SeeleColors.success)
                }
            }
            .padding(SeeleSpacing.sm)
            .background(isSelected ? SeeleColors.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return SeeleColors.success
        } else if score >= 70 {
            return SeeleColors.info
        } else if score >= 50 {
            return SeeleColors.warning
        } else {
            return SeeleColors.textTertiary
        }
    }
}

#Preview {
    RecordingSearchResults(state: MetadataState())
        .frame(width: 400, height: 300)
        .padding()
        .background(SeeleColors.background)
}
