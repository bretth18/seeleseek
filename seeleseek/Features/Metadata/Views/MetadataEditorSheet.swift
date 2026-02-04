import SwiftUI

/// Sheet for editing file metadata with MusicBrainz integration
struct MetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: MetadataState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            HStack(alignment: .top, spacing: SeeleSpacing.lg) {
                // Left: Search and results
                searchSection
                    .frame(minWidth: 300)

                Divider()

                // Right: Selected metadata and cover art
                selectedMetadataSection
                    .frame(minWidth: 250, maxWidth: 300)
            }
            .padding(SeeleSpacing.lg)

            Divider()

            // Footer
            footer
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(SeeleColors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text("Edit Metadata")
                    .font(SeeleTypography.title)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text(state.currentFilename)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Cancel") {
                state.closeEditor()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(SeeleSpacing.lg)
    }

    // MARK: - Search Section

    private var searchSection: some View {
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
                            recordingRow(recording)
                        }
                    }
                }
            }
        }
    }

    private func recordingRow(_ recording: MusicBrainzClient.MBRecording) -> some View {
        Button {
            Task { await state.selectRecording(recording) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
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
                    .padding(.vertical, 2)
                    .background(scoreColor(recording.score).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if state.selectedRecording?.id == recording.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SeeleColors.success)
                }
            }
            .padding(SeeleSpacing.sm)
            .background(state.selectedRecording?.id == recording.id ? SeeleColors.accent.opacity(0.1) : Color.clear)
            .cornerRadius(6)
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

    // MARK: - Selected Metadata Section

    private var selectedMetadataSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Selected Metadata")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            if let recording = state.selectedRecording {
                // Cover art
                coverArtView

                // Metadata fields
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    metadataRow("Title", value: recording.title)
                    metadataRow("Artist", value: recording.artist)

                    if let release = state.selectedRelease {
                        metadataRow("Album", value: release.title)
                        if let date = release.date {
                            metadataRow("Year", value: String(date.prefix(4)))
                        }
                        metadataRow("Tracks", value: "\(release.trackCount)")
                    } else if let releaseTitle = recording.releaseTitle {
                        metadataRow("Album", value: releaseTitle)
                    }

                    if let duration = recording.durationSeconds {
                        let mins = duration / 60
                        let secs = duration % 60
                        metadataRow("Duration", value: String(format: "%d:%02d", mins, secs))
                    }
                }

                Spacer()
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "music.note.list")
                } description: {
                    Text("Select a result to view metadata")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var coverArtView: some View {
        Group {
            if state.isLoadingCoverArt {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SeeleColors.surfaceSecondary)
                    .frame(width: 150, height: 150)
                    .overlay {
                        ProgressView()
                    }
            } else if let data = state.coverArtData {
                #if os(macOS)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 150)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                }
                #else
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 150)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                }
                #endif
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SeeleColors.surfaceSecondary)
                    .frame(width: 150, height: 150)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            Text(value)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(2)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if state.selectedRecording != nil {
                Text("Selected: \(state.selectedRecording?.title ?? "") by \(state.selectedRecording?.artist ?? "")")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Apply Metadata") {
                Task {
                    if await state.applyMetadata() {
                        state.closeEditor()
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.selectedRecording == nil || state.isApplying)
        }
        .padding(SeeleSpacing.lg)
    }
}

#Preview {
    MetadataEditorSheet(state: MetadataState())
}
