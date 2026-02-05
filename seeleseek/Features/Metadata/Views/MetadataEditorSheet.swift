import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

                // Right: Editable metadata and cover art
                editableMetadataSection
                    .frame(minWidth: 280, maxWidth: 320)
            }
            .padding(SeeleSpacing.lg)

            Divider()

            // Footer
            footer
        }
        .frame(minWidth: 750, minHeight: 550)
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

    // MARK: - Editable Metadata Section

    private var editableMetadataSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Metadata")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            // Cover art with edit options
            coverArtEditView

            // Editable metadata fields
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    editableField("Title", text: $state.editTitle)
                    editableField("Artist", text: $state.editArtist)
                    editableField("Album", text: $state.editAlbum)

                    HStack(spacing: SeeleSpacing.sm) {
                        editableField("Year", text: $state.editYear)
                            .frame(width: 80)
                        editableField("Track #", text: $state.editTrackNumber)
                            .frame(width: 80)
                        Spacer()
                    }

                    editableField("Genre", text: $state.editGenre)
                }
            }

            if let error = state.applyError {
                Text(error)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.error)
            }

            Spacer()
        }
    }

    private var coverArtEditView: some View {
        VStack(spacing: SeeleSpacing.sm) {
            // Cover art display
            ZStack {
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
                            VStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundStyle(SeeleColors.textTertiary)
                                Text("Drop image here")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleImageDrop(providers)
            }

            // Cover art action buttons
            HStack(spacing: SeeleSpacing.sm) {
                #if os(macOS)
                Button("Choose...") {
                    state.selectCoverArtFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif

                if state.coverArtData != nil {
                    Button("Clear") {
                        state.clearCoverArt()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(SeeleColors.error)
                }
            }

            // Source indicator
            if state.coverArtData != nil {
                Text(coverArtSourceText)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
    }

    private var coverArtSourceText: String {
        switch state.coverArtSource {
        case .none: return ""
        case .musicBrainz: return "From MusicBrainz"
        case .manual: return "Custom image"
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try to load as file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        state.loadCoverArtFromFile(url)
                    }
                }
            }
            return true
        }

        // Try to load as image data
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data = data {
                    DispatchQueue.main.async {
                        state.setCoverArt(data)
                    }
                }
            }
            return true
        }

        return false
    }

    private func editableField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(SeeleTypography.body)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Show what will be applied
            if !state.editTitle.isEmpty || !state.editArtist.isEmpty {
                HStack(spacing: SeeleSpacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text("Will apply: \(state.editTitle.isEmpty ? "(no title)" : state.editTitle) by \(state.editArtist.isEmpty ? "(no artist)" : state.editArtist)")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text("Enter metadata or search MusicBrainz to get started")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()

            if state.isApplying {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, SeeleSpacing.sm)
            }

            Button("Apply Metadata") {
                Task {
                    if await state.applyMetadata() {
                        state.closeEditor()
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isApplying || (state.editTitle.isEmpty && state.editArtist.isEmpty))
        }
        .padding(SeeleSpacing.lg)
    }
}

#Preview {
    MetadataEditorSheet(state: MetadataState())
}
