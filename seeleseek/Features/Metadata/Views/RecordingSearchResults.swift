import SwiftUI

/// MusicBrainz recording search results list with score badges
struct RecordingSearchResults: View {
    @Bindable var state: MetadataState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Search MusicBrainz")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            // Search fields
            HStack(spacing: SeeleSpacing.sm) {
                TextField("Artist", text: $state.detectedArtist)
                    .textFieldStyle(.roundedBorder)

                TextField("Title", text: $state.detectedTitle)
                    .textFieldStyle(.roundedBorder)

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
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: MusicBrainzClient.MBRecording
    @Bindable var state: MetadataState

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

                if state.selectedRecording?.id == recording.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SeeleColors.success)
                }
            }
            .padding(SeeleSpacing.sm)
            .background(state.selectedRecording?.id == recording.id ? SeeleColors.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
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
